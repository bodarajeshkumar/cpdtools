#!/bin/bash
# Version 1 (with CNSA 5.1.0.3/CSI 2.2.0 older)
#OLD: cnsaCorePod=$(oc get pods --namespace ibm-spectrum-scale-ns -o jsonpath='{range.items[?(.metadata.generateName=="ibm-spectrum-scale-core-")]}{.metadata.name}{"\n"}{end}' |head -1)
cnsaCorePod=$(oc get pod -n ibm-spectrum-scale -l app.kubernetes.io/name=core --no-headers |head -1 |awk '{print $1}')
#OLD: stgContactNode=$(oc exec $cnsaCorePod --namespace ibm-spectrum-scale-ns -- mmremotecluster show | awk -F: '/Contact nodes/ {print $2}' |awk -F, '{print $1}' |sed 's/^[[:space:]]*//')
stgContactNode=$(oc exec $cnsaCorePod --namespace ibm-spectrum-scale -- mmremotecluster show | awk -F: '/Contact nodes/ {print $2}' |awk -F, '{print $1}' |sed 's/^[[:space:]]*//')
#OLD: stgRemoteFs=$(oc exec $cnsaCorePod --namespace ibm-spectrum-scale-ns -- mmremotecluster show | awk '/File systems/ {print $NF}' |sed  's/[\(\)]//g')
stgRemoteFs=$(oc exec $cnsaCorePod --namespace ibm-spectrum-scale -- mmremotecluster show | awk '/File systems/ {print $NF}' |sed  's/[\(\)]//g')

echo "Core pod '$cnsaCorePod'"
echo "Contact node '$stgContactNode'"
echo "Remote fs '$stgRemoteFs'"

allfilesetOut=$(ssh root@${stgContactNode} /usr/lpp/mmfs/bin/mmlsfileset ${stgRemoteFs} -i)

echo "PVC-name                       Name                     Status    Path                                         InodeSpace      MaxInodes    AllocInodes     UsedInodes"
for pvcVol in $(oc get pvc --all-namespaces |grep Bound | awk '/pvc/ {print $4}')
do
  pvcName=$(oc get pvc --all-namespaces |grep "$pvcVol" |awk '{print $2}')
  #echo "--- $pvcName ---"
  #filesetOut=$(ssh root@${stgContactNode} /usr/lpp/mmfs/bin/mmlsfileset ${stgRemoteFs} $pvcVol -i |grep $pvcVol)
  filesetOut=$(echo "$allfilesetOut" |grep $pvcVol)
  printf "%-30s %s\n" "$pvcName" "$filesetOut"
done
