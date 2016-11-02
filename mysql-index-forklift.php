#!/usr/bin/php
<?php

#title           : mysql-index-forklift.php
#description     : This script can be used to discover, drop, add indexes on all tables in a database.  Primarily designed for data imports using INFILE.
#usage           : ./mysql-index-forklift.php
#==============================================================================

$DB_HOST = '';
$DB = '';
$TARGET_DIR = '';
$SOURCE_LIST = '';
$INDEX_ACTION = '';
$TABLE = '';

function capture_input($args){
        $db_not_found = false;
        $db_slave_not_found = false;

        foreach($args as $key => $arg){
                if($arg === "-d"){
                        $GLOBALS['DB'] = $args[$key+1];
                }
                if($arg === "-h"){
                        $GLOBALS['DB_HOST'] = $args[$key+1];
                }
                if($arg === "-a"){
                        $GLOBALS['INDEX_ACTION'] = $args[$key+1];
                }
                if($arg === "-t"){
                        $GLOBALS['TARGET_DIR'] = $args[$key+1];
                }
                if($arg === "-T"){
                        $GLOBALS['TABLE'] = $args[$key+1];
                }
                if($arg === "-s"){
                        $GLOBALS['SOURCE_LIST'] = $args[$key+1];
                }
        }
        if($GLOBALS['DB_HOST'] === '' && $GLOBALS['INDEX_ACTION'] === "discover"){
                echo "!!! Please specify a DB Server with the -h option.\n";
                return false;
        }
        elseif($GLOBALS['DB'] === '' && $GLOBALS['INDEX_ACTION'] === "discover"){
                echo "!!! Please specify a Database with the -d option.\n";
                return false;
        }
        elseif($GLOBALS['INDEX_ACTION'] !== 'discover' && $GLOBALS['INDEX_ACTION'] !== 'add' && $GLOBALS['INDEX_ACTION'] !== 'drop'){
                echo "!!! Please specify an action (discover, drop, or add)  with the -a option.\n";
                return false;
        }
        elseif($GLOBALS['INDEX_ACTION'] === 'discover' && $GLOBALS['TARGET_DIR'] === ''){
                 echo "!!! When discovering please choose a target location with the -t option.\n";
                return false;
        }
        elseif(($GLOBALS['INDEX_ACTION'] === 'drop' || $GLOBALS['INDEX_ACTION'] === 'add') && $GLOBALS['SOURCE_LIST'] === ''){
                 echo "!!! When adding or dropping please choose a source index list with the -s option.\n";
                return false;
        }
        else{
                return true;
        }
}

function display_usage(){
        echo "\nCommand was not executed properly.  This script assumes you have a MySQL .my.cnf file configured for credentials and mysql client is installed.\n";
        echo "-h \t: Host that you wish to run the discovery against.\n";
        echo "-d \t: Database to be run against.\n";
        echo "-a \t: [discover,drop,insert] You must choose one of the three options.  [discover / drop / add].  Skips all Primary Keys.\n";
        echo "-t \t: (Required for discovery) Target directory to place the discovered indexes.\n";
        echo "-s \t: (Required for drop and insert) Target index discovery file.\n";
        echo "-T \t: (Optional) Specify the table that you wish to process the indexes on.\n";
        echo "\n";
        echo "\tex : php " . __FILE__ . " -h 127.0.0.1 -d cs -a discover -t ./\n";
        echo "\tex : php " . __FILE__ . " -d cs -a drop -s ./cs_index_discovery.log\n";
        echo "\tex : php " . __FILE__ . " -d cs -a add -s ./cs_index_discovery.log\n\n";
        exit(1);
}

echo "\nStarting MySQL Index Forklift\n\n";

$start_result = capture_input($argv);
if(!$start_result){
        display_usage();
}

$target_index_file = "$TARGET_DIR/$DB" . "_index_discovery.log";
if(file_exists($target_index_file)){
        echo "\tFound $target_index_file.  Removing it now!\n";
        `rm -rf $target_index_file`;
}
if($INDEX_ACTION === 'discover'){
        echo "\tStarting index discovery for $DB on $DB_HOST\n";
        exec("mysql -h $DB_HOST $DB -e 'SHOW TABLES;' | awk '{print \$1}' | grep -v Tables_in_",$DB_TABLES);
        #print_r($DB_TABLES);
        foreach($DB_TABLES as $table){
                if($TABLE === '' || $TABLE === "$line"){
                        $table_details = '';
                        $T_CREATE = '';
                        echo "\t\t$table\n";
                        exec("mysql -h $DB_HOST $DB -e 'SHOW CREATE TABLE $table;'",$T_CREATE);
                        #print_r($T_CREATE);
                        $table_details = explode('\n',$T_CREATE[1]);
                        #print_r($table_details);
                        foreach($table_details as $line){
                                $line = trim($line);
                                if (strpos($line,"CREATE TABLE") !== false) {
                                        #echo "REMOVING CREATE TABLE LINE\n";
                                }
                                elseif(strpos($line,"ENGINE") !== false){
                                        #echo "REMOVING ENGINE LINE\n";
                                }
                                elseif(substr($line, 0, 1) === '`'){
                                        #echo "REMOVING COLUMN LINE\n";
                                }
                                elseif(strpos($line,"KEY") !== false) {
                                        `echo '$table\t$line' >> $target_index_file`;
                                }
                                else{
                                        echo "\t\t\tNo Indexes\n";
                                }
                        }
                }
        }
        exit(1);
}

# Pulling in the list of indexes for either dropping or adding.
if(file_exists($SOURCE_LIST)){
        exec("cat $SOURCE_LIST",$index_list);
}
else{
        echo "\n\n\t\t!!! Source List $SOURCE_LIST was not found!!\n\n";
        exit(1);
}


# Starting index drop processing

if($INDEX_ACTION === 'drop'){
        echo "\tStarting index drop statement creation for $DB on $DB_HOST\n";
        foreach($index_list as $i){
                $index_details = explode("\t",$i);
                $table_name = $index_details[0];
                $index_exp = explode('`',$index_details[1]);

                if(strpos($index_exp[0],"PRIMARY") !== false){
                        #echo "\t\tSkipping PRIMARY KEY for $table_name\n";
                }
                else{
                        #print_r($index_exp);
                        # Remove the garbage from the array
                        $found = true;
                        $i=0;
                        while($found){
                                $i = 0;
                                $found = false;
                                foreach($index_exp as $index_item){
                                        if((strpos($index_item,",") !== false) || (strpos($index_item,")") !== false) || (strpos($index_item,"(") !== false)){
                                                array_splice($index_exp,$i,1);
                                                $found = true;
                                        }
                                        $i++;
                                }
                        }

                        $index_name = $index_exp[1];
                        # Generate Drop Statement
                        echo "DROP INDEX `$index_name` ON `$table_name`;\n";
                        #print_r($index_exp);
                }
        }
        exit(1);
}


# Starting index add processing

if($INDEX_ACTION === 'add'){
        echo "\tGenerating index create statements\n";
        foreach($index_list as $i){
                $index_details = explode("\t",$i);
                $table_name = $index_details[0];
                $index_exp = explode('`',$index_details[1]);

                if(strpos($index_exp[0],"PRIMARY") !== false){
                        #echo "\t\tSkipping PRIMARY KEY for $table_name\n";
                }
                else{
                        #print_r($index_exp);
                        # Remove the garbage from the array
                        $found = true;
                        $i=0;
                        foreach($index_exp as $index_item){
                                if(!(preg_match('#[0-9]#',$index_item))){
                                        if((strpos($index_item,",") !== false) || (strpos($index_item,")") !== false) || (strpos($index_item,"(") !== false)){
                                                #echo "Splicing $index_item\n";
                                                array_splice($index_exp,$i,1);
                                                $i--;
                                        }
                                }
                                $i++;
                        }

                        # Fix formating on index columns with a size
                        $i = 0;
                        foreach($index_exp as $index_item){
                                if (preg_match('#[0-9]#',$index_item) && strpos($index_item,")") !== false){
                                        #echo "$index_item\n";
                                        $index_exp[$i] = rtrim($index_exp[$i],',');
                                        if(substr_count($index_exp[$i],")") > 1){
                                                $index_exp[$i] = substr($index_exp[$i],0,1-substr_count($index_exp[$i],")"));
                                        }
                                        $index_item = $index_exp[$i];
                                        #echo "$index_item\n";
                                }
                                $i++;
                        }

                        #print_r($index_exp);

                        # Generate Create Statements

                        $index_name = $index_exp[1];
                        $statement = "";
                        if(strpos($index_exp[0],"UNIQUE") !== false){
                                $statement .= "CREATE UNIQUE INDEX ";
                        }
                        elseif(strpos($index_exp[0],"FULLTEXT") !== false){
                                $statement .= "CREATE FULLTEXT INDEX ";
                        }
                        else{
                                $statement .= "CREATE INDEX ";
                        }
                        $statement .= "`$index_name` ON $table_name (";

                        $p = 2;

                        $array_size = count($index_exp) - 1;
                        while($p <= $array_size){
                                $column_name = $index_exp[$p];
                                if (preg_match('#[0-9]#',$column_name) && strpos($column_name, ")") !== false){
                                        # This is not a column name it's the size of the last column
                                        # Chop off the last two characters `, and add the column size
                                        $statement = substr($statement,0,-1);
                                        $statement .= "$column_name,";
                                }
                                else{
                                        $statement .= "`$column_name`,";
                                }
                                $p++;
                        }
                        $statement = rtrim($statement, ",");
                        $statement .= ");";
                        echo "$statement\n";
                }
        }

        exit(1);
}

?>
