#!/usr/bin/python

import os
import sys
import getopt
import subprocess
import time 

mysql_master = ''
mysql_slave = ''
mysql_user = ''
mysql_pass = ''
mysql_defaults = ''
mysql_master_args = '-B -N'
mysql_slave_args = ''
execution_time = 5
master_long_query = 0

""" Functions """

def usage():
    print
    print "This script is designed to stop slave to be used for load testing and flush logs and set long_query_time on the master to 0 to capture load.  Then reverse the process after the specified amount of time."
    print "!! Credentials used to connect need to be the same on both master and slave !!"
    print
    print "Usage : "
    print "-m --master      Description : MySQL master to modify long_query_time. Required"
    print "-s --slave       Description : MySQL slave to stop replication. Required"
    print "-u --user        Description : MySQL account username."
    print "-p --password    Description : MySQL account password."
    print "-d --defaults    Description : Defaults file that contains MySQL credentials.  Use either username and password or defaults.  Do not use both."
    print "-t --time        Description : Time in minutes to capture data on the master. Default = 5"
    print "-h --help        Description : Show script usage."
    print
    print "Example : "
    print "%s -m server -s localhost -u root -p password -t 60" % sys.argv[0]
    print "%s -m server -s server -d /file/path -t 5" % sys.argv[0]
    print

def myrun(cmd):
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout = []
    for line in p.stdout:
        line = str(line).rstrip()
        stdout.append(line)

    return stdout

def mysql_command(cmd):
    mysql_response = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    results = mysql_response.stdout.readlines()
    return results 

def mysql_connectivity(args):
    cmd = "mysql %s -e 'SHOW DATABASES'" % args
    output = mysql_command(cmd)
    for line in output:
        if "mysql" in line:
            return True
    return False

def mysql_slave_status(arg):
    output = mysql_command("mysql %s -e 'SHOW SLAVE STATUS\G'" % arg)
    for line in output:
        if "Slave_IO_Running" in line:
            print "        " + line.strip()
            if "Yes" not in line:
                print "Slave is not running correctly.  Please correct and try again!"
                sys.exit()

        if "Slave_SQL_Running" in line and "Slave_SQL_Running_State" not in line:
            print "        " + line.strip()
            if "Yes" not in line:
                print "Slave is not running correctly.  Please correct and try again!"
                sys.exit()

        if "Seconds_Behind_Master" in line:
            print "        " + line.strip()
            if "0" not in line:
                print "Did not find that the slave is 0 Seconds behind.  Please try again later when it's not so busy."
                sys.exit()

def stop_slave(arg):
    os.system("mysql %s -e \"STOP SLAVE;\"" % arg)
    output = mysql_command("mysql %s -e 'SHOW SLAVE STATUS\G'" % arg)
    for line in output:
        if "Slave_IO_Running" in line:
            print "        " + line.strip()
            if "Yes" in line:
                print "Slave is running.  Slave was not stopped as expected"
                sys.exit()

        if "Slave_SQL_Running" in line and "Slave_SQL_Running_State" not in line:
            print "        " + line.strip()
            if "Yes" in line:
                print "Slave is running.  Slave was not stopped as expected"
                sys.exit()

        if "Seconds_Behind_Master" in line:
            print "        " + line.strip()

def master_check_slow_log(arg):
    output = mysql_command("mysql %s -e \"SHOW VARIABLES WHERE Variable_name = 'slow_query_log'\"" % arg)
    line_result = str(output[0]).split("\t")
    print "        Slow Query Log is : " + line_result[1].strip()
    if line_result[1].strip() != "ON":
        print 
        print "Please make sure that slow query logging is set to ON on the master to get a capture of the data!!"
        print
        sys.exit()

def get_long_query(arg):
    output = mysql_command("mysql %s -e \"SHOW VARIABLES WHERE Variable_name = 'long_query_time'\"" % arg)
    line_result = str(output[0]).split("\t")
    return float(line_result[1].strip())

def set_long_running(arg,time):
    os.system("mysql %s -e \"SET GLOBAL long_query_time = %s;\"" % (arg,time))
    new_long_time = get_long_query(arg)
    print "        New long_query_time is now : ", str(new_long_time)

def flush_logs(arg):
    os.system("mysql %s -e \"FLUSH LOGS\"" % arg)
    output = mysql_command("mysql %s -e \"SHOW BINARY LOGS\"" % arg)
    item_split = output[-1].strip().split("\t")
    return item_split[0]

""" Process Command Line Arguments """
try:
    myopts, args = getopt.getopt(sys.argv[1:],"m:s:u:p:d:t:h",['master=','slave=','user=','password=','defaults=','time','help'])
except getopt.GetoptError as e:
    print (str(e))
    usage()
    sys.exit(2)

for o, a in myopts:
    if o in ("-m", "--master"):
        mysql_master = a
        mysql_master_args = "%s -h %s" % (mysql_master_args, mysql_master)
    elif o in ("-s", "--slave"):
        mysql_slave = a
        mysql_slave_args = "%s -h %s" % (mysql_slave_args, mysql_slave)
    elif o in ("-u", "--user"):
        mysql_user = a
    elif o in ("-p", "--password"):
        mysql_pass = a
    elif o in ("-d", "--defaults"):
        mysql_defaults = a
    elif o in ("-t", "--time"):
        execution_time = int(a)
    elif o in ("-h", "--help"):
        print "Displaying usage"
        usage()
        sys.exit()
    else:
        assert False, "unhandled option"

""" Check Parameter Inputs """
if mysql_master == '' and mysql_slave == '':
    print "Please specify both master and slave hosts"
    usage()
    sys.exit()
elif (mysql_defaults == '' and mysql_user == '') or (mysql_defaults != '' and mysql_user != ''):
    print "Please specify either a mysql user or a mysql defaults file for authentication"
    usage()
    sys.exit()
    
""" Building MySQL defaults """
if mysql_user != '':
    os.system("echo \"[client]\" > ~/.my.capture; echo \"user=%s\" >> ~/.my.capture; echo \"password='%s'\" >> ~/.my.capture; chmod 600 ~/.my.capture" % (mysql_user,mysql_pass))
    mysql_defaults = "~/.my.capture"

mysql_master_args = "--defaults-file=%s %s" % (mysql_defaults, mysql_master_args) 
mysql_slave_args = "--defaults-file=%s %s" % (mysql_defaults, mysql_slave_args)

""" Starting Main Script """

print
print "Starting Production Data Load Capture"
print "    Checking MySQL Connectivity"

master_result = mysql_connectivity(mysql_master_args)
if master_result:
    print "        MySQL master connected successfully"
else:
    print "        MySQL master connection failed!"
    sys.exit()

slave_result = mysql_connectivity(mysql_slave_args)
if master_result:
    print "        MySQL slave connected successfully"
else:
    print "        MySQL slave connection failed!"
    sys.exit()    

print "    Checking Slave Status (Should be running so that it is up to date with the master)"
mysql_slave_status(mysql_slave_args)

print "    Verifying that Slow Query Logging is enabled on the master"
master_check_slow_log(mysql_master_args)

print "    Checking Master Long Query Time (To set it back after completion)"
master_long_query = get_long_query(mysql_master_args)
print "        " + str(master_long_query)

print "    Setting Long Query Time to 0"
set_long_running(mysql_master_args, 0)

print "    Flushing The Logs on the Master, and getting the newest binary log where our data will be located."
new_log = flush_logs(mysql_master_args)
print "        %s" % new_log

print "    Stop Slave"
stop_slave(mysql_slave_args)

print "    Waiting %s minute(s)" % execution_time
wait_time = 0
sleep_time = execution_time * 60

while wait_time < execution_time:
    print "        Waited %s minute(s) of a total execution time of %s" % (wait_time, execution_time)
    #time.sleep(sleep_time)        
    wait_time += 1
print "        Waited %s minute(s).  Process Complete" % wait_time

print "    Flushing The Logs on the Master, to close out the binary logs."
new_log = flush_logs(mysql_master_args)
print "        Use logs before %s" % new_log

print "    Setting Long Query Time to %s" % master_long_query
set_long_running(mysql_master_args, master_long_query)

print "Process is complete."
print
