#!/bin/bash
LAST_COUNT=0
SLEEP_TIME=$1
while [ 1 > 0 ]; do
	date
	START_TIME=`date +%s`
	mysql -e "SHOW STATUS LIKE 'connections'"
	END_TIME=`date +%s`
	RUNTIME=$((END_TIME-START_TIME))
	echo "MySQL Execution Time : $RUNTIME sec."
	CONN_COUNT=`mysql -e "SHOW STATUS LIKE 'connections'" | grep Connections | awk '{print \$2}'`
	DIFF_COUNT=$((CONN_COUNT - LAST_COUNT))
	TOTAL_EXECUTION_TIME=$((SLEEP_TIME+RUNTIME))
	echo "Total Execution Time : $TOTAL_EXECUTION_TIME sec."
	PER_SEC=$((DIFF_COUNT / TOTAL_EXECUTION_TIME))
	echo "Difference in Connections : $DIFF_COUNT ($PER_SEC / sec)"
	LAST_COUNT=$CONN_COUNT
	sleep $SLEEP_TIME
done
