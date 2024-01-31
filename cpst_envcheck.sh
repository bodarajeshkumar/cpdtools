#!/usr/bin/bash
# Abstract:
#  Meant for OpenShift environments running CloudPaks with an emphasis on Spectrum Scale.
#  Gathers the high level details and versions of the various pieces of the cluster environment.
#  Note: During CloudPak info collection, it may take a minute or two (it is not hanging, just
#        running a lot of oc cli commands.
# Author: Todd Tosseth
# Version: 1 - 23-Mar-2022 - Initial creation
# Version: 2 - 23-Mar-2022 - Ignored another operator ibm-common-services when checking CloudPak services.
# Version: 3 - 23-Mar-2022 - Fixed a few more small bugs.
# Version: 4 - 28-Mar-2022 - Fixed isScaleRemote check.
# Version: 5 - 19-Apr-2022 - Display remote scale gui host. Check other possible fusion namespaces.
# Version: 6 - 03-May-2022 - Fix looping through operators and the services within.
# Version: 7 - 25-May-2022 - Look for operators in ibm-common-services and cpd-operators.
# Version: 8 - 19-January-2023 - Get information about ODF clusters

# Makes debugging easier 
# To use, run TRACE=1 ./cpst_envcheck.sh
if [[ "${TRACE-0}" == "1" ]]; then
  set -o xtrace
fi

#--- Global vars ---#
OPERATORS_NS="ibm-common-services"
DEBUG="FALSE"
SPECTRUM_FUSION_NS="ibm-spectrum-fusion-ns"
ODF_NS="openshift-storage"


#--- Function: Is OCP login valid (return bool) ---#
isOcpLoggedIn()
{
  loginCheck=$(oc whoami 2>/dev/null)
  rc=$?
  if (( rc == 0 ))
  then
    return 1
  else
    return 0
  fi
}

#--- Function: Get server name ---#
getServerName()
{
  echo "$(oc whoami --show-server)"
}

#--- Function: Get openshift console ---#
getOcpConsole()
{
  console=$(oc get route console -n openshift-console -o jsonpath='{.spec.host}')
  targetPort=$(oc get route console -n openshift-console -o jsonpath='{.spec.port.targetPort}')
  consoleUrl="${targetPort}://${console}"
  echo "$consoleUrl"
}

#--- Function: Get openshift version ---#
getOcpVersion()
{
  ocVersion=$(oc version 2> /dev/null)
  if [[ "$?" -ne 0 ]]
  then
    echo "Failed to get oc version"
    return 1
  fi

  serverVersion="$(oc version 2>/dev/null |grep Server |awk '{print $NF}')"
  kubeVersion="$(oc version 2>/dev/null |grep Kubernetes |awk '{print $NF}')"
  echo "${serverVersion} (Kubernetes: ${kubeVersion})"
  return 0
}

#--- Function: Get nodes (return array) ---#
#    Input: 'master' or 'worker' to get that type.
getTypeNodes()
{
  declare -n nodeArray="$1"
  declare typeIn=$2
  declare labelCheck=""

  if [[ "$typeIn" == "master" ]]
  then
    labelCheck="node-role.kubernetes.io/master="
  elif [[ "$typeIn" == "worker" ]]
  then
    labelCheck="node-role.kubernetes.io/worker="
  else
    echo "Unknown node type to get"
    return 1
  fi

  nodes=$(oc get nodes -l $labelCheck --no-headers 2>&1)
  rc=$?

  for node in $(echo "$nodes" | awk '{print $1}')
  do
    nodeArray[$node]=$node
  done

  return $rc
}

#--- Function: Get memory capacity for given node ---#
getNodeMem()
{
  declare nodeIn=$1
  memOut=$(oc get node $nodeIn -o jsonpath='{.status.capacity.memory}' 2>&1 )
  rc=$?
  echo "$memOut"
  return $rc
}

#--- Function: Get cpu capacity for given node ---#
getNodeCpu()
{
  declare nodeIn=$1
  cpuOut=$(oc get node $nodeIn -o jsonpath='{.status.capacity.cpu}' 2>&1 )
  rc=$?
  echo "$cpuOut"
  return $rc
}

#--- Function: Is Scale deployed (return bool) ---#
isScaleDeployed()
{
  oc get project ibm-spectrum-scale >/dev/null 2>&1
  scaleProjRC=$?
  oc get project ibm-spectrum-scale-csi >/dev/null 2>&1
  scaleCsiProjRC=$?
  declare -i scaleDaemons=$(oc get daemons.scale.spectrum.ibm.com -n ibm-spectrum-scale 2>/dev/null |wc -l)
  declare -i scalePods=$(oc get pod -n ibm-spectrum-scale --no-headers 2>/dev/null |wc -l)
  declare -i scaleCsiPods=$(oc get pod -n ibm-spectrum-scale-csi --no-headers 2>/dev/null |wc -l)

  if (( scaleProjRC == 0 && scaleCsiProjRC == 0 && scaleDaemons > 0 && scalePods > 0 && scaleCsiPods > 1 ))
  then
    return 1
  else
    [[ "$DEBUG" == "TRUE" ]] && echo "[D] Scale not deployed: scaleProjRC=$scaleProjRC, scaleCsiProjRC=$scaleCsiProjRC, scaleDaemons=$scaleDaemons, scalePods=$scalePods, scaleCsiPods=$scaleCsiPods"
    return 0
  fi
}


#--- Function: Is Scale local or remote attached ---#
isScaleRemote()
{
  remoteclusters=$(oc get remoteclusters -n ibm-spectrum-scale 2>/dev/null)
  rc=$?
  if [[ -n "$remoteclusters" ]]
  then
    return 1
  else
    return 0
  fi
}

#--- Function: Get Scale file system name (local or remote) ---#
getScaleFs()
{
  declare scope=$1
  if [[ "$scope" == "local" ]]
  then
    oc get filesystems -n ibm-spectrum-scale --no-headers |awk '{print $1}' |head -1
  elif [[ "$scope" == "remote" ]]
  then
    oc get filesystems -n ibm-spectrum-scale $(getScaleFs "local") -o jsonpath='{.spec.remote.fs}'
  fi
}


#--- Function: Get remote cluster GUI hostname ---#
getRemoteGuiHost()
{
  guihost=$(oc get remotecluster -n ibm-spectrum-scale -o jsonpath='{.items[].spec.gui.host}')
  rc=$?
  if (( rc == 0 ))
  then
    echo "$guihost"
  fi
  return $rc
}


#--- Function: Get all Scale CSI based storage classes (return in input array) ---#
getScaleStorageClasses()
{
  declare -n storageClasses="$1"
  for sc in $(oc get sc -o jsonpath='{.items[?(.provisioner=="spectrumscale.csi.ibm.com")].metadata}' |jq -r '.name')
  do
    storageClasses[$sc]=$sc
  done
}

#--- Function: Get a Scale core pod name ---#
getScaleCorePod()
{
  oc get pod -o name -l app.kubernetes.io/name=core -n ibm-spectrum-scale |head -1
}

#--- Function: Get Scale CNSA version ---#
getScaleCnsaVersion()
{
  declare scaleVersion=""
  declare scaleRelease=""

  scaleConfigLogsOut=$(oc logs $(getScaleCorePod) -n ibm-spectrum-scale config 2>&1)
  scaleRC=$?

  if (( scaleRC != 0 ))
  then
    echo "Unknown"
    return $scaleRC
  fi

  IFS_sv=$IFS
  IFS=$'\n'
  for configLine in $(echo "$scaleConfigLogsOut")
  do
    [[ "$configLine" =~ "GPFS Version:" ]] && scaleVersion=$(echo "$configLine" |awk '{print $NF}')
    [[ "$configLine" =~ "GPFS Release:" ]] && scaleRelease=$(echo "$configLine" |awk '{print $NF}')
  done
  IFS=$IFS_sv #restore

  if [[ -n $scaleVersion && -n $scaleRelease ]]
  then
    scaleVersionRelase="${scaleVersion}.${scaleRelease}"
    echo "$scaleVersionRelase"
    return 0
  else
    echo "Unknown VR"
    return 1
  fi
}


#--- Function: Get Scale CSI version ---#
getScaleCsiVersion()
{
  csiPod=$(oc get pods -n ibm-spectrum-scale-csi -l app.kubernetes.io/name=ibm-spectrum-scale-csi-operator --no-headers 2>/dev/null |head -1 |awk '{print $1}')
  csiProductVersion=$(oc get pod $csiPod -n ibm-spectrum-scale-csi -o jsonpath={.metadata.annotations.productVersion} 2>/dev/null)
  rc=$?
  if (( rc == 0 ))
  then
    echo "$csiProductVersion"
    return 0
  else
    echo "Unknown"
    return $rc
  fi
}


#--- Function: Get file system status. Return in the input array. ---#
getScaleFsStats()
{
  declare -n statsArray="$1"
  declare fsIn="$2"
  #Example output of below command: remote-sample  1000G   28G  973G   3% /mnt/remote-sample
  fsStatsOut=$(oc exec -it $(getScaleCorePod) -n ibm-spectrum-scale -c gpfs -- sh -c "df -h |grep \"^${fsIn}\"")
  statsRc=$?

  if (( statsRc == 0 ))
  then
    statsArray["fsName"]=$(echo "$fsStatsOut" | awk '{print $1}')
    statsArray["capacity"]=$(echo "$fsStatsOut" | awk '{print $2}')
    statsArray["used"]=$(echo "$fsStatsOut" | awk '{print $3}')
    statsArray["free"]=$(echo "$fsStatsOut" | awk '{print $4}')
    statsArray["percentUsed"]=$(echo "$fsStatsOut" | awk '{print $5}')
    statsArray["mntPath"]=$(echo "$fsStatsOut" | awk '{print $6}')
    return 0
  else
    return 1
  fi
}


#--- Function: Check if this is a Fusion Cluster ---#
isFusionCluster()
{
  hasFusionProject=$(oc get project $SPECTRUM_FUSION_NS 2>/dev/null)
  fusionProjRC=$?
  if (( fusionProjRC != 0 ))
  then
    otherFusionProj=$(oc get project 2>/dev/null |grep fusion-ns |head -1 |awk '{print $1}')
    if [[ -n $otherFusionProj ]]
    then
      SPECTRUM_FUSION_NS=$otherFusionProj
    else
      return 0
    fi
  fi

  declare -i fusionNsPodsCount
  fusionNsPodsCount=$(oc get pod -n $SPECTRUM_FUSION_NS --no-headers 2>/dev/null |wc -l)
  [[ "$DEBUG" == "TRUE" ]] && echo "[D] fusionNsPodsCount '$fusionNsPodsCount'"
  if (( fusionNsPodsCount > 0 ))
  then
    return 1
  else
    return 0
  fi

  return 0
}


#--- Function: Get Spectrum Fusion version ---#
getSpectrumFusionVersion()
{
  declare fusionUiOpPod=$(oc get pod -l control-plane=isf-ui-operator --no-headers -n $SPECTRUM_FUSION_NS 2>/dev/null |awk '{print $1}')
  [[ "$DEBUG" == "TRUE" ]] && echo "[D] fusionUiOpPod='$fusionUiOpPod'"
  if [[ -z "$fusionUiOpPod" ]]
  then
    echo "Unknown"
    return 1
  fi

  fusionVersion=$(oc get pod $fusionUiOpPod -n $SPECTRUM_FUSION_NS -o jsonpath='{.metadata.annotations}' |jq -r '."operatorframework.io/properties"' |jq -r '.properties[] | select(.type=="olm.package") |.value.version')
  rc=$?
  if (( rc == 0 ))
  then
    echo "$fusionVersion"
  else
    echo "Unknown (operatorframework)"
  fi
  return $rc
}


#--- Function: old Get Spectrum Fusion version ---#
getSpectrumFusionVersionOld()
{
  declare computefirmwares=$(oc get computefirmwares -n $SPECTRUM_FUSION_NS --no-headers 2>/dev/null |head -1)
  if [[ -z "$computefirmwares" ]]
  then
    echo "Unknown"
    return 1
  fi

  fusionVersion=$(oc get computefirmwares $computefirmwares -n $SPECTRUM_FUSION_NS -o jsonpath='{.status.currentFirmwareVersion}' 2>/dev/null)
  rc=$?
  if (( rc == 0 ))
  then
    echo "$fusionVersion"
  else
    echo "Unknown"
  fi
  return $rc
}

#--- Function: Get Fusion type: HCI vs SDS ---#
#    Warning: This function is wonky!!
#    rc non-zero if unable to detect
getSpectrumFusionType()
{
  declare fusionType=""

  #Check the Spectrum Fusion ui operator "env" annotation, if it exists:
  declare fusionUiOpPod=$(oc get pod -l control-plane=isf-ui-operator --no-headers -n $SPECTRUM_FUSION_NS 2>/dev/null |awk '{print $1}')
  rc=$?
  if [[ -n "$fusionUiOpPod" && "$rc" -eq 0 ]]
  then
    tmpType=$(oc get pod $fusionUiOpPod -n $SPECTRUM_FUSION_NS -o jsonpath='{.metadata.annotations.environment}' 2>/dev/null)
    rc=$?
    if [[ -n "$tmpType" && "$rc" -eq 0 ]]
    then
      #Found Fusion type in env annotation. Done.
      fusionType=${tmpType^^} #Make upper case
      echo "$fusionType"
      return 0
    fi
  fi

  #Now check in the isf node label, if it exists
  getIsfLabeledNode=$(oc get node -l storage.isf.ibm.com/cluster --no-headers 2>/dev/null |awk '{print $1}' |head -1)
  rc=$?
  if [[ -n "$getIsfLabeledNode" && "$rc" -eq 0 ]]
  then
    tmpType=$(oc get node $getIsfLabeledNode -o jsonpath='{.metadata.labels.storage\.isf\.ibm\.com/cluster}' 2>/dev/null)
    rc=$?
    if [[ -n "$tmpType" && "$rc" -eq 0 ]]
    then
      #Found Fusion type in node label. Done.
      fusionType=${tmpType^^} #Make upper case
      echo "$fusionType"
      return 0
    fi
  fi

  #Made it here but didn't find it. Time to return.
  return 1
}


#--- Function: Get Spectrum Protect Plus client version ---#
getSppClientVersion()
{
  baasSppAgentPod=$(oc get pod -l app.kubernetes.io/component=spp-agent -n baas -o name 2>/dev/null)
  rc=$?
  if [[ -z "$baasSppAgentPod" || "$rc" -ne 0 ]]
  then
    echo "Unknown"
    return 1
  fi

  sppClientVersion=$(oc get $baasSppAgentPod -n baas -o jsonpath='{.metadata.annotations.productVersion}' 2>/dev/null)
  rc=$?
  if [[ -n "$sppClientVersion" && "$rc" -eq 0 ]]
  then
    echo "$sppClientVersion"
    return 0
  else
    echo "Unknown ver"
    return 1
  fi
}

#--- Function: Get bedrock common services version ---#
getCommonServicesVersion()
{
  csCsv=$(oc get csv -n ibm-common-services --no-headers 2>&1 |grep ibm-common-service-operator | awk '{print $1}')
  if [[ -z "$csCsv" ]]
  then
    echo "Unknown"
    return 1
  fi

  csVersion=$(oc get csv ${csCsv} -n ibm-common-services -o jsonpath='{.spec.version}' 2>/dev/null)
  csRc=$?
  if (( csRc == 0 ))
  then
    echo "$csVersion"
  else
    echo "Unknown."
  fi
  return $csRc
}

#--- Function: Check if ODF is deployed, return bool ---#
isODFDeployed()
{
  oc get project ${ODF_NS} >/dev/null 2>&1
  odfNsRc=$?
  odfPodNum=$(oc get -n ${ODF_NS} --no-headers pods 2>/dev/null | wc -l)
  odfCsvNum=$(oc get -n ${ODF_NS} --no-headers csv 2>/dev/null | wc -l)
  if [[ ${odfNsRc} -eq 0 && ${odfPodNum} -gt 0 && ${odfCsvNum} -gt 0 ]]; then
    return 1
  else
    return 0
  fi
}

#--- Function: Get version of ODF operator ---#
getODFVersion()
{
  odfCsv=$(oc get csv -n ${ODF_NS} 2>&1 | grep odf-operator | awk '{print $1}')
  if [[ -z "$odfCsv" ]]; then
    echo "Unknown"
    return 1
  fi
  odfVersion=$(oc get csv -n ${ODF_NS} ${odfCsv} -o jsonpath='{.spec.version}' 2>&1)
  echo "${odfVersion}"
  return 0
}

#--- Function: Get storage classes using ODF as provisioner ---#
ODFStorageClasses()
{
#  namerefs not available in bash 4.2 (highest version on RHEL7), trying another way
#  declare -n storageClasses="$1"
  for sc in $(oc get sc -o json | jq -r '.items[] | select (.provisioner | contains("openshift-storage")) | .metadata.name'); do
     echo -n "$sc "
  done
  echo ""
}

#--- Function: Utility to convert 1st argument from bytes to gigabytes ---#
convertBytesToGb()
{
  declare bytes="$1"
  echo $(expr ${bytes} / 1000000000)
}

#--- Function: Get info about Ceph clusters ---#
getCephClusters()
{
  clusters=$(oc get cephcluster -n ${ODF_NS} --no-headers | awk '{ print $1 }')
  for c in ${clusters}; do
    clinfo=$(oc get cephcluster -n ${ODF_NS} ${c} -o json 2>&1)
    rc=$?
    if [[ rc -gt 0 ]]; then
      return 1
    else
      cephVer=$(echo ${clinfo} | jq -r '.status.version.version')
      health=$(echo ${clinfo} | jq -r '.status.ceph.health')

      totalCap=$(echo ${clinfo} | jq -r '.status.ceph.capacity.bytesTotal')
      totalCapGb=$(convertBytesToGb ${totalCap})
      usedCap=$(echo ${clinfo} | jq -r '.status.ceph.capacity.bytesUsed')
      usedCapGb=$(convertBytesToGb ${usedCap})
      availCap=$(echo ${clinfo} | jq -r '.status.ceph.capacity.bytesAvailable')
      availCapGb=$(convertBytesToGb ${availCap})
      percentage=$(( 100 * ${usedCap} / ${totalCap}))
      echo "  - Name: ${c}" 
      echo "  - Version: ${cephVer}"
      echo "  - Status: ${health}"
      echo "  - Capacity: ${totalCapGb} [Used: ${usedCapGb}G (${percentage}%) | Free: ${availCapGb}G]"
    fi
  done
  return 0
}

#--- Function: Print out compiled ODF information ---#
printODFInformation()
{
  echo "OpenShift Data Foundation"
  isODFDeployed
  rc=$?
  if [[ ${rc} -gt 0 ]]; then
    odfVersion=$(getODFVersion)
    echo "- ODF Version: ${odfVersion}"
    # TODO: get noobaa version
    echo "- Ceph Clusters:"
    getCephClusters
    sc=$(ODFStorageClasses)
    echo "- ODF Storage Classes: ${sc}"
  else
    echo "ODF not deployed"
  fi
}

#--- Function: Get the operators running in ibm-common-services. Return via input array. ---#
getCommonServicesOperators()
{
  declare -n operators="$1"
  declare nspace="$2"

  nspace_check=$(oc get project $nspace 2>/dev/null)
  if [[ "$?" -ne 0 ]]
  then
    [[ "$DEBUG" == "TRUE" ]] && echo "Namespace $nspace does not exist"
    return
  fi

  csvs=$(oc get csv -n $nspace --no-headers 2>/dev/null |awk '{print $1}' |grep -v -e "ibm-common-service-operator" -e "ibm-cert-manager-operator" -e "ibm-namespace-scope-operator" -e "operand-deployment-lifecycle-manager" -e "ibm-licensing-operator" -e "ibm-healthcheck-operator")
  for csv in $csvs
  do
    operator_label=$(oc get csv $csv -n $nspace -o jsonpath='{.metadata.labels}' |jq '.' |grep operators.coreos.com |awk -F\" '{print $2}' |awk -F/ '{print $2}')
    #Comment this line. Don't remove suffix now: operator_label=$(echo "$operator_label" | awk -F. '{print $1}')
    [[ "$DEBUG" == "TRUE" ]] && echo "[D] csv='$csv', operator_label='$operator_label'"
    if [[ -n "$operator_label" ]]
    then
      operators["$operator_label"]="$operator_label"
    fi
  done

  [[ "$DEBUG" == "TRUE" ]] && echo "[D] nspace: $nspace, operators: '${operators[*]}'"
  #for operator in $(oc get csv -n ibm-common-services --no-headers 2>/dev/null |grep -v -e "ibm-common-service-operator" -e "ibm-cert-manager-operator" -e "ibm-namespace-scope-operator" -e "operand-deployment-lifecycle-manager" |awk '{print $1}' |awk -F. '{print $1}')
  #do
  #  operators["$operator"]="$operator"
  #done

}


#--- Function: Go through all installed csvs/operators and find their crds and get the installed instances of them ---#
compileCloudPakServices()
{
  declare -n nsListAA="$1"
  declare -n operatorsA="$2"
  declare -n crdA="$3"
  declare -n kindA="$4"
  declare -n namespaceA="$5"
  declare -n nameA="$6"
  declare -n versionA="$7"

  #-Get operators-#
  declare -A csOps
  getCommonServicesOperators csOps "ibm-common-services"
  getCommonServicesOperators csOps "cpd-operators"

  #-Loop through operators, looking for their owned crds, then find all services deployed from those crds-#
  let serviceCounter=0
  for operator in ${csOps[@]}
  do
    [[ "$DEBUG" == "TRUE" ]] && echo "[D] -------------------- loop operator='$operator' --------------------"
    #for crd in $(oc get crd -l operators.coreos.com/${operator}.ibm-common-services --no-headers --ignore-not-found=true | awk '{print $1}')
    for crd in $(oc get crd -l operators.coreos.com/${operator} --no-headers --ignore-not-found=true | awk '{print $1}')
    do
      for cpService in $(oc get $crd -A --no-headers --ignore-not-found=true 2>/dev/null |awk '{print $1 "," $2}')
      do
        [[ "$DEBUG" == "TRUE" ]] && echo "[D] operator='$operator', crd='$crd', cpService='$cpService'"
        #Split input to get namespace and service name
        declare curNs=$(echo "$cpService" | awk -F, '{print $1}')
        #Check namespace is valid
        oc get ns $curNs >/dev/null 2>&1
        if [[ $? -ne 0 ]]
        then
          [[ "$DEBUG" == "TRUE" ]] && echo "[D] fail ns $curNs from $cpService is invalid"
          continue
        fi

        declare curName=$(echo "$cpService" | awk -F, '{print $2}')

        #Get service kind
        declare curKind=$(oc get $crd $curName -n $curNs -o jsonpath='{.kind}' 2>/dev/null)

        #Get service version
        #declare curVersion=$(oc get $crd $curName -n $curNs -o jsonpath='{.spec.version}' 2>/dev/null)
        declare curVersion=$(getVersionForService "$curNs" "$curKind" "$curName")

        #Populate all arrays with service details
        nsListAA["$curNs"]="$curNs"

        operatorsA[$serviceCounter]="$operator"
        crdA[$serviceCounter]="$crd"
        kindA[$serviceCounter]="$curKind"
        namespaceA[$serviceCounter]="$curNs"
        nameA[$serviceCounter]="$curName"
        versionA[$serviceCounter]="$curVersion"

        #increment service counter
        (( serviceCounter++ ))
      done #End for service
    done #End for crd
  done #End for operator

  #Return the number of services as the function rc value
  return $serviceCounter
}

#--- Function: For a given service, get the version. ---#
getVersionForService()
{
  declare nsIn="$1"
  declare kindIn="$2"
  declare nameIn="$3"
  declare versionStringOut=""

  #for jsonElement in spec.version status.currentVersion status.versionBuild status.zenOperatorBuildNumber status.versions.reconciled #metadata.resourceVersion
  for jsonElement in spec.version status.currentVersion status.versionBuild status.versions.reconciled spec.operatorVersion #metadata.resourceVersion
  do
    ocCmd="oc get $kindIn $nameIn -o jsonpath={.${jsonElement}} -n $nsIn"
    jsonOut=$($ocCmd 2>/dev/null) #Run formatted oc command
    if [[ -n "$jsonOut" ]]
    then
      case "$jsonElement" in
        spec.version) versionStringOut="${versionStringOut}[Version: $jsonOut]";;
        status.currentVersion) versionStringOut="${versionStringOut}[Cur Version: $jsonOut]";;
        status.versionBuild) versionStringOut="${versionStringOut}[Version Build: $jsonOut]";;
        status.zenOperatorBuildNumber) versionStringOut="${versionStringOut}[Zen Op Build Number: $jsonOut]";;
        status.versions.reconciled) versionStringOut="${versionStringOut}[Version reconciled: $jsonOut]";;
        spec.operatorVersion) versionStringOut="${versionStringOut}[Operator Version: $jsonOut]";;
        *) versionStringOut="${versionStringOut}[${jsonElement}: ${jsonOut}]"
      esac
    fi
  done

  echo "$versionStringOut"
}








#---------- MAIN ----------#

#-- Check for debug printing parameter --#
if [[ "$1" == "-v" ]]
then
  DEBUG="TRUE"
  echo "[D] Debug enabled"
fi

#-- Make sure oc login is valid --#
isOcpLoggedIn
boolLoginCheck=$?
if (( !boolLoginCheck ))
then
  echo "You are not logged into the ocp server"
  exit 1
fi

#---- Display openshift details ----#
echo "OpenShift:"

#-- Display ocp server --#
ocpserver=$(getServerName)
echo "- OCP Server: $ocpserver"

#-- Display ocp cluster console --#
ocpconsole=$(getOcpConsole)
echo "- OCP Console: $ocpconsole"

#-- Display OCP cluster version --#
ocpVersionString=$(getOcpVersion)
echo "- OCP Version: $ocpVersionString"

#-- Work with nodes --#
declare -A masterNodeList
declare -A workerNodeList
declare -A nodeMemoryCapacity
declare -A nodeCpuCapacity

#-- Get master nodes --#
getTypeNodes masterNodeList "master"
rc=$?
if (( rc != 0 ))
then
  echo "Failed to get master node list"
fi

#-- Get worker nodes --#
getTypeNodes workerNodeList "worker"
rc=$?
if (( rc != 0 ))
then
  echo "Failed to get worker node list"
fi

#-- Get node resources --#
for mNode in ${masterNodeList[@]} ${workerNodeList[@]}
do
  curMem=$(getNodeMem "$mNode")
  memrc=$?
  if (( memrc != 0 ))
  then
    curMem="unknown"
  fi
  nodeMemoryCapacity[$mNode]=$curMem

  curCpu=$(getNodeCpu "$mNode")
  cpurc=$?
  if (( cpurc != 0 ))
  then
    curCpu="unknown"
  fi
  nodeCpuCapacity[$mNode]=$curCpu
done

masterAlphabeticalList=$(for n in ${masterNodeList[@]}
do
  echo "$n"
done |sort)

workerAlphabeticalList=$(for n in ${workerNodeList[@]}
do
  echo "$n"
done |sort)

#-- Print master and worker node details --#
echo "- Master Nodes:"
for node in $masterAlphabeticalList
do
  echo "  - $node: ${nodeCpuCapacity[$node]} vCPUs and ${nodeMemoryCapacity[$node]} mem"
done

echo "- Worker Nodes:"
for node in $workerAlphabeticalList
do
  echo "  - $node: ${nodeCpuCapacity[$node]} vCPUs and ${nodeMemoryCapacity[$node]} mem"
done

#-- Scale storage --#
isScaleDeployed
scaleDeployed=$?

echo "Spectrum Scale:"
if [[ $scaleDeployed -gt 0 ]]
then
  #Get CNSA version
  scaleCnsaVersion=$(getScaleCnsaVersion)
  echo "- Spectrum Scale CNSA version: $scaleCnsaVersion"

  #Get Scale CSI version
  scaleCsiVersion=$(getScaleCsiVersion)
  echo "- Spectrum Scale CSI version: $scaleCsiVersion"

  #Get other details
  scaleRemoteGuiHost=""

  isScaleRemote
  scaleIsRemote=$?
  scaleFs=$(getScaleFs "local")
  if (( scaleIsRemote ))
  then
    scaleRemoteGuiHost=$(getRemoteGuiHost)
    if [[ "$?" -ne 0 ]]
    then
      scaleRemoteGuiHost="Unknown"
    fi
    scaleFsRemote=$(getScaleFs "remote")
    echo "- Spectrum Scale file system is remotely mounted"
  else
    echo "- Spectrum Scale file system is local storage"
  fi
  [[ "$scaleIsRemote" > 0 ]] && echo "- Spectrum Scale remote cluster GUI host: $scaleRemoteGuiHost"

  declare -A scaleStorageClasses
  getScaleStorageClasses scaleStorageClasses

  declare -A scaleFsStats #keys: fsName, capacity, used, free, percentUsed, mntPath
  getScaleFsStats scaleFsStats "$scaleFs"

  fsMsg=""
  [[ "$scaleIsRemote" > 0 ]] && fsMsg="(remote fs: ${scaleFsRemote})"
  echo "- Spectrum Scale fs name: ${scaleFs} $fsMsg"
  echo "- Spectrum Scale fs capacity: ${scaleFsStats["capacity"]} [Used: ${scaleFsStats["used"]} (${scaleFsStats["percentUsed"]}) | Free: ${scaleFsStats["free"]}]"
  echo "- Spectrum Scale CSI storage classes: ${scaleStorageClasses[@]}"
else
  echo "- Spectrum Scale storage not deployed."
fi

#-- Spectrum Fusion --#
isFusionCluster
isFusionBool=$?
if (( isFusionBool ))
then
  echo "Spectrum Fusion:"

  specFusionVersion=$(getSpectrumFusionVersion)
  echo "- Spectrum Fusion version: $specFusionVersion"

  specFusionType=$(getSpectrumFusionType)
  fusionTypeRc=$?
  if (( fusionTypeRc == 0 ))
  then
    echo "- Spectrum Fusion environment: $specFusionType"
  fi

  specProtPlusVersion=$(getSppClientVersion)
  sppCheckRc=$?
  if (( sppCheckRc == 0 ))
  then
    echo "- Spectrum Protect Plus client version: $specProtPlusVersion"
  fi
fi

#-- ODF --#
printODFInformation

#-- CloudPak service details --#
echo "Cloud Paks:"

#Common services / Bedrock:
csVersion=$(getCommonServicesVersion)
rc=$?
if (( rc != 0 ))
then
  csVersion="Not installed"
fi
echo "- Foundational Services (Bedrock) version: $csVersion"

#Pull the service info:
declare -A namespaceList
declare -a operator
declare -a crd
declare -a kind
declare -a namespace
declare -a name
declare -a version

compileCloudPakServices namespaceList operator crd kind namespace name version
numServices=$?


for ns in ${namespaceList[@]}
do
  declare kindList=""

  #Below is my complicated way to alphabetize the service list. :-P
  # 1. Go through all services and find the ones matching the current namespace.
  # 2. Append the kind with index number to a string, which will list all services for the namespace.
  # 3. Sort the list (which will be alphabetical), then strip off the index number and use it to
  #    reference the array value for the given service.
  let count=0
  while (( count < numServices ))
  do
    if [[ "$ns" == "${namespace[$count]}" ]]
    then
      kindList="${kindList} ${kind[$count]},${count}"
    fi
    (( count += 1 ))
  done
  [[ "$DEBUG" == "TRUE" ]] && echo "[D] kindList='$kindList'"

  echo "- Services in Namespace: $ns"
  for serviceItem in $(for service in $(echo "$kindList");do echo $service;done | sort)
  do
    index=$(echo "$serviceItem" | awk -F, '{print $2}')
    echo "  - [Kind: ${kind[$index]}][Name: ${name[$index]}]${version[$index]}"
  done
done


