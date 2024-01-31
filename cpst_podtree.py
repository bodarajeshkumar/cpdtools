#!/usr/bin/python3
#Author: Todd Tosseth
#Abstract:
#  Gathers details from the OCP cluster to list all resources for a given
#  high level "service" resource owner, including total requested cpu and
#  memory, and pvc capacity, as well as listing of pods, in a tree format.

#-------------------------------------------------------------------------#
# Imports
#-------------------------------------------------------------------------#
from os import name
import sys
import subprocess
import re
import shlex
import json
import threading
from random import randint
from time import sleep
import collections
import getopt


#-------------------------------------------------------------------------#
# Global variables/defines
#-------------------------------------------------------------------------#
PRINTLINE="---------------------------------------------------------------\n"
DEBUG_MODE = False
QUIET = False
ASPACE=" "

GLOBAL_POD_OBJECTS = collections.defaultdict(dict) #Nested dictionary: [namespace][podname]
GLOBAL_PVC_OBJECTS = collections.defaultdict(dict) #Nested dictionary: [namespace][pvcname]
GLOBAL_SERVICE_OBJECTS = collections.defaultdict(dict) #Nested dictionary: [namespace][servicename]

#Define global json dictionaries for initial data pull.
#These are nested dictionaries, first level is namespace.
GLOBAL_STATEFULSET = {}
GLOBAL_REPLICASET = {}
GLOBAL_JOBS = {}
GLOBAL_DEPLOYMENT = {}
GLOBAL_PODS = {}
GLOBAL_IBM = {}
GLOBAL_PVCS = {}
GLOBAL_CONFIGMAP = {}
GLOBAL_COGNITIVEDATA = {}
GLOBAL_EVENTS = {}

#-------------------------------------------------------------------------#
# Classes
#-------------------------------------------------------------------------#

#---------- class podObject ----------#
class podObject:

  def __init__(self,name,namespace):
    self.name=name
    self.longName=f"pod/{name}"
    self.namespace=namespace
    if DEBUG_MODE: print(f"podObject:------- Init: {self.longName} in ns {self.namespace}")
    self.podJson=self.getPodJson()
    self.ownerHierarchy=[] #List
    self.populateOwnerHierarchy()
    self.primaryOwner=self.getPrimaryOwner()
    self.nodeName=self.getNodeName()
    self.cpuRequest=self.getCpu("requests")
    self.cpuLimit=self.getCpu("limits")
    self.cpuActive=0  #Value of requests for active containers
    self.memoryRequest=self.getMem("requests")
    self.memoryLimit=self.getMem("limits")
    self.memoryActive=0 #Value of requests for active containers
    self.status=self.getStatus()
    self.pvcList=self.getPvcs()
    self.restarts=0
    self.events=""

  def getPodName(self):
    return self.name
  
  def getPodJson(self):
    resJson = None
    items = GLOBAL_PODS[self.namespace].get("items")
    for item in items:
      itemName=item.get("metadata").get("name")
      if itemName == self.name:
        if DEBUG_MODE: print(f"podObject: getPodJson - MATCH! item.metadata.name = '{itemName}'")
        resJson = item

    #We didn't find a matching json in our pre-pulled jsons. Get the resource directly.
    if resJson is None:
      if DEBUG_MODE: print(f"podObject: getPodJson - Did not find pod in cache, make oc call")
      resJson = getJsonForResource(self.longName, self.namespace)

    return resJson

  def populateOwnerHierarchy(self):
    ownerList=[]
    controller = controlledBy(self.longName, self.namespace)
    while controller:
      if DEBUG_MODE: print(f"podObject: getOwnerH: controller {controller}")
      ownerList.append(controller)
      controller = controlledBy(controller, self.namespace)
    if DEBUG_MODE: print(f"podObject: getOwnerH: ownerList: '{ownerList}'")
    self.ownerHierarchy = ownerList
    return ownerList

  def getOwnerHierarchy(self):
    return self.ownerHierarchy
    
  def getPrimaryOwner(self):
    if len(self.ownerHierarchy) > 0:
      return self.ownerHierarchy[-1]
    else:
      return None
  
  def getNodeName(self):
    return self.podJson.get("spec").get("nodeName",None)
  
  #Returns pod's cpu in mili
  def getCpu(self, scope):
    cpuCount = 0

    initContStatusList = self.podJson.get("status").get("initContainerStatuses",[])
    contStatusList = self.podJson.get("status").get("containerStatuses",[])

    #Go through init containers:
    containerList = self.podJson.get("spec").get("initContainers",[])
    for cont in containerList:
      contName = cont.get("name")

      #Check to see if the container is active, otherwise it doesn't count.
      contStatus = "terminated" 
      for contStatusJson in initContStatusList:
        if (contStatusJson.get("name") == contName) and (contStatusJson.get("state").get("running",None)):
          contStatus = "running"
          break
      if contStatus == "terminated":
        if DEBUG_MODE: print(f"podObject: getCpu: pod {self.name} initCont {contName} (scope {scope}) not running, continue...")
        #This container is not running, continue to next.
        continue

      #If we made it here, we should get the pod container stats and count them.
      if DEBUG_MODE: print(f"podObject: getCpu: pod '{self.name}', initContainer '{contName}', scope '{scope}'")
      try:
        cpuVal = cont.get("resources").get(scope).get("cpu")
        if cpuVal is None:
          cpuVal = "0"
      except:
        if DEBUG_MODE: print(f"Info: pod {self.name} has no {scope} cpu resources")
        cpuVal = "0"
      cpuVal = ocpValToInteger(cpuVal, "m")
      if DEBUG_MODE: print(f"podObject: cpuVal '{cpuVal}'")
      cpuCount += cpuVal

    #Go through containers:
    containerList = self.podJson.get("spec").get("containers",[])
    for cont in containerList:
      contName = cont.get("name")

      #Check to see if the container is active, otherwise it doesn't count.
      contStatus = "terminated" 
      for contStatusJson in contStatusList:
        if (contStatusJson.get("name") == contName) and (contStatusJson.get("state").get("running",None)):
          contStatus = "running"
          break
      if contStatus == "terminated":
        if DEBUG_MODE: print(f"podObject: getCpu: pod {self.name} cont {contName} (scope {scope}) not running, continue...")
        #This container is not running, continue to next.
        continue

      #If we made it here, we should get the pod container stats and count them.
      if DEBUG_MODE: print(f"podObject: getCpu: pod '{self.name}', container '{contName}', scope '{scope}'")
      try:
        cpuVal = cont.get("resources").get(scope).get("cpu")
        if cpuVal is None:
          cpuVal = "0"
      except:
        if DEBUG_MODE: print(f"Info: pod {self.name} has no {scope} cpu resources")
        cpuVal = "0"
      cpuVal = ocpValToInteger(cpuVal, "m")
      if DEBUG_MODE: print(f"podObject: cpuVal '{cpuVal}'")
      cpuCount += cpuVal

    if DEBUG_MODE: print(f"podObject: cpuCount '{cpuCount}'")
    return cpuCount

  #Returns pod's memory in KiB
  def getMem(self, scope):
    memCount = 0

    initContStatusList = self.podJson.get("status").get("initContainerStatuses")
    contStatusList = self.podJson.get("status").get("containerStatuses")

    #Go through init containers:
    containerList = self.podJson.get("spec").get("initContainers",[])
    for cont in containerList:
      contName = cont.get("name")

      #Check to see if the container is active, otherwise it doesn't count.
      contStatus = "terminated" 
      for contStatusJson in initContStatusList:
        if (contStatusJson.get("name") == contName) and (contStatusJson.get("state").get("running",None)):
          contStatus = "running"
          break
      if contStatus == "terminated":
        if DEBUG_MODE: print(f"podObject: getMem: pod {self.name} initCont {contName} (scope {scope}) not running, continue...")
        #This container is not running, continue to next.
        continue

      #If we made it here, we should get the pod container stats and count them.
      if DEBUG_MODE: print(f"podObject: getMem: pod '{self.name}', initContainer '{contName}', scope '{scope}'")
      try:
        memVal = cont.get("resources").get(scope).get("memory")
        if memVal is None:
          memVal = "0"
      except:
        if DEBUG_MODE: print(f"Info: pod {self.name} has no {scope} memory resources")
        memVal = "0"
      if DEBUG_MODE: print(f"podObject: memVal before '{memVal}'")
      memVal = ocpValToInteger(memVal, "Ki")

      if DEBUG_MODE: print(f"podObject: memVal '{memVal}'")
      memCount += memVal
      
    #Go through containers:
    containerList = self.podJson.get("spec").get("containers",[])
    for cont in containerList:
      contName = cont.get("name")

      #Check to see if the container is active, otherwise it doesn't count.
      contStatus = "terminated" 
      for contStatusJson in contStatusList:
        if (contStatusJson.get("name") == contName) and (contStatusJson.get("state").get("running",None)):
          contStatus = "running"
          break
      if contStatus == "terminated":
        if DEBUG_MODE: print(f"podObject: getMem: pod {self.name} cont {contName} (scope {scope}) not running, continue...")
        #This container is not running, continue to next.
        continue

      #If we made it here, we should get the pod container stats and count them.
      if DEBUG_MODE: print(f"podObject: getMem: pod '{self.name}', container '{contName}', scope '{scope}'")
      try:
        memVal = cont.get("resources").get(scope).get("memory")
        if memVal is None:
          memVal = "0"
      except:
        if DEBUG_MODE: print(f"Info: pod {self.name} has no {scope} memory resources")
        memVal = "0"
      if DEBUG_MODE: print(f"podObject: memVal before '{memVal}'")
      memVal = ocpValToInteger(memVal, "Ki")

      if DEBUG_MODE: print(f"podObject: memVal '{memVal}'")
      memCount += memVal

    if DEBUG_MODE: print(f"podObject: memCount '{memCount}'")
    return memCount

  #Pod phases are: Pending, Running, Succeeded, Failed, and Unknown
  def getStatus(self):
    return self.podJson.get("status").get("phase")

  def getPvcs(self):
    pvcsOut = []
    volList = self.podJson.get("spec").get("volumes")
    for vol in volList:
      pvc = vol.get("persistentVolumeClaim")
      if pvc:
        pvcName = pvc.get("claimName")
        pvcsOut.append(pvcName)
        if DEBUG_MODE: print(f"podObject: pod {self.name}: getPvcs - pvc '{pvcName}'")
    return pvcsOut

  def getEvents(self):
    events = []
    return events
#---------- End class podObject ----------#

#---------- class pvcObject ----------#
class pvcObject:

  def __init__(self,name,namespace):
    self.name=name
    self.longName=f"persistentvolumeclaim/{name}"
    self.namespace=namespace
    if DEBUG_MODE: print(f"pvcObject:------- Init: {self.longName} in ns {self.namespace}")
    self.pvcJson=self.getPvcJson()
    self.ownerHierarchy=[] #List
    self.populateOwnerHierarchy()
    self.primaryOwner=self.getPrimaryOwner()
    self.capacity=self.getPvcCapacity()
    self.accessModes=self.getAccessModes()
    self.storageClass=self.getStorageClass()
    self.volumeName=self.getVolumeName()

  def getPvcs(self):
    return None

  def getPvcJson(self):
    if DEBUG_MODE: print(f"pvcObject: getPvcJson {self.name} (ns {self.namespace})")
    resJson = None
    items = GLOBAL_PVCS[self.namespace].get("items")
    for item in items:
      itemName=item.get("metadata").get("name")
      if itemName == self.name:
        if DEBUG_MODE: print(f"pvcObject: getPvcJson - MATCH! item.metadata.name = '{itemName}'")
        resJson = item

    #We didn't find a matching json in our pre-pulled jsons. Get the resource directly.
    if resJson is None:
      if DEBUG_MODE: print(f"pvcObject: getPvcJson - Did not find pvc in cache, make oc call")
      resJson = getJsonForResource(self.longName, self.namespace)

    return resJson
  
  def populateOwnerHierarchy(self):
    ownerList=[]
    controller = controlledBy(self.longName, self.namespace)
    while controller:
      if DEBUG_MODE: print(f"pvcObject: getOwnerH: controller {controller}")
      ownerList.append(controller)
      controller = controlledBy(controller, self.namespace)
    if DEBUG_MODE: print(f"pvcObject: getOwnerH: ownerList: '{ownerList}'")
    self.ownerHierarchy = ownerList
    return ownerList
  
  def getOwnerHierarchy(self):
    return self.ownerHierarchy

  def getPrimaryOwner(self):
    if len(self.ownerHierarchy) > 0:
      return self.ownerHierarchy[-1]
    else:
      return None
  
  def getPvcCapacity(self):
    capacity = self.pvcJson.get("spec").get("resources").get("requests").get("storage")
    #Convert to number
    capacity = ocpValToInteger(capacity, "Gi")
    if DEBUG_MODE: print(f"pvcObject: capacity {capacity}Gi for pvc {self.name}")
    return capacity

  def getAccessModes(self):
    self.pvcJson.get("spec").get("accessModes")
    return None

  def getStorageClass(self):
    return self.pvcJson.get("spec").get("storageClassName")

  #pv name
  def getVolumeName(self):
    return self.pvcJson.get("spec").get("volumeName")
#---------- End class pvcObject ----------#

#---------- class serviceObject ----------#
class serviceObject:

  def __init__(self,name,namespace):
    self.name=name.lower()  #name format is: kind/name
    self.longName=self.name
    self.namespace=namespace
    if DEBUG_MODE: print(f"serviceObject:------- Init: {self.longName} in ns {self.namespace}")
    self.shortName=self.longName.split("/")[1]
    self.serviceKind=self.longName.split("/")[0]
    self.podList=[] #Initially an empty list, pods added through addPod()
    self.pvcList=[] #Initially an empty list, pvcs added through addPvc()
    self.totalPvcCapacity=0
    self.requestedMemory=0
    self.requestedCpu=0
    self.nodeName="" #Which node the pod is running on

  def getPvcs(self):
    return self.pvcList

  #Add pod name to list, and increment mem and cpu totals
  def addPod(self, podobj):
    self.podList.append(podobj.name)
    #If the pod is active, add it's resources to the totals:
    if podobj.getStatus() == "Running" or podobj.getStatus() == "Pending":
      self.requestedMemory += podobj.memoryRequest
      self.requestedCpu += podobj.cpuRequest

  #Add pvc name to list
  def addPvc(self, pvcobj):
    self.pvcList.append(pvcobj.name)
    self.totalPvcCapacity += pvcobj.getPvcCapacity()

  def getPodList(self):
    return self.podList
  
  #Pretty print the service's pod and pvc details:
  def printPodTree(self, summary=False):
    '''
    Service: mykind/myserviceinstance
        Total Requested Memory: 12700Ki
        Total Requested CPU: 4000m
        Total PVC Capacity: 30Gi
        Pods:
            pod-1-yo
        Pvcs:
            pvc-1-yo
    '''
    print(f"Service (Primary Owner): {self.longName}")

    reducedMem=reduceValue(f"{self.requestedMemory}Ki")
    print(f"{ASPACE:4}Total Requested Memory: {self.requestedMemory}Ki ({reducedMem})")
    reducedCpu=reduceValue(f"{self.requestedCpu}m")
    print(f"{ASPACE:4}Total Requested CPU: {self.requestedCpu}m ({reducedCpu})")
    print(f"{ASPACE:4}Total PVC Capacity: {self.totalPvcCapacity}Gi")

    #If only printing summary, return now:
    if summary:
      return

    #Print pods:
    print(f"{ASPACE:4}Pods:")
    if len(self.podList) == 0:
      print(f"{ASPACE:8}None")
    else:
      for pod in self.podList:
        print(f"{ASPACE:8}Name: {pod}")
        print(f"{ASPACE:12}Resources: cpu:{GLOBAL_POD_OBJECTS[self.namespace][pod].cpuRequest}m/mem:{GLOBAL_POD_OBJECTS[self.namespace][pod].memoryRequest}Ki")
        print(f"{ASPACE:12}Status: {GLOBAL_POD_OBJECTS[self.namespace][pod].getStatus()}")
        print(f"{ASPACE:12}Node: {GLOBAL_POD_OBJECTS[self.namespace][pod].getNodeName()}")
        #Print ownership path list in a formatted way:
        print(f"{ASPACE:12}Ownership Path: {GLOBAL_POD_OBJECTS[self.namespace][pod].getOwnerHierarchy()}")
        #print(f"{ASPACE:12}Ownership Path:")
        #for owner in GLOBAL_POD_OBJECTS[self.namespace][pod].getOwnerHierarchy():
        #  print(f"{ASPACE:16}{owner}")

        print(f"{ASPACE:12}PVC Mounts: {GLOBAL_POD_OBJECTS[self.namespace][pod].getPvcs()}")

    #Print pvcs:
    print(f"{ASPACE:4}Pvcs:")
    if len(self.pvcList) == 0:
      print(f"{ASPACE:8}None")
    else:
      for pvc in self.pvcList:
        print(f"{ASPACE:8}Name: {pvc}")
        print(f"{ASPACE:12}Capacity: {GLOBAL_PVC_OBJECTS[self.namespace][pvc].getPvcCapacity()}Gi")
        print(f"{ASPACE:12}Volume: {GLOBAL_PVC_OBJECTS[self.namespace][pvc].getVolumeName()}")
        print(f"{ASPACE:12}Storage Class: {GLOBAL_PVC_OBJECTS[self.namespace][pvc].getStorageClass()}")
        print(f"{ASPACE:12}Ownership Path:")
        for owner in GLOBAL_PVC_OBJECTS[self.namespace][pvc].getOwnerHierarchy():
          print(f"{ASPACE:16}{owner}")
    return
  #End printPodTree(self, summary=False)

  def printServiceCpu(self):
    #Get longest service name, for formatting printing:
    serviceColumns = len(getLongestServiceName(self.namespace))
    if DEBUG_MODE: print(f"serviceobj:printServiceCpu: serviceColumns={serviceColumns}")

    reducedCpu=reduceValue(f"{self.requestedCpu}m")
    print(f"Service (Primary Owner): {self.longName.ljust(serviceColumns)}   Requested CPU: {self.requestedCpu}m ({reducedCpu})")
    return

  def printServiceMemory(self):
    #Get longest service name, for formatting printing:
    serviceColumns = len(getLongestServiceName(self.namespace))

    reducedMem=reduceValue(f"{self.requestedMemory}Ki")
    print(f"Service (Primary Owner): {self.longName.ljust(serviceColumns)}   Requested Memory: {self.requestedMemory}Ki ({reducedMem})")
    return

  def printServicePvc(self):
    #Get longest service name, for formatting printing:
    serviceColumns = len(getLongestServiceName(self.namespace))

    print(f"Service (Primary Owner): {self.longName.ljust(serviceColumns)}   PVC Capacity: {self.totalPvcCapacity}Gi")
    return

  #Print pods for the service:
  def printPodTreeSummary(self):
    print(f"Service (Primary Owner): {self.longName}")
    #Print pods:
    print(f"{ASPACE:4}Pods:")
    if len(self.podList) == 0:
      print(f"{ASPACE:8}None")
    else:
      for pod in self.podList:
        print(f"{ASPACE:8}Name: {pod}")
    return

#---------- End class serviceObject ----------#

#-------------------------------------------------------------------------#
# End classes
#-------------------------------------------------------------------------#


#-------------------------------------------------------------------------#
# Library functions
#-------------------------------------------------------------------------#
# Run command line
def runIt(cmdStr, shV=False):
  if shV is False:
    cmdList = shlex.split(cmdStr)
  else:
    cmdList = cmdStr

  cmd = subprocess.Popen(cmdList,stdout=subprocess.PIPE,stderr=subprocess.PIPE, shell=shV)
  (cOut,cErr) = cmd.communicate()
  cRC = cmd.returncode
  return (cOut.decode(),cErr.decode(),cRC)


# Get the json output for a given OCP resource in a given namespace
# Where resourceIn is <type>/<name>. Ex: pvc/mypvc1
# Output is json dictionary from the json.loads
def getJsonForResource(resourceIn, namespaceIn):
  if DEBUG_MODE: print(f"getJsonForResource: runIt oc get {resourceIn} -n {namespaceIn} -o json")
  (resJson,rErr,rRC) = runIt(f"oc get {resourceIn} -n {namespaceIn} -o json")
  if rRC != 0:
    print(f"Error: 'oc get {resourceIn} -n {namespaceIn} -o json' returned: '{rRC}'. stderr: '{rErr}' ",file=sys.stderr)
    return None
  else:
    jsonLoad = json.loads(resJson)
  return jsonLoad


#Get all api resources in OCP cluster with ibm in the name.
#Return as comma separated string of resources.
def getJsonIbmResources(namespaceIn):
  #Get ibm resource list
  if DEBUG_MODE: print(f"getJsonIbmResources: runIt 'oc api-resources --namespaced=true -o name | grep ibm'")
  (resList,rErr,rRC) = runIt("oc api-resources --namespaced=true -o name | grep ibm", True)
  if rRC != 0:
    print(f"getJsonIbmResources: Error: 'oc api-resources --namespaced=true -o name' returned: '{rRC}'. stderr: '{rErr}' ",file=sys.stderr)
    return None
  
  resListComma = resList.replace("\n",",")

  #Get all entries for the resource list with json output:
  #(resJson,rErr,rRC) = 
  #oc get --show-kind $(oc api-resources --namespaced=true -o name | grep ibm | awk '{printf "%s%s",sep,$0; sep=","} END{print ""}') -o json -n zen-test-msk
  if DEBUG_MODE:
    print(f"getJsonIbmResources: resList '{resList}'")
    print(f"getJsonIbmResources: resListComma '{resListComma}'")

  return resListComma


#Check to see if the ocp connection is good and logged in, otherwise oc commands will fail.
def isOcpLoginValid():
  # oc cluster-info
  #Kubernetes control plane is running at https://api.cpst-ocp-cluster-d.cpst-lab.no-users.ibm.com:6443
  #
  #To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
  if DEBUG_MODE: print(f"isOcpLoginValid: runIt 'oc cluster-info'")
  (rOut,rErr,rRC) = runIt("oc cluster-info")
  if rRC != 0:
    if DEBUG_MODE: print(f"isOcpLoginValid: Error: 'oc cluster-info' returned: '{rRC}'. stderr: '{rErr}' ")
    return False
  else:
    return True

#Get the string list of the pods, for the given namespace
def getPodList(namespaceIn):
  podList=[]
  for item in GLOBAL_PODS[namespaceIn].get("items"):
    podList.append(item.get("metadata").get("name").lower())
  if DEBUG_MODE: print(f"getPodList: '{podList}'")
  return podList


#For all pods in the given namespace, create and add a pod object to the global dictionary.
def createPodObjects(nameSpaceIn):
  if DEBUG_MODE: print(f"createPodObjects: Create podobjs for ns {nameSpaceIn}")
  podList = getPodList(nameSpaceIn)
  for pod in podList:
#    try:
    podobj = podObject(pod, nameSpaceIn)
    GLOBAL_POD_OBJECTS[nameSpaceIn][pod] = podobj
#    except:
#      print(f"createPodObjects: Failed on pod {pod}")


#For all pvcs in the given namespace, create and add a pvc object to the global dictionary.
def createPvcObjects(nameSpaceIn):
  if DEBUG_MODE: print(f"createPvcObjects: Create pvcobjs for ns {nameSpaceIn}")
  for item in GLOBAL_PVCS[nameSpaceIn].get("items"):
    pvcName = item.get("metadata").get("name")
#    try:
    pvcobj = pvcObject(pvcName, nameSpaceIn)
    GLOBAL_PVC_OBJECTS[nameSpaceIn][pvcName] = pvcobj
#    except:
#      print(f"createPvcObjects: Failed on pvc {pvcName}")

#Create service objects, for all primary services found in pods and pvcs.
def createServiceObjects(nameSpaceIn):
  if DEBUG_MODE: print(f"createServiceObjects: Create serviceobjs for ns {nameSpaceIn}")
  #Go through pods and find all high level services
  if DEBUG_MODE: print(f"createServiceObjects: pod keys '{GLOBAL_POD_OBJECTS[nameSpaceIn].keys()}'")
  for podName in GLOBAL_POD_OBJECTS[nameSpaceIn].keys():
    if GLOBAL_POD_OBJECTS[nameSpaceIn][podName]:
      if DEBUG_MODE: print(f"createServiceObjects: pod {podName}")
      podobj = GLOBAL_POD_OBJECTS[nameSpaceIn][podName]

      if podobj.primaryOwner:
        #Check to see if the pod's primary owner service has been added to the global service dict.
        if podobj.primaryOwner not in GLOBAL_SERVICE_OBJECTS[nameSpaceIn].keys():
          if DEBUG_MODE: print(f"createServiceObjects: Create servobj for {podobj.primaryOwner} (hierarchy: {podobj.getOwnerHierarchy()}) (ns {nameSpaceIn})")
          servobj = serviceObject(podobj.primaryOwner, nameSpaceIn)
          GLOBAL_SERVICE_OBJECTS[nameSpaceIn][podobj.primaryOwner] = servobj

        #Add the pod to the respective service object.
        if DEBUG_MODE:
          print(f"createServiceObjects: Add pod {podobj.name} to service {GLOBAL_SERVICE_OBJECTS[nameSpaceIn][podobj.primaryOwner].name}")
        GLOBAL_SERVICE_OBJECTS[nameSpaceIn][podobj.primaryOwner].addPod(podobj)

  #Go through pvcs and find all high level services
  if DEBUG_MODE: print(f"createServiceObjects: pvc keys '{GLOBAL_PVC_OBJECTS[nameSpaceIn].keys()}'")
  for pvcName in GLOBAL_PVC_OBJECTS[nameSpaceIn].keys():
    if GLOBAL_PVC_OBJECTS[nameSpaceIn][pvcName]:
      if DEBUG_MODE: print(f"createServiceObjects: pvc {pvcName}")
      pvcobj = GLOBAL_PVC_OBJECTS[nameSpaceIn][pvcName]

      if pvcobj.primaryOwner:
        #Check to see if the pvc's primary owner service has been added to the global service dict.
        if pvcobj.primaryOwner not in GLOBAL_SERVICE_OBJECTS[nameSpaceIn].keys():
          if DEBUG_MODE: print(f"createServiceObjects: Create servobj for {pvcobj.primaryOwner} (hierarchy: {pvcobj.getOwnerHierarchy()}) (ns {nameSpaceIn})")
          servobj = serviceObject(pvcobj.primaryOwner, nameSpaceIn)
          GLOBAL_SERVICE_OBJECTS[nameSpaceIn][pvcobj.primaryOwner] = servobj

        #Add the pvc to the respective service object.
        if DEBUG_MODE:
          print(f"createServiceObjects: Add pvc {pvcobj.name} to service {GLOBAL_SERVICE_OBJECTS[nameSpaceIn][pvcobj.primaryOwner].name}")
        GLOBAL_SERVICE_OBJECTS[nameSpaceIn][pvcobj.primaryOwner].addPvc(pvcobj)
#End createServiceObjects(nameSpaceIn)

def getLongestServiceName(nameSpaceIn):
  serviceNames = GLOBAL_SERVICE_OBJECTS[nameSpaceIn].keys()
  longestName = max(serviceNames, key=len)
  if DEBUG_MODE: print(f"getLongestServiceName: longest service '{longestName}' for '{serviceNames}'")
  return str(longestName)

#Returns list of pvc name strings which have no owner
def getOrphanPvcs(nameSpaceIn):
  pvcOrphans=[]
  for pvcName in GLOBAL_PVC_OBJECTS[nameSpaceIn].keys():
    pvcobj = GLOBAL_PVC_OBJECTS[nameSpaceIn][pvcName]
    if pvcobj.primaryOwner is None:
      pvcOrphans.append(pvcName)
  return pvcOrphans


#Add up capacity of all orphan pvcs and return (in Gi):
def getOrphanPvcsCapacity(nameSpaceIn):
  capacityOut = 0
  for pvcName in getOrphanPvcs(nameSpaceIn):
    pvcobj = GLOBAL_PVC_OBJECTS[nameSpaceIn][pvcName]
    capacityOut += pvcobj.getPvcCapacity()
  return capacityOut


#Returns list of pod name strings which have no owner
def getOrphanPods(nameSpaceIn):
  podOrphans=[]
  for podName in GLOBAL_POD_OBJECTS[nameSpaceIn].keys():
    podobj = GLOBAL_POD_OBJECTS[nameSpaceIn][podName]
    if podobj.primaryOwner is None:
      podOrphans.append(podName)
  return podOrphans


#Print orphan resources:
def printOrphanResources(nameSpaceIn, summary=False):
  print(f"Standalone Pods (No owner/controller):")

  if len(getOrphanPods(nameSpaceIn)) == 0:
    print(f"{ASPACE:4}None")
  else:
    if not summary:
      for pod in getOrphanPods(nameSpaceIn):
        print(f"{ASPACE:4}Name: {pod}")
        print(f"{ASPACE:8}Resources: cpu:{GLOBAL_POD_OBJECTS[nameSpaceIn][pod].cpuRequest}m/mem:{GLOBAL_POD_OBJECTS[nameSpaceIn][pod].memoryRequest}Ki")
        print(f"{ASPACE:8}Status: {GLOBAL_POD_OBJECTS[nameSpaceIn][pod].getStatus()}")

  print(f"Standalone Pvcs (No owner/controller):")
  if len(getOrphanPvcs(nameSpaceIn)) == 0:
    print(f"{ASPACE:4}None")
  else:
    print(f"{ASPACE:4}Total PVC Capacity: {getOrphanPvcsCapacity(nameSpaceIn)}Gi")
    if not summary:
      for pvc in getOrphanPvcs(nameSpaceIn):
        print(f"{ASPACE:4}Name: {pvc}")
        print(f"{ASPACE:8}Capacity: {GLOBAL_PVC_OBJECTS[nameSpaceIn][pvc].getPvcCapacity()}Gi")
        print(f"{ASPACE:8}Volume: {GLOBAL_PVC_OBJECTS[nameSpaceIn][pvc].getVolumeName()}")
        print(f"{ASPACE:8}Storage Class: {GLOBAL_PVC_OBJECTS[nameSpaceIn][pvc].getStorageClass()}")
  return
#End printOrphanResources(nameSpaceIn)


def ocpValToInteger(valIn, returnType):
  normVal = 0
  retVal = 0

  #First normalize the input value, to bytes/baseunits:
  if DEBUG_MODE: print(f"ocpValToInteger: value in '{valIn}' (returnType '{returnType}')")

  if "m" in valIn:
    normVal = int(valIn.rstrip("m")) / 1000
  elif "Ki" in valIn:
    normVal = int(valIn.rstrip("Ki")) * 1024
  elif "K" in valIn:
    normVal = int(valIn.rstrip("K")) * 1000
  elif "Mi" in valIn:
    normVal = int(valIn.rstrip("Mi")) * 1024 * 1024
  elif "M" in valIn:
    normVal = int(valIn.rstrip("M")) * 1000 * 1000
  elif "Gi" in valIn:
    normVal = int(valIn.rstrip("Gi")) * 1024 * 1024 * 1024
  elif "G" in valIn:
    normVal = int(valIn.rstrip("G")) * 1000 * 1000 * 1000
  else:
    try:
      normVal = int(valIn)
    except:
      print(f"Error: ocpValToInteger: {valIn} unknown type",file=sys.stderr)
      return -1
  
  #Now convert normalized value to return type:
  if DEBUG_MODE: print(f"ocpValToInteger: normalized value '{normVal}'")

  if "m" == returnType:
    retVal = normVal * 1000
  elif "Ki" == returnType:
    retVal = normVal / 1024
  elif "K" == returnType:
    retVal = normVal / 1000
  elif "Mi" == returnType:
    retVal = normVal / 1024 / 1024
  elif "M" == returnType:
    retVal = normVal / 1000 / 1000
  elif "Gi" == returnType:
    retVal = normVal / 1024 / 1024 / 1024
  elif "G" == returnType:
    retVal = normVal / 1000 / 1000 / 1000
  else:
    retVal = normVal
  
  #Now round the number to nearest whole:
  retVal = round(retVal)
  if DEBUG_MODE: print(f"ocpValToInteger: return val '{retVal}'")
  return retVal
#End ocpValToInteger(valIn, returnType)


#Reduces input value to a more human readable value.
#Only support "m" or "Ki" values.
def reduceValue(valIn):
  newVal = valIn
  if "m" in valIn:
    valueString = valIn.rstrip("m")
    if len(valueString) >= 4:
      try:
        vInt = round(int(valueString) / 1000, 1)
        newVal = f"{vInt}"
      except:
        newVal = valIn
  elif "Ki" in valIn:
    valueString = valIn.rstrip("Ki")
    if ( (len(valueString) >= 4) and (len(valueString) < 7) ):
      #Convert to Mi:
      try:
        vInt = round(int(valueString) / 1024, 1)
        newVal = f"{vInt}Mi"
      except:
        newVal = valIn
    elif len(valueString) >= 7:
      #Convert to Gi:
      try:
        vInt = round(int(valueString) / 1024 / 1024, 1)
        newVal = f"{vInt}Gi"
      except:
        newVal = valIn
  return newVal


#TODO Delete these next few functions?
def getPvcVolume(pvcIn, namespaceIn):
  cmd = f"oc get pvc {pvcIn} -n {namespaceIn}"
  (pvcVolOut,rErr,rRC) = runIt(cmd + " -o jsonpath='{.spec.volumeName}'")
  if rRC != 0:
    print("Error: '" + cmd + " -o jsonpath='{.spec.volumeName}''")
  return (pvcVolOut, rRC)

def getPodsMountingPvc(pvcIn, namespaceIn):
  matchOn = False
  podListOut = []
  (pvcDescribe,rErr,rRC) = runIt(f"oc describe pvc {pvcIn} -n {namespaceIn}")
  if rRC != 0:
    print(f"Error: 'oc describe pvc {pvcIn} -n {namespaceIn}' returned: '{rErr}'")
    return (podListOut,rRC)
  #print("podsOut '{0}'".format(pvcDescribe))
  pvcLines = pvcDescribe.splitlines()
  for line in pvcLines:
    if re.search("Mounted By:",line):
      line = line.split('Mounted By:')[1]
      if not re.search("<none>",line):
        matchOn = True
    if re.search("Events:",line):
      matchOn = False
    if matchOn:
      podListOut.append(line.lstrip().rstrip())
  #print(f"Done here. podListOut '{podListOut}'")
  return (podListOut,rRC)


def getFs1MountPointForPod(podIn, namespaceIn):
  mountDir = ""
  (rOut,rErr,rRC) = runIt("oc exec {podIn} -n {namespaceIn} -- df | grep \"^fs1\"".format(podIn=podIn,namespaceIn=namespaceIn), True)
  if rRC != 0:
    print(f"Error: 'oc exec {podIn} -n {namespaceIn} -- df' returned: '{rRC}'. stderr: '{rErr}'")
  else:
    mountDir = rOut.split()[-1]
  return (mountDir, rRC)


def getFs1Contents(podIn, namespaceIn, dirIn):
  (contents, rErr, rRC) = runIt(f"oc exec {podIn} -n {namespaceIn} -- ls -l {dirIn}")
  return (contents, rRC)


#For the given resource, get the owner/controller and return in kind/name format (lower case).
#Looks through the cached json resources first. If not found, performs an oc command to get json details.
def controlledBy(resourceIn, nsIn):
  #oc get pod/zen-metastoredb-0
  #ownerReferences:
  #- apiVersion: apps/v1
  #  blockOwnerDeletion: true
  #  controller: true
  #  kind: StatefulSet
  #  name: zen-metastoredb
  #  uid: ff60c9b0-3cd5-46ed-82a4-398568bc0ce2

  #Check the pre-populated kinds first
  kindIn = resourceIn.split('/')[0].lower()
  resNameIn = resourceIn.split('/')[1]
  resJson = None
  items = None

  if DEBUG_MODE: print(f"controlledBy: kindIn '{kindIn}'")
  if kindIn == "statefulset":
    if DEBUG_MODE: print(f"controlledBy: sts it. kind={kindIn}/name={resNameIn}")
    items = GLOBAL_STATEFULSET[nsIn].get("items",[])
  elif kindIn == "replicaset":
    if DEBUG_MODE: print(f"controlledBy: repset it. kind={kindIn}/name={resNameIn}")
    items = GLOBAL_REPLICASET[nsIn].get("items",[])
  elif kindIn == "job":
    if DEBUG_MODE: print(f"controlledBy: job it. kind={kindIn}/name={resNameIn}")
    items = GLOBAL_JOBS[nsIn].get("items",[])
  elif kindIn == "deployment":
    if DEBUG_MODE: print(f"controlledBy: deploy it. kind={kindIn}/name={resNameIn}")
    items = GLOBAL_DEPLOYMENT[nsIn].get("items",[])
  elif kindIn == "pod":
    items = GLOBAL_PODS[nsIn].get("items",[])
    if DEBUG_MODE: print(f"controlledBy: pod it. kind={kindIn}/name={resNameIn} (items list size: {len(items)}, GLOBAL_PODS size: {len(GLOBAL_PODS[nsIn])})")
  elif kindIn == "persistentvolumeclaim":
    if DEBUG_MODE: print(f"controlledBy: pvc it. kind={kindIn}/name={resNameIn}")
    items = GLOBAL_PVCS[nsIn].get("items",[])
  elif kindIn == "configmap":
    if DEBUG_MODE: print(f"controlledBy: configmap it. kind={kindIn}/name={resNameIn}")
    items = GLOBAL_CONFIGMAP[nsIn].get("items",[])
  else:
    if DEBUG_MODE: print(f"controlledBy: else... lets try ibm and cognitive data")
    items = GLOBAL_IBM[nsIn].get("items",[])
    try:
      items.extend(GLOBAL_COGNITIVEDATA[nsIn].get("items",[]))
    except BaseException as err:
      if DEBUG_MODE: print(f"controlledBy: No entries in GLOBAL_COGNITIVEDATA[{nsIn}]. {type(err)} '{err}'")


  if items:
    for item in items:
      itemKind=item.get("kind").lower()
      itemName=item.get("metadata").get("name")
      #if itemKind == "pod":
      #  print(f"pod iterate item: {item}")
      #  sleep(1)
      if itemKind == kindIn and itemName == resNameIn:
        if DEBUG_MODE: print(f"controlledBy: MATCH! item.metadata.name = '{itemName}'")
        resJson = item

  #We didn't find a matching json in our pre-pulled jsons. Get the resource directly.
  if resJson is None:
    if DEBUG_MODE: print(f"other: {resourceIn}")
    resJson = getJsonForResource(resourceIn, nsIn)
    
  #GLOBAL_STATEFULSET = getJsonForResource("statefulset","zen-test-msk")
  #GLOBAL_REPLICASET = getJsonForResource("replicaset","zen-test-msk")
  #GLOBAL_JOBS = getJsonForResource("jobs","zen-test-msk")
  #GLOBAL_PODS = getJsonForResource("pods","zen-test-msk")

  #podJson = getJsonForResource(resourceIn, nsIn)
  if not resJson:
    if DEBUG_MODE: print(f"Error: controlledBy: resJson for {resourceIn} is empty")
    return 0
  
  ownerJson = resJson.get("metadata").get("ownerReferences")
  if not ownerJson:
    return 0
  
  if type(ownerJson) is list:
    ownerKind = ownerJson[0].get("kind")
    ownerName = ownerJson[0].get("name")
  else:
    ownerKind = ownerJson.get("kind")
    ownerName = ownerJson.get("name")
  owner = f"{ownerKind}/{ownerName}".lower()
  return owner
#End controlledBy(resourceIn, nsIn)


#Pull common json data from OCP cluster, running several oc commands. May take a while.
def getGlobalJson(nameSpaceIn):
  print(f"Pulling initial json data from cluster for namespace {nameSpaceIn}.",end='')
  sys.stdout.flush()
  GLOBAL_STATEFULSET[nameSpaceIn] = getJsonForResource("statefulset",nameSpaceIn)
  print(".",end='')
  sys.stdout.flush()
  GLOBAL_REPLICASET[nameSpaceIn] = getJsonForResource("replicaset",nameSpaceIn)
  print(".",end='')
  sys.stdout.flush()
  GLOBAL_JOBS[nameSpaceIn] = getJsonForResource("jobs",nameSpaceIn)
  print(".",end='')
  sys.stdout.flush()
  GLOBAL_DEPLOYMENT[nameSpaceIn] = getJsonForResource("deployment",nameSpaceIn)
  print(".",end='')
  sys.stdout.flush()
  GLOBAL_PODS[nameSpaceIn] = getJsonForResource("pods",nameSpaceIn)
  print(".",end='')
  sys.stdout.flush()
  GLOBAL_PVCS[nameSpaceIn] = getJsonForResource("pvc",nameSpaceIn)
  print(".",end='')
  sys.stdout.flush()
  GLOBAL_CONFIGMAP[nameSpaceIn] = getJsonForResource("configmap",nameSpaceIn)
  print(".",end='')
  sys.stdout.flush()

  #Get ibm resource list
  if DEBUG_MODE: print(f"getGlobalJson: runIt 'oc api-resources --namespaced=true -o name | grep ibm'")
  (resList,rErr,rRC) = runIt("oc api-resources --namespaced=true -o name | grep ibm", True)
  if rRC == 0:
    print(".",end='')
    sys.stdout.flush()

    resListComma = resList.replace("\n",",").rstrip(",")
    GLOBAL_IBM[nameSpaceIn] = getJsonForResource(resListComma, nameSpaceIn)
  print(".",end='')
  sys.stdout.flush()

  #Get cognitivedata resource list
  if DEBUG_MODE: print(f"getGlobalJson: runIt 'oc api-resources --namespaced=true -o name | grep cognitivedata'")
  (resList,rErr,rRC) = runIt("oc api-resources --namespaced=true -o name | grep cognitivedata", True)
  if rRC == 0:
    print(".",end='')
    sys.stdout.flush()

    resListComma = resList.replace("\n",",").rstrip(",")
    GLOBAL_COGNITIVEDATA[nameSpaceIn] = getJsonForResource(resListComma, nameSpaceIn)
  print(". complete.")
#End getGlobalJson(nameSpaceIn)


#Pull common json data from OCP cluster, running several oc commands. May take a while.
def getGlobalEventsJson(nameSpaceIn):
  print(f"Pulling Events json data from cluster for namespace {nameSpaceIn}.")
  GLOBAL_EVENTS[nameSpaceIn] = getJsonForResource("events",nameSpaceIn)


#Create objects for pods, pvcs, and services, to be used throughout the program.
def compileClusterObjects(nameSpaceIn):
  print(f"Compiling pod, pvc, and service objects for namespace {nameSpaceIn}.",end='')
  sys.stdout.flush()
  if DEBUG_MODE: print(f"Create podobjs")
  createPodObjects(nameSpaceIn)
  print(".",end='')
  sys.stdout.flush()

  if DEBUG_MODE: print(f"Create pvcobjs")
  createPvcObjects(nameSpaceIn)
  print(".",end='')
  sys.stdout.flush()

  if DEBUG_MODE: print(f"Create servobjs")
  createServiceObjects(nameSpaceIn)
  print(". complete.\n")

def printUsage():
  printVars="{Ttsacmp}"
  print(f'''\
Usage: {sys.argv[0]} -n <ns> -{printVars} [-S <service>]
  Parameters:
    -n ns / --namespace    - Namespace to query
    -S service / --service - [Optional] Specific service to query, in format 'kind/serviceName'
  Print options:
    Note: All outputs are based on the owning high-level service.
    -T                     - Print full pod tree
    -t                     - Print pod tree summary
    -s                     - Print service usage summary
    -c                     - Print total CPU requests for pods under each service
    -m                     - Print total memory requests for pods under each service
    -p                     - Print total PVC capacity for pods under each service
    -a                     - Print standalone (no controller) resources
  Other:
    -d / --debug           - Debug prints
    -h / --help            - Help''')


#-------------------------------------------------------------------------#
# Main
#-------------------------------------------------------------------------#
def main():

  #--- Handle getops ---#
  #Init vars:
  nameSpaceIn=None
  getEvents=False
  printPodTree=False
  printFullPodTree=False
  printServiceSummary=False
  printServiceMemory=False
  printServiceCpu=False
  printServicePvc=False
  printStandaloneResources=False
  specificService=None

  
  #-Prepare options-:
  try:
    options, args = getopt.getopt(sys.argv[1:], "hacdEmn:psS:tT", ["help","debug","namespace=","service-summary","service="])
  except:
    printUsage()
    sys.exit(2)
  
  #-Go through options-:
  for opt, arg in options:
    if opt in ("-h","--help"):
      printUsage()
      sys.exit(2)
    elif opt == "-a": printStandaloneResources=True
    elif opt == "-c": printServiceCpu=True
    elif opt in ("-d","--debug"):
      global DEBUG_MODE
      DEBUG_MODE = True
    elif opt == "-E": getEvents=True
    elif opt == "-m": printServiceMemory=True
    elif opt in ("-n","--namespace"): nameSpaceIn=arg
    elif opt == "-p": printServicePvc=True
    elif opt in ("-s","--service-summary"): printServiceSummary=True
    elif opt in ("-S","--service"): specificService=arg
    elif opt == "-t": printPodTree=True
    elif opt == "-T": printFullPodTree=True
  if DEBUG_MODE: print(f"getopts: {options}")
  
  #-Validate arguments-:
  if nameSpaceIn is None:
    print("Error: Requires namespace as input.",file=sys.stderr)
    printUsage()
    sys.exit(2)
  
  #TODO Events not ready yet:
  if getEvents:
    print("TODO Event display not available yet.")
    sys.exit(2)

  #Count number of printing options (should only be one):
  printCount = [printServiceSummary, printPodTree, printFullPodTree, printServiceCpu, printServiceMemory, printServicePvc, printStandaloneResources].count(True)
  #Make sure only one printing options was provided:
  if printCount > 1:
    print("Error: Only one print option is allowed.",file=sys.stderr)
    printUsage()
    sys.exit(2)
  elif printCount == 0:
    print("Error: A print command is required.",file=sys.stderr)
    printUsage()
    sys.exit(2)
  
  #--- Make sure the ocp server session is good ---#
  if not isOcpLoginValid():
    print(f"Error: Not logged in to ocp server or server connection problems",file=sys.stderr)
    sys.exit(1)


  #--- Collect all global data ahead of time ---#
  global GLOBAL_STATEFULSET
  global GLOBAL_REPLICASET
  global GLOBAL_JOBS
  global GLOBAL_DEPLOYMENT
  global GLOBAL_PODS
  global GLOBAL_IBM
  global GLOBAL_PVCS
  global GLOBAL_CONFIGMAP
  global GLOBAL_COGNITIVEDATA
  global GLOBAL_EVENTS

  global GLOBAL_POD_OBJECTS
  global GLOBAL_SERVICE_OBJECTS
  global GLOBAL_PVC_OBJECTS

  #This will perform several oc gets to the OCP cluster and takes the most amount of time in the script.
  getGlobalJson(nameSpaceIn)

  #Get events, if requested:
  if getEvents:
    getGlobalEventsJson(nameSpaceIn)

  #Create objects
  compileClusterObjects(nameSpaceIn)


  #--- Decide what to output ---#
  #Determine which service(s) to act upon:
  if specificService:
    if specificService not in GLOBAL_SERVICE_OBJECTS[nameSpaceIn].keys():
      print(f"Error: Service '{specificService}' not found for namespace {nameSpaceIn}. All services found: {GLOBAL_SERVICE_OBJECTS[nameSpaceIn].keys()}", file=sys.stderr)
      sys.exit(1)
    serviceList=[specificService]
  else:
    serviceList=GLOBAL_SERVICE_OBJECTS[nameSpaceIn].keys()
  if DEBUG_MODE: print(f"serviceList: {serviceList}")

  #Print the desired items:
  if printServiceSummary:
  #- Print footprint summary for all desired services -#
    for serviceName in serviceList:
      servobj = GLOBAL_SERVICE_OBJECTS[nameSpaceIn][serviceName]
      servobj.printPodTree(summary=True)
    #Print orphan resources:
    if not specificService: printOrphanResources(nameSpaceIn, summary=True)

  elif printPodTree:
  #Print just pods for each desired service:
    for serviceName in serviceList:
      servobj = GLOBAL_SERVICE_OBJECTS[nameSpaceIn][serviceName]
      servobj.printPodTreeSummary()

    #Print orphan pods:
    if not specificService: 
      print(f"Standalone Pods (No owner/controller):")
      if len(getOrphanPods(nameSpaceIn)) == 0:
        print(f"{ASPACE:4}None")
      else:
        print(f"{ASPACE:4}Name: {pod}")

  elif printFullPodTree:
  #Print verbose pod tree for all desired services:
    for serviceName in serviceList:
      servobj = GLOBAL_SERVICE_OBJECTS[nameSpaceIn][serviceName]
      servobj.printPodTree()
    #Print orphan resources:
    if not specificService: printOrphanResources(nameSpaceIn)

  elif printServiceCpu:
  #Print total requested cpus for desired services:
    for serviceName in serviceList:
      servobj = GLOBAL_SERVICE_OBJECTS[nameSpaceIn][serviceName]
      servobj.printServiceCpu()

  elif printServiceMemory:
  #Print total requested cpus for desired services:
    for serviceName in serviceList:
      servobj = GLOBAL_SERVICE_OBJECTS[nameSpaceIn][serviceName]
      servobj.printServiceMemory()

  elif printServicePvc:
  #Print total requested cpus for desired services:
    for serviceName in serviceList:
      servobj = GLOBAL_SERVICE_OBJECTS[nameSpaceIn][serviceName]
      servobj.printServicePvc()
    
    #Print orphan resources:
    if not specificService: 
      #This count is for the longest service name - (diff of "Service (Primary Owner):" and "Standalone Pvcs (No owner/controller)")
      formatColumnCount = len(getLongestServiceName(nameSpaceIn)) - 14
      orphanPvcCap=getOrphanPvcsCapacity(nameSpaceIn)
      print(f"Standalone Pvcs (No owner/controller): {' '.ljust(formatColumnCount)}   PVC Capacity: {orphanPvcCap}Gi")

  elif printStandaloneResources:
    printOrphanResources(nameSpaceIn)

#End main()

if __name__ == "__main__":
  main()

