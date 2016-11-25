#!/usr/bin/env python

import sys
import subprocess

if len(sys.argv) == 3:
    defaults_file = sys.argv[1]
    host_name = sys.argv[2]
    #print defaults_file
    #print host_name
else:
    print
    print "Please specify the first argument as the defaults file, and the second as the host name of the MySQL instnace"
    print "ex. %s <defaults_file_path> <hostname>" % sys.argv[0]
    print
    sys.exit()

def myrun(cmd):
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout = []
    for line in p.stdout:
	line = str(line).rstrip()
    	stdout.append(line)
    return stdout

cmd1 = "mysql --defaults-file=%s -h %s -e \"SELECT user FROM mysql.user\" | grep -v user" % (defaults_file, host_name)
output = myrun("mysql --defaults-file=%s -h %s -e \"SELECT user FROM mysql.user\" | grep -v user") % (defaults_file, host_name)
failed_users = []
for line in output:
    #print line
    cmd2 = "mysql --defaults-file=%s -h %s -e \"SELECT PASSWORD('%s')\" | grep -v PASSWORD" % (defaults_file, host_name, line)
    #cmd = 'ls'
    user_hash = myrun(cmd2)
    #print "USERNAME HASH = %s" % user_hash[0]
    cmd3 = "mysql --defaults-file=%s -h %s -e \"SELECT password FROM mysql.user WHERE user = '%s'\" | grep -v password" % (defaults_file, host_name, line)
    #print cmd2
    mysql_hash = myrun(cmd3)
    #print "PASSWORD HASH = %s" % mysql_hash[0]
    if user_hash == mysql_hash:
        print "!! HASHES MATCH FOR %s" % line
    	failed_users.append(line)

print "The following users have a username and password that match"
print failed_users
