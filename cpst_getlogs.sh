#!/usr/bin/bash
confirmed=$1

if [[ "$confirmed" != "-y" ]]
then
  echo "Creates a tmp directory and pushes logs to it, then archives it up back to local dir."
  echo "usage: $0 -y"
  echo "  -y is a confirmation to collect the logs, else show usage statement."
  exit 1
fi


pods=$(oc get pods |grep -v NAME |awk '{print $1}')
[[ -n "$podnamegrep" && $podnamegrep != "all" ]] && pods="$(echo "$pods" | grep "$podnamegrep")" && podcomment=" for pods with '$podnamegrep' in the podname"
numpods=$(echo "$pods" |wc -l)

tmpdir=$(mktemp -d)
tmpbasename=$(basename $tmpdir)
curns=$(oc config view --minify -o 'jsonpath={..namespace}')
curdir=$(pwd)

echo "Get logs for $numpods pods in namespace $curns (logs in $tmpdir)"
for pod in $pods
do
  if ! oc logs $pod >/dev/null 2>&1
  then
    for cont in $(oc logs $pod 2>&1 | sed 's/ /\n/g' |sed -n "/\[/,/\]/p" |sed 's/[][]//g')
    do
      echo "- $pod ($cont) -- ${tmpdir}/${curns}.${pod}.${cont}.logs"
      oc logs $pod -c $cont > ${tmpdir}/${curns}.${pod}.${cont}.logs
    done
  else
    echo "- $pod -- ${tmpdir}/${curns}.${pod}.logs"
    oc logs $pod > ${tmpdir}/${curns}.${pod}.logs
  fi
done

echo "Compress logs files"
zip cpd-grp4.${tmpbasename}.logs.zip -r /tmp/tmp.f2foVzvaar/

echo "===================================================="
echo "tmp log files in ${tmpdir}"
echo "Log archive: ${curdir}/cpd-grp4.${tmpbasename}.logs.zip"
