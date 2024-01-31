#!/bin/env bash

script_directory=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $script_directory/cpst_common.sh

checkOCLogin () {
    [ $(oc project 2>&1>/dev/null;echo $?) -ne 0 ] && { logError "Openshift is not logged in, Please login to the Openshift cluster"; exit 1; } 
}

#Assertions
function checkClusterVersionStatus () {
    clusterversionoutput="$(oc get clusterversion)"
    logTitle "========================================================"
    logTitle "==================ClusterVersion status================="
    logTitle "========================================================" 
    outputContains "$clusterversionoutput" "luster version is" && { logInfo "\n$clusterversionoutput\n";logSuccess "✅ ClusterVersion is in a correct status"; } || { logInfo "\n$clusterversionoutput\n";logWarning "⚠️  ClusterVersion is either degraded or an upgrade is in progress"; }
}



function checkClusterOperators () {
    costatus="$(oc get co)"
    logTitle "========================================================"
    logTitle "=============== Cluster Operators status ==============="
    logTitle "========================================================"
    for co in $(echo "$costatus"|grep -Evi "NAME"|tr ' ' '?')
    do 
        coname=$(echo "$co"|tr '?' ' '|awk '{print $1}')
        status=$(echo "$co"|tr '?' ' '|awk '{print $3,$4,$5}')
        
        if [[ "$status" == "False True False" ]];then
            coprogressing+="$coname "
        elif [[ "$status" == "False True True" ]];then
            codegraded+="$coname "
        else
            cohealthy=+"$coname "
        fi
    done

    for co in $(echo "$costatus"|grep -Evi "NAME"|tr ' ' '?')
    do

        if [[ $coprogressing =~ (^|[[:space:]])$(echo $co|awk -F '?' '{print $1}')($|[[:space:]]) ]];then
            logWarning "$(echo $co|tr '?' ' ')"
        elif [[ $codegraded =~ (^|[[:space:]])$(echo $co|awk -F '?' '{print $1}')($|[[:space:]]) ]];then
            logError "$(echo $co|tr '?' ' ')"
        else
            logInfo "$(echo $co|tr '?' ' ')"
        fi
        
    done

    if [[ -z "$coprogressing" && -z "$codegraded" ]];then
        logSuccess "✅ All Cluster operators are in a correct status"
    elif [[ ! -z "$coprogressing" && -z "$codegraded" ]];then
        logWarning "⚠️ Some cluster operator are not available"
    elif [[ ! -z "$codegraded" ]];then
        highlightTextError "❌ Cluster operators found in a degraded status Please take a look"
    fi
}


function checkCpdPatch () {
    logTitle "========================================================"
    logTitle "================== CP4D  Check ====================="
    logTitle "========================================================"
    namespaces=$(oc get ns)
    if [[ "$namespaces" == *"cpd-operators"* ]];then
        logInfo "cpd-operators namespace found, assuming it is an specialized cp4d installation"
        cpdprojects=$(oc get ibmcpd -A --no-headers|awk '{print $1}'|tr '\n' ' ')" ibm-common-services cpd-operators"    
    elif [[ "$namespaces" != *"cpd-operators"* && "$namespaces" != *"ibm-common-services"* ]];then
        logError "No ibm-common-services nor cpd-operators namespace were found, Something looks bad. Please check"
        return 1
    else
        logInfo "cpd-operators namespace not found, assuming it is an express cp4d installation"
        cpdprojects=$(oc get ibmcpd -A --no-headers|awk '{print $1}'|tr '\n' ' ')" ibm-common-services"
    fi    
    for project in $cpdprojects
    do
        logInfo "----------------------------------------------------"
        logInfo "      Checking $project namespace "
        logInfo "----------------------------------------------------"
        [[ "$project" != "ibm-common-services" && "$project" != "cpd-operators" ]] && checkCpdCrdStatus $project
        [[ "$project" == "ibm-common-services" || "$project" == "cpd-operators" ]] && checkCsvStatus $project
    done

    
    [[ -z $tflag ]] && logSuccess "✅ Any resource was found in a bad state" || logWarning "Resources found that might need to be investigated"

}


function checkCpdCrdStatus () {
    namespace=$1
    if [[ -z $namespace ]];then
        logInfo "[NOTE]: Namespace was not provided,assuming current namespace\n"
        logTitle "========================================================"
        logTitle "===== Checkind CPD CRDs at current namespace     ======="
        logTitle "========================================================"
        #crdstatuscheck=$(oc api-resources|grep cpd|awk '{print $1}'|xargs -I{} oc get {} --ignore-not-found  --no-headers -oyaml|grep -E "^    name:|Status"|tr -d '\n'|sed 's/name:/\nname:/g'|column -t|tr ' ' ';')
        for ar in $(oc api-resources|grep cpd|awk '{print $1}')
        do
            #crdline=$(oc get $ar --ignore-not-found  --no-headers -oyaml|grep -E "^    name:|Status"|tr -d '\n'|sed 's/name:/\nname:/g'|column -t)
            #[[ ! -z $crdline ]] && { crdstatuscheck+="kind:  $ar  $crdline"$'\n'; }
            crdline=$(oc get $ar --ignore-not-found --no-headers -oyaml | grep -E "^    name:|Status|image_tags:|image_digests:|ignoreForMaintenance:" | tr -d '\n' | sed 's/name:/\nname:/g' | column -t)
            [[ ! -z $crdline ]] && { crdstatuscheck+="kind:  $ar  $crdline"$'\n'; }
        done
        crdstatuscheck=$(echo "$crdstatuscheck"|column -t)
    else
        logTitle "========================================================"
        logTitle "====== Checkind CPD CRDs at $namespace namespace  ======"
        logTitle "========================================================"
        #crdstatuscheck=$(oc api-resources|grep cpd|awk '{print $1}'|xargs -I{} oc -n $namespace get {} --ignore-not-found  --no-headers -oyaml|grep -E "^    name:|Status"|tr -d '\n'|sed 's/name:/\nname:/g'|column -t|tr ' ' ';')    
        for ar in $(oc api-resources|grep cpd|awk '{print $1}')
        do
            #crdline=$(oc -n $namespace get $ar --ignore-not-found  --no-headers -oyaml|grep -E "^    name:|Status"|tr -d '\n'|sed 's/name:/\nname:/g'|column -t)
            #[[ ! -z $crdline ]] && { crdstatuscheck+="kind:  $ar  $crdline"$'\n'; }
            crdline=$(oc -n $namespace get $ar --ignore-not-found --no-headers -oyaml | grep -E "^    name:|Status|image_tags:|image_digests:|ignoreForMaintenance:" | tr -d '\n' | sed 's/name:/\nname:/g' | column -t)
            [[ ! -z $crdline ]] && { crdstatuscheck+="kind:  $ar  $crdline"$'\n'; }
        done
        crdstatuscheck=$(echo "$crdstatuscheck"|column -t)
    fi
    [[ -z $crdstatuscheck ]] && { logInfo "\n No CPD crds were found!";return 0; }
    logInfo "[Checking CRDs]" 
    IFS=$'\n'
    for crd in $crdstatuscheck
    do          
        #[[ "$crd" == *"ccs"* ]] && crd=$(echo $crd|sed 's/Completed/Failed/g')
        if [[ "$crd" == *"rogress"* ]];then
            logWarning "$crd"
            failedcrd+="$(echo $crd|awk '{print $2" "$4}') "
            tflag=2
        elif [[ "$crd" == *"ail"* ]];then
            logError "$crd"
            failedcrd+="$(echo $crd|awk '{print $2" "$4}') "
            tflag=2
        else
            logInfo "$crd"
        fi 
    done
    unset IFS

    if [[ ! -z $debug ]];then
        if [[ -z $namespace ]];then
            IFS=$'\n'
            for crd in $failedcrd
            do
                logHighlight "\n[Printing debug information on crd $crd"
                logInfo "...."
                logInfo ".."
                logInfo "." 
                kind=$(echo $crd|awk '{ print $1}')
                crdname=$(echo $crd|awk '{ print $2}')
                logInfo "$(oc describe $kind $crdname|grep -A500 Spec)"
            done 
            unset IFS
        else 
            for crd in $failedcrd
            do
                logHighlight "\n[Printing debug information on crd $crd"
                logInfo "...."
                logInfo ".."
                logInfo "." 
                kind=$(echo $crd|awk '{ print $1}')
                crdname=$(echo $crd|awk '{ print $2}')
                logInfo "$(oc -n $namespace describe $kind $crdname|grep -A500 Spec)"
            done 
            unset IFS
        fi
    fi   
     [[ -z $tflag ]] && logInfo "\nNo crd were found in a bad state\n" || logWarning "\nCRDs found that might need to be investigated\n"
}




function usage() { 
    echo
    echo "$0"
    echo
    echo "Description:"
    echo "The goal of this checktool is to check the status of different resources in the system"
    echo "it is meant to be run before during or after the execution of a test of the different "
    echo "CloudPaks. "
    echo 
    echo "Usage:"
    echo
    echo "$0 -c <check or checks(separated by a comma)>"
    echo "$0 --check <check or checks(separated by a comma)>"
    echo "$0 -cd <check or checks(separated by a comma)> [USE THIS OPTION TO ENABLE DEBUG INFO]" 
    echo "$0 --check-and-debug <check or checks(separated by a comma)> [USE THIS OPTION TO ENABLE DEBUG INFO]"
    echo "$0 -h   to print this help"
    echo "$0 --h   to print this help"
    echo
    echo "Available checks:"
    echo
    myf=$(declare -F)  
    echo "$myf"|grep check|awk '{print $3}'
    echo
    echo
    }

while [ $# -gt 0 ] ; do
  case $1 in
    -c | --check) 
        unset debug
        for checkfunction in $(echo $2|sed 's/,/ /g')
        do
            checkOCLogin
            $checkfunction $3 $4 $5
        done
        exit 0
        ;;
    -cd | --check-and-debug)
        debug=1 
        for checkfunction in $(echo $2|sed 's/,/ /g')
        do
            checkOCLogin
            $checkfunction $3 $4 $5
        done
        exit 0
        ;;
    -h | --help) usage;exit 1;;
    * )
        usage
        echo "[Parameter not recognized. Please check the usage above]"
        exit 1
        ;;


  esac
  shift
done
usage

: '
for operator in $(oc get operator|awk '{print $1}')
do
    operatorname=$(echo $operator|awk -F '.' '{print $1}')
    operatorproject=$(echo $operator|awk -F '.' '{print $2}')
    echo $operatorname
    echo $operatorproject
done
'

