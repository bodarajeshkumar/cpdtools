#!/usr/bin/bash
grepterm=$1
podnamegrep=$2
podcomment=""
prevlogflag=$3
prev=""
sinceIn=$4
since=""

if [[ -z "$grepterm" ]]
then
  echo "usage: $0 <grep_term> [<pod_name_filter>] [p|c] [<since_time>]"
  echo "    grep_term        - Item to grep on"
  echo "    pod_name_filter  - Pod name grep (if keyword 'all' used, then all pods will be looked at)"
  echo "    p or c           - Grep on previous or current logs"
  echo "    since_time       - Only grep on logs since time. Ex: '10m' for 10 minutes"
  exit 1
fi

pods=$(oc get pods |grep -v NAME |awk '{print $1}')
[[ -n "$podnamegrep" && $podnamegrep != "all" ]] && pods="$(echo "$pods" | grep "$podnamegrep")" && podcomment=" for pods with '$podnamegrep' in the podname"
numpods=$(echo "$pods" |wc -l)

[[ "$prevlogflag" == "p" ]] && prev="-p"
[[ -n "$sinceIn" ]] && since="--since=$sinceIn"

echo "Look through logs of $numpods pods for instances of '$grepterm'${podcomment}:"
for pod in $pods
do
  if ! oc logs $pod >/dev/null 2>&1
  then
    for cont in $(oc logs $pod 2>&1 | sed 's/ /\n/g' |sed -n "/\[/,/\]/p" |sed 's/[][]//g')
    do
      echo "--- $pod ($cont) ---"
      oc logs $pod $cont $prev $since |grep "$grepterm"
    done
  else
    echo "--- $pod ---"
    oc logs $pod $prev $since |grep "$grepterm"
  fi
done
