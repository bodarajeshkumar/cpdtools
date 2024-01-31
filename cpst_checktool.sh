#!/usr/bin/env bash

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

function checkMcpUpdates () {
    mcpoutput="$(oc get mcp)"
    logTitle "========================================================"
    logTitle "==================  MCP Update status  ================="
    logTitle "========================================================"
    logInfo "\n$mcpoutput\n"
    if [[ "$(echo "$mcpoutput"|grep master|awk '{print $4,$5}')" == "False False" ]];then
        
        logSuccess "✅ The MCP updates for master nodes are in a correct status"
    else
        
        logWarning "⚠️  MCP update for master nodes are in Degraded status or in the middle of an update. Please check"
    fi
    if [[ "$(echo "$mcpoutput"|grep worker|awk '{print $4,$5}')" == "False False" ]];then
        
        logSuccess "✅ The MCP updates for worker nodes are in a correct status"
    else
        
        logWarning "⚠️  MCP update for worker nodes are in Degraded status or in the middle of an update. Please check"
    fi
}

function checkNodesStatus () {
    nodesoutput="$(oc get nodes)"
    logTitle "========================================================"
    logTitle "================== Nodes status   ======================"
    logTitle "========================================================"
    for node in $(echo "$nodesoutput"|grep -Evi "NAME"|tr ' ' '?')
    do 
        outputContains "$(echo $node)" "??Ready??" && { healthynodes+="\n"$(echo "$node"|awk -F '?' '{print $1,$4}'); } || { unhealthynodes+="\n"$(echo "$node"|awk -F '?'  '{print $1,$4}'); }
        
    done
    for node in $(echo "$nodesoutput"|grep -Evi "NAME"|tr ' ' '?')
    do 

        nodename="$(echo $node|awk -F '?' '{print $1}')"
        compareto="$(echo "$unhealthynodes"|tr -d '\\n')"
        if [[ "$compareto" == *"$nodename"* ]];then
            logWarning "$(echo $node|tr '?' ' ')"
        else
            logInfo "$(echo $node|tr '?' ' ')"
        fi    
    done

    [[ -z "$unhealthynodes" ]] && { logSuccess "✅ All nodes are in a correct status"; } || { logWarning "⚠️  Some Nodes are not in Ready status Please take a look"; }
}

function checkNodesCpuMemUsg () {
    topnodesoutput="$(oc adm top nodes)"
    logTitle "========================================================"
    logTitle "=================== Nodes CPU/MEM USG =================="
    logTitle "========================================================"

    for node in $(echo "$topnodesoutput"|grep -Evi "NAME"|tr ' ' '?')
    do
        
        nodename=$(echo "$node"|awk -F '?' '{print $1}')
        cpu_usg=$(echo "$node"|awk -F '?' '{print $12,$13,$14}'|tr -d ' ')
        mem_usg=$(echo "$node"|awk -F '?' '{print $25,$26,$27}'|tr -d ' ')
        #CPU USG
        if [ $(( $(echo $cpu_usg|tr -d \%) )) -gt 80 -a $(( $(echo $cpu_usg|tr -d \%) )) -lt 90 ];then
            fillingcpunodes+="\n$nodename   CpuUsage:  $cpu_usg"
        elif [ $(( $(echo $cpu_usg|tr -d \%) )) -gt 90 ];then
            overloadingcpunodes+="\n$nodename   CpuUsage:  $cpu_usg"
        elif [ $(( $(echo $cpu_usg|tr -d \%) )) -lt 80 ];then
            cpustablenodes+="\n$nodename   CpuUsage:  $cpu_usg"
        fi
        #MEM USG
        if [ $(( $(echo $mem_usg|tr -d \%) )) -gt 79 -a $(( $(echo $mem_usg|tr -d \%) )) -lt 90 ];then
            fillingmemnodes+="\n$nodename   MemoryUsage:  $mem_usg"
        elif [ $(( $(echo $mem_usg|tr -d \%) )) -gt 90 ];then
            overloadingmemnodes+="\n$nodename   MemoryUsage:  $mem_usg"
        elif [ $(( $(echo $mem_usg|tr -d \%) )) -lt 80 ];then
            memstablenodes+="\n$nodename   MemoryUsage:  $mem_usg"
        fi

    done
    #Print Format
    for node in $(echo "$topnodesoutput"|grep -Evi "NAME"|tr ' ' '?')
    do
        f=""
        if [[ $fillingcpunodes == *"$(echo $node|awk -F '?' '{print $1}')"* ]];then
            f+="cw"
        elif [[ $overloadingcpunodes == *"$(echo $node|awk -F '?' '{print $1}')"* ]];then
            f+="ce"
        elif [[ $fillingmemnodes == *"$(echo $node|awk -F '?' '{print $1}')"* ]];then
            f+="mw"
        elif [[ $overloadingmemnodes == *"$(echo $node|awk -F '?' '{print $1}')"* ]];then
            f+="me"
        fi

        if [[ "$f" == *"w"* ]];then
            logWarning "$(echo $node|tr '?' ' ')"
        elif [[ "$f" == *"e"* ]];then
            logError "$(echo $node|tr '?' ' ')"
        else
            logInfo "$(echo $node|tr '?' ' ')"
        fi   
    done
   
    if [[ -z "$fillingcpunodes" && -z "$overloadingcpunodes" ]];then
        logSuccess "✅ No CPU usage issues found in the cluster"
    elif [[ ! -z "$fillingcpunodes" && -z "$overloadingcpunodes" ]];then
        logWarning "⚠️  Some nodes are getting CPU constrained Please take a look"
    elif [[ ! -z "$overloadingcpunodes" ]];then
        highlightTextError "❌ Some nodes are CPU overloaded and requires your immediate attention"
    fi

    if [[ -z "$fillingmemnodes" && -z "$overloadingmemnodes" ]];then
        logSuccess "✅ No Memory usage issues found in the cluster"
    elif [[ ! -z "$fillingmemnodes" && -z "$overloadingmemnodes" ]];then
        logWarning "⚠️  Some nodes are getting Memory constrained Please take a look"
    elif [[ ! -z "$overloadingmemnodes" ]];then
        highlightTextError "❌ Some nodes are Memory overloaded and requires your immediate attention"
    fi
}

function checkNodesCpuMemRequests () {
    noderequests="$(oc describe nodes |grep -A8 -E "Name:|Allocated"|grep -Ei "Name:|cpu|memory"|tr '\n' ' '|sed 's/Name:/\nName:/g'|awk '{print $2,$3.$5,$8,$10}'|tr '()' ' '|tail -n +2)" #One liner for cpu/mem requests
    logTitle "========================================================"
    logTitle "=============== Nodes CPU/MEM Requests ================="
    logTitle "========================================================"
    for node in $(echo "$noderequests"|grep -Evi "NAME"|tr ' ' '?')
    do
        
        nodename=$(echo "$node"|awk -F '?' '{print $1}')
        cpu_req=$(echo "$node"|awk -F '?' '{print $3}'|tr -d ' ')
        mem_req=$(echo "$node"|awk -F '?' '{print $4}'|tr -d ' ')
        #CPU REQ
        if [ $(( $(echo $cpu_req|tr -d \%) )) -gt 80 -a $(( $(echo $cpu_req|tr -d \%) )) -lt 90 ];then
            fillingcpureqnodes+="$nodename   CpuRequests:  $cpu_req|"
        elif [ $(( $(echo $cpu_req|tr -d \%) )) -gt 90 ];then
            overloadingcpureqnodes+="$nodename   CpuRequests:  $cpu_req|"
        elif [ $(( $(echo $cpu_req|tr -d \%) )) -lt 80 ];then
            cpureqstablenodes+="$nodename   CpuRequests:  $cpu_req|"
        fi
        #MEM REQ
        if [ $(( $(echo $mem_req|tr -d \%) )) -gt 79 -a $(( $(echo $mem_req|tr -d \%) )) -lt 90 ];then
            fillingmemreqnodes+="$nodename   MemoryRequests:  $mem_req|"
        elif [ $(( $(echo $mem_req|tr -d \%) )) -gt 90 ];then
            overloadingmemreqnodes+="$nodename   MemoryRequests:  $mem_req|"
        elif [ $(( $(echo $mem_req|tr -d \%) )) -lt 80 ];then
            memreqstablenodes+="$nodename   MemoryRequests:  $mem_req|"
        fi

    done
    #Print Format
    for node in $(echo "$noderequests"|grep -Evi "NAME"|tr ' ' '?')
    do
        f=""
        if [[ $fillingcpureqnodes == *"$(echo $node|awk -F '?' '{print $1}')"* ]];then
            f+="cw"
        elif [[ $overloadingcpureqnodes == *"$(echo $node|awk -F '?' '{print $1}')"* ]];then
            f+="ce"
        elif [[ $fillingmemreqnodes == *"$(echo $node|awk -F '?' '{print $1}')"* ]];then
            f+="mw"
        elif [[ $overloadingmemreqnodes == *"$(echo $node|awk -F '?' '{print $1}')"* ]];then
            f+="me"
        fi

        if [[ "$f" == *"w"* ]];then
            logWarning "$(echo $node|tr '?' ' ')"
        elif [[ "$f" == *"e"* ]];then
            logError "$(echo $node|tr '?' ' ')"
        else
            logInfo "$(echo $node|tr '?' ' ')"
        fi   
    done

    if [[ -z "$fillingcpureqnodes" && -z "$overloadingcpureqnodes" ]];then
        logSuccess "✅ No CPU requests issues found in the cluster"
    elif [[ ! -z "$fillingcpureqnodes" && -z "$overloadingcpureqnodes" ]];then
        logWarning "⚠️ Some nodes are getting CPU requests constrained Please take a look"
    elif [[ ! -z "$overloadingcpureqnodes" ]];then
        logError "❌ Some nodes are CPU requests overloaded and requires your immediate attention"
    fi

    if [[ -z "$fillingmemreqnodes" && -z "$overloadingmemreqnodes" ]];then
        logSuccess "✅ No Memory requests issues found in the cluster"
    elif [[ ! -z "$fillingmemreqnodes" && -z "$overloadingmemreqnodes" ]];then
        logWarning "⚠️ Some nodes are getting Memory requests constrained Please take a look"
    elif [[ ! -z "$overloadingmemreqnodes" ]];then
        highlightTextError "❌ Some nodes are Memory requests overloaded and requires your immediate attention"
    fi
}

function checkNodesDiskPressure () {
    nodediskpressure="$(oc describe nodes |grep -Ei "Name:|disk pressure"|tr -d '\n'|sed 's/Name:/\nName:/g'|tail -n +2|awk '{print $2,$4}')" # One liner for all nodes disk pressure
    logTitle "========================================================"
    logTitle "================== Nodes Disk Pressure ================="
    logTitle "========================================================"

    for node in $(echo "$nodediskpressure"|grep -Evi "NAME"|tr ' ' '?')
    do
        
        nodename=$(echo "$node"|awk -F '?' '{print $1}')
        diskpressure=$(echo "$node"|awk -F '?' '{print $2}')
        #DISK PRESSURE
        if [[ "$diskpressure" == *"rue"* ]];then
            nodesbadpressure+="$nodename $diskpressure|"
        fi
    done

    for node in $(echo "$nodediskpressure"|grep -Evi "NAME"|tr ' ' '?')
    do    
        #Disk Pressure
        [[ $nodesbadpressure =~ (^|[[:space:]])$(echo $node|awk -F '?' '{print $1}')($|[[:space:]]) ]] && { logError "$(echo $node|tr '?' ' ')"; } || { logInfo "$(echo $node|tr '?' ' ')"; }  
    done

    [[ -z $nodesbadpressure ]] && { logSuccess "✅ No disk pressure was found in the nodes"; } || { logError "❌ Disk pressure was found on at least one node, Please take a look"; }
}

function checkNodesPIDPressure () {
    nodepidpressure="$(oc describe nodes |grep -Ei "Name:|PIDPressure"|tr -d '\n'|sed 's/Name:/\nName:/g'|tail -n +2|awk '{print $2,$4}')" # One liner for all nodes PID pressure
    logTitle "========================================================"
    logTitle "================== Nodes PID Pressure =================="
    logTitle "========================================================"

    for node in $(echo "$nodepidpressure"|grep -Evi "NAME"|tr ' ' '?')
    do
        
        nodename=$(echo "$node"|awk -F '?' '{print $1}')
        pidpressure=$(echo "$node"|awk -F '?' '{print $2}')
        #PID PRESSURE
        if [[ "$pidpressure" == *"rue"* ]];then
            nodesbadpidpressure+="$nodename $pidpressure|"
        fi
    done

    for node in $(echo "$nodepidpressure"|grep -Evi "NAME"|tr ' ' '?')
    do    
        #PID Pressure
        [[ $nodesbadpidpressure =~ (^|[[:space:]])$(echo $node|awk -F '?' '{print $1}')($|[[:space:]]) ]] && { logError "$(echo $node|tr '?' ' ')"; } || { logInfo "$(echo $node|tr '?' ' ')"; }  
    done

    [[ -z $nodesbadpidpressure ]] && { logSuccess "✅ No PID pressure was found in the nodes"; } || { logError "❌ PID pressure was found on at least one node, Please take a look"; }
}

function checkNodeTimeDifference () {
    ## Function taken from https://github.com/IBM-ICP4D/cpd-health-check-v3/blob/main/README.md
    ## Credit to developer @sanjitc
    nodesoutput="$(oc get nodes -owide)"
    NODE_TIMEDIFF=400
    logTitle "========================================================"
    logTitle "=============== Nodes Time difference =================="
    logTitle "========================================================"   
    IFS=$'\n'
    for node in $(echo "$nodesoutput" |grep -v NAME|awk '{print $1" "$6}')
    do
        diff=$(sudo clockdiff $(echo $node|awk '{print $2}') | awk '{print $3}')
        (( diff = $diff < 0 ? $diff * -1 : $diff ))        
        if [ $diff -lt  $NODE_TIMEDIFF ]; then
            logInfo "Time difference with node $(echo $node|awk '{print $1}') is less than $NODE_TIMEDIFF ms" 
        else
            logWarning "Time difference with node $(echo $node|awk '{print $1}') is above $NODE_TIMEDIFF ms." 
            tf=1
        fi            
    done    
    unset IFS
    [[ $tf -ne 0 ]] && logWarning "⚠️ Time difference was found on at least one node. Please take a look" || logSuccess "✅ Time difference check passed"
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

function checkScaleStatus () {
    #Spectrum scale
    tf=0
    cnsans="ibm-spectrum-scale"
    csins="ibm-spectrum-scale-csi"
    gpfscr="$(oc -n $cnsans get gpfs --no-headers)"   
    if [[ -z $gpfscr ]];then
        if [[ "$gpfscr" != *"rasure"* ]];then
            scaleremotecluster="$(oc -n $cnsans get remotecluster)"
        fi
    fi
    #[[ -z $gpfscr ]] || scaleremotecluster="$(oc -n $cnsans get remotecluster)"    
    [[ -z $gpfscr ]] || scalefs="$(oc -n $cnsans get fs)"
    [[ -z $gpfscr ]] || scaledaemon="$(oc -n $cnsans get daemon)"
    [[ -z $gpfscr ]] || cnsapods="$(oc -n $cnsans get pods)"
    
    [[ -z "$(echo $cnsapods|grep -Evi "completed|1/1|2/2|3/3|4/4|5/5|6/6|7/7|8/8|9/9|10/10|11/11|12/12|13/13|NAME")" ]] && scalemount="$(oc -n $cnsans exec `echo "$cnsapods"|grep -Evi "gui|pmcollector|NAME"|head -n 1|awk '{print $1}'` -c gpfs -- mmlsmount all)"
    [[ -z "$(echo $cnsapods|grep -Evi "completed|1/1|2/2|3/3|4/4|5/5|6/6|7/7|8/8|9/9|10/10|11/11|12/12|13/13|NAME")" ]] && mmdfoutput="$(oc -n $cnsans exec `echo "$cnsapods"|grep -Evi "gui|pmcollector|NAME"|head -n 1|awk '{print $1}'` -c gpfs -- mmdf $(echo "$scalefs"|grep -Evi NAME|awk '{print $1}'))"
    [[ -z "$(echo $cnsapods|grep -Evi "completed|1/1|2/2|3/3|4/4|5/5|6/6|7/7|8/8|9/9|10/10|11/11|12/12|13/13|NAME")" ]] && fsinode="$(oc -n $cnsans exec `echo "$cnsapods"|grep -Evi "gui|pmcollector|NAME"|head -n 1|awk '{print $1}'` -c gpfs -- df -i|grep $(echo "$scalefs"|grep -Evi NAME|awk '{print $1}'))"
    logTitle "========================================================"
    logTitle "======= Storage Verification: Spectrum Scale ==========="
    logTitle "========================================================"
    [[ -z $gpfscr ]] && { logError "Spectrum Scale was not found in the cluster";return 1; } 
    #logInfo "----------------------------------------------------"
    #logInfo "  Checking for Erasure Code "
    #logInfo "----------------------------------------------------"
    if [[ ! "$gpfscr" == *"rasure"* ]];then
        #logInfo "--> Spectrum Scale Erasure Code was detected, No remotecluster will be checked"
    #else
        logInfo "--> No Erasure code detected, proceeding to check remotecluster status"
        logInfo "----------------------------------------------------"
        logInfo "  Checking for Remote Cluster "
        logInfo "----------------------------------------------------"
        logInfo "\n--> Remote cluster"
        outputContains "$scaleremotecluster" "rue" && { logInfo "$scaleremotecluster"; logSuccess "✅ Remote cluster is in a correct status"; } || { logWarning "$scaleremotecluster"; logWarning "⚠️  Status needs to be checked for Remote Cluster";tf=1; }
    fi
    logInfo "----------------------------------------------------"
    logInfo "  Checking for Filesystem "
    logInfo "----------------------------------------------------"
    outputContains "$scalefs" "rue" && { logInfo "$scalefs";logSuccess "✅ Filesystem is in a correct status"; } || { logWarning "$scalefs";logWarning "⚠️  Status needs to be checked for Filesystem";tf=1; }
    logInfo "----------------------------------------------------"
    logInfo "  Checking for Filesystem mount "
    logInfo "----------------------------------------------------"
    outputContains "$(echo $scalemount)" "is mounted on" && { logInfo "$scalemount";logSuccess "✅ Filesystem is in mounted correctly"; }  || { logWarning "$scalemount";logWarning "⚠️  Filesystem not mounted";tf=1; }
    logInfo "----------------------------------------------------"
    logInfo "  Checking for Inode Usage "
    logInfo "----------------------------------------------------"
    if [ $(( $(echo $fsinode|awk '{print $5}'|tr -d '%') )) -gt 79 -a $(( $(echo $fsinode|awk '{print $5}'|tr -d '%') )) -lt 90 ];then
        logWarning "$fsinode"
        logWarning "⚠️  Running out of Inodes, Please check"
        tf=1
    elif [ $(( $(echo $fsinode|awk '{print $5}'|tr -d '%') )) -gt 90 ];then
        logError "$fsinode"
        logError "❌ No Inodes left on the Filesystem, Please check"
        tf=1
    elif [ $(( $(echo $fsinode|awk '{print $5}'|tr -d '%') )) -lt 80 ];then
        logInfo "$fsinode"
        logSuccess "✅ Enough Inodes available"
    fi
    logInfo "----------------------------------------------------"
    logInfo "  Checking for Daemon "
    logInfo "----------------------------------------------------"
    outputContains "$(echo "$scaledaemon"|grep -v NAME|awk '{print $2}')" "rue" && { logInfo "$scaledaemon";logSuccess "✅ Daemon is in a correct status"; } || { logWarning "$scaledaemon";logWarning "⚠️  Status needs to be checked for Daemon";tf=1; }
    #logInfo "----------------------------------------------------"
    #logInfo "  Checking for CNSA/CSI pods "
    #logInfo "----------------------------------------------------"
    #querypods="$(echo $cnsapods|grep -Evi "completed|1/1|2/2|3/3|4/4|5/5|6/6|7/7|8/8|9/9|10/10|11/11|12/12|13/13|NAME")"
    #[[ -z "$querypods" ]] && logInfo "$cnsapods" || { logWarning "$querypods";tf=1; }
    checkPods "ibm-spectrum-scale"
    checkPods "ibm-spectrum-scale-csi"

    logInfo "----------------------------------------------------"
    logInfo "  Checking for Storage Classes for CP4D"
    logInfo "----------------------------------------------------"
    csiversion=$(oc -n ibm-spectrum-scale-csi get csiscaleoperators -ojsonpath='{.items[*].status.versions[*].version}')
    for line in $(oc describe sc|grep -E "^Name:|Parameters:"|tr -d '\n '|sed 's/Name:/\nName: /g;s/Parameters/ Parameters/g'|tr ' ' ';'|tail -n +2|sed 's/Name:;//g;s/Parameters://g')
    do
        scname=$(echo $line|awk -F ';' '{print $1}')
        parameters=$(echo $line|awk -F ';' '{print $2}')
        if [[ "$line" == *"permissions=777"* && $(echo $csiversion|awk -F '.' '{print $1}') -ge 2 && $(echo $csiversion|awk -F '.' '{print $2}') -ge 7 ]];then
            logWarning "⚠️  Storage Class: $scname contains the parameters permissions=777 but CSI version is above 2.7.x. Consider changing the parameter to shared:\"true\""
            
        elif [[ "$line" == *"permissions=777"* && $(echo $csiversion|awk -F '.' '{print $1}') -ge 2 && $(echo $csiversion|awk -F '.' '{print $2}') -le 6 ]];then
            logInfo "Storage Class: $scname contains the parameters permissions=777 and CSI version is $csiversion if youre installing CP4D this SC is a good candidate"
            
        elif [[ "$line" == *"shared=true"* && $(echo $csiversion|awk -F '.' '{print $1}') -ge 2 && $(echo $csiversion|awk -F '.' '{print $2}') -ge 7 ]];then
            logInfo "Storage Class: $scname contains the parameter shared=true and CSI version is $csiversion if youre installing CP4D this SC is a good candidate"
            sc_flag=1
        fi
    done
    [[ -z $sc_flag ]] && logWarning "⚠️  No storage class was found with the proper settings for CP4D. If you are installing this CloudPak make sure to create the proper SC for it"
    [[ $tf -eq 0 ]] && logSuccess "✅ Spectrum Scale is in a correct status" || logError "❌ Problems found in the Spectrum Scale instance"

}

function checkCpdPrereqs () {
    logTitle "========================================================"
    logTitle "================== CP4D Pre Checks ====================="
    logTitle "========================================================"
    # Checking PID limit
    logInfo "\n--> Checking PID limit"
    actual_pid_limit=$(oc -n openshift-machine-config-operator exec $(oc -n openshift-machine-config-operator get pods -owide|grep unning|grep -E $(oc get nodes|grep -i orker|head -n 1|awk '{print $1}')|head -n 1) -- cat /proc/sys/kernel/pid_max 2>/dev/null)
    if [ $actual_pid_limit -lt 16385 -a $actual_pid_limit  -gt 12288 ];then
        logWarning "Recommended PID limit value is 16384 or above specially for advanced DB2 operations, but for core installation is good enough"
        prflag=1
    elif [ $actual_pid_limit -lt 12288 ];then
        logError "Minimum recommended PID limit value is 12288, Please consider updating this value through an MCP update"
        prflag=2
    else
        logInfo "PID limit value is OK"
    fi
    logInfo "\n--> Checking SCC"
    [[ -z "$(oc get scc wkc-iis-scc 2>/dev/null)" ]] && { logWarning "⚠️  No wkc-scc was found in the cluster if youre planning to install WKC in your cpd instance, Please apply this prereq"; prflag=1; } || logInfo "WKC scc was found in the system"
    [[ -z "$(oc get scc informix-scc 2>/dev/null)" ]] && { logWarning "⚠️  No informix-scc was found in the cluster, cp4d v.4.6.0 and later requires this scc if youre planning to install Informix in your cpd instance,  If youre installing CP4D v4.6.0 or later please apply this prereq, if not please omit this message";prflag=1; } || logInfo "IIS scc was found in the system"
    logInfo "\n--> Checking required node settings"
    logHighlight "NOTE: if youre installing WKC you need to setup some parameters in the cpd-cli command please refer to the following info:"
    logHighlight '''On your client workstation, create a file called install-options.yml in the cpd-cli-workspace/olm-utils-workspace/work directory with the following content:
custom_spec:
  wkc:
    wkc_db2u_set_kernel_params: True
    iis_db2u_set_kernel_params: True

When you run the apply-cr command to install Watson Knowledge Catalog, specify --param-file=/tmp/work/install-options.yml.
'''
    if [[ $prflag -eq 2 ]];then
        logError "❌ There are some configuration missing that are required for the cp4d installation check the output above for more information"
    elif [[ $prflag -eq 1 ]];then
        logWarning "⚠️  There are some configuration that may be needed for some services, Please check if the services you plan to install require them"
    else 
        logSuccess "✅ All CP4D prereqs were found, Please proceed with your installation"
    fi
}

function checkOpenshift () {
    
    checkClusterVersionStatus
    checkNodesStatus
    checkClusterOperators
    checkMcpUpdates
    checkNodesCpuMemRequests
    checkNodesCpuMemUsg
    checkNodesDiskPressure
    checkNodesPIDPressure
    ### cannot do this since clockdiff is not a common utility - nor is sudo always permitted
    ###checkNodeTimeDifference
    
}
function checkAllCpd () {
    checkCpdPrereqs
    checkCpd
}

function checkAll () {
    #myf2=$(declare -F)  
    #myf3=$(echo "$myf2"|grep check|grep -Ev "checkOpenshift|checkAll|checkPods"|awk '{print $3}')
    #for fcheck in $myf3
    #do 
    #    $fcheck
    #done
    checkOpenshift
    checkScaleStatus
    checkAllCpd

}

function checkCpd () {
    logTitle "========================================================"
    logTitle "================== CP4D  Check ====================="
    logTitle "========================================================"
    namespaces=$(oc get ns)
    checkCatSrcStatus "openshift-marketplace"
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
        checkPods $project
        [[ "$project" != "ibm-common-services" && "$project" != "cpd-operators" ]] && checkCpdCrdStatus $project
        [[ "$project" == "ibm-common-services" || "$project" == "cpd-operators" ]] && checkCsvStatus $project
    done

    
    [[ -z $tflag ]] && logSuccess "✅ Any resource was found in a bad state" || logWarning "Resources found that might need to be investigated"

}

function checkPods () {
    namespace=$1
    if [[ -z $namespace ]];then
        logInfo "[NOTE]: Namespace was not provided,assuming current namespace\n"
        notreadypods=$(oc get po --no-headers -o wide| grep -Ev '([[:digit:]])/\1.*R' | grep -v 'Completed'|tr ' ' ';')
        logTitle "========================================================"
        logTitle "> Checking Pods at current namespace                    "
        logTitle "========================================================"
        logInfo "[Checking Pods at current Namespace]"
        unset allflag
    elif [[ $namespace == "all" ]];then
        notreadypods=$(oc get po --no-headers --all-namespaces -o wide| grep -Ev '([[:digit:]])/\1.*R' | grep -v 'Completed'|tr ' ' ';')
        logTitle "========================================================"
        logTitle ">  Checkind pods on all namespaces                      "
        logTitle "========================================================"
        logInfo "[Checking Pods on all namespaces]"
        allflag=1
    else
        notreadypods=$(oc get po --no-headers --all-namespaces -o wide| grep -Ev '([[:digit:]])/\1.*R'|grep -E "^$namespace "| grep -v 'Completed'|tr ' ' ';')
        logTitle "========================================================"
        logTitle ">     Checkind pods at $namespace                       "
        logTitle "========================================================"
        logInfo "[Checking Pods at $namespace]"
        allflag=1
    fi 
    for pod in $notreadypods
    do
        tempod=$(echo $pod|tr ';' ' ')
        if [[ "$tempod" == *"rash"* || "$tempod" == *"rror"* || "$tempod" == *"ackOff"* ]];then
            logError "$tempod"
            [[ -z $allflag ]] && failedpods+="$(echo $tempod|awk '{print $1}')"$'\n' || failedpods+="$(echo $tempod|awk '{print $1","$2}')"$'\n'  
            #failedpods+="$(echo $tempod|awk '{print $1","$2}') "
            tflag=2
        elif [[ "$tempod" == *"unning"* || "$tempod" == *"nit"* && $(echo $tempod|awk '{print $2}'|awk -F '/' '{print $1}') != $(echo $tempod|awk '{print $2}'|awk -F '/' '{print $2}') ]];then
            logWarning "$tempod"
            [[ -z $allflag ]] && failedpods+="$(echo $tempod|awk '{print $1}')"$'\n' || failedpods+="$(echo $tempod|awk '{print $1","$2}')"$'\n'  
            #failedpods+="$(echo $tempod|awk '{print $1","$2}') "
            tflag=2
        else
            logInfo "$tempod"
        fi 
    done
    if [[ ! -z $debug ]];then 
        if [[ ! -z $failedpods ]]; then
            highlightText "-------------------------------------------------"
            highlightText "|                    DEBUG                      |"
            highlightText "-------------------------------------------------"
            PS3=$'\n[Hit enter to see the options again or select the number of the POD you want to choose:] >>  '
            IFS=$'\n'
            select answer in ${failedpods[@]}"exit"
            do
                if [[ $answer == "exit" ]]; then
                        break
                fi
                for item in ${failedpods[@]}"exit"
                do   
                    if [[ $item == $answer ]]; then
                        highlightText "User has selected : $answer"
                        podnamespace=$(echo $answer|awk -F ',' '{print $1}')
                        podname=$(echo $answer|awk -F ',' '{print $2}')                     
                        PS3=$'\n[Hit enter to see the options again or select the number of the COMMAND you want to choose:] >>  '
                        select x in "podDescription" "podLogs" "previousPodLogs" "operatorLogs [These option takes some minutes to find the operator]" "exit"
                        do
                            highlightText "User has selected : $x"
                            if [[ $x == "podDescription" ]]; then
                                checkDescription "pod" $podname $podnamespace                          
                            elif [[ $x == "podLogs" ]]; then
                                checkFailedPodLogs $podname $podnamespace
                            elif [[ $x == "previousPodLogs" ]]; then
                                checkFailedPodLogs $podname $podnamespace "-p"                          
                            elif [[ $x == *"operatorLogs"* ]]; then
                                checkFailedPodOperatorLogs $podname $podnamespace
                            elif [[ $x == "exit" ]]; then
                                PS3=$'\n[Hit enter to see the options again or select the number of the POD you want to choose:] >>  '
                                break                           
                            fi
                        done
                        break
                        #checkFailedPodLogs $podname $podnamespace
                        #checkFailedPodOperatorLogs $podname $podnamespace
                    fi
                done
            done;unset IFS
        fi
    fi
    # if [[ ! -z $debug ]];then 
    #     for pod in $failedpods
    #     do
    #             podnamespace=$(echo $pod|awk -F ',' '{print $1}')
    #             podname=$(echo $pod|awk -F ',' '{print $2}')
    #             checkFailedPodLogs $podname $podnamespace
    #             checkFailedPodOperatorLogs $podname $podnamespace
    #     done
    # fi

    [[ -z $tflag ]] && logSuccess "✅ No pods were found in a bad state" || logWarning "⚠️  Pods found that might need to be investigated"
    
}

function checkFailedPodLogs() {
    pod=$1
    namespace=$2
    previousflag=$3
    #echo $pod
    #echo $namespace
    [[ -z $pod ]] && { logWarning "Pod was not provided, exiting";return 1; }
    #pod="baas-transaction-manager-594745786f-5lb5n"
    if [[ -z $namespace ]];then
        logTitle "========================================================"
        logTitle "> POD: $pod                                             "
        logTitle "========================================================"
        podcontainers=$(oc get pod $pod -oyaml|grep -A500 containerStatuses|sed -n -e '/name:/,/\(reason\|startedAt\)/ p')
    else
        logTitle "========================================================"
        logTitle "> POD: $pod namespace: $namespace                       "
        logTitle "========================================================"
        podcontainers=$(oc -n $namespace get pod $pod -oyaml|grep -A500 containerStatuses|sed -n -e '/name:/,/\(reason\|startedAt\)/ p')
    fi
    IFS=$'\n'
    failedcontainers=''
    #echo "$podcontainers"
    for line in $podcontainers
    do  
        containerstatus='' 
        [[ "$line" == *"name:"* ]] && containername=$(echo $line|awk '{print $2}')
        [[ "$line" == *"ready:"* ]] && containerstatus=$(echo $line|awk '{print $2}')
        if [[ $containerstatus == "false" ]];then
            if [[ -z $namespace ]];then
                failedcontainers+="oc logs $pod -c $containername $previousflag|less -R"$'\n'
            else
                failedcontainers+="oc -n $namespace logs $pod -c $containername $previousflag|less -R"$'\n'
            fi
        fi
    done
    [[ -z $failedcontainers ]] && { logSuccess "All containers in the pod $pod are in a correct status. Nothing to persue";return 0; }
    unset IFS
    # for container in $failedcontainers
    # do
    #     logHighlight "\n[Printing debug information on logs for pod $pod and container $container. Note: Only printing the latest 30 lines in the log]"
    #     logInfo "...."
    #     logInfo ".."
    #     logInfo "."
    #     if [[ -z $namespace ]];then
    #         logInfo "$(oc logs $pod -c $container --tail=30)"
    #     else
    #         logInfo "$(oc -n $namespace logs $pod -c $container --tail=30)"
    #     fi
    # done
    #echo FD: $failedcontainers
    echo
    echo
    latestPS3=$PS3
    PS3=$'\n[Hit enter to see the options again or select the number of the CONTAINER LOGS you want to choose:] >>  '
    IFS=$'\n'
    select answer in ${failedcontainers[@]}"exit"
    do        
        highlightText "User has selected: $answer"
        if [[ $answer == *"exit"* ]]; then
                PS3=$'\n[Hit enter to see the options again or select the number of the COMMAND you want to choose:] >>  '
                break
        fi
        for item in ${failedcontainers[@]}"exit"
        do   
            if [[ $item == $answer ]]; then
            #echo $answer|awk '{print $2}'
            #echo $answer|awk '{print $4}'
                # if [[ -z $namespace ]];then
                #     oc logs $(echo $answer|awk '{print $2}') -c $(echo $answer|awk '{print $4}') $previousflag|less -R
                # else
                #     oc -n $namespace logs $(echo $answer|awk '{print $2}') -c $(echo $answer|awk '{print $4}') $previousflag|less -R
                # fi        
                bash -c "$answer"    
            fi
        done

    done;unset IFS
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
            crdline=$(oc get $ar --ignore-not-found  --no-headers -oyaml|grep -E "^    name:|Status"|tr -d '\n'|sed 's/name:/\nname:/g'|column -t)
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
            crdline=$(oc -n $namespace get $ar --ignore-not-found  --no-headers -oyaml|grep -E "^    name:|Status"|tr -d '\n'|sed 's/name:/\nname:/g'|column -t)
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

function checkCsvStatus () {
    namespace=$1
    local tflag
    if [[ -z $namespace ]];then
        logInfo "[NOTE]: Namespace was not provided,assuming all namespace\n"
        csvstatuscheck=$(oc get csv --no-headers -A|tr ' ' ';')
        logTitle "========================================================"
        logTitle "========== Checking CSVs at all namespaces ============="
        logTitle "========================================================"
    else
        logTitle "========================================================"
        logTitle "========== Checking CSVs at $namespace     ============="
        logTitle "========================================================"
        csvstatuscheck=$(oc -n $namespace get csv --no-headers|tr ' ' ';')
    fi
    
    logInfo "[Checking CSVs]" 
    for csv in $csvstatuscheck
    do        
        tempcsv=$(echo $csv|tr ';' ' ')
        if [[ "$tempcsv" != *"ucceeded"* ]];then
            logWarning "$tempcsv"
            tflag=2
        else
            logInfo "$tempcsv"
        fi 
    done
    [[ -z $tflag ]] && logInfo "\nNo csv were found in a bad state\n" || logWarning "\nCSVs found that might need to be investigated\n"
}

function checkCatSrcStatus () {
    namespace=$1
    if [[ -z $namespace ]];then
        logInfo "[NOTE]: Namespace was not provided,assuming openshift-marketplace namespace\n"
        namespace="openshift-marketplace"
    fi
    catsrcstatuscheck=$(oc -n $namespace describe catsrc|grep -E "^Name:|Last Observed State"|tr -d '\n'|sed 's/Name/\nName/g'|tail -n +2|column -t|tr ' ' ';')
    logInfo "[Checking CatSrc]" 
    for cs in $catsrcstatuscheck
    do        
        tempcs=$(echo $cs|tr ';' ' ')
        if [[ "$tempcs" != *"READY"* ]];then
            logWarning "$tempcs"
            tflag=2
        else
            logInfo "$tempcs"
        fi 
    done
    [[ -z $tflag ]] && logInfo "\nNo catsrc were found in a bad state\n" || logWarning "\CatSrc found that might need to be investigated\n"
}

function checkDescription(){    
    resource=$1
    resourcename=$2    
    namespace=$3
    unset IFS
    [[ -z $resourcename ]] && echo "Assuming all"
    if [[ -z $namespace ]];then
        logInfo "[NOTE]: Namespace was not provided,assuming current namespace\n"
        logTitle "========================================================"
        logTitle "> $resource $resourcename"
        logTitle "========================================================"        
        describeoutput=$(oc describe $resource $resourcename)
    else
        logTitle "========================================================"
        logTitle "> $resource $resourcename Namespace: $namespace"
        logTitle "========================================================"
        describeoutput=$(oc -n $namespace describe $resource $resourcename)
    fi
    echo "$describeoutput"|less -R
        
}

function checkFailedPodOperatorLogs(){
    highlightText "-------------------------------------------------"
    highlightText "|                    DEBUG                      |"
    highlightText "-------------------------------------------------"
    highlightText "Looking for operator pod this can take a few minutes"
    failedpod=$1
    [[ -z $failedpod ]] && { logInfo "[Pod not provided,Exiting...]";return 1; }
    unset podscontaining
    unset fl
    unset IFS
    spin='-\|/'
    #operatorproject="ibm-common-services"
    for operatorproject in $(oc get operatorgroups -A --no-headers|awk '{print $1}')
    do
        #operatorname=$(echo $operator|awk -F '.' '{print $1}')
        #operatorproject=$(echo $operator|awk -F '.' '{print $2}')
        #echo ONAME: $operatorname
        #echo LOOKING FOR FAILED POD OPERATOR AT: $operatorproject
        for pod in $(oc -n $operatorproject get pods --no-headers|awk '{print $1}') 
        do 
            i=$(( (i+1) %4 ))
            printf "\rSearching operator pod... ${spin:$i:1}"
            #echo POD:$pod
            [[ -z $(oc -n $operatorproject describe pod $pod|grep olm.operatorGroup) ]] && continue #|| echo "$pod is an operatorPod"
            #Getting containers of operator pod
            containersnames=$(oc -n $operatorproject get pod $pod -ojsonpath='{.spec.containers[*].name}')
            for container in $containersnames
            do
                containerlogs="$(oc -n $operatorproject logs $pod -c $container)"
                #if [[ "$containerlogs" == *"$failedpod"* ]]; then
                if [[ ! -z $(echo $containerlogs|grep "\<$failedpod\>") ]]; then
                    #echo "containerlogs: $containerlogs"
                    #echo "FOUND OPERATOR POD : $pod"
                    #podscontaining+="NS: $operatorproject POD: $pod CONTAINER: $container"$'\n'
                    podscontaining+="oc -n $operatorproject logs $pod -c $container"$'\n'
                    #echo "$containerlogs"|grep -A 20 -B 20 -Ei "fail|error|$pod"
                    fl=1
                    break
                fi
            done
        done
        [[ ! -z $fl ]] && break
    done
    [[ -z $fl ]] && { echo "Operator not found";unset fl;return 0; } 
    echo "\r"
    echo "The pod was found in the following operator pod/containers"
    echo
    PS3=$'\n[Hit enter to see the options again or select the number of the OPERATOR LOGS you want to choose:] >>  '
    IFS=$'\n'
    select answer in ${podscontaining[@]}"exit"
    do
        if [[ $answer == "exit" ]]; then
                PS3=$'\n[Hit enter to see the options again or select the number of the COMMAND you want to choose:] >>  '
                break
        fi
        for item in ${podscontaining[@]}"exit"
        do   
            if [[ $item == $answer ]]; then
            #echo $answer|awk '{print $2}'
            #echo $answer|awk '{print $4}'
            #echo "EXECUTING $answer"
            bash -c "$answer"|less -R
            #oc -n $(echo $answer|awk '{print $2}') logs $(echo $answer|awk '{print $4}') -c $(echo $answer|awk '{print $6}')|less -R 
            fi
        done
    done;unset IFS
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

