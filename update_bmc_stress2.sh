#!/bin/bash
set -o nounset

workDir=$(cd $(dirname $0)&&pwd)
logDir=$workDir/log_tmp
fail_count=0
fail=0
pass=0
unknown=0
old_log_count=0
log=$workDir/run.log
result=$workDir/result.log
start_err=0
end_err=0
wait_err=0
null_err=0


function killPID(){
	sled_ref_id=$(ps -e | grep "sled_ref" | head -n1 | awk '{print $1}')
	kill -9 $sled_ref_id 1>/dev/null 2>&1
}

function check_finish(){

	local time_count=0
	local get_result=""
	local current_log_count=0
	local log_count=0
	while true;do
		echo "$(date) Checking...${time_count}" | tee -a $result
		sleep 60
		
		current_count=$(cat ${log} | wc -l)
		if [[ $time_count -eq 0 ]];then
			if [[ "$(cat $log | tail -n2)" == "" ]];then
				((null_err++))
				echo "run.log doesn't have any data." | tee -a $result
				break
			fi
		fi
		get_result=$(cat ${log} | egrep "Burn firmware successful|Burn firmware failed|Failed to get start_fw_update response")
		if [[ "$get_result" != "" ]];then
			if [[ "$(echo ${get_result} | grep 'Burn firmware successful')" != "" ]];then
				((pass++))
			elif [[ "$(echo ${get_result} | grep 'Burn firmware failed')" != "" ]];then
				((fail_count++))
				((end_err++))
			elif [[ "$(echo ${get_result} | grep 'Failed to get start_fw_update response')" != "" ]];then
				((fail_count++))
				((start_err++))
			fi
			echo $get_result | tee -a $result
			break
		fi
		
		if [[ $current_log_count -eq $old_log_count ]];then
			((log_count++))
		else
			old_log_count=$current_log_count
		fi

		if [[ $log_count -gt 5 ]];then
			((fail_count++))
			((wait_err++))
			echo "The run.log doesn't have new data." | tee -a $result
			break
		fi
		((time_count++))

		if [[ $time_count -eq 300 ]];then 
			echo "Waitting over 5 hours." | tee -a $result
			killPID
			exit 1
		fi
	done
}

function ctrl_c(){
	killPID
	exit 1	
}

if [[ $EUID -ne 0 ]];then
	echo "Error: This script must be run as root."
	exit 1
fi


if [[ $# -eq 1 ]];then
	count=$1
else
	echo "Usage: ./update_bmc_stress.sh <count>"
	exit 1
fi

trap ctrl_c INT
echo "" > $result
[[ -d $logDir ]] && rm -rf $logDir
mkdir -p $logDir

for((i=0;i<count;i++));do
	echo "Round $((i+1))" | tee -a $result
	
	./sled_ref --tty=/dev/ttyS1>${log}&
	sleep 30

	./ds_uart_tool --tty=/dev/ttyS1 --burn=A7K_BMC02400.ima_enc,1
	check_finish

	killPID
	mv ${log} $logDir/log_24_$((i+1)).log
	sleep 300

	./sled_ref --tty=/dev/ttyS1>${log}&
	sleep 30

	./ds_uart_tool --tty=/dev/ttyS1 --burn=A7K_BMC02500.ima_enc,1
	check_finish

	killPID
	mv ${log} $logDir/log_25_$((i+1)).log
	sleep 300

	[[ $fail_count -gt 0 ]] && ((fail++))
	fail_count=0

	echo "PASS count: $pass" | tee -a $result
	echo "FAIL count: $fail" | tee -a $result
	echo "UNKNOWN count: $unknown" | tee -a $result
done
