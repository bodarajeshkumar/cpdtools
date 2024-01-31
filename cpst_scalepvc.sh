#!/usr/bin/bash
#Abstract: Gets details for Spectrum Scale provisioned PVCs (provisioner == spectrumscale.csi.ibm.com)
#Author:   Todd Tosseth
#Date:     30-Mar-2022



declare DEBUG="FALSE"
declare SCALE_GUI_URL
declare SCALE_GUI_SECRET_USERNAME
declare SCALE_GUI_SECRET_PASSWORD
declare SCALE_FS_NAME
declare OCP_NAMESPACE_STRING
declare -a KEYS
declare -A FILESETS
declare -A PVCS


#--- Function: Check for any spectrumscale.csi.ibm.com in scope ---#
hasScalePvcs()
{
  pvcJson=$(oc get pvc ${OCP_NAMESPACE_STRING} -o json |jq -r '.items[] | select(.metadata.annotations."volume.beta.kubernetes.io/storage-provisioner" == "spectrumscale.csi.ibm.com")')
  if [[ -n "$pvcJson" ]]
  then
    return 1 #True
  else
    return 0 #False
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


#--- Function: Set credentials ---#
setCredentials()
{
  isScaleRemote
  scaleRemote=$?

  if (( scaleRemote ))
  then
    guiSecret="$(oc get remoteclusters -n ibm-spectrum-scale -o jsonpath='{.items[].spec.gui.secretName}')"
    getSecretRc=$?
    user=$(oc get secret $guiSecret -n ibm-spectrum-scale -o jsonpath='{.data.username}' |base64 -d);
    pass=$(oc get secret $guiSecret -n ibm-spectrum-scale -o jsonpath='{.data.password}' |base64 -d);
    if [[ "$getSecretRc" -eq 0 && -n $user && -n $pass ]]
    then
      SCALE_GUI_SECRET_USERNAME=$user
      SCALE_GUI_SECRET_PASSWORD=$pass
      [[ "$DEBUG" == "TRUE" ]] && echo "[D] user '$SCALE_GUI_SECRET_USERNAME', pass '$SCALE_GUI_SECRET_PASSWORD'"
      return 0
    else
      echo "Unable to get remote Spectrum Scale GUI credentials"
      return 1
    fi

  else
    creds=$(oc get secret -n ibm-spectrum-scale ibm-spectrum-scale-gui-authentication -o jsonpath='{.data.authentication\.xml}' 2>/dev/null | base64 -d |grep "<user name=" |head -1)
    #Example: <user name="ContainerOperator" password="6Ta1WbqYdX4fueSCXMmb"></user>
    if [[ -z "$creds" ]]
    then
      echo "Unable to get Spectrum Scale GUI credentials"
      return 1
    fi

    #Set username
    SCALE_GUI_SECRET_USERNAME=$(echo "$creds" | awk -F\" '{print $2}')
    #Set password
    SCALE_GUI_SECRET_PASSWORD=$(echo "$creds" | awk -F\" '{print $4}')

    [[ "$DEBUG" == "TRUE" ]] && echo "[D] user '$SCALE_GUI_SECRET_USERNAME', pass '$SCALE_GUI_SECRET_PASSWORD'"
    return 0
  fi
}


#--- Function: set gui url ---#
setGuiUrl()
{
  isScaleRemote
  scaleRemote=$?

  if (( scaleRemote ))
  then
    scaleroute=$(oc get remoteclusters -n ibm-spectrum-scale -o jsonpath='{.items[].spec.gui.host}' 2>/dev/null)
    rc=$?
  else
    scaleroute=$(oc get route -n ibm-spectrum-scale -o jsonpath='{.items[].spec.host}' 2>/dev/null)
    rc=$?
  fi

  if (( rc != 0 ))
  then
    echo "Unable to get Spectrum Scale GUI URL"
    return $rc
  fi

  SCALE_GUI_URL="$scaleroute"
  [[ "$DEBUG" == "TRUE" ]] && echo "[D] Scale gui route '$SCALE_GUI_URL'"
  return $rc
}



#--- Function: ---#
setFsName()
{
  isScaleRemote
  scaleRemote=$?

  if (( scaleRemote ))
  then
    fsName=$(oc get filesystem -n ibm-spectrum-scale -o jsonpath='{.items[0].spec.remote.fs}' 2>/dev/null)
    fsRc=$?
  else
    fsName=$(oc get filesystem -n ibm-spectrum-scale -o jsonpath='{.items[].metadata.name}' 2>/dev/null)
    fsRc=$?
  fi
  [[ "$DEBUG" == "TRUE" ]] && echo "[D] Scale fs name '$fsName' (rc $fsRc)"

  if [[ "$fsRc" -eq 0 && -n "$fsName" ]]
  then
    SCALE_FS_NAME=$fsName
    return 0
  else
    echo "Unable to get Spectrum Scale file system name"
    return 1
  fi  
}

#SCALE_FILESETS=$(curl -X GET -k -u ${SCALE_GUI_SECRET_USERNAME}:${SCALE_GUI_SECRET_PASSWORD} --header 'accept:application/json' "https://${SCALE_GUI_URL}:443/scalemgmt/v2/filesystems/${SCALE_REMOTE_FS}/filesets" 2>/dev/null |jq -r '.filesets[] | .filesetName')
#for SCALE_FILESET in $(echo $SCALE_FILESETS);do echo -- $SCALE_FILESET --;curl -X GET -k -u ${SCALE_GUI_SECRET_USERNAME}:${SCALE_GUI_SECRET_PASSWORD} --header 'accept:application/json' "https://${SCALE_GUI_URL}:443/scalemgmt/v2/filesystems/${SCALE_REMOTE_FS}/filesets/${SCALE_FILESET}";echo;done


#--- Function: Get curl status code ---#
getCurlStatusCode()
{
  declare jsonIn=$1
  statusCode=$(echo "$jsonIn" | jq '.status.code')
  echo "$statusCode"
}


#--- Function: Get all fileset names in file system and add to global array ---#
setFilesetNames()
{
  [[ "$DEBUG" == "TRUE" ]] && echo "[D] SCALE_GUI_SECRET_USERNAME='$SCALE_GUI_SECRET_USERNAME', SCALE_GUI_SECRET_PASSWORD='$SCALE_GUI_SECRET_PASSWORD', SCALE_GUI_URL='$SCALE_GUI_URL', SCALE_FS_NAME='$SCALE_FS_NAME'"
  curlCmd="curl -X GET -k -u ${SCALE_GUI_SECRET_USERNAME}:${SCALE_GUI_SECRET_PASSWORD} --header 'accept:application/json' \"https://${SCALE_GUI_URL}:443/scalemgmt/v2/filesystems/${SCALE_FS_NAME}/filesets\""
  [[ "$DEBUG" == "TRUE" ]] && echo "[D] curlCmd '$curlCmd'"

  fsetsJsonOut=$(curl -X GET -k -u ${SCALE_GUI_SECRET_USERNAME}:${SCALE_GUI_SECRET_PASSWORD} --header 'accept:application/json' "https://${SCALE_GUI_URL}:443/scalemgmt/v2/filesystems/${SCALE_FS_NAME}/filesets" 2>/dev/null)

  #fsetsJsonOut=$curlCmd 2>/dev/null # |jq -r '.filesets[] | .filesetName')
  fsetRc=$?

  fsetsStatus=$( getCurlStatusCode "$fsetsJsonOut" )
  if [[ "$fsetsStatus" != "200" ]]
  then
    echo "Curl command to get filesets for fs $SCALE_FS_NAME failed with status code $fsetsStatus"
    echo "$fsetsJsonOut"
    return 1
  fi


  #Parse json fileset output to get just the fileset names:
  for fset in $(echo $fsetsJsonOut | jq -r '.filesets[].filesetName')
  do
    FILESETS[$fset]="$fset"
  done
  return 0
}



#--- Function: Get all pvcs in spectrumscale.csi.ibm.com provisioner for the given namespace ---#
setPvcs()
{
  pvcsOut=$(oc get pvc ${OCP_NAMESPACE_STRING} -o json |jq -r '.items[] | select(.metadata.annotations."volume.beta.kubernetes.io/storage-provisioner" == "spectrumscale.csi.ibm.com") | (.metadata.name) + "," + (.spec.volumeName) + "," + (.spec.storageClassName) + "," + (.metadata.namespace) + "," + (.spec.resources.requests.storage)')
  pvcsRc=$?
  #Output format example:
  #user-home-pvc,pvc-cbf2ae1b-8ab1-41b1-8c65-7e8f62ecc2e4,ibm-spectrum-scale-sc,cpd,10Gi
  #ibm-spectrum-scale-test-2,pvc-8ea7ea1b-9c23-439b-b9d6-ce85fe1883a1,ibm-spectrum-scale-sc,default,100Gi

  if [[ "$pvcsRc" -ne 0 || -z "$pvcsOut" ]]
  then
    echo "Failed to get PVCs in namespace $OCP_NAMESPACE_STRING ($pvcsOut)"
    return 1
  fi

  #Put pvcs in global array
  for pvcline in $(echo "$pvcsOut")
  do
    pv=$(echo "$pvcline" | awk -F, '{print $2}')
    PVCS[$pv]="$pvcline"
  done

  return 0
}


#--- Function: Update the global array FILESETS with Scale fileset details for each desired PVC ---#
setFilesetDetails()
{
  for fset in ${!PVCS[@]}
  do
    fsetdetailsJsonOut=$(curl -X GET -k -u ${SCALE_GUI_SECRET_USERNAME}:${SCALE_GUI_SECRET_PASSWORD} --header 'accept:application/json' "https://${SCALE_GUI_URL}:443/scalemgmt/v2/filesystems/${SCALE_FS_NAME}/filesets/${fset}" 2>/dev/null)
    fsetRc=$?

    fsetStatus=$( getCurlStatusCode "$fsetdetailsJsonOut" )
    if [[ "$fsetStatus" != "200" ]]
    then
      echo "Curl command to get fileset details for fset $fset in fs $SCALE_FS_NAME failed with status code $fsetStatus. '$fsetdetailsJsonOut'"
      continue
    fi

    [[ "$DEBUG" == "TRUE" ]] && echo "[D] setFilesetDetails: $fset json output: $fsetdetailsJsonOut"

    isScaleRemote
    remote=$?
    if (( remote ))
    then
      usedbytes=$(echo $fsetdetailsJsonOut | jq -r --arg fset "$fset" '.filesets[] | select(.filesetName == $fset) | .usage.usedBytes')
    else
      #Workaround for local/Fusion storage:
      fsetPath=$(echo $fsetdetailsJsonOut | jq -r --arg fset "$fset" '.filesets[] | select(.filesetName == $fset) | .config.path')
      usedbytes=$(getUsedBytesLocal "$fset" "$fsetPath")
      rc=$?
      [[ "$DEBUG" == "TRUE" ]] && echo "[D] workaround path: fsetPath '$fsetPath', usedbytes '$usedbytes', rc '$rc'"
      if (( rc != 0 ))
      then
        usedbytes="Unknown"
      fi
    fi

    usedbytesFormatted=$(simplifyUsedbytes "$usedbytes")
    maxinodes=$(echo $fsetdetailsJsonOut | jq -r --arg fset "$fset" '.filesets[] | select(.filesetName == $fset) | .config.maxNumInodes')
    usedinodes=$(echo $fsetdetailsJsonOut | jq -r --arg fset "$fset" '.filesets[] | select(.filesetName == $fset) | .usage.usedInodes')

    #Format example:
    #pvc-cbf2ae1b-8ab1-41b1-8c65-7e8f62ecc2e4,270860288,100352,2909
    FILESETS[$fset]="${FILESETS[$fset]},${usedbytesFormatted},${maxinodes},${usedinodes}"
    [[ "$DEBUG" == "TRUE" ]] && echo "[D] for '$fset': usedbytes=$usedbytes, usedbytesFormatted=$usedbytesFormatted, maxinodes=$maxinodes, usedinodes=$usedinodes: FILESETS[$fset]='${FILESETS[$fset]}'"
  done
}

#--- Function: Get used bytes for Spectrum Fusion/local mount ---#
#---   This is a workaround to get used bytes, since local storage
#---   doesn't seem to report used bytes from REST call properly.
getUsedBytesLocal()
{
  declare fsetIn="$1"
  declare fsetPathIn="$2"
  declare -i bytesOut=0

  #-- Check inputs non-zero --#
  if [[ -z "$fsetIn" || -z "$fsetPathIn" ]]
  then
    [[ "$DEBUG" == "TRUE" ]] && >&2 echo "[D] getUsedBytesLocal: Invalid inputs: fsetIn='$fsetIn', fsetPathIn='$fsetPathIn'"
    return 1
  fi

  #-- Get scale core pod --#
  corepod=$(oc get pod -o name -l app.kubernetes.io/name=core -n ibm-spectrum-scale 2>/dev/null |head -1)
  if [[ -z "$corepod" ]]
  then
    [[ "$DEBUG" == "TRUE" ]] && >&2 echo "[D] getUsedBytesLocal: Could not get scale core pod"
    return 1
  fi

  #-- Run command to core pod to get usage via du -s --#
  duOut=$(oc exec $corepod -n ibm-spectrum-scale -c gpfs -- sh -c "du -s $fsetPathIn" 2>/dev/null)
  duRc=$?
  if (( duRc != 0 ))
  then
    [[ "$DEBUG" == "TRUE" ]] && >&2 echo "[D] getUsedBytesLocal: Failed to run 'du -s $fsetPathIn' on scale core pod $corepod"
    return 1
  fi

  #Example output:
  #118648	/mnt/tucsonrackbfs/pvc-169f8c11-7163-4dc7-ad58-b4fcf9e323a3
  [[ "$DEBUG" == "TRUE" ]] && >&2 echo "[D] getUsedBytesLocal: du -s output: '$duOut'"

  if [[ -n "$(echo $duOut | awk '{print $2}')" ]]
  then
    bytesOut=$(echo "$duOut" | awk '{print $1}')
    echo "$bytesOut"
    return 0
  else
    [[ "$DEBUG" == "TRUE" ]] && >&2 echo "[D] getUsedBytesLocal: Invalid du -s output: '$duOut'"
    return 1
  fi

  #Why did we get here?
  return 1
}

#--- Function: Simply usedbytes ---#
simplifyUsedbytes()
{
  declare -i usedbytesIn=$1
  declare usedbytesStrIn="$1"
  declare -i usedbytesStrLen=${#usedbytesStrIn}
  declare usedbytesOut=""

  if [[ "$usedbytesStrIn" == "Unknown" ]]
  then
    echo "$usedbytesStrIn"
    return 0
  fi

  if (( usedbytesStrLen > 10 )) #Gi
  then
    usedbytesOut="$(( usedbytesIn / 1024 / 1024 / 1024 ))Gi"
  elif (( usedbytesStrLen > 7 )) #Mi
  then
    usedbytesOut="$(( usedbytesIn / 1024 / 1024 ))Mi"
  elif (( usedbytesStrLen > 4 )) #Ki
  then
    usedbytesOut="$(( usedbytesIn / 1024 ))Ki"
  else
    usedbytesOut=$usedbytesIn
  fi

  #[[ "$DEBUG" == "TRUE" ]] && echo "[D] simplifyUsedbytes: in: $usedbytesIn, out: $usedbytesOut"
  echo "$usedbytesOut"
  return 0
}


#--- Function: Get longest entry of input type, to help with formatting ---#
getLongest()
{
  declare typeIn="$1"
  declare -i curLen=0
  declare -i curLong=0
  declare -i strLenOut=0

  #Examples:
  #PVCS[x] = user-home-pvc,pvc-cbf2ae1b-8ab1-41b1-8c65-7e8f62ecc2e4,ibm-spectrum-scale-sc,cpd,10Gi
  #FILESETS[x] = pvc-cbf2ae1b-8ab1-41b1-8c65-7e8f62ecc2e4,270860288,100352,2909

  case $typeIn in
  NAMESPACE)
    curLong=$(echo "NAMESPACE" |wc -c)
    for pvcline in ${PVCS[@]}
    do
      curLen=$(echo $pvcline | awk -F, '{print $4}' |wc -c)
      if (( curLen > curLong ))
      then
        curLong=$curLen
      fi
    done
    strLenOut=$curLong
    ;;

  NAME)
    curLong=$(echo "NAME" |wc -c)
    for pvcline in ${PVCS[@]}
    do
      curLen=$(echo $pvcline | awk -F, '{print $1}' |wc -c)
      if (( curLen > curLong ))
      then
        curLong=$curLen
      fi
    done
    strLenOut=$curLong
    ;;

  VOLUME)
    curLong=$(echo "VOLUME" |wc -c)
    for vol in ${!PVCS[@]}
    do
      curLen=$(echo $vol |wc -c)
      if (( curLen > curLong ))
      then
        curLong=$curLen
      fi
    done
    strLenOut=$curLong
    ;;

  CAPACITY)
    curLong=$(echo "CAPACITY" |wc -c)
    for pvcline in ${PVCS[@]}
    do
      curLen=$(echo $pvcline | awk -F, '{print $5}' |wc -c)
      if (( curLen > curLong ))
      then
        curLong=$curLen
      fi
    done
    strLenOut=$curLong
    ;;

  #FILESETS[x] = pvc-cbf2ae1b-8ab1-41b1-8c65-7e8f62ecc2e4,270860288,100352,2909
  USEDBYTES)
    curLong=$(echo "USEDBYTES" |wc -c)
    for fsetline in ${FILESETS[@]}
    do
      curLen=$(echo $fsetline | awk -F, '{print $2}' |wc -c)
      if (( curLen > curLong ))
      then
        curLong=$curLen
      fi
    done
    strLenOut=$curLong
    ;;

  MAXINODES)
    curLong=$(echo "MAXINODES" |wc -c)
    for fsetline in ${FILESETS[@]}
    do
      curLen=$(echo $fsetline | awk -F, '{print $3}' |wc -c)
      if (( curLen > curLong ))
      then
        curLong=$curLen
      fi
    done
    strLenOut=$curLong
    ;;

  USEDINODES)
    curLong=$(echo "USEDINODES" |wc -c)
    for fsetline in ${FILESETS[@]}
    do
      curLen=$(echo $fsetline | awk -F, '{print $4}' |wc -c)
      if (( curLen > curLong ))
      then
        curLong=$curLen
      fi
    done
    strLenOut=$curLong
    ;;

  *)
    echo "Unknown type"
    ;;
  esac

  [[ "$DEBUG" == "TRUE" ]] && echo "[D] Longest $typeIn len: $strLenOut"
  return $strLenOut
}


#--- Function: Set key in array order ---#
setKeys()
{
  declare -i count=0
  for key in $(oc get pvc ${OCP_NAMESPACE_STRING} --no-headers |awk '{print $(NF-4)}')
  do
    KEYS[$count]="$key"
    (( count += 1 ))
  done
}



#--- Function: Pretty print the info ---#
prettyPrintPvcs()
{
  if [[ "${#PVCS[@]}" -eq 0 ]]
  then
    echo "No resources found"
    return 1
  fi

  #Examples:
  #PVCS[x] = user-home-pvc,pvc-cbf2ae1b-8ab1-41b1-8c65-7e8f62ecc2e4,ibm-spectrum-scale-sc,cpd,10Gi
  #FILESETS[x] = pvc-cbf2ae1b-8ab1-41b1-8c65-7e8f62ecc2e4,270860288,100352,2909

#[if -A: NAMESPACE] NAME(pvc name)  VOLUME(fsetname)  CAPACITY  USEDBYTES  MAXINODES  USEDINODES

  #-- Get longest entries for each column --#
  if [[ "$OCP_NAMESPACE_STRING" == "-A" ]]
  then
    getLongest "NAMESPACE"
    longNamespace=$?
  fi
  getLongest "NAME"
  longName=$?
  getLongest "VOLUME"
  longVolume=$?
  getLongest "CAPACITY"
  longCapacity=$?
  getLongest "USEDBYTES"
  longUsedbytes=$?
  getLongest "MAXINODES"
  longMaxinodes=$?
  getLongest "USEDINODES"
  longUsedinodes=$?


  #-- Start printing --#
  if [[ "$OCP_NAMESPACE_STRING" == "-A" ]]
  then
    #printf "NAMESPACE\n"  ${padding:${#longNamespace}}"
    printf "%-${longNamespace}s  " "NAMESPACE"
  fi
  #Print header line:
  printf "%-${longName}s  %-${longVolume}s  %-${longCapacity}s  %-${longUsedbytes}s  %-${longMaxinodes}s  %-${longUsedinodes}s\n" "NAME" "VOLUME" "CAPACITY" "USEDBYTES" "MAXINODES" "USEDINODES"

  #Print entries:
  for key in ${KEYS[@]}
  do
    #If the current key (PV name) isn't a Scale PV the skip it.
    if [[ -z "${PVCS[$key]}" ]]
    then
      [[ "$DEBUG" == "TRUE" ]] && echo "[D] Skipping non-Scale PV key $key"
      continue
    fi

    if [[ "$OCP_NAMESPACE_STRING" == "-A" ]]
    then
      #NAMESPACE:
      printf "%-${longNamespace}s  " "$(echo ${PVCS[$key]} | awk -F, '{print $4}')"
    fi
    #NAME:
      printf "%-${longName}s  " "$(echo ${PVCS[$key]} | awk -F, '{print $1}')"
    #VOLUME:
      printf "%-${longVolume}s  " "$key"
    #CAPACITY:
      printf "%-${longCapacity}s  " "$(echo ${PVCS[$key]} | awk -F, '{print $5}')"
    #USEDBYTES:
      printf "%-${longUsedbytes}s  " "$(echo ${FILESETS[$key]} | awk -F, '{print $2}')"
    #MAXINODES:
      printf "%-${longMaxinodes}s  " "$(echo ${FILESETS[$key]} | awk -F, '{print $3}')"
    #USEDINODES:
      printf "%-${longUsedinodes}s  " "$(echo ${FILESETS[$key]} | awk -F, '{print $4}')"
    #End of line
      printf "\n"
  done
}


#--- Function: Syntax message ---#
syntax()
{
  echo "Gets details for Spectrum Scale provisioned PVCs"
  echo "usage: $0 [ {-n <NAMESPACE>} | {-A} ]"
  echo "-n <NAMESPACE>    - [Optional] Select specific namespace to check (default: current namespace)"
  echo "-A                - [Optional] Check for all namespaces"
  echo "-h | --help       - Print usage statement"
  echo ""
  echo "Note: For Spectrum Fusion/local storage, the data collection (via du -s) may take a few minutes."
}







#--------------------------- MAIN ---------------------------#

#--- Bad way to handle inputs ---#
if [[ "$1" == "-v" || "$2" == "-v" || "$3" == "-v" ]]
then
  DEBUG="TRUE"
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]
then
  syntax
  exit 2
fi


#Handle oc namespace
if [[ "$1" == "-A" ]]
then
  OCP_NAMESPACE_STRING="-A"
elif [[ "$1" == "-n" ]]
then
  if [[ -z "$2" ]]
  then
    echo "Namespace required with -n parameter"
    exit 1
  fi
  OCP_NAMESPACE_STRING="-n $2"
else
  proj="$(oc project 2>/dev/null |awk -F "Using project" '{print $2}' |awk -F\" '{print $2}')"
  OCP_NAMESPACE_STRING="-n $proj"
fi


#-- Check to see if there are even any Scale pvcs to get details for --#
hasScalePvcs
scalePvcCheck=$?
if (( scalePvcCheck == 0 ))
then
  echo "No Spectrum Scale PVC resources found"
  exit 0
fi


#-Set global vars -#
setCredentials
rc=$?
if (( rc != 0 ))
then
  echo "Failed to get Scale gui credentials"
  exit $rc
fi

setGuiUrl
rc=$?
if (( rc != 0 ))
then
  echo "Failed to get Scale gui url"
  exit $rc
fi

setFsName
rc=$?
if (( rc != 0 ))
then
  echo "Failed to get Scale file system name" 
  exit $rc
fi

setFilesetNames
rc=$?
if (( rc != 0 ))
then
  echo "Failed to get Scale fileset names for file system $SCALE_FS_NAME"
  exit $rc
fi


#-- Get current Scale pvcs --#
setPvcs
rc=$?
if (( rc != 0 ))
then
  echo "Failed to get PVCs for namespace identifier $OCP_NAMESPACE_STRING"
  exit $rc
fi

#-- Call function to loop through all Scale filesets to get their usage and details --#
setFilesetDetails

#-- This is to help with alphabetical order of the PVCs --#
setKeys

#-- Print the details in nice column form --#
prettyPrintPvcs

