#!/bin/bash
SERVER_NAME=`hostname`
CAPTURE_DIR="Pythian_MySQL_Capture_$SERVER_NAME"

mkdir $CAPTURE_DIR
mkdir $CAPTURE_DIR/os_logs

echo "Getting INNODB STATUS"
mysql -e "SHOW ENGINE INNODB STATUS\G" > $CAPTURE_DIR/innodb_status.txt

echo "Getting MySQL Variables"
mysql -e "SHOW VARIABLES" > $CAPTURE_DIR/variables.txt

echo "Getting MySQL Status"
mysql -e "SHOW STATUS" > $CAPTURE_DIR/status.txt
sleep 30
mysql -e "SHOW STATUS" > $CAPTURE_DIR/status_after30.txt
diff $CAPTURE_DIR/status.txt $CAPTURE_DIR/status_after30.txt > $CAPTURE_DIR/status_diff.txt

echo "Getting MySQL Processes"
mysql -e "SHOW FULL PROCESSLIST" > $CAPTURE_DIR/process_list.txt


echo "Getting MySQL Logs"
ERROR_LOG=`mysql -B -N -e "SHOW VARIABLES WHERE Variable_name = 'log_error'" | awk '{print $2}'`
cp $ERROR_LOG $CAPTURE_DIR/

if [ `mysql -B -N -e "SHOW VARIABLES WHERE Variable_name = 'slow_query_log'" | awk '{print $2}'` == "ON" ]; then
    SLOW_LOG_FILE=`mysql -B -N -e "SHOW VARIABLES WHERE Variable_name = 'slow_query_log_file'" | awk '{print $2}'`
    cp $SLOW_LOG_FILE $CAPTURE_DIR/
fi

echo "Getting OS Logs"
tar zcvf $CAPTURE_DIR/os_logs/logs.tar.gz /var/log

echo "Getting TOP"
top -n 1 -b > $CAPTURE_DIR/top.txt

echo "Getting Free Memory"
free -m > $CAPTURE_DIR/free.txt

echo "Getting IO"
iostat -x 3 6 > $CAPTURE_DIR/iostat.txt

cat /proc/sys/vm/swappiness > $CAPTURE_DIR/swapiness.txt

echo "Getting Disk Schedulers"
DEVICES=`ls -1 /sys/block/`
rm -rf $CAPTURE_DIR/schedulers.txt

for dev in $DEVICES; do
    SCHED=`cat /sys/block/$dev/queue/scheduler`
    echo $dev >> $CAPTURE_DIR/schedulers.txt
    echo $SCHED >> $CAPTURE_DIR/schedulers.txt
done

echo "Getting Binary Log Info"
mysql -e "SHOW BINARY LOGS" > $CAPTURE_DIR/binary_logs.txt

echo "Getting Master/Slave Status"
echo "MASTER" > $CAPTURE_DIR/master_slave.txt
echo "" > $CAPTURE_DIR/master_slave.txt
mysql -e "SHOW MASTER STATUS\G" >> $CAPTURE_DIR/master_slave.txt
echo "" > $CAPTURE_DIR/master_slave.txt
echo "SLAVE" > $CAPTURE_DIR/master_slave.txt
echo "" > $CAPTURE_DIR/master_slave.txt
mysql -e "SHOW SLAVE STATUS\G" >> $CAPTURE_DIR/master_slave.txt

echo "Getting Netstat"
netstat -a > $CAPTURE_DIR/netstat.txt

tar zcvf pythian_capture_"$SERVER_NAME".tar.gz $CAPTURE_DIR
