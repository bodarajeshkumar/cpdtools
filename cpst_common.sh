#!/bin/env bash
########################################
#  Library of commonly used functions  #
########################################

script_directory=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
declare -A cnarr
declare -A contactnodes

function initLogFile () { 
    mkdir -p $script_directory/logs
    logfile_date=$(echo `date`|sed "s/ /_/g")
    echo $script_directory"/logs/"$logfile_date"_scale_install.log"
}


[[ -z $enablelog ]] && logfile=""|| logfile=$(initLogFile)

[[ -z $enabletimestamp ]] && date_var=""|| date_var=`date`"-"

function logError () {
  string=$(echo "$*" | sed "s/^/$date_var ERROR:   /;s/\\\n/\\n$date_var ERROR:   /g"| tee -a $logfile)
  printf "\e[31m\e[1m%s\e[0m\n" "$string"
}

function logSuccess () {
  string=$(echo "$*" | sed "s/^/$date_var SUCCESS: /;s/\\\n/\\n$date_var SUCCESS: /g"| tee -a $logfile)
  printf "\e[32m\e[1m%s\e[0m\n" "$string"
}

function logInfo () {
  string=$(echo "$*" | sed "s/^/$date_var INFO:    /;s/\\\n/\\n$date_var INFO:    /g"| tee -a $logfile)
  printf "\e[1m%s\e[0m\n" "$string"
}

function logTitle () {
   string=$(echo "$*" | sed "s/^/$date_var INFO:    /;s/\\\n/\\n$date_var INFO:    /g"| tee -a $logfile)
   printf "\e[36m\e[1m%s\e[0m\n" "$string"
}

function logHighlight () {
   string=$(echo "$*" | sed "s/^/$date_var INFO:    /;s/\\\n/\\n$date_var INFO:    /g"| tee -a $logfile)
   printf "\e[44m\e[1m%s\e[0m\n" "$string"
}

function logWarning () {
  string=$(echo "$*" | sed "s/^/$date_var WARNING: /;s/\\\n/\\n$date_var WARNING: /g"| tee -a $logfile)
  printf "\e[33m\e[1m%s\e[0m\n" "$string"
}

function highlightText () {
  string=$(echo "$*" | sed "s/^/$date_var INFO:    /;s/\\\n/\\n$date_var INFO:    /g")
  printf "\e[33m\e[1m%s\e[0m\n" "$string"
}

function highlightTextError () {
  string=$(echo "$*" | sed "s/^/$date_var ERROR:   /;s/\\\n/\\n$date_var ERROR:   /g")
  printf "\e[31m\e[1m%s\e[0m\n" "$string"
}
  
function executeAndLogInfo () {
    rc=$?
    output=$*
    [[ $rc == 0 ]] && { logInfo "$output"; } || { logError "$output";exit 1; } 
}

function executeAndLogSuccess () {
    rc=$?
    output=$*
    [[ $rc == 0 ]] && { logSuccess "$output"; } || { logError "$output";exit 1; } 
}

function executeAndIgnoreError () {
    rc=$?
    output=$*
    [[ $rc == 0 ]] && logSuccess "$output" || logError "$output"
}

function getOcpVersion () {
    oc version|grep -i "server"|awk -F ': ' '{print $2}'
}

function outputContains () {
    output="$1"
    str="$2"
    [[ "$output" == *"$str"* ]]
}

function outputNotContains () {
    output="$1"
    str="$2"
    [[ "$output" != *"$str"* ]]
}

function outputIsExactly () {
    output="$1"
    str="$2"
    [[ "$output" == "$str" ]]
}




