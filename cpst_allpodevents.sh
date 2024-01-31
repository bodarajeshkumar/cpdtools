#!/usr/bin/bash

ns=$1

if [[ -z "$ns" ]]
then
  echo "Fail: Requires namespace to query pods"
  exit 1
fi

for pod in $(oc get pod --no-headers -n $ns |awk '{print $1}')
do
  echo "--------------------- $pod ---------------------"
  oc describe pod $pod -n $ns | sed -n '/Events:/,//p'
done
