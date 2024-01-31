CPD health check cmdline tool

https://github.ibm.com/PrivateCloud-analytics/cpd-healthcheck/tree/main/tools/cmdlinetool

## Background
The scripts are referenced from Storage team's test pipeline [cloudpak-storage-test](https://github.ibm.com/sit/cloudpak-storage-test). It coveres storage integration test for CP4BA, CP4D, CP4NA, CP4WAIOPs and CP4S. 
COE team reference some test scripts to cover CP4D and OCP health check, as a tool for account team, fields team to do daily health check and quickly identify the issues.

## Prerequisite: 
Login to OpenShift with an user having cluster-admin role
```
oc login <OpenShift Console URL> -u <username> -p <password>
```

## Health Check for OCP
- Download scripts under https://github.ibm.com/PrivateCloud-analytics/cpd-healthcheck/tree/main/tools/cmdlinetool
- Run script cpst_checktool.sh with below tasks.
- 
| ID | Task | Usage | Description |
| -- | --- | --- | --- |
| 1 | checkNodesStatus | ./cpst_checktool.sh -c checkNodesStatus | Check node status is ready |
| 2 | checkNodesCpuMemRequests | ./cpst_checktool.sh -c checkNodesCpuMemRequests | Check node CPU and Memory request|
| 3 | checkNodesCpuMemUsg | ./cpst_checktool.sh -c checkNodesCpuMemUsg  | Check node CPU and Memory |
| 4 | checkNodesDiskPressure | ./cpst_checktool.sh -c checkNodesDiskPressure  | Check node disk pressure |
| 5 | checkNodesPIDPressure | ./cpst_checktool.sh -c checkNodesPIDPressure  | Check node PID pressure |
| 6 | checkNodeTimeDifference | ./cpst_checktool.sh -c checkNodeTimeDifference  | Check node time difference less than 400ms |
| 7 | checkMcpUpdates | ./cpst_checktool.sh -c checkMcpUpdates  | Check MCP updates for nodes are in a correct status |
| 8 | checkClusterOperators | ./cpst_checktool.sh -c checkClusterOperators  | Check all Cluster operators are in a correct status |
| 9 | checkClusterVersionStatus | ./cpst_checktool.sh -c checkClusterVersionStatus |  Check ClusterVersion is in a correct status |
| 10 | **checkOpenshift** | ./cpst_checktool.sh -c checkOpenshift | Check task 1-9 |
| 11 | checkCpdPrereqs | ./cpst_checktool.sh -c checkCpdPrereqs | Check PID limit, SCC, node settings for WKC and Informix |
| 12 |checkCatSrcStatus | ./cpst_checktool.sh -c checkCatSrcStatus | Check CatalogSource status in given namespace, default is openshift-marketplace |


## Health Check for CP4D
- Download scripts under https://github.ibm.com/PrivateCloud-analytics/cpd-healthcheck/tree/main/tools/cmdlinetool
- Run script cpst_checktool.sh with below tasks.

| ID | Task | Usage | Description |
| -- | --- | --- | --- |
| 1 | checkClusterOperators | ./cpst_checktool.sh -c checkClusterOperators | All Cluster operators are in a correct status |
| 2 | checkCpdCrdStatus | ./cpst_checktool.sh -c checkCpdCrdStatus ***namespace*** | Check cpd crd status in given namespace |
| 3 |checkCsvStatus | ./cpst_checktool.sh -c checkCsvStatus ***namespace*** | Check CSV status in given namespace|
| 4 | checkFailedPodLogs | ./cpst_checktool.sh -c checkFailedPodLogs ***podname*** ***podnamespace*** | |
| 5 | **checkPods** | ./cpst_checktool.sh -c checkPods ***all*** | Checking Pods on all namespaces |
| 6 | **checkCpd** | ./cpst_checktool.sh -c checkCpd | Check pod, crd at cpd namespace, check pod, CSV in ibm-common-services  |
| 7 | **checkAllCpd** | ./cpst_checktool.sh -c checkAllCpd | Check task checkCpdPrereqs, checkCpdCrdStatus |
| 8 | checkScaleStatus | ./cpst_checktool.sh -c checkScaleStatus | Special check for Storage Specturm scale  |
| 9 | checkAll | ./cpst_checktool.sh -c checkAll | Check task checkOpenshift, checkAllCpd |

## Troubleshooting
In some cases we have seen errors attempting to run the checks relating to Windows carriage returns in the scripts. If you receive an error:
/bin/env: ‘bash\r’: No such file or directory
You need to convert the files. You can do this by using > dos2unix * or > sed -i $'s/\r$//' ./* from the cmdlinetool directory.
