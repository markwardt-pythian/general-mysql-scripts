#!/bin/sh

clear

echo "################################"
echo "## Pythian - MySQL Multi Dump ##"
echo "################################"
echo ""
echo "## This dump process is designed to run on a slave where the slave process has been stopped and the position can be captured."
echo "## No updates should be happening on the server being dumped."
echo ""
echo "## Make sure to STOP the slave process"
echo ""

printf "Please enter MySQL Host [localhost] : "
read MYSQL_HOST
if [ ! $MYSQL_HOST ]; then
        MYSQL_HOST="localhost"
fi

printf "Please enter MySQL User [root] : "
read MYSQL_USER
if [ ! $MYSQL_USER ]; then
        MYSQL_USER="root"
fi

printf "Please enter MySQL Pass : "
read -s MYSQL_PASS
echo ""

printf "Please enter MySQL Port [3306] : "
read MYSQL_PORT
if [ ! $MYSQL_PORT ]; then
	MYSQL_PORT=3306
fi

printf "Dump target path [./$MYSQL_HOST] : "
read TARGET
if [ ! $TARGET ]; then
        TARGET="./$MYSQL_HOST"
fi

printf "Import Threads [3] : "
read THREADS
if [ ! $THREADS ]; then
        THREADS=3
fi
if [ $THREADS -gt 10 ]; then
        echo "More than 10 threads is not advised.  Please choose less than or equal to 10"
        `rm -rf ./.my.multi.cnf`
        exit 1
fi

echo ""
echo "Attempting connection to $MYSQL_HOST using $MYSQL_USER on $MYSQL_PORT.  Creating temporary pass file .my.multi.cnf"
echo ""

echo "[client]" > ./.my.multi.cnf
echo "user=$MYSQL_USER" >> ./.my.multi.cnf
echo "password='$MYSQL_PASS'" >> ./.my.multi.cnf
echo "port=$MYSQL_PORT" >> ./.my.multi.cnf

MYSQLDBCHECK=`mysql --defaults-file=./.my.multi.cnf -B -N -h $MYSQL_HOST -e "SHOW DATABASES" | grep mysql | wc -l`
if [ $MYSQLDBCHECK -ge 1 ]; then
		echo "MySQL connection passed!"
	else   	 
        	echo "MySQL connection failed!"
        	exit 1  
fi
echo ""

echo "Checking for $TARGET"
if [ ! -d $TARGET ]; then
	echo "Creating target directory $TARGET"
	`mkdir $TARGET`
else
	echo "Target direcotry $TARGET found"
fi
echo ""

echo "Gathering databases"
DBs=`mysql --defaults-file=./.my.multi.cnf -B -N -h $MYSQL_HOST -e "SHOW DATABASES" | grep -v mysql | grep -v information_schema | grep -v test | grep -v performance_schema`

for i in $DBs; do
	echo "  Found database $i"
	if [ ! -d "$TARGET/$i" ]; then
		echo "    Creating directory for database $i at $TARGET/$i"
		`mkdir $TARGET/$i`
	fi
	echo "    Creating db schema file for $i at $TARGET/$i-schema.sql"
	`mysqldump --defaults-file=./.my.multi.cnf -h $MYSQL_HOST --no-data -f --skip-triggers --single-transaction --skip-add-drop-table --routines --comments $i > $TARGET/$i-schema.sql`
	echo "    Dumping triggers for db $i at $TARGET/$i-triggers.sql"
	`mysqldump --defaults-file=./.my.multi.cnf -h $MYSQL_HOST --no-create-info --no-data --no-create-db --skip-opt -f > $TARGET/$i-triggers.sql`
	
	echo "  Dumping tables for $i"
	TABLEs=`mysql --defaults-file=./.my.multi.cnf -B -N -h $MYSQL_HOST $i -e "SHOW FULL TABLES IN $i" | grep -v VIEW | grep -v Table_type | awk '{print $1}'`
	RUNNING_THREADS=`ps aux | grep mysqldump | grep -v grep | wc -l`
	for t in $TABLEs; do
		RUNNING_THREADS=`ps aux | grep mysqldump | grep -v grep | wc -l`
		echo "Running Threads $RUNNING_THREADS"
		echo "    Dumping table $t to $TARGET/$i/$t.sql"
		`mysqldump --defaults-file=./.my.multi.cnf -h $MYSQL_HOST $i $t --skip-add-drop-table --no-create-info -vv > $TARGET/$i/$t.sql &`
		
		while [ $RUNNING_THREADS -ge $THREADS ]; do
                	sleep 5
                	RUNNING_THREADS=`ps aux | grep mysqldump | grep -v grep | wc -l`
        	done
	done
	
	echo ""
done

echo "Capturing Grants using pt-show-grants.  The percona toolkit is required for this step"
`pt-show-grants -u $MYSQL_USER -p $MYSQL_PASS -h $MYSQL_HOST > $TARGET/grants.sql`
echo "Capturing Master Status"
`mysql --defaults-file=./.my.multi.cnf -h $MYSQL_HOST -e "SHOW MASTER STATUS\\G" > $TARGET/master-status.txt`
echo "Capturing Slave Status"
`mysql --defaults-file=./.my.multi.cnf -h $MYSQL_HOST -e "SHOW SLAVE STATUS\\G" > $TARGET/slave-status.txt`
echo "" 
