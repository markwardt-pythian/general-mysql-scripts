#!/bin/bash

# Author : Pythian
# Purpose : This script is made to auto uncompress and load the pt-query-digest results into the slow-query-log database to populate data for Anemometer that is running on this server in /var/www/html/anemomter/
# 
# Required Files : completed-slow-log-list - Used to track the logs that have been processed.  We cannot rename the logs because then the logs will get synced from the server again.  Have to keep the names the same
#
# Fixed some issues around not deleting partion log files
# 

# Find all of the files that are to be processed

ROOT="/home/logs/bin"
DIRS=`/usr/bin/find /home/logs/hosts/* -maxdepth 1 -type d`
COMPLETED=`cat $ROOT/completed-slow-log-list`

for DIR in $DIRS ; do
	echo "PROCESSING DIRECTORY : $DIR"
	HOST=`echo ${DIR} | gawk -F / '{print $NF}'`

	# Discover and process all of the files for this directory	
	for FILE in `/usr/bin/find ${DIR} -maxdepth 1 -type f | sort` ; do	
		FILENAME=`echo ${FILE} | gawk -F / '{print $NF}'`
                echo -e "\tFound file : $FILENAME"

		PROCESSED=false
		for COMPLETED in `cat $ROOT/completed-slow-log-list` ; do
			if [ $COMPLETED = $FILE ]; then
				PROCESSED=true
			fi
		done
	
		if $PROCESSED; then
			echo -e "\tThis file ${FILE} was found to have already been processed"
		else
			COMPRESSED=false
			if [[ $FILE == *".gz"* ]] ; then
				COMPRESSED=true
				echo -e "\t\tUncompressing $FILE"
				`gunzip $FILE`
				UNCOMPRESSED_FILE=`echo "$FILENAME" | sed 's/.gz//'`
				echo -e "\t\t$FILENAME uncompressed to $UNCOMPRESSED_FILE"
			
				FINALFILE="$DIR/$UNCOMPRESSED_FILE"
				echo -e "\t\tProcessing $DIR/$UNCOMPRESSED_FILE into Anemometer"
	
			else
				FINALFILE="$DIR/$FILENAME"		
				echo -e "\t\tProcessing $DIR/$FILENAME into Anemometer"	
			fi
		
			# Process the file
			echo -e "\t\t Running pt-query-digest for ${HOST}\n";
			
			pt-query-digest --user=mysql_backup --password='' --review h=localhost,D=slow_query_log,t=global_query_review --history h=localhost,D=slow_query_log,t=global_query_review_history --no-report --limit=0% --filter=" \$event->{Bytes} = length(\$event->{arg}) and \$event->{hostname}=\"${HOST}\"" ${FINALFILE}
			
			echo "RUNNING COMMAND $COMMAND"
			# Done processing.  Compressing files back
			echo -e "\t\tCompressing $FINALFILE"
			if [[ -e "$FINALFILE.gz" ]]; then
				`rm -rf $FINALFILE`
			else
				`gzip $FINALFILE`
			fi
			
			# If the file that was processed was not compressed then it was the most recent BUT was not fully complete.  I have processed the file to get the newest data into the database.  Then I compressed it so it will be cleaned up later and I dont have uncompressed files laying around.  But I dont want to add the file into the complete list because I want to process the rest of the statements after it has been fully updated and completed on the MySQL server.  I am going to remove the partial file so that way when the full file gets uploaded from MySQL it will then get processed adding any missing statements.
			if $COMPRESSED; then
				`echo $FINALFILE.gz >> "$ROOT/completed-slow-log-list"`
			else
				echo -e "\t\tRemoving the partial file as it will get fully processed when it is completed and compressed on the MySQL server : $FINALFILE"
				echo -e "\t\tThe only uncompressed slow query logs should be the most recent partial log."
				`rm -rf $FINALFILE`
			fi
		fi	
	done

	# Clean out logs older than 90 days
	echo ""
	echo -e "\tCleaning out old files from $DIR"
	find $DIR -mtime +90 -type f
	find ${DIR} -mtime +90 -type f -delete
	
	echo -e "\tCleaning out old log files from $ROOT/script_logs"
        find $ROOT/script_logs -mtime +90 -type f
        find $ROOT/script_logs -mtime +90 -type f -delete
done

# Delete old files from our completed list that have been deleted past 90 days to keep the completed list at a smaller size and not always increasing in size

echo ""
echo "Cleaning out the completed-slow-log-list for files that don't exist any longer"
for CLIST in `cat $ROOT/completed-slow-log-list` ; do
	if [ ! -f $CLIST ]; then
  		echo -e "\tFile $CLIST not found!"
		UPDATENAME=${CLIST//\//\\/}
		echo -e "\t\tRemoving $CLIST with : sed -i '/$UPDATENAME/d' $ROOT/completed-slow-log-list"
		sed -i "/$UPDATENAME/d" $ROOT/completed-slow-log-list
	fi
done
