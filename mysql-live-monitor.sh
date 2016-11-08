#!/bin/bash

# Overview Variables
HOSTNAME=''
V_NUM=''
V_NAME=''
VERSION=''
UPTIME=0
NUM_SCHEMAS=0
TOTAL_SIZE=0
BASE_DATA_DIR=''

# Current Status Variables
C_C_CURRENT=99999
C_C_MAX=0
C_Q_QUERIES=0
C_C_ABORT=0
C_C_MERR=0
C_C_TCON=0
C_C_TCACH=0
C_C_TCREA=0
C_C_TRUN=0
C_C_DELAY=0

# Delta Status Variables
D_C_CURRENT=0
D_C_MAX=0

# MySQL Variable Variables
CONN_PARAM=''

# Functions
usage(){
	echo ""
	echo "Usage for $0 : "
	echo " By default the script will look for ~/.my.cnf and try to connect to the database.  If username and password are needed please provide as shown below"
	echo " -h	Provide MySQL host"
	echo " -u	Provide MySQL username"
	echo " -p	Provide MySQL password"
	echo " -o	Provide other command line options"
	echo " -d	Defaults configuration file that contains the client configuration user and password"
	echo ""
	echo "Example :"
	echo " $0"
	echo " $0 -u root -p password"
	echo " $0 -h remote.mysql.com -u root -p password"
	echo " $0 -u root -p password -o \"-P3306 --protocol=tcp\""
	echo " $0 -d ~/.my.cnf"
	echo ""
	exit 1
}

collect_data_once(){
        # Collecting overview data
	HOSTNAME=`mysql $CONN_PARAM -e "SELECT @@hostname;"`
        V_NUM=`mysql $CONN_PARAM -e "SHOW VARIABLES" | grep version | grep -v innodb | grep 5 | cut -d- -f1 | awk '{print $2}'`
        V_NAME=`mysql $CONN_PARAM -e "SHOW VARIABLES" | grep version_comment | sed 's/version_comment//' | sed 's/^[ \t]*//;s/[ \t]*$//'`
        VERSION="$V_NAME $V_NUM"
        NUM_SCHEMAS=`mysql $CONN_PARAM -e "SELECT COUNT(DISTINCT TABLE_SCHEMA) FROM information_schema.TABLES;"`
        TOTAL_SIZE=$(convert_size `mysql $CONN_PARAM -e "SELECT SUM(DATA_LENGTH + INDEX_LENGTH) FROM information_schema.TABLES;"`)
	BASE_DATA_DIR=`mysql $CONN_PARAM -e "SHOW VARIABLES" | grep datadir | sed 's/datadir//' | sed 's/^[ \t]*//;s/[ \t]*$//'`
}

collect_data(){
	# FOR LOOP FOR THE SERVER STATUS
	STATUS_CHECK="$1"
	cat /tmp/mysql_status_results.txt | while read STATUS VALUE; do
		if [ "$STATUS" = "$STATUS_CHECK" ]; then
			echo $(convert_size $VALUE)
			#C_C_CURRENT=$(convert_size $VALUE)
		fi	
	done 
}

convert_size(){
	SIZE=$1
	if [ $SIZE -lt 100000 ]; then
		SIZE=$(add_space $SIZE 5)
		echo "$SIZE"
	elif [ $SIZE -ge 100000 ] && [ $SIZE -lt 1000000 ]; then
		SIZE=$(( ${SIZE%% *} / 1024))
		SIZE=$(add_space $SIZE 3)
		echo "$SIZE K"
	elif [ $SIZE -ge 1000000 ] && [ $SIZE -lt 1000000000 ]; then
		SIZE=$(( ${SIZE%% *} / 1024 / 1024))
		echo "$SIZE M"
	elif [ $SIZE -ge 1000000000 ] && [ $SIZE -lt 1000000000000 ]; then
		SIZE=$(( ${SIZE%% *} / 1024 / 1024 / 1024))
		echo "$SIZE G"
	elif [ $SIZE -ge 1000000000000 ] && [ $SIZE -lt 1000000000000000 ]; then
		SIZE=$(( ${SIZE%% *} / 1024 / 1024 / 1024 / 1024))
		echo "$SIZE T"
	fi 
}

add_space(){
	N=$1
	TO_SPACE=$2
	LENGTH=${#N}
	while [ ${#N} -lt $TO_SPACE ]; do
		N="0$N"
	done
	echo $N
}

# Start Main

#Verifying command line parameters.
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h) mysqlhost="$2"; shift 2;;
    -u) mysqluser="$2"; shift 2;;
    -p) mysqlpass="$2"; shift 2;;
    -d) defaults="$2"; shift 2;;
    -o) options="$2"; shift 2;;

    -*) echo "unknown option: $1" >&2; usage; exit 1;;
    *) echo "unrecognized argument: $1"; usage; exit 1;;
  esac
done

# Verify Connectivity

MYSQLDBCHECK_USER=0

# If the MySQL pass variable is set we will export it
if [ $mysqlpass ] ; then
        export MYSQL_PWD=$mysqlpass
fi

# Configure parameters of connectivity
if [ $mysqluser ]; then
	echo "Checking with Username $mysqluser and Password :"
        CONN_PARAM="-B -N $options -u $mysqluser"
elif [ $defaults ]; then
	echo "Checking using Defaults File $defaults"
        CONN_PARAM="--defaults-file=$defaults -B -N $options"
else
	CONN_PARAM="-B -N $options"
fi

# Add remote host if set
if [ $mysqlhost ]; then
	CONN_PARAM="$CONN_PARAM -h $mysqlhost"
fi

# Check connectivity
MYSQLDBCHECK_USER=`mysql $CONN_PARAM -e "SHOW DATABASES" | grep mysql | wc -l`

if [ $MYSQLDBCHECK_USER -ge 1 ]; then
	#echo "MySQL connection succeded"
	echo ""
else
       	echo "MySQL connection failed!"
       	exit 1   	
fi 

# Display Output

collect_data_once 
while [ 1 -eq 1 ]; do
	mysql $CONN_PARAM -e "SHOW STATUS;" > /tmp/mysql_status_results.txt
	C_C_CURRENT=$(collect_data "Connections")
	C_C_MAX=$(collect_data "Max_used_connections")
	C_C_ABORT=$(collect_data "Aborted_connects")
	C_C_MERR=$(collect_data "Connection_errors_max_connections")
	C_C_TCON=$(collect_data "Threads_connected")
	C_C_TCACH=$(collect_data "Threads_cached")
	C_C_TCREA=$(collect_data "Threads_created")
	C_C_TRUN=$(collect_data "Threads_running")
	C_C_DELAY=$(collect_data "Delayed_insert_threads")
	C_C_SLOW=$(collect_data "Slow_launch_threads")
	C_C_BYTES_REC=$(collect_data "Bytes_received")
	C_C_BYTES_SENT=$(collect_data "Bytes_sent")

	C_Q_QUERIES=$(collect_data "Queries")
	C_Q_SELECT=$(collect_data "Com_select")
	C_Q_INSERT=$(collect_data "Com_insert")
	C_Q_UPDATE=$(collect_data "Com_update")
	C_Q_DELETE=$(collect_data "Com_delete")
	C_Q_ROLLBACK=$(collect_data "Com_rollback")
	C_Q_SLOW=$(collect_data "Slow_queries")
	C_Q_S_F_J=$(collect_data "Select_full_join")
	C_Q_SELECT_S=$(collect_data "Select_scan")
	C_Q_SELECT_R=$(collect_data "Select_range")
	C_Q_S_R_C=$(collect_data "Select_range_check")
	C_Q_F_R_J=
	C_Q_S_M_P=
	C_Q_S_RANGE=
	C_Q_S_ROWS=
	C_Q_S_SCAN=
	C_Q_QC_FREE=
	C_Q_QC_HIT=
	C_Q_QC_INSERTS=
	C_Q_QC_NOT=
	C_Q_QC_IN=
	C_Q_QC_BLOCK=
	C_B_PAGES_DATA=
	C_B_BYTES_DATA=
	C_B_PAGES_DIRTY=
	C_B_BYTES_DIRTY=
	C_B_PAGES_FLUSH=
	C_B_PAGES_FREE=
	C_B_READ_AHEAD_RND=
	C_B_READ_AHEAD=
	C_B_READS=
	C_B_WAIT_FREE=
	C_B_WRITE_REQUESTS=
		
	clear	
	echo "################################################################################################################################################################"
	echo "#  $VERSION"
	echo "################################################################################################################################################################"
	echo "# UPTIME : $UPTIME  NUM OF SCHEMAS : $NUM_SCHEMAS  TOTAL SIZE : $TOTAL_SIZE  BASE DATA DIR : $BASE_DATA_DIR "
	echo "################################################################################################################################################################"
	echo "#                                                                     STATUS CURRENT                                                                           #"
	echo "################################################################################################################################################################"
	echo "# CONN / THREADS (T_)  # QUERIES AND CACHE         # QUERIES AND CACHE         # BUFFER POOL            # TABLES              # DISK                           #"
	echo "################################################################################################################################################################"
	echo "# CURRENT      : $C_C_CURRENT # QUERIES           : $C_Q_QUERIES # S FULL RANGE JOIN : $C_Q_F_R_J # PAGES DATA     : 12345 # OPEN        : 12345 # BINLOG DISK            : 12345 #"
	echo "# MAX USED     : $C_C_MAX # SELECT            : $C_Q_SELECT # SORT MERGE PASS   : $C_Q_S_M_P # BYTES DATA     : 12345 # OPEN DEF    : 12345 # BINLOG STMT CACHE DISK : 12345 #"
	echo "# ABORTED      : $C_C_ABORT # INSERT            : $C_Q_INSERT # SORT RANGE        : $C_Q_S_RANGE # PAGES DIRTY    : 12345 # OPENED      : 12345 # OPEN FILES             : 12345 #"
	echo "# MAX ERRORS   : $C_C_MERR # UPDATE            : $C_Q_UPDATE # SORT ROWS         : $C_Q_S_ROWS # BYTES DIRTY    : 12345 # OPENED DEF  : 12345 # OPENED FILES           : 12345 #"
	echo "# T_CONNECTED  : $C_C_TCON # DELETE            : $C_Q_DELETE # SORT SCAN         : $C_Q_S_SCAN # PAGES FLUSHED  : 12345 # CREATED TMP : 12345 # TMP FILES              : 12345 #"
	echo "# T_CACHED     : $C_C_TCACH # ROLLBACK          : $C_Q_ROLLBACK # QC FREE MEM       : $C_Q_QC_FREE # PAGES FREE     : 12345 # LOCKS IMM   : 13245 # CREATED TMP ON DISK    : 12345 #"
	echo "# T_CREATED    : $C_C_TCREA # SLOW QUERIES      : $C_Q_SLOW # QC HITS           : $C_Q_QC_HIT # READ AHEAD RND : 12345 # LOCKS WAIT  : 12345 #                                #"
	echo "# T_RUNNING    : $C_C_TRUN # SELECT FULL JOIN  : $C_Q_S_F_J # QC INSERTS        : $C_Q_QC_INSERTS # READ AHEAD     : 12345 # CACHE HITS  : 12345 #                                #"
	echo "# T_DELAYED IN : $C_C_DELAY # SELECT SCAN       : $C_Q_SELECT_S # QC NOT CACHED     : $C_Q_QC_NOT # READ REQUESTS  : 12345 # CACHE MISS  : 12345 #                                #"
	echo "# SLOW THREADS : $C_C_SLOW # SELECT RANGE      : $C_Q_SELECT_R # QC QUERIES IN     : $C_Q_QC_IN # READS          : 12345 # CACHE OVER  : 12345 #                                #"
	echo "# BYTES REC    : $C_C_BYTES_REC # S RANGE CHECK     : $C_Q_S_R_C # QC BLOCKS         : $ # WAIT FREE      : 12345 #                     #                                #"
	echo "# BYTES SENT   : $C_C_BYTES_SENT #                           #                           # WRITE REQUESTS : 12345 #                     #                                #"
	echo "################################################################################################################################################################"
	echo "#                                                                     STATUS DELTA                                                                             #"
	echo "################################################################################################################################################################"
	echo "# CONN / THREADS (T_)  # QUERIES AND CACHE         # QUERIES AND CACHE         # BUFFER POOL            # TABLES              # DISK                           #"
	echo "################################################################################################################################################################"
	echo "# CURRENT      : 12345 # QUERIES           : 12345 # S FULL RANGE JOIN : 12345 # PAGES DATA     : 12345 # OPEN        : 12345 # BINLOG DISK            : 12345 #"
	echo "# MAX USED     : 12345 # SELECT            : 12345 # SORT MERGE PASS   : 12345 # BYTES DATA     : 12345 # OPEN DEF    : 12345 # BINLOG STMT CACHE DISK : 12345 #"
	echo "# ABORTED      : 12345 # INSERT            : 12345 # SORT RANGE        : 12345 # PAGES DIRTY    : 12345 # OPENED      : 12345 # OPEN FILES             : 12345 #"
	echo "# MAX ERRORS   : 12345 # UPDATE            : 12345 # SORT ROWS         : 12345 # BYTES DIRTY    : 12345 # OPENED DEF  : 12345 # OPENED FILES           : 12345 #"
	echo "# T_CONNECTED  : 12345 # DELETE            : 12345 # SORT SCAN         : 12345 # PAGES FLUSHED  : 12345 # CREATED TMP : 12345 # TMP FILES              : 12345 #"
	echo "# T_CACHED     : 12345 # ROLLBACK          : 12345 # QC FREE MEM       : 12345 # PAGES FREE     : 12345 # LOCKS IMM   : 13245 # CREATED TMP ON DISK    : 12345 #"
	echo "# T_CREATED    : 12345 # SLOW QUERIES      : 12345 # QC HITS           : 12345 # READ AHEAD RND : 12345 # LOCKS WAIT  : 12345 #                                #"
	echo "# T_RUNNING    : 12345 # SELECT FULL JOIN  : 12345 # QC INSERTS        : 12345 # READ AHEAD     : 12345 # CACHE HITS  : 12345 #                                #"
	echo "# T_DELAYED IN : 12345 # SELECT SCAN       : 12345 # QC NOT CACHED     : 12345 # READ REQUESTS  : 12345 # CACHE MISS  : 12345 #                                #"
	echo "# SLOW THREADS : 12345 # SELECT RANGE      : 12345 # QC QUERIES IN     : 12345 # READS          : 12345 # CACHE OVER  : 12345 #                                #"
	echo "# BYTES REC    : 12345 # S RANGE CHECK     : 12345 # QC BLOCKS         : 12345 # WAIT FREE      : 12345 #                     #                                #"
	echo "# BYTES SENT   : 12345 #                           #                           # WRITE REQUESTS : 12345 #                     #                                #"
	echo "################################################################################################################################################################"
	echo "#                                                                     VARIABLES                                                                                #"
	echo "################################################################################################################################################################"
	echo "# CONN / THREADS (T_)        # QUERIES AND CACHE         # BUFFER POOL                     # TABLES                         # DISK                             #"
	echo "################################################################################################################################################################"
	echo "# MAX_CONNECTIONS    : 12345 # SLOW_QUERY_LOG    : ON    # INNODB_BUFFER_SIZE      : 12345 # TABLE_OPEN_CACHE       : 12345 # INNODB_LOG_BUFFER_SIZE  : 12345  #"
	echo "# CONNECT_TIMEOUT    : 12345 # LONG_QUERY_TIME   : 1     # INNODB_BUFFER_INSTANCES : 10    # TABLE_DEFINITION_CACHE : 12345 # FLUSH_LOG_AT_TRX_COMMIT : 12345  #"
	echo "# MAX_CONNECT_ERRORS : 12345 # LOCK_WAIT_TIMEOUT : 12345 # INNODB_SORT_BUFFER_SIZE : 12345 #                                # FILE_PER_TABLE          : 12345  #"
	echo "# THREAD_CACHE_SIZE  : 12345 # TX_ISOLATION      : RR    # JOIN_BUFFER_SIZE        : 12345 #                                # MAX_TMP_TABLES          : 12345  #"
	echo "# THREAD_CONCURRENCY : 12345 # QC TYPE           : ON    #                                 #                                # IO_CAPACITY             : 12345  #"
	echo "# SLOW_LAUNCH_TIME   : 12345 # QC SIZE           : 12345 #                                 #                                # IO_CAPACITY_MAX         : 12345  #"
	echo "#                            #                           #                                 #                                # READ_IO_THREADS         : 12345  #"
	echo "#                            #                           #                                 #                                # WRITE_IO_THREADS        : 12345  #"
	echo "#                            #                           #                                 #                                # OPEN_FILES              : 12345  #"
	echo "################################################################################################################################################################"
	date
	sleep 1
done

