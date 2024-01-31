#!/usr/bin/bash
DEBUG=0

NODEIN=$1
if [[ -z "$NODEIN" ]]
then
  echo "syntax: $0 <node>"
  exit 1
fi

#--- Get kickstart ---#
getKickstart()
{
  kickstart=$(oc -n ibm-spectrum-fusion-ns get cm |grep kickstart |awk '{print $1}')
  [[ "$DEBUG" > 0 ]] && (>&2 echo "[D] kickstart '$kickstart'")
  echo "$kickstart"
  return 0
}

#--- Get IMM details for given node ---#
getIMMJson()
{
  kickstartIn=$1
  nodeIn=$2
  jsonOut=$(oc -n ibm-spectrum-fusion-ns get cm $kickstartIn -o jsonpath='{.data.kickstart\.json}' | jq -r --arg NODE "$nodeIn" '.computeNodeIntegratedManagementModules[] | select(.OCPRole == $NODE)')
  echo "$jsonOut"
}

#--- Get ipv6 address from kickstart ---#
getIpv6addr()
{
  jsonIn=$1
  echo $jsonIn | jq -r '.ipv6ULA'
}

#--- Get secret from kickstart ---#
getNodeSecret()
{
  jsonIn=$1
  echo $jsonIn | jq -r '.secretName'
}

#--- Get username from secret ---#
getUsername()
{
  secretIn=$1
  userName=$(oc extract -n ibm-spectrum-fusion-ns secret/${secretIn} --keys=defaultUserName --to=- 2>/dev/null)
  echo $userName
}

#--- Get password from secret ---#
getPassword()
{
  secretIn=$1
  password=$(oc extract -n ibm-spectrum-fusion-ns secret/${secretIn} --keys=defaultUserPasswrd --to=- 2>/dev/null)
  echo $password
}

#--- Find a ready node ---#
getReadyNode()
{
  node=$(oc get node |grep " Ready" |head -1 |awk '{print $1}')
  echo $node
}

kickstart_cm=$(getKickstart)
jsonImm=$(getIMMJson "$kickstart_cm" "$NODEIN")
ipv6=$(getIpv6addr "$jsonImm")
nodeSecret=$(getNodeSecret "$jsonImm")
userName=$(getUsername "$nodeSecret")
password=$(getPassword "$nodeSecret")
accessNode=$(getReadyNode)


# Start debug session to the node
echo "--- Access IMM for $NODEIN ---"
echo "Perform: ssh -o StrictHostKeyChecking=false ${userName}@${ipv6}"
echo "Password: $password"
echo "--------------------------------"

oc debug node/${accessNode}
