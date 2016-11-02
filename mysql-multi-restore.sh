#!/bin/sh

clear

echo "###################################"
echo "## Pythian - MySQL Multi Restore ##"
echo "###################################"
echo ""
echo "## This restore process will drop any of the databases that are in the Multi Dump Path.  Make sure you do not drop any data that is needed."
echo ""
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

printf "Multi Dump path [./$MYSQL_HOST] : "
read TARGET
if [ ! $TARGET ]; then
        TARGET="./$MYSQL_HOST"
fi

printf "Drop and Add Indexes? (y/n) : "
read DOINDEX
while [[ $DOINDEX != "y" ]] && [[ $DOINDEX != "n" ]]; do
	printf "  Please use y or n : "
	read DOINDEX
done 

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
echo "Gathering databases to import from $TARGET"
DBs=`ls -d $TARGET/*/ | xargs -n 1 basename`
for d in $DBs; do
	echo "Found DB $d in the directory"
done

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

printf "Are you sure you want to start the import now? [y/n] : "
read CONFIRM
if [ $CONFIRM == "y" ] || [ $CONFIRM == "Y" ]; then
        echo "Starting import now"
else
	echo "Y or y was not chosen.  Exiting."
	`rm -rf ./.my.multi.cnf`
	exit 1
fi

for i in $DBs; do
	echo "Working on $i"
	`mkdir /tmp/$i; rm -rf /tmp/$i/*`

	DBCHECK=`mysql --defaults-file=./.my.multi.cnf -B -N -h $MYSQL_HOST -e "SHOW DATABASES" | grep $i | wc -l`
	if [ $DBCHECK -ge 1 ]; then
#		printf "WARNING, FOUND $i DB on the server.  Dump it? [y/n] : "
#		read CONFIRMDB
#		if [ $CONFIRMDB == "y" ] || [ $CONFIRMDB == "Y" ]; then
		        echo "Dropping DB $i now."
			`mysql --defaults-file=./.my.multi.cnf -h $MYSQL_HOST -e "DROP DATABASE $i;"`
#		else
#	        	echo "Y or y was not chosen.  Exiting."
#	        	`rm -rf ./.my.multi.cnf`
#		        exit 1
#		fi
	fi
	# Create database Schema
	`mysql --defaults-file=./.my.multi.cnf -h $MYSQL_HOST -e "CREATE DATABASE $i;"`

	echo "Checking for the schema file for $i at $TARGET/$i-schema.sql"
	if [ ! -f "$TARGET/$i-schema.sql" ]; then
		echo "Unable to find the schema for this database.  Exiting"
		`rm -rf ./.my.multi.cnf`
		exit 1
	else
		echo "Importing $i schema from $TARGET/$i-schema.sql"
		`mysql --defaults-file=./.my.multi.cnf -h $MYSQL_HOST $i < $TARGET/$i-schema.sql`
	fi
	
	echo "  Gathering tables for $i from $TARGET/$i"
	TABLES=`ls -1 $TARGET/$i | cut -f1 -d.`

	echo "  Restoring tables for $i"
	for t in $TABLES; do
		RUNNING_THREADS=`ps aux | grep mysql | grep $MYSQL_HOST | grep $i | grep -v grep | wc -l`
		echo "Running Threads $RUNNING_THREADS"
	
		if [ $DOINDEX = "y" ]; then
			echo "Working on indexes"	
			# Discover non primary indexes for the table
			OLDIFS=$IFS
			IFS=$'\n'
			INDEXES=`mysql --defaults-file=./.my.multi.cnf -B -N -h $MYSQL_HOST $i -e "SHOW CREATE TABLE $t\G" | grep KEY | grep -v PRIMARY | awk '{print \$1,\$2,\$3,\$4}'`
			
			# Dropping indexes and generating .sql file to re create the indexes after the table is complete
			`rm -rf /tmp/$t-indexes.sql`
			for ind in $INDEXES; do
				echo "Processing $ind"
				INDEX_TYPE=`echo $ind | awk '{print \$1}'`
				INDEX_NAME=`echo $ind | awk '{print \$2}'`
	                        INDEX_COLUMNS=`echo $ind | awk '{print \$3}'`
				if [ $INDEX_TYPE == 'UNIQUE' ] ||  [ $INDEX_TYPE == 'FULLTEXT' ]; then
					INDEX_TYPE=`echo $ind | awk '{print \$1}'`
					INDEX_NAME=`echo $ind | awk '{print \$3}'`
		                        INDEX_COLUMNS=`echo $ind | awk '{print \$4}'`
				fi
			
				# Remove trailing comma
				LAST=`echo -n $INDEX_COLUMNS | tail -c 1`
				echo "CHECK LAST CHARACTER FOR COMMA : $LAST"
				if [ $LAST == ',' ]; then
					INDEX_COLUMNS=`echo "\${INDEX_COLUMNS%?}"`
				fi
				echo "New COlumns : $INDEX_COLUMNS"
	
				echo "  Found a $INDEX_TYPE INDEX $INDEX_NAME with columns $INDEX_COLUMNS on $t"
				echo "    DROPPING INDEX : $INDEX_NAME"
				`mysql --defaults-file=./.my.multi.cnf -B -N -h $MYSQL_HOST $i -e "DROP INDEX $INDEX_NAME ON $t"`
	
				echo "    Generating Index Creation script for this table"
				INDEX_COMMAND=''
				if [ $INDEX_TYPE == 'KEY' ]; then
					INDEX_COMMAND="CREATE INDEX $INDEX_NAME ON $t $INDEX_COLUMNS;"
				else
					INDEX_COMMAND="CREATE $INDEX_TYPE INDEX $INDEX_NAME ON $t $INDEX_COLUMNS;"
				fi
				echo "      INDEX COMMAND : $INDEX_COMMAND"
				`echo "$INDEX_COMMAND" >> /tmp/$t-indexes.sql`
			done
			IFS=$OLDIFS
		fi

		# Starting Restore/index creation
		echo "    Restoring table $t from $TARGET/$i/$t.sql"
		if [ $DOINDEX = "y" ]; then
			`(mysql --defaults-file=./.my.multi.cnf -h $MYSQL_HOST $i < $TARGET/$i/$t.sql; mysql --defaults-file=./.my.multi.cnf -h $MYSQL_HOST $i < /tmp/$t-indexes.sql  ; rm -rf /tmp/$t-indexes.sql) > /tmp/$i/$t-restore.log  2>&1 3>&1 &`
		else
			`mysql --defaults-file=./.my.multi.cnf -h $MYSQL_HOST $i < $TARGET/$i/$t.sql > /tmp/$i/$t-restore.log 2>&1 3>&1 &`	
		fi
		
		while [ $RUNNING_THREADS -ge $THREADS ]; do
                	sleep 5
                	RUNNING_THREADS=`ps aux | grep mysql | grep $MYSQL_HOST | grep $i | grep -v grep | wc -l`
        	done
	done
	
	echo ""
done
