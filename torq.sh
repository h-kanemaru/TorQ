#!/bin/bash 

getfield() {
  fieldno=$(awk -F, '{if(NR==1) for(i=1;i<=NF;i++){if($i=="'$2'") print i}}' "$CSVPATH")            # get number for field based on headers
  fieldval=$(awk -F, '{if(NR == '$1') print $'$fieldno'}' "$CSVPATH")                               # pull one field from one line of file
  echo "$fieldval" | envsubst                                                                       # substitute env vars
 }

parameter() {
  fieldval=$(getfield "$1" "$2")
  if [[ "" == "$fieldval" ]]; then                                                                  # check for empty string
    echo ""
  else
    echo " -""$2" "$fieldval"
  fi
 }

findproc() {
  procno=$(awk '/,'$1',/{print NR}' "$CSVPATH")                                                     # get line number for file
  pgrep -f "\-stackid ${KDBBASEPORT} \-proctype $(getfield "$procno" proctype) \-procname $1"       # get pid of process
 }

startline() {
  procno=$(awk '/,'$1',/{print NR}' "$CSVPATH")                                                     # get line number for file
  proctype=$(getfield "$procno" "proctype")                                                         # get proctype for process 
  params="U localtime g T w load"                                                                   # list of params to read from config 
  sline="${TORQHOME}/torq.q -stackid ${KDBBASEPORT} -proctype $proctype -procname $1"               # base part of startup line
  for p in $params; do                                                                              # iterate over params
    a=$(parameter "$procno" "$p");                                                                  # get param
    sline="$sline$a";                                                                               # append to startup line
  done
  qcmd=$(getfield "$procno" "qcmd")
  sline="$qcmd $sline $(getfield "$procno" extras) -procfile $CSVPATH $EXTRAS"                      # append csv file and extra arguments to startup line
  echo "$sline"
 }

start() {
  if [[ -z $(findproc "$1") ]]; then                                                                # check process not running
    sline=$(startline "$1")                                                                         # line to run each process
    echo "$(date '+%H:%M:%S') | Starting $1..."
    eval "nohup $sline </dev/null >${KDBLOG}/torq${1}.txt 2>&1 &"                                   # run in background and redirect output to log file
  else
    echo "$(date '+%H:%M:%S') | $1 already running"
  fi 
 }

print() {
  sline=$(startline "$1")                                                                           # line to run each process 
  echo "Start line for $1:"
  echo "nohup $sline </dev/null >${KDBLOG}/torq${1}.txt 2>&1 &"                                     # echo not evaluate to print
 }

debug() {
  if [[ -z $(findproc "$1") ]]; then                             
    sline=$(startline "$1")                                                                         # get start line for process
    printf "$(date '+%H:%M:%S') | Executing...\n$sline -debug\n\n"
    eval "$sline -debug"                                                                            # append flag to start in debug mode
  else
    echo "$(date '+%H:%M:%S') | Debug failed - $1 already running"
  fi
 }

summary() {
  if [[ -z $(findproc "$1") ]]; then                                                                # check process not running
    printf "%-8s | %-14s | %-6s |\n" "$(date '+%H:%M:%S')" "$1" "down"                              # summary table row for down process
  else
    pid=$(findproc "$1")
    port=$(netstat -nlp 2>/dev/null | grep "$pid" | awk '{ print $4 }' | head -1 | awk -F: '{ print $2 }')  # get port process is running on
    printf "%-8s | %-14s | %-6s | %-6s | %-6s\n" "$(date '+%H:%M:%S')" "$1" "up" "$port" "$pid"     # summary table row for running process    
  fi
 }

stop() {
  if [[ -z $(findproc "$1") ]]; then                                                                # check process not running
    echo "$(date '+%H:%M:%S') | $1 is not currently running"
  else
    echo "$(date '+%H:%M:%S') | Shutting down $1..."
    pid=$(findproc "$1")
    eval "kill -15 $pid"                                                                            # kill process pid
  fi
 }

getall() {
  procs=$(awk -F, '{if(NR>1) print $4}' "$CSVPATH")                                                 # get all processes from csv
  start=""
  for a in $procs; do 
    procno=$(awk '/,'$a',/{print NR}' "$CSVPATH")                                                   # get line number for file
    f=$(getfield "$procno" startwithall) 
    if [[ "1" == "$f" ]]; then                                                                      # checks csv column startwithall equals 1
      start="$start $a"
    fi
  done
  echo "$start"
 }

checkinput() {
  input=$*                                                                                          # get all input process names
  PROCS=$(awk -F, '{if(NR>1) print $4}' "$CSVPATH")                                                 # get all process names from csv
  avail=()
  for i in $input; do
    if [[ $(echo "$PROCS" | grep -w "$i") ]]; then                                                  # check input process is valid
      avail+="$i "                                                                                  # get only valid processes
    else 
      echo "$(date '+%H:%M:%S') | $i failed - unavailable processname"
    fi
  done
  PROCS=$avail                                                                                      # assign valid processes
 }

getprocs() {
  if [[ "$2" == "all" ]]; then 
    PROCS=$(getall)                                                                                 # get all processes
  else
    shift                                                                                           # ignore first argument
    checkinput "$@"                                                                                 # check input process names
  fi
 }

flag() {
  count=0
  for i in ${BASH_ARGV[*]}; do
    count=$((count+1))
    if [[ $i == "-$1" ]]; then                                                                      # find flag argument in command line
      N=$((count-2))                                                                                # find index of flag arugment 
    fi
  done
 }

flagextras() {
  flag "$*"
  z=$N
  while [ $z -ge 0 ]; do
    EXTRAS+="${BASH_ARGV[$z]} "                                                                     # get all parameters following extras flag
    z=$((z-1))
  done
 }

flagcsv() {
  flag "$*"
  CSVPATH="${BASH_ARGV[$N]}"                                                                        # assign specifed csv file
 }

getextras() {
  if [[ $(echo ${BASH_ARGV[*]} | grep -e extras) ]]; then                                            
    eval flagextras "extras";                                                                       # get arguments following flag
    length=$(($#-N-2));                                                                             # number of arguments minus extras 
    array=${*:1:$length};                                                                           # arguments without extras 
  else
    array=$*;
  fi
 }

getcsv() {
  if [[ $(echo ${BASH_ARGV[*]} | grep -e csv) ]]; then
    eval flagcsv "csv";                                                                             # get csv file following flag
    length=$(($#-2));                                                                               # number of arguments minus csv 
    array=${*:1:$length};                                                                           # arguments without csv 
    getprocs $array;
  else
    CSVPATH=${TORQPROCESSES};                                                                       # set csv file to default
    getprocs $array;
  fi
 }

getextrascsv() {
  eval flagextras "extras";                                                                         # get arguments following flag
  eval flagcsv "csv";
  length=$(($#-N-2));
  array=${*:1:$length};                                                                             # arguments without extras and csv
  getprocs $array;                                                                                  # get process names from the remaining arguments
 }

checkextrascsv() {
  if [[ $(echo ${BASH_ARGV[*]} | grep -e extras) ]] && [[ $(echo ${BASH_ARGV[*]} | grep -e csv) ]]; then
    getextrascsv $@;                                                                                # gets extras and csv arguments 
  else
    getextras $@;                                                                                   # checks if extras flag present
    getcsv $@;                                                                                      # sets process csv file
  fi
 }

allcsv() {
  if [[ $(echo ${BASH_ARGV[*]} | grep -e csv) ]]; then
    eval flagcsv "csv";                                                                             # get all procs from csv without starting 
  else
    CSVPATH=${TORQPROCESSES};                                                                            
  fi
 }

startprocs() {
  for p in $PROCS; do
    start "$p";                                                                                     # start each process in variable
  done
 }

stopprocs() {
  for p in $PROCS; do
    stop "$p";                                                                                      # kill each process in variable 
  done
 }

usage() {
  printf -- "Arguments:\n"
  printf -- "  start all|<processname(s)>               to start all|process(es)\n"
  printf -- "  stop all|<processname(s)>                to stop all|process(es)\n"
  printf -- "  print all|<processname(s)>               to view default startup lines\n"
  printf -- "  debug <processname(s)>                   to debug a single process\n"
  printf -- "  procs                                    to list all processes\n"
  printf -- "  summary                                  to view summary table\n"
  printf -- "Optional flags:\n"
  printf -- "  -csv <fullcsvpath>                       to run a different csv file\n"
  printf -- "  -extras <args>                           to add/overwrite extras to the start line\n"
  printf -- "  -csv <fullcsvpath> -extras <args>        to run both\n"
  exit 1
 }

if [[ -z $SETENV ]]; then 
  SETENV=${PWD}/setenv.sh;                                                                          # set the environment if not predefined 
fi

if [ -f $SETENV ]; then                                                                             # check script exists 
  . $SETENV                                                                                         # load the environment
else
  echo "ERROR: Failed to load environment - $SETENV: No such file or directory"                     # show input file error
  exit 1
fi

if [[ "$1" == "start" ]]; then
  checkextrascsv "$*";
  startprocs "$PROCS";
elif [[ "$1" == "print" ]]; then         
  checkextrascsv "$*";
  for p in $PROCS; do 
    print "$p";  
  done
elif [[ "$1" == "stop" ]]; then
  checkextrascsv $@;
  stopprocs "$PROCS";
elif [[ "$1" == "debug" ]]; then
  checkextrascsv "$*";
  if [[ $(echo $PROCS | wc -w) -gt 1 ]]; then 
    echo "ERROR: Cannot debug more than one process at a time"
  else 
    for p in $PROCS; do
      debug "$p";
    done
  fi
elif [[ "$1" == "summary" ]]; then
  allcsv "$*";
  PROCS=$(awk -F, '{if(NR>1) print $4}' "$CSVPATH");
  printf "%-8s | %-14s | %-6s | %-6s | %-6s\n" "TIME" "PROCESS" "STATUS" "PORT" "PID"
  for p in $PROCS; do
    summary "$p";
  done
elif [[ "$1" == "procs" ]]; then
  allcsv "$*";
  awk -F, '{if(NR>1) print $4}' "$CSVPATH" | tr " " "\n"
elif [[ "$#" -eq 0 ]]; then                                                                             
  usage
else
  echo "ERROR: Invalid argument(s)"
  exit 1
fi
