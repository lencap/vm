""" vm """

# Import required modules
import sys
import os
import time
import shutil
import subprocess
import traceback
import tarfile
import re
import socket

try:
  from configparser import ConfigParser  # For ver > 3.0
except ImportError:
  from ConfigParser import ConfigParser  # For ver < 3.0

# String colorization functions need to be defined as early as possible
def whi1 (s): s = str(s) ; return '\033[0;37m' + s + '\033[0m'
def red2 (s): s = str(s) ; return '\033[1;31m' + s + '\033[0m'
def yel2 (s): s = str(s) ; return '\033[1;33m' + s + '\033[0m'

# Ensure vboxapi module is installed
try:
  from vboxapi import VirtualBoxManager
except ImportError:
  print "Missing " + whi1('vboxapi') + " module. VirtualBox needs to be installed."
  sys.exit(1)

# Global variables
prgVer    = 'v2.2.5'
prgName   = 'vm'
prgNameC  = whi1(prgName)
vmhome    = os.environ['HOME'] + '/.vm'    # Program's configuration area
vmprikey  = vmhome + '/vmbin/vmkey'        # Global private SSH key
vmpubkey  = vmhome + '/vmbin/vmkey.pub'    # Global public SSH key
vmksconf  = vmhome + '/vmbin/ks.cfg'       # Automated Kickstart installation file
vmrootrc  = vmhome + '/vmbin/root.bashrc'  # Default root bashrc file
vmpreprc  = vmhome + '/vmbin/vmprep'       # Pre-imaging preparation script
vmbootrc  = vmhome + '/vmbin/vmboot'       # Bootstrap script
vmconf    = 'vm.conf'                      # Default provisioning filename
vmhddsize = 8589934592                     # Default VM disk size in bytes (8GB)
vbnictype = 'Virtio'                       # Virtio and 82545EM offer best CentOS perf
vmdefip   = '10.11.12.2'                   # Default IP address
vmuser    = 'root'                         # WARNING: Be aware that this is poor
vmpwd     = 'password'                     # WARNING: but convenient security


def vmUsage():
  print "Simple CentOS VM Manager " + prgVer + "\n" + \
    prgNameC + " list                                               List all VMs\n" + \
    prgNameC + " create <vmName> <imgName>                          Create VM from image\n" + \
    prgNameC + " del <vmName> [-f]                                  Delete VM. Force option\n" + \
    prgNameC + " start <vmName> [-gui]                              Start VM. GUI option\n" + \
    prgNameC + " stop <vmName> [-f]                                 Stop VM. Force option\n" + \
    prgNameC + " ssh <vmName> [<command>]                           SSH into or optionally run command on VM\n" + \
    prgNameC + " prov [init]                                        Provision VMs as per vmconf file. Use init to create basic file\n" + \
    prgNameC + " info <vmName>                                      Dump VM details\n" + \
    prgNameC + " mod <vmName> <cpus> [<memory>]                     Modify VM CPUs and memory. Memory defaults to 1024\n" + \
    prgNameC + " ip <vmName> <ip>                                   Set VM IP address\n" + \
    prgNameC + " netlist                                            List available networks\n" + \
    prgNameC + " netadd <ip>                                        Create new network\n" + \
    prgNameC + " netdel <vboxnetX>                                  Delete given network\n" + \
    prgNameC + " imglist                                            List all available images\n" + \
    prgNameC + " imgcreate <imgName> <ISOfile|vmName> [-f1] [-f2]   Create new image from vmName or ISO. Force imgName|vmName options\n" + \
    prgNameC + " imgdel <imgName> [-f]                              Delete image. Force option\n" + \
    prgNameC + " imgimp <imgFile>                                   Import image. Make available to this program"
  sys.exit(1)


def dumpObj(obj):
  for attr in dir(obj):
    print "obj.%s = %s" % (attr, getattr(obj, attr))


def enumElem(enumerate, element):
  all = const.all_values(enumerate)     # Global variable
  for key in all.keys():
    if str(element) == str(all[key]):
      return key
  return "<unknown>"


def openSession(vm, lockType):
  # Give last session 5 sec to close
  timeOut = time.time() + 5
  while timeOut > time.time() and vm.sessionState != const.SessionState_Unlocked:   
    time.sleep(0.01)
  session = vboxmgr.getSessionObject(vbox)  # Get ISession objects
  vm.lockMachine(session, lockType)
  # LockType_Null=0   LockType_Shared=1   LockType_Write=2  LockType_VM=3
  return session.machine, session           # Return mutable IMachine and ISession objects


def closeSession(session):
  session.machine.saveSettings()  # Save all settings and unlock session
  session.unlockMachine()
  return 0


def getVmIp(vm):
  ip = vm.getGuestPropertyValue('/vm/netip')  # Try official store location for this program
  if ip == '' or ip == None:                   # If missing, try another area, used by others
    ip = vm.getGuestPropertyValue('/VirtualBox/GuestInfo/Net/1/V4/IP')
    if ip == '' or ip == None:                 # If missing still, try yet another area 
      ip = vm.getGuestPropertyValue('/VirtualBox/GuestInfo/Net/0/V4/IP')
      if ip == '' or ip == None:
        ip  = '<undefined>'                    # Default to it being undefined 
  return ip


def aliveIP(ip):
  ret = subprocess.call('ping -c 1 -W 300 ' + ip + ' >/dev/null 2>&1', shell=True)
  # Send 1 packet and wait 300 milliseconds for a reply
  if ret == 0:
    return True  # Zero means success
  else:
    return False # Any other integer is a failure


def uniqueIP(ip):
  for vm in vbox.getMachines():
    if getVmIp(vm) == ip:
      return False
  return True


def nextUniqueIP(ip):
  while not uniqueIP(ip):
    ipNet = '.'.join(ip.split('.')[:3])     # Network address
    ip4th = str(int(ip.split('.')[3]) + 1)  # Add one to 4th octect
    ip = ipNet + '.' + ip4th
    if int(ip4th) > 254:                    # If it's greater than 254 restart at 2
      ip = ipNet + '.' + str(int(2))        # Add one to 4th octect
  return ip


def setVmIp(vm, ip):
  # We only support one of the 7 VirtualBox network configuration types: HostOnly.
  # HostOnly uses 2 interfaces; NIC0 with NAT (for routing external traffic) and NIC1
  # with the actual HostOnly interface attached to a vboxnet network 

  if not validIP(ip):
    print "%s is an invalid IP address" % whi1(ip)
    return 1
  if ip.split('.')[3] == '1':
    print "IP ending in .1 is reserved for the vboxnet gateway itself"
    return 1
  for vmTmp in vbox.getMachines():
    if vmTmp.name == vm.name:
      continue   # Skip this machine itself
    if getVmIp(vmTmp) == ip:
      print "Error: IP %s is taken by %s" % (whi1(ip), whi1(vmTmp.name))
      return 1
  ipNet = '.'.join(ip.split('.')[:3])  # Derive IP's network address (the first 3 octects)
  # If given IP address fits into an existing vboxnet network, then put it in that vboxnet
  # else create a new vboxnet
  newHOName = newHOIP = None
  for tmpHO in getNetList():
    if ipNet == '.'.join(tmpHO.IPAddress.split('.')[:3]):  # vboxnet network exists so lets use it
      newHOName = tmpHO.name
      break
  if newHOName == None:  # If not assigned by above loop, it means we have to create new vboxnet
    newHOName = vmNetAdd([ipNet + '.1'])
  (vmMuta, session) = openSession(vm, const.LockType_Write)
  # HostOnly uses NIC0 (with NAT) for routing external traffic (with no SSH port forwarding)
  nic0 = vmMuta.getNetworkAdapter(0)
  nic0.enabled           = True
  nic0.attachmentType    = const.all_values("NetworkAttachmentType")["NAT"] 
  nic0.adapterType       = const.all_values("NetworkAdapterType")[vbnictype]  # Global variable
  nic0.bridgedInterface  = None
  nic0.hostOnlyInterface = None
  nic0.NATEngine.DNSPassDomain = True
  nic0.NATEngine.DNSUseHostResolver = True
  for pfRule in nic0.NATEngine.getRedirects():
    # Remove ssh-port forwarding rule if it exists
    if pfRule.split(",")[0] == "ssh":
      nic0.NATEngine.removeRedirect("ssh")
  # But it uses NIC1 as its primary adapter
  nic1 = vmMuta.getNetworkAdapter(1)
  nic1.enabled           = True
  nic1.attachmentType    = const.all_values("NetworkAttachmentType")["HostOnly"] 
  nic1.adapterType       = const.all_values("NetworkAdapterType")[vbnictype]  # Global variable
  nic1.bridgedInterface  = None
  nic1.hostOnlyInterface = newHOName

  # Store official IP address for this VM in its /vm/* guest property area
  vmMuta.setGuestPropertyValue("/vm/netip", ip)
  vmMuta.setGuestPropertyValue("/VirtualBox/GuestInfo/Net/1/V4/IP",        ip)
  vmMuta.setGuestPropertyValue("/VirtualBox/GuestInfo/Net/1/V4/Broadcast", ".".join(ip.split(".")[:3]) + ".255")
  vmMuta.setGuestPropertyValue("/VirtualBox/GuestInfo/Net/1/V4/Netmask",   "255.255.255.0")
  closeSession(session)

  return 0


def vmList():
  if len(vbox.getMachines()) == 0:
    return 0
  print "%-30s %-5s %-6s %-12s %s" % ("NAME", "CPU", "MEM", "STATE", "SSH")
  for vm in vbox.getMachines():
    state = enumElem("MachineState", vm.state)
    ip = getVmIp(vm)
    sshConn = vmuser + "@" + ip   # vmuser is global
    print "%-30s %-5s %-6s %-12s %s" % (vm.name, vm.CPUCount, vm.memorySize, state, sshConn)
  return 0


def vmCreate(args):
  vmName = imgName = None
  if len(args) == 2:
    (vmName, imgName) = args
  else:
    print "Usage: vm create <vmName> <imgName>"
    return 1

  imgFile = vmhome + '/' + imgName
  if not (os.path.isfile(imgFile)): 
    print "Image " + whi1(imgFile) + " doesn't exist."
    return 1

  try:
    vm = vbox.findMachine(vmName)  # get the IMachine object
    print "VM %s already exist" % whi1(vmName)
    return 1
  except:
    dummyVar = 1   # ... let' continue creating VM

  # Inspect OVA before importing into this new VM we're creating from it
  appliance = vbox.createAppliance()   # Create empty IAppliance object
  appliance.read(imgFile)              # Read OVA file into this IAppliance object
  appliance.interpret()                # Populate virtualSystemDescriptions object
  warnings = appliance.getWarnings()   # Check for warnings during OVA interpretation
  if warnings:
    print "OVA interpretation warnings: %s" % (yel2(warnings))
  sysDesc = appliance.getVirtualSystemDescriptions()  # Get IVirtualSystemDescription object
  if len(sysDesc) != 1:
    print red2("Error: There are 0 or more than 1 VM described in this OVA. Unsupported.")
    return 1

  # getDescription returns a list data structure of 5 other lists, which we'll call descList
  descList = sysDesc[0].getDescription() # Get descriptions for the only VM we expect in the OVA
  dCount = sysDesc[0].count              # Get the number of descriptions
  types = descList[0]                    # 1st list holds all the VirtualSystemDescriptionType
          # Ignore                 01  OS                     02  Name                   03
          # Product                04  Vendor                 05  Version                06
          # ProductUrl             07  VendorUrl              08  Description            09
          # License                10  Miscellaneous          11  CPU                    12
          # Memory                 13  HardDiskControllerIDE  14  HardDiskControllerSATA 15
          # HardDiskControllerSCSI 16  HardDiskControllerSAS  17  HardDiskImage          18
          # Floppy                 19  CDROM                  20  NetworkAdapter         21
          # USBController          22  SoundCard              23  SettingsFile           24
  refs = descList[1]               # 2nd list is 'refs' use by some descriptions
  OVFValues = descList[2]          # 3rd list is original 'OVFValues' saved in the OVF
  VBoxValues = descList[3]         # 4th list is 'VBoxValues' suggestions for new VMs to be created with this OVF
  extraConfigValues = descList[4]  # 5th list is 'extraConfigValues' for additional configs for each entry

  # Note: The index in each list corresponds to values for that specific description. so
  # For instance if types[2] = 3, the Name of the machine, then actual name is stored in
  # VBoxValues[2]. The most important value for each description is whether or not it is
  # enabled, which is held in list enableValue[]

  # Now let's import all resources defined in the OVA, but disable USB and Sound Card.
  # Always create VM with: 1 cpu, 1GB RAM, HostOnly networking, and 2 disks

  enableValue = [True] * (dCount) # Create/init boolean list assuming all items will remain enabled
  onlyOneHdd = True               # Make these 2 inverse assumptions to then adjust within the loop 
  onlyOneNic = True
  for i in range(dCount):
    if types[i] in [22, 23]:   # Disable USB and sound
      enableValue[i] = False
      continue
    if types[i] == 3:          # Set VM Name
      VBoxValues[i] = vmName
      continue
    if types[i] == 12:         # Set CPU numbers (string value)
      VBoxValues[i] = '1'
      continue
    if types[i] == 13:         # Set Memory amount (string value)
      VBoxValues[i] = '1024'
      continue
    if types[i] == 18 and onlyOneHdd:        # Set HardDiskImage path, and corresponding extraConfig
      VBoxValues[i] = vmhome + '/' + vmName + '/' + vmName + "-disk1.vmdk"
      extraConfigValues[i] = "controller=6;channel=0"
      onlyOneHdd = False
      continue
    elif types[i] == 18 and not onlyOneHdd:
      VBoxValues[i] = vmhome + '/' + vmName + '/' + vmName + "-disk2.vmdk"
      extraConfigValues[i] = "controller=6;channel=1"
    if types[i] == 21 and onlyOneNic:        # Set NetworkAdapter in slot 1 to NAT
      VBoxValues[i] = "6"
      extraConfigValues[i] = "slot=0;type=NAT"
      onlyOneNic = False
      continue
    elif types[i] == 21 and not onlyOneNic:  # Set NetworkAdapter in slot 2 to HostOnly
      VBoxValues[i] = "6"
      extraConfigValues[i] = "slot=1;type=HostOnly"

  # Update the values for this machine we're creating
  sysDesc[0].setFinalValues(enableValue, VBoxValues, extraConfigValues)

  importOptions = []  # Empty means new MAC addresses will be generated, while [1, 2] means
                      # don't generate new MAC addresses for regular (1) and NAT(2) interfaces
  
  # Import the appliance, creating the VM, and dot the progress while we wait
  progress = appliance.importMachines(importOptions)
  lapCount = 0
  while not progress.completed:
    sys.stdout.write('.') ; sys.stdout.flush()  # Flush out every dot
    time.sleep(0.2)
    lapCount += 1
    if lapCount % 78 == 0:
      print                                     # Carriage return after every 78 dots
  
  print # Bring cursor back to far left

  # Machine was created successfully if we can get its IMachine object
  try:
    vm = vbox.findMachine(vmName)
  except:
    print red2("Error creating VM")
    return 1

  # Get a write lock session on the VM and ensure disk1 is the only bootable device, and
  # Also enable HPET, RTC/UTC, I/O APIC, and disable BIOS boot menu
  (vmMuta, session) = openSession(vm, const.LockType_Write)
  vmMuta.setBootOrder(1, const.DeviceType_HardDisk)
  vmMuta.setBootOrder(2, const.DeviceType_Null)
  vmMuta.setBootOrder(3, const.DeviceType_Null)
  vmMuta.setBootOrder(4, const.DeviceType_Null)  
  vmMuta.HPETEnabled = True
  vmMuta.RTCUseUTC   = True
  vmMuta.BIOSSettings.IOAPICEnabled = True
  vmMuta.BIOSSettings.bootMenuMode  = const.BIOSBootMenuMode_Disabled
  closeSession(session)  # Close write session

  # Let's make sure this VM gets a proper IP address
  ip = getVmIp(vm)                         # Get officially defined IP
  if not validIP(ip) or not uniqueIP(ip):  # Ensure we have a good IP address
    ip = vmdefip                           # Use global default IP if necessary
    if not uniqueIP(ip):                   # Call nextUniqueIP if global default is already taken
      ip = nextUniqueIP(ip)
  setVmIp(vm, ip)                          # Store IP in official location and setup net devices
  # We're trusting setVmIp won't failed after so many checks 
  return 0


def  attachDisk2(vm):
  # Create second 1MB HDD to facilitate VM bootstrapping
  # 1. Create RAW FAT32 disk2 : hdiutil create -size 1m "FilePath.dmg" -fs MS-DOS -volname VMCONF
  # 2. Mount it               : hdiutil attach "FilePath.dmg"
  # 3. Copy files to it
  # 4. Unmount/eject the disk : hdiutil eject "disk2s1"
  # 5. Convert it to VMDK     : VBoxManage convertfromraw "FilePath.dmg" "FilePath.vmdk" --format vmdk
  
  # First, detach and delete old 2nd drive if it exists
  try:
    oldMedium = vm.getMedium('SATA', 1, 0)
  except:
    oldMedium = None
  if oldMedium:
    (vmMuta, session) = openSession(vm, const.LockType_Write)
    vmMuta.detachDevice('SATA', 1, 0)
    vmMuta.saveSettings()              # Required to release the medium
    oldMedium.deleteStorage()
    closeSession(session)

  vmDrvDmg = vmhome + '/' + vm.name + '/' + vm.name + '-disk2.dmg'
  vmDrvVmdk = vmhome + '/' + vm.name + '/' + vm.name + '-disk2.vmdk'
  if os.path.isfile(vmDrvDmg):   # Remove old file if it exists
    os.remove(vmDrvDmg)

  cmdStr = "hdiutil create -size 1m \"" + vmDrvDmg + "\" -fs MS-DOS -volname VMCONF > /dev/null 2>&1"
  if subprocess.call(cmdStr, shell=True) != 0:
    print "Error creating %s" % (whi1(vmDrvDmg))
    return 1

  # Mount drive and get the mount volume path
  cmdStr = "hdiutil attach \"" + vmDrvDmg + "\" | grep VMCONF"
  mountOut = subprocess.check_output(cmdStr, shell=True).rstrip('\r\n')
  vmDrvDevice = mountOut.split()[0].split('/')[2]  # disk2s1 etc
  vmDrvMount = mountOut.split()[2]                 # /Volumes/VMCONF etc

  # Create hostname and ip files in this drive
  with open(vmDrvMount + '/hostname.txt', "a") as f:
    f.write(vm.name + '\n')
  ipAddr = getVmIp(vm)
  with open(vmDrvMount + '/ip.txt', "a") as f:
    f.write(ipAddr + '\n')

  # Unmount/eject drive
  cmdStr = "hdiutil eject \"" + vmDrvDevice + "\" > /dev/null 2>&1"
  if subprocess.call(cmdStr, shell=True) != 0:
    print "Error ejecting %s:%s" % (red2(vmDrvDevice), red2(vmDrvMount))
    return 1

  # Convert DMG drive file to the VirtualBox VDI format
  # No API call for this, so we have to invoke VBoxManage
  cmdStr = "VBoxManage convertfromraw \"" + vmDrvDmg + "\" \"" + vmDrvVmdk + "\" --format vmdk > /dev/null 2>&1"
  if subprocess.call(cmdStr, shell=True) != 0:
    print "Error converting to %s" % (red2(vmDrvVmdk))
    return 1
  os.remove(vmDrvDmg)  # Remove the DMG one

  # Create IMedium object for this drive
  hddMedium = vbox.openMedium(vmDrvVmdk, const.DeviceType_HardDisk, const.AccessMode_ReadWrite, True)
  hddMedium.refreshState()
  if hddMedium.state != const.MediumState_Created:
    print hddMedium.id
    print "Error trying to setup the second drive:\n%s" % (red2(hddMedium.lastAccessError))
    return 1

  # Set up storage controller for this drive, attach the drive, and make it nonbootable
  (vmMuta, session) = openSession(vm, const.LockType_Write)
  vmMuta.getStorageControllerByName('SATA').portCount = 3
  vmMuta.attachDevice('SATA', 1, 0, const.DeviceType_HardDisk, hddMedium) 
  closeSession(session)
  return


def vmStart(args):
  vmName = option = None
  if len(args) == 2:
    (vmName, option) = args
  elif len(args) == 1:
    vmName = args[0]
    option = 'headless'
  else:
    print "Usage: vm start <vmName> [-gui]"
    return 1
  if option == '-gui':
    option = 'gui'

  try:
    vm = vbox.findMachine(vmName)  # Get the IMachine object (read-only)
  except:
    print "VM %s doesn't exist" % whi1(vmName)
    return 1
  if vm.state == const.MachineState_Running:   
    print "VM %s is already running" % whi1(vmName)
    return 1

  # Don't start VM unless IP is defined and is valid
  ipAddr = getVmIp(vm)               # Get officially defined IP
  if ipAddr == '<undefined>':
    print "Error. IP address is %s" % whi1('<undefined>')
    return 1
  if not validIP(ipAddr):
    print "Error. IP address %s is invalid." % whi1(ipAddr)
    return 1
  ret = setVmIp(vm, ipAddr)  # Store IP in official location and setup net devices
  if ret != 0:               # Don't start if we couldn't set IP address
    return 1

  attachDisk2(vm)   # Setup and attach bootstraping disk2
  # VMs are built to call /usr/sbin/vmboot from /etc/rc.d/rc.local on every boot, then
  # vmboot mounts disk2, from where it reads the hostname and IP address to assign the VM

  # Launch VM process
  session = vboxmgr.getSessionObject(vbox)    # Get ISession object
  feType  = option                            # Front-end Type [gui, headless, sdl, '']
  envStr  = ''                                # Environment string
  progress = vm.launchVMProcess(session, feType, envStr) # Launch VM process
  while not progress.completed:               # Wait for launch process to start
    time.sleep(0.01)
  session.unlockMachine()                     # Now we can unlock this session object
  # Note, at this point the VM is still booting up

  # Give it no more than 5 sec before erroring out if VM process has no 'Running' status 
  timeOut = time.time() + 5
  while timeOut > time.time() and vm.state != const.MachineState_Running:   
    time.sleep(0.1)
  if vm.state != const.MachineState_Running:   
    print red2("Error starting VM.")
    return 1

  return 0


def vmStop(args):
  vmName = option = None
  if len(args) == 2:
    (vmName, option) = args
  elif len(args) == 1:
    vmName = args[0]
  else:
    print "Usage: vm stop <vmName> [-f]"
    return 1
  if option != "-f": option = "normal"

  try:
    vm = vbox.findMachine(vmName)  # Get IMachine object (read-only)
  except:
    print "VM %s doesn't exist" % whi1(vmName)
    return 1

  if vm.state == const.MachineState_Aborted:
    print whi1("Aborted") + " state is synonymous with " + whi1("PoweredOff") + " state"
    return 1

  if vm.state != const.MachineState_Running:   
    print "%s is not running" % whi1(vmName)
    return 1

  if option == "normal": 
    msg = "Are you sure you want to STOP " + whi1(vmName) + "? y/n "
    response = raw_input(msg)
    if response != "y":
      return 1

  # Try running poweroff command from within the VM (most graceful method)
  if vm.state == const.MachineState_Running:
    vmSSH([vmName, '/usr/sbin/poweroff'], False)
    # Give this method no more than 3 sec to finish  
    timeOut = time.time() + 3
    while timeOut > time.time() and vm.state != const.MachineState_PoweredOff:   
      time.sleep(0.1)

  # Try normal powerDown API call
  downable = [const.MachineState_Running, const.MachineState_Paused, const.MachineState_Stuck]
  if vm.state in downable and vm.state != const.MachineState_PoweredOff:
    try:
      (dummy1, session) = openSession(vm, const.LockType_Shared)
      session.console.powerDown()
      # Give this method no more than 3 sec to finish  
      timeOut = time.time() + 3
      while timeOut > time.time() and vm.state != const.MachineState_PoweredOff:   
        time.sleep(0.1)
      closeSession(session)
    except:
      dummy1 = True  # Dummy code. Try another method below

  # Try power button API call
  if vm.state != const.MachineState_PoweredOff:   
    try:
      (dummy1, session) = openSession(vm, const.LockType_Shared)
      session.console.powerButton()
      # Give this method no more than 3 sec to finish  
      timeOut = time.time() + 3
      while timeOut > time.time() and vm.state != const.MachineState_PoweredOff:   
        time.sleep(0.1)
      closeSession(session)
    except:
      dummy1 = True  # Dummy code. Try another method below

  # Finally just kill the OS processes. Caviat: leaves VM in Aborted state
  if vm.state != const.MachineState_PoweredOff:
    cmdStr = "kill -9 `ps auxwww | grep \"VBoxHeadles[s] --comment " + vmName + \
             " --startvm\" | awk '{print $2}'` > /dev/null 2>&1"
    subprocess.call(cmdStr, shell=True)

  return 0


def sshListening(ip):
  if not validIP(ip):
    return False
  if not aliveIP(ip):
    return False
  from contextlib import closing
  with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as sock:
    if sock.connect_ex((ip, 22)) == 0:
      return True
    else:
      return False


def vmSSH(args, verbose=True):
  vmName = cmd = None
  if len(args) == 2:
    (vmName, cmd) = args
  elif len(args) == 1:
    vmName = args[0]
  else:
    print "Usage: vm ssh <vmName> [<cmd-to-run>]"
    return 1

  try:
    vm = vbox.findMachine(vmName)  # get the IMachine object (read-only)
  except:
    print "%s doesn't exist" % whi1(vmName)
    return 1
  if vm.state != const.MachineState_Running:   
    print "%s is not running" % whi1(vmName)
    return 1

  ssh = "ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no"
  ssh += " -o UserKnownHostsFile=/dev/null -i " + vmprikey

  ip = getVmIp(vm)
  if not sshListening(ip):
    print "VM unreachable via %s:%s" % (whi1(ip), whi1('22'))
    return 1

  # Run remote SSH command or do interactive logon. Note, vmuser is global
  if cmd != None:
    cmdstr = ssh + ' ' + vmuser + "@" + ip + " \"" + cmd + "\""
  else:
    cmdstr = ssh + ' ' + vmuser + "@" + ip

  if verbose:
    subprocess.call(cmdstr, shell=True)
  else:
    subprocess.call(cmdstr + " > /dev/null 2>&1", shell=True)

  return 0


def vmSSHCopy(source, vmName, destination, verbose=True):
  try:
    vm = vbox.findMachine(vmName)  # get the IMachine object (read-only)
  except:
    print "%s doesn't exist" % whi1(vmName)
    return 1
  if vm.state != const.MachineState_Running:   
    print "%s is not running" % whi1(vmName)
    return 1

  scp = "scp -o ConnectTimeout=2 -o StrictHostKeyChecking=no"
  scp += " -o UserKnownHostsFile=/dev/null -i " + vmprikey

  ip = getVmIp(vm)
  if not sshListening(ip):
    print "VM unreachable via %s:%s" % (whi1(ip), whi1('22'))
    return 1

  # Copy source file to vm:destination
  cmdStr = scp + ' ' + source + ' ' + vmuser + "@" + ip + ":" + destination

  if verbose:
    subprocess.call(cmdStr, shell=True)
  else:
    subprocess.call(cmdStr + " > /dev/null 2>&1", shell=True)

  return 0


def vmDelete(args):
  vmName = option = None
  if len(args) == 2:
    (vmName, option) = args
  elif len(args) == 1:
    vmName = args[0]
  else:
    print "Usage: vm del <vmName> [-f]"
    return 1

  if option != "-f": option = "normal"

  try:
    vm = vbox.findMachine(vmName)  # get the IMachine object (read-only)
  except:
    print "%s doesn't exist" % whi1(vmName)
    return 1

  if option == "normal": 
    msg = "Are you sure you want to destroy " + whi1(vmName) + "? y/n "
    response = raw_input(msg)
    if response != "y":
      return 1

  if vm.state == const.MachineState_Running:   # Stop vm if it's running
    vmStop([vmName, "-f"])

  # Give it 5 sec to stop
  timeOut = time.time() + 5
  while timeOut > time.time() and vm.sessionState != const.SessionState_Unlocked:   
    time.sleep(0.1)

  # Unregister machine and get the list of media attached to it
  vmMedia = vm.unregister(const.CleanupMode_DetachAllReturnHardDisksOnly)
  # CleanupMode UnregisterOnly=0, DetachAllReturnNone=1, DetachAllReturnHardDisksOnly=2, Full=3
  # Delete all the media
  progress = vm.deleteConfig(vmMedia)
  while not progress.completed:
    time.sleep(0.1)

  return 0


def vmInfo(args):
  if len(args) != 1:
    print "Usage: vm info <vmName>"
    return 1
  vmName = args[0]

  try:
    vm = vbox.findMachine(vmName)  # get the IMachine object (read-only)
  except:
    print "VM", whi1(vmName), "doesn't exist"
    return 1

  # Generic attributes
  print "%-40s  %s" % ("Name", vmName)
  print "%-40s  %s" % ("Description", vm.description)
  print "%-40s  %s" % ("ID", vm.id)
  print "%-40s  %s (%s)" % ("OS Type", vbox.getGuestOSType(vm.OSTypeId).description, vm.OSTypeId)
  print "%-40s  %s" % ("FirmwareType", enumElem("FirmwareType", vm.firmwareType))
  print "%-40s  %s" % ("CPUs", vm.CPUCount)
  print "%-40s  %sM" % ("RAM", vm.memorySize)
  print "%-40s  %sM" % ("Video RAM", vm.VRAMSize)
  print "%-40s  %s" % ("Monitors", vm.monitorCount)
  print "%-40s  %s" % ("ChipsetType", enumElem("ChipsetType", vm.chipsetType))
  print "%-40s  %s" % ("ClipboardMode", enumElem("ClipboardMode", vm.clipboardMode))
  print "%-40s  %s" % ("MachineStatus", enumElem("MachineState", vm.state))
  print "%-40s  %s" % ("SessionStatus", enumElem("SessionState", vm.sessionState))
  if vm.teleporterEnabled:
    print "%-40s %d (%s)" % ("Teleport target on port" , vm.teleporterPort, vm.teleporterPassword)
  print "%-40s  %s" % ("ACPI", vm.BIOSSettings.ACPIEnabled)
  print "%-40s  %s" % ("APIC", vm.BIOSSettings.IOAPICEnabled)
  print "%-40s  %s" % ("Hardware virtualization", vm.getHWVirtExProperty(const.HWVirtExPropertyType_Enabled))
  print "%-40s  %s" % ("VPID support", vm.getHWVirtExProperty(const.HWVirtExPropertyType_VPID))
  print "%-40s  %s" % ("Nested paging", vm.getHWVirtExProperty(const.HWVirtExPropertyType_NestedPaging))
  print "%-40s  %s" % ("Hardware 3d acceleration", vm.accelerate3DEnabled)
  print "%-40s  %s" % ("Hardware 2d video acceleration", vm.accelerate2DVideoEnabled)
  print "%-40s  %s" % ("Use universal time", vm.RTCUseUTC)
  print "%-40s  %s" % ("HPET", vm.HPETEnabled)
  if vm.audioAdapter.enabled:
    print "%-40s  chip %s; host driver %s" % ("Audio", vm.audioAdapter.audioController, vm.audioAdapter.audioDriver)
  print "%-40s  %s" % ("CPU hotplugging", vm.CPUHotPlugEnabled)
  print "%-40s  %s" % ("Keyboard", enumElem("KeyboardHIDType", vm.keyboardHIDType))
  print "%-40s  %s" % ("Pointing device", enumElem("PointingHIDType", vm.pointingHIDType))
  # OSE has no VRDE
  try:
    print "%-40s  %s" % ("VRDE serve", vm.VRDEServer.enabled)
  except:
    pass
  for usbCtrl in vboxmgr.getArray(vm, 'USBControllers'):
    print "%-40s  type %s  standard: %s" % ("USB Controllers", usbCtrl.type, usbCtrl.USBStandard);
  print "%-40s  %s" % ("I/O subsystem Cache enabled", vm.IOCacheEnabled)
  print "%-40s  %sM" % ("I/O subsystem Cache size", vm.IOCacheSize)
  ctrls = vboxmgr.getArray(vm, 'storageControllers')
  if ctrls:
    for ctrl in ctrls:
      print "%-40s  '%s': bus %s type %s" % ("Storage Controllers", ctrl.name, ctrl.bus, enumElem("StorageControllerType", ctrl.controllerType))
  attaches = vboxmgr.getArray(vm, 'mediumAttachments')
  if attaches:
    for a in attaches:
      print "%-40s  Controller: '%s'   port/device: %d:%d   type: %s" % ("Media", a.controller, a.port, a.device, enumElem("DeviceType", a.type))
      medium = a.medium
      if a.type == const.DeviceType_HardDisk:
        print "%-40s  %s" % ("  HDD:", '')
        print "%-40s  %s" % ("    Id: ", medium.id)
        print "%-40s  %s" % ("    Location: ", medium.location)
        print "%-40s  %s" % ("    Name: ", medium.name)
        print "%-40s  %s" % ("    Format: ", medium.format)
      if a.type == const.DeviceType_DVD:
        print "%-40s  %s" % ("  DVD:", '')
        if medium:
          print "%-40s  %s" % ("    Id: ", medium.id)
          print "%-40s  %s" % ("    Name: ", medium.name)
          if medium.hostDrive:
            print "%-40s  %s" % ("    Host DVD ", medium.location)
            if a.passthrough:
              print "%-40s  %s" % ("    [passthrough mode]", '')
          else:
            print "%-40s  %s" % ("    Virtual image at ", medium.location)
            print "%-40s  %s" % ("    Size: ", medium.size)
      if a.type == const.DeviceType_Floppy:
        print "%-40s  %s" % ("  Floppy:", '')
        if medium:
          print "%-40s  %s" % ("    Id: ", medium.id)
          print "%-40s  %s" % ("    Name: ", medium.name)
          if medium.hostDrive:
            print "%-40s  %s" % ("    Host floppy ", medium.location)
          else:
            print "%-40s  %s" % ("    Virtual image at ", medium.location)
            print "%-40s  %s" % ("    Size: ", medium.size)

  # Note: The API documentation has getSharedFolders() func incorectly listed as sharedFolders()
  if len(vm.getSharedFolders()) > 0:
    print "%-40s  %s" % ("Shared Folders", '')
    for sf in vm.getSharedFolders():
      print "%-40s  %s" % ("  Name:", sf.name)
      print "%-40s  %s" % ("    HostPath:", sf.hostPath)
      print "%-40s  %s" % ("    Accessible:", sf.accessible)
      print "%-40s  %s" % ("    Writable:", sf.writable)
      print "%-40s  %s" % ("    AutoMount:", sf.autoMount)
      print "%-40s  %s" % ("    LastAccessErr:", sf.lastAccessError)

  # Network Adapters: We only care about nic0 and nic1
  print "%-40s  %s" % ("Network Adapters", '')
  for slot in [0, 1]:
    nic = vm.getNetworkAdapter(slot)
    nicStatus = "Disabled"
    if nic.enabled:
      nicStatus = "Enabled"
    print "%-40s  %s" % ("  eth" + str(slot) + ":", nicStatus)
    if nicStatus == "Disabled": continue 
    print "%-40s  %s" % ("    Type:", enumElem("NetworkAdapterType", nic.adapterType))
    attachType = enumElem("NetworkAttachmentType", nic.attachmentType)
    print "%-40s  %s" % ("    AttachmentType:", attachType)
    print "%-40s  %s" % ("    MAC:", nic.MACAddress)
    print "%-40s  %s" % ("    CableConnected:", nic.cableConnected)
    print "%-40s  %s" % ("    PromiscuousMode:", enumElem("NetworkAdapterPromiscModePolicy", nic.promiscModePolicy))
    if attachType == "Bridged":
      print "%-40s  %s" % ("    BridgedInterface:", nic.bridgedInterface)
    elif attachType == "HostOnly":
      print "%-40s  %s" % ("    HostOnlyInterface:", nic.hostOnlyInterface)
    elif attachType == "NAT":
      if len(nic.NATEngine.getRedirects()) > 0:      # List any existing port-forward rules
        print "%-40s  %s" % ("    NATEngine:", '')
        for pfRule in nic.NATEngine.getRedirects():
          pfRule = pfRule.split(",")  # convert string to list
          if pfRule[1] == 0:          # enum 2nd element constant to either 0:udp or 1:tcp
            pfRule[1] = "udp"
          else:
            pfRule[1] = "tcp"
          pfRule = ",".join(pfRule)   # convert list back to string
          print "%-40s  %s" % ("      PortFwdRule:", pfRule)
      print "%-40s  %s" % ("      DNSPassDomain:", nic.NATEngine.DNSPassDomain)               
      print "%-40s  %s" % ("      DNSProxy:", nic.NATEngine.DNSProxy)               
      print "%-40s  %s" % ("      DNSUseHostResolver:", nic.NATEngine.DNSUseHostResolver)               
    ipProp = "/VirtualBox/GuestInfo/Net/" + str(slot) + "/V4/IP"
    ip = vm.getGuestPropertyValue(ipProp)
    print "%-40s  %s" % ("    IPAddress:", ip)

  # Guest Addition properties
  # Do the ISO path manually
  print "%-40s  %s" % ("/VirtualBox/GuestAdd/ISOFile", vbox.systemProperties.defaultAdditionsISO)
  # The others in a sorted loop
  propFilter = None    # Pattern to search for. None = get all properties
  propList = vm.enumerateGuestProperties(propFilter)
  # The SDK/API documentation again confusingly states that enumerateGuestProperties returns a 'void'
  # when in actuality it returns a list of 4 lists data structure, which we'll call propList. We only
  # care about Names and Values list, and we disregard Timestamps and Flags
  propNames = propList[0]
  propValues = propList[1]
  propDict = {}                           # Create/use a dictionary for printing them sorted
  for i in range(len(propNames)):         propDict[propNames[i]] = propValues[i]
  for key in sorted(propDict.iterkeys()): print "%-40s  %s" % (key, propDict[key])

  return 0


def getNetList():
  # Get list of vboxnet networks defined on this host. We only care about HostOnly networks
  netList = []
  for nic in vbox.host.getNetworkInterfaces():
    if nic.interfaceType == 2:  # HostNetworkInterfaceType  0=None  1=Bridged  2=HostOnly 
      netList.append(nic)
  return netList


def vmNetList():
  netList = getNetList()
  if len(netList) == 0:
    return 0
  else:
    print "%-20s%-12s%-16s%-16s%s" % ("NAME", "DHCP", "GATEWAY", "NETMASK", "STATUS")
    for net in netList:
      dhcpStatus = 'Disabled'
      if net.DHCPEnabled:
        dhcpStatus = 'Enabled'
      print "%-20s%-12s%-16s%-16s%s" % (net.name, dhcpStatus, net.IPAddress, \
             net.networkMask, enumElem("HostNetworkInterfaceStatus", net.status))
             # HostNetworkInterfaceStatus Unknown=0, Up=1, Down=2
  return 0


def vmNetAdd(args):
  if len(args) != 1:
    print "Usage: vm netadd <gateway-ip>"
    return 1
  ip = args[0]
  if not validIP(ip):
    print "%s is an invalid IP address" % whi1(ip)
    return 1
  if ip.split('.')[3] != "1":
    print "Gateway IP address must end in .1"
    return 1
  (progress, newNet) = vbox.host.createHostOnlyNetworkInterface()
  # NOTE: Another API function poorly documented (not 100% clear it returns 2 values)
  while not progress.completed:
    time.sleep(0.01)
  if newNet.name == None:
    print "Error creating new vboxnet"
    return None
  # Assign given IP address to the new vboxnet
  newNet.enableStaticIPConfig(ip, '255.255.255.0')
  return newNet.name


def vmNetDel(args):
  if len(args) != 1:
    print "Usage: vm netdel <vboxnetX>"
    return 1
  vboxnetName = args[0]
  vboxnetDoesntExists = True
  for net in getNetList():
    if net.name == vboxnetName:
      vboxnetDoesntExists = False
      break
  if vboxnetDoesntExists:
    print "%s doesn't exist." % whi1(vboxnetName)
    return 1
  progress = vbox.host.removeHostOnlyNetworkInterface(net.id)
  while not progress.completed:
    time.sleep(0.01)
  return 0


def validIP(ip):
  octects = ip.split('.')
  if len(octects) != 4: return False
  for x in octects:
    if not x.isdigit(): return False
    if int(x) > 255: return False
  return True


def vmIp(args):
  vmName = ip = None
  if len(args) == 2:
    (vmName, ip) = args
  else:
    print "Usage: vm ip <vmName> <ip>"
    return 1

  try:
    vm = vbox.findMachine(vmName)  # get the IMachine object (read-only)
  except:
    print "%s doesn't exist" % whi1(vmName)
    return 1

  if not uniqueIP(ip):
    print "IP %s is already in used by another VM" % whi1(ip)
    return 1

  if vm.state == const.MachineState_Running:   
    print "%s needs to be powered off for this" % whi1(vmName)
    return 1

  if setVmIp(vm, ip) != 0:
    print "[%s] Unable to set IP to %s" % (whi1(vmName), whi1(ip))
    return 1

  return 0


def vmMod(args):
  vmName = cpu = memory = None
  if len(args) == 3 and args[1].isdigit() and args[2].isdigit():
    (vmName, cpu, memory) = args
  elif len(args) == 2 and args[1].isdigit():
    (vmName, cpu) = args
    memory = "1024"        # Default to 1024, if no memory setting provided
  else:
    print "Usage: vm mod <vmName> <cpus> [<memory>]"
    return 1
  cpu = int(cpu)
  memory = int(memory) 

  try:
    vm = vbox.findMachine(vmName)  # get the IMachine object (read-only)
  except:
    print whi1(vmName) + " doesn't exist"
    return 1
  if vm.state == const.MachineState_Running:   
    print whi1(vmName) + " needs to be powered off for this"
    return 1

  if (vbox.host.processorOnlineCount - cpu) < 2:
    print "Error: This host only has %s CPUs. Assigning %s will oversubscribe it" % \
          (red2(vbox.host.processorOnlineCount), red2(cpu))
    return 1
  if (vbox.host.memoryAvailable - memory) < 1024:
    print "Error: This host only has %sMB of RAM. Assigning %s will oversubscribe it" % \
          (red2(vbox.host.memoryAvailable), red2(memory))
    return 1

  (vmMuta, session) = openSession(vm, const.LockType_Write)
  vmMuta.CPUCount    = cpu
  vmMuta.memorySize  = memory
  vmMuta.HPETEnabled = True
  vmMuta.RTCUseUTC   = True
  vmMuta.BIOSSettings.IOAPICEnabled = True
  vmMuta.BIOSSettings.bootMenuMode  = const.BIOSBootMenuMode_Disabled
  closeSession(session)
  return 0


def vmProvision(args):
  if len(args) == 1 and args[0].lower() == "init":    # Create a template file if it was requested
    if os.path.isfile(vmconf):
      msg = "File " + whi1(vmconf) + " exists already. Overwrite it? y/n "
      response = raw_input(msg)
      if response != "y":
        return 1
    genFile("#01=>", vmconf, 0644)
    return 0
  if not os.path.isfile(vmconf):                      # If vmconf file doesn't exist in CWD
    print "Usage: vm prov [init]"
    return 0  

  # Prohibit running this command from HOME directory
  if os.getcwd() == os.environ['HOME']:
    print "Error: Running this command from your HOME dir is prohibited for security reasons.\n" \
          "Please cd into a special project directory."
    return 1

  # Parse vmconf for inconsistencies
  cfg = ConfigParser()
  cfg.read(vmconf)
  if len(cfg.sections()) < 1:
    print "Error: %s file has no sections (no VMs) defined" % red2(vmconf)
    return 1

  # Ensure each VM section has the required minimum number of variables
  for sect in cfg.sections():
    if 'image' in cfg.options(sect) and 'netip' in cfg.options(sect):
      continue
    print "Error: Each section in %s needs at least these variables defined: %s and %s" % \
           (red2(vmconf), red2('image'), red2('netip'))
    return 1

  # Provision each VM as per its parameters defined in its vmconf section
  for sect in cfg.sections():
    # NOTE: We leave an existing VM running if it is both named and configured exactly as
    # defined in  vmconf. If it's configured differently, then we'll stop it, modify it, then
    # restart it. If the VM doesn't exist then the process is to simply create a new one

    # Get the 6 possible config entries for this VM

    vmName = sect                            # 1 name (Mandatory). Same as the section name

    print "[%s] Provisioning" % (whi1(vmName))

    vmImg = cfg.get(sect, 'image')           # 2 image (Mandatory)
    vmImgPath = vmhome + '/' + vmImg
    if not os.path.isfile(vmImgPath): 
      print whi1(vmImg) + " doesn't exist. Please specify an available VM image for " + whi1(key)
      return 1

    vmNetIp = cfg.get(sect, 'netip')         # 3 netip (Mandatory)
    if not validIP(vmNetIp) or vmNetIp.endswith(".1"):
      print "%s is an invalid IP address" % whi1(vmNetIp)
      return 1

    if 'cpus' in cfg.options(sect):          # 4 cpus
      vmCpus = cfg.get(sect, 'cpus')
    else:
      vmCpus = 1
  
    if 'memory' in cfg.options(sect):        # 5 memory
      vmMemory = cfg.get(sect, 'memory')
    else:
      vmMemory = 1024
  
    if 'vmcopy' in cfg.options(sect):        # 6 vmcopy
      vmCopy = cfg.get(sect, 'vmcopy')
    else:
      vmCopy = None

    if 'vmrun' in cfg.options(sect):         # 7 vmrun
      vmRun = cfg.get(sect, 'vmrun')
    else:
      vmRun = None

    # Note, basic parameters updates can only be applied when the VM is powered off,
    # which is why we're doing the checks/updates here. If the VM is running and it's
    # already configured as per vmconf then we want to leave it alone
    try:
      vm = vbox.findMachine(vmName)  # get the IMachine object (read-only)
      print "[%s] VM already exists" % whi1(vmName)
    except:
      if vmCreate([vmName, vmImg]) != 0:
        print "Error creating VM %s" % (whi1(vmName))
        return 1
      vm = vbox.findMachine(vmName)   # get the IMachine object (read-only)
    
    # Assume VM is already configured as per vmconf, then compare each parameter to disprove that
    sameConfig = True

    # IP Address
    currentVmNetIp = getVmIp(vm)
    if currentVmNetIp != vmNetIp:
      for vmTmp in vbox.getMachines():   # Check if proposed IP is already taken
        if vmTmp.name == vm.name:
          continue   # Skip this machine itself
        if getVmIp(vmTmp) == vmNetIp:
          print "[%s] Error: IP %s is already taken by %s" % (whi1(vmName), red2(ip), whi1(vmTmp.name))
          return 1
      sameConfig = False
      print "[%s] Setting IP address to %s" % (whi1(vmName), whi1(vmNetIp))

    # CPUs
    if vm.CPUCount != int(vmCpus):
      sameConfig = False
      print "[%s] Setting CPU count to %s" % (whi1(vmName), whi1(str(vmCpus)))

    # Memory  
    if vm.memorySize != int(vmMemory):
      sameConfig = False
      print "[%s] Setting memory amount to %s" % (whi1(vmName), whi1(str(vmMemory)))

    # Perform update if any one parameter was different
    if sameConfig:
      print "[%s] VM already configured as per %s" % (whi1(vmName), whi1(vmconf)) 
      if vm.state != const.MachineState_Running:   # Start machine if not already running
        ret = vmStart([vmName])
        if ret != 0:
          print "[%s] Error starting VM" % (red2(vmName))
    else:
      print "[%s] Updating VM as per %s" % (whi1(vmName), whi1(vmconf))
      if vm.state == const.MachineState_Running:   # Stop machine if already running
        vmStop([vmName, "-f"])
      vmMod([vmName, str(vmCpus), str(vmMemory)])  # Update cpu and memory (note the string conversion)
      setVmIp(vm, vmNetIp)                         # Update IP address
      ret = vmStart([vmName])                      # Start machine
      if ret != 0:
        print "[%s] Error starting VM" % (red2(vmName))
  
    # Run VMCOPY COMMAND
    if vmCopy:
      print "[%s] VMCOPY: %s" % (whi1(vmName), whi1(vmCopy))
      source = vmCopy.strip('"').split()[0]
      destination = vmCopy.strip('"').split()[1]
      timeOut = time.time() + 120
      while timeOut > time.time() and not sshListening(vmNetIp):  # Wait a bit till SSH is ready
        time.sleep(0.1)
      vmSSHCopy(source, vmName, destination)

    # Run VMRUN COMMAND
    if vmRun:
      print "[%s] VMRUN: %s" % (whi1(vmName), whi1(vmRun))
      vmSSH([vmName, vmRun])

  return 0


def vmImgList():
  fList = []
  for f in os.listdir(vmhome):
    if f.lower().endswith(".ova"):
      fList.append(f)
  if len(fList) < 1: return 1   # No OVA files to list, so return empty-handed
  print "%-20s%-54s%s" % ('NAME', 'FILE', 'SIZE')
  for fName in fList:
    fPath = vmhome + '/' + fName
    fSize = str(os.path.getsize(fPath) >> 20) + 'MB'    # Note shift by 20 to get size in MB
    hddFile = '<undefined>' 
    if not tarfile.is_tarfile(fPath): continue          # It's named *.ova but it's not an OVA file (tar file)
    print "%-20s%-54s%s" % (fName, fPath, fSize)
  return 0


def vmImgDel(args):
  imgName = option = None
  if len(args) == 2:
    (imgName, option) = args
  elif len(args) == 1:
    imgName = args[0]
  else:
    print "Usage: vm imgdel <imgName> [-f]"
    return 1
  if option != "-f": option = "normal"
  imgFile = vmhome + '/' + imgName
  if not os.path.isfile(imgFile): 
    print "Error: No such OVA file."
    return 1
  if option == "normal": 
    msg = "Are you sure you want to delete " + whi1(imgName) + "? y/n "
    response = raw_input(msg)
    if response != "y":
      return 1
  os.remove(imgFile)  # Remove OVA file
  return 0


def vmImgImport(args):
  imgFile = None
  if len(args) == 1:
    imgFile = args[0]
  else:
    print "Usage: vm imgimp <imgFile>"
    return 1
  if not (os.path.isfile(imgFile)): 
    print "That OVA image file doesn't exist"
    return 1
  imgName = os.path.basename(imgFile)
  if os.path.isfile(vmhome + '/' + imgName): 
    print "%s exists already" % whi1(imgName)
    return 1
  # Reject if it doesn't end with .ova, or if it's not a tar file (what OVAs are)
  if not (tarfile.is_tarfile(imgFile)) or not (imgFile.lower().endswith("ova")):
    print "Unsupported OVA image file"
    return 1
  # Reject image tar package if it doesn't have the right files
  badOva = True
  tar = tarfile.open(imgFile, "r")
  for tarf in tar.getnames():
    if tarf.lower().endswith(("vmdk","vdi","vhd", "ovf")): badOva = False
  tar.close()
  if badOva:
    print "Content of that OVA image file is not valid"
    return 1
  # Copy the OVA to where OVAs are kept
  shutil.copy(imgFile, vmhome)
  return 0


def vmImgCreate(args):
  imgName = source = option1 = option2 = None
  if len(args) == 4:
    (imgName, source, option1, option2) = args
  elif len(args) == 3:
    (imgName, source, option1) = args
    option2 = "normal"
  elif len(args) == 2:
    (imgName, source) = args
    option1 = "normal"
    option2 = "normal"
  else:
    print "Usage: vm imgcreate <imgName> <ISOfile|vmName> [-f1] [-f2]"
    return 1

  if not imgName.lower().endswith('.ova'):
    print "imgName %s must end with .ova" % (whi1(imgName))
    return 1

  imgFile = vmhome + '/' + imgName

  if os.path.isfile(imgFile) and option1 != "-f1" and option2 != "-f1": 
    msg = "OVA " + whi1(imgName) + " already exists. Overwrite it? y/n "
    response = raw_input(msg)
    if response != 'y':
      return 1

  vmName = isoFile = None
  try:
    vm = vbox.findMachine(source)  # Get the IMachine object (read-only)
    vmName = source                # The source for this OVA will be this VM
  except:
    if os.path.isfile(source) and source.lower().endswith('.iso'):
      isoFile = source
    else:
      print "Error: %s is not an existing VM, nor a valid ISO file" % red2(source)
      return 1

  # Create OVA from provided vmName, if it exists
  if source == vmName:  # Note how after above try block we can know if source is either VM or ISO
    if option1 != '-f2' and option2 != '-f2': 
      msg = "Did you run /usr/sbin/vmprep on " + whi1(vmName) + " yet? y/n "
      response = raw_input(msg)
      if response != 'y':
        return 1
    if vm.state == const.MachineState_Running:   
      print "%s needs to be powered off for this" % whi1(vmName)
      return 1

    # At this point we know we can forcefully overwrite an existing duplicate
    if os.path.isfile(imgFile):
      os.remove(imgFile)

    # Create OVA = Create appliance and export VM to it
    appliance = vbox.createAppliance()        # Create empty IAppliance object
    sysDesc = vm.exportTo(appliance, imgFile) # Each call adds another VM to sysDesc list

    # OPTIONAL: Here you could override any VirtualSystemDescriptionType values (see vmCreate for more info)
    #sysDesc[0].setFinalValues(enableValue, VBoxValues, extraConfigValues)
    exportOptions = []  # Empty is typically better, but here are the ExportOptions
                        # CreateManifest=1  ExportDVDImages=2  StripAllMACs=3  StripAllNonNATMACs=4

    # Export the appliance, creating OVA file, and get IProgress object
    progress = appliance.write('ovf-2.0', exportOptions, imgFile)
    lapCount = 0
    while not progress.completed:
      sys.stdout.write('.') ; sys.stdout.flush()  # Dot progress
      time.sleep(0.2)
      lapCount += 1
      if lapCount % 78 == 0:
        print
    print

    return 0

  # Create OVA from a Kickstart installation of CentOS using given ISO file
  if subprocess.check_output("file " + isoFile, shell=True).find('ISO') == -1:
    print "%s is not an ISO file" % whi1(isoFile)
    return 1

  from distutils import spawn
  mkisofs = spawn.find_executable("mkisofs")
  if mkisofs == None:
    print red2("Can't find ") + whi1("mkisofs") + red2(", which is required to \proceed. Note, this tool isn't native\n" + \
          "to Mac OS X, so you'll need to install it with ") + whi1("brew install cdrtools") + red2(" or equivalent")
    return 1

  print "Creating " + whi1(imgName) + " can take about 10 minutes depending on below activities\n" + \
        "1. Remastering " + whi1(os.path.basename(isoFile)) + " for unattended install.\n" + \
        "2. Building a temporary VM using the remastered ISO.\n" + \
        "3. Creating the new OVA from that temporary VM."
  response = raw_input("Do you really want to proceed with all of this? y/n ")
  if response != "y":
    return 1

  # Remove temp VM for doing KS build, if it exists
  ksVMName = "tempvm"
  try:
    ksVM = vbox.findMachine(ksVMName)    # Get the IMachine object (read-only)
    response = raw_input("A VM named " + whi1(ksVMName) + " already exists. Can we delete it? y/n ")
    if response != 'y':
      return 1
    vmDelete([ksVMName, '-f'])
  except:
    dummyVar = True  # All's good, we can continue

  print "START %s" % (time.strftime("%H:%M:%S", time.localtime()))

  # Create isoFileKS var now so we can announce the process, but it's actually used later
  isoFileKS = vmhome + '/' + os.path.basename(isoFile)[:-4] + "-KS.iso"
  print "Remastering original ISO into %s" % whi1(os.path.basename(isoFileKS))

  # Create temp mount dir
  isoMountDir = vmhome + '/' + "isomount"
  if os.path.isdir(isoMountDir):
    shutil.rmtree(isoMountDir)
  os.makedirs(isoMountDir)   

  # Mount ISO file
  # CentOS 7 now uses hybrid ISO files, and 'hdiutil mount -quiet isoFile' no longer
  # works on Mac OS X. So below is an ugly workaround to a much easier previous method:
  lastDisk1 = lastDisk2 = None
  lastDiskcmd = "diskutil list | grep '^/dev/disk' | sort | tail -1 | awk '{print $1}'"
  lastDisk1 = subprocess.check_output(lastDiskcmd, shell=True).rstrip('\r\n')
  cmdstr = "hdiutil attach -quiet -noverify -nomount \"" + isoFile + "\" 2>&1"
  if subprocess.call(cmdstr, shell=True) != 0:
    print "Error 1 pre-mounting", isoFile
    return 1
  lastDisk2 = subprocess.check_output(lastDiskcmd, shell=True).rstrip('\r\n')
  if lastDisk1 == None or lastDisk1 == lastDisk2:
    print "Error 2 pre-mounting", isoFile
    return 1
  cmdstr = "mount_cd9660 " + lastDisk2 + " \"" + isoMountDir + "\""
  if subprocess.call(cmdstr, shell=True) != 0:
    print "Error mounting", isoFile
    return 1

  # Duplicate ISO content 
  isoMountDirKS = isoMountDir + "KS"  # Temp dir for building ISO KS
  if os.path.isdir(isoMountDirKS): shutil.rmtree(isoMountDirKS)  # Remove previous one
  os.makedirs(isoMountDirKS)
  cmdstr = "rsync -av \"" + isoMountDir + "/\" \"" + isoMountDirKS + "/\" > /dev/null 2>&1"
  if subprocess.call(cmdstr, shell=True) != 0:
    print "Error rsync'ing ISO content"
    return 1
  if subprocess.call("chmod -R u+w \"" + isoMountDirKS + "\"", shell=True) != 0:
    print "Error chmod -R u+w on %s" % red2(isoMountDirKS) 
    return 1

  # Unmount ISO file
  # Command 'hdiutil unmount -quiet isomount 2>&1' also doesn't work anymore, so instead we do:
  cmdstr = "umount \"" + isoMountDir + "\" && diskutil eject " + lastDisk2 + " > /dev/null 2>&1"
  #print "[%s]" % cmdstr
  if subprocess.call(cmdstr, shell=True) != 0:
    print "Error unmounting \"%s\"" % red2(isoFile)
    return 1
  os.rmdir(isoMountDir)

  # Modify isolinux.cfg to boot into Kickstart, and reduce prompt wait time, etc
  sedInPlace(isoMountDirKS + "/isolinux/isolinux.cfg", r"^default.*$", "default ks")
  sedInPlace(isoMountDirKS + "/isolinux/isolinux.cfg", r"^timeout.*$", "timeout 0")
  sedInPlace(isoMountDirKS + "/isolinux/isolinux.cfg", r"^.*prompt.*$", "prompt 0")
  with open(isoMountDirKS + "/isolinux/isolinux.cfg", "a") as f:
    f.write("label ks\n  kernel vmlinuz\n  append ks=cdrom:/vmbin/ks.cfg initrd=initrd.img\n")

  # Copy special VM management files to this new ISO
  cmdstr = "rsync -av \"" + vmhome + "/vmbin/\" \"" + isoMountDirKS + "/vmbin/\" > /dev/null 2>&1"
  if subprocess.call(cmdstr, shell=True) != 0:
    print "Error rsync'ing special VM management files"
    return 1

  # Use root password defined by this program
  sedInPlace(isoMountDirKS + "/vmbin/ks.cfg", r"^rootpw password", "rootpw " + vmpwd)

  # Create the new Kickstart ISO
  cmdstr = "cd \"" + isoMountDirKS + "\"/ && " + mkisofs + " -quiet -o \"" + isoFileKS + "\" -b isolinux/isolinux.bin" + \
          " -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -R -J -T . 2>&1"
  if subprocess.call(cmdstr, shell=True) != 0:
    print "Error creating %s" % isoFileKS
    return 1

  # Remove temp KS dir
  shutil.rmtree(isoMountDirKS)

  print "Creating temporary VM using above remastered Kickstart (KS) ISO"
  try:                          # Create empty/mutable IMachine object
    settingsFile = ''           # Null string so composeMachineFilename gets called automatically 
    groups = '/'                # '/' is REQUIRED for the default no-group association
    osTypeId = 'RedHat_64'      # Default for these CentOS 64bit images
    flags = ''                  # Null string is fine for a new machine
    vm = vbox.createMachine(settingsFile, ksVMName, groups, osTypeId, flags)
  except:
    print "Error creating basic VM %s" % red2(ksVMName)
    return 1
   
  # Set these default settings
  vm.CPUCount    = 1
  vm.memorySize  = 1024
  vm.HPETEnabled = True
  vm.RTCUseUTC   = True
  vm.BIOSSettings.IOAPICEnabled = True
  vm.BIOSSettings.bootMenuMode  = const.BIOSBootMenuMode_Disabled

  # Set networking to HostOnly
  # HostOnly uses NIC0 (with NAT) for routing external traffic (with no SSH port forwarding)
  nic0 = vm.getNetworkAdapter(0)
  nic0.enabled           = True
  nic0.attachmentType    = const.all_values('NetworkAttachmentType')['NAT'] 
  nic0.adapterType       = const.all_values('NetworkAdapterType')[vbnictype]  # Global variable
  nic0.bridgedInterface  = None
  nic0.hostOnlyInterface = None
  nic0.NATEngine.DNSPassDomain = True
  nic0.NATEngine.DNSUseHostResolver = True
  # But it uses NIC1 (with HostOnly) as its primary adapter
  nic1 = vm.getNetworkAdapter(1)  
  nic1.enabled           = True
  nic1.attachmentType    = const.all_values('NetworkAttachmentType')['HostOnly'] 
  nic1.adapterType       = const.all_values('NetworkAdapterType')[vbnictype]  # Global variable
  nic1.bridgedInterface  = None

  # Create hdd/dvd media, and sets up storage controllers
  location = vmhome + '/' + ksVMName + '/' + ksVMName + "-disk1.vmdk"
  hddMedium = vbox.createMedium('VMDK', location, const.AccessMode_ReadWrite, const.DeviceType_HardDisk)

  # Create IMedium object for DVD
  forceNewUuid = False
  dvdMedium = vbox.openMedium(isoFileKS, const.DeviceType_DVD, const.AccessMode_ReadOnly, forceNewUuid)
  hddSize = vmhddsize    # Global variable
  hddVariant = [const.MediumVariant_Standard] 
  progress = hddMedium.createBaseStorage(hddSize, hddVariant) # Create hdd and get IProgress object
  while not progress.completed:
    time.sleep(0.1)
  if not hddMedium.id:
    print "Error creating 8GB disk1 file"
    return 1

  # Setup SATA storage controller
  ctrlSATA = vm.addStorageController('SATA', const.StorageBus_SATA)
  ctrlSATA.controllerType = const.StorageControllerType_IntelAhci
  ctrlSATA.portCount = 3
  ctrlSATA.useHostIOCache = True
  vm.setStorageControllerBootable('SATA', True)

  vbox.registerMachine(vm)   # Create this temporary VM

  # Attach DVD and HDDs. Can only be done after registering machine
  (vmMuta, session) = openSession(vm, const.LockType_Write)
  vmMuta.attachDevice('SATA', 0, 0, const.DeviceType_HardDisk, hddMedium) 
  #vmMuta.attachDevice('SATA', 1, 0, const.DeviceType_HardDisk)   # Disk2 gets added by vmStart
  vmMuta.attachDevice('SATA', 2, 0, const.DeviceType_DVD, dvdMedium) 
  vmMuta.setBootOrder(1, const.DeviceType_DVD)  # Make DVD primary AND only boot device, so we can do unattended install
  vmMuta.setBootOrder(2, const.DeviceType_Null)
  vmMuta.setBootOrder(3, const.DeviceType_Null)
  vmMuta.setBootOrder(4, const.DeviceType_Null)
  closeSession(session)

  # Let's make sure this temp VM gets a proper IP address
  ip = getVmIp(vm)                         # Get officially defined IP
  if not validIP(ip) or not uniqueIP(ip):  # Ensure we have a good IP address
    ip = vmdefip                           # Use global default IP if necessary
    if not uniqueIP(ip):                   # Call nextUniqueIP if global default is already taken
      ip = nextUniqueIP(ip)
  setVmIp(vm, ip)                          # Store IP in official location and setup net devices
  # We're trusting setVmIp won't failed after so many checks 

  # Initiate kickstart build of temp VM
  vmStart([vm.name, '-gui'])

  # Then wait at most 10 min for VM to poweroff after Kickstart completes
  timeOut = time.time() + 600
  lapCount = 0
  while timeOut > time.time() and vm.state != const.MachineState_PoweredOff:   
    sys.stdout.write('.') ; sys.stdout.flush()  # Dot the progress
    time.sleep(0.5)
    lapCount += 1
    if lapCount % 78 == 0:
      print
  if lapCount % 78 != 0:
    print

  if vm.state != const.MachineState_PoweredOff:
    print "Aborting. Seems like Kickstart install is hung."
    return 1
  if vm.sessionState != const.SessionState_Unlocked:
    closeSession(session)
    if vm.sessionState != const.SessionState_Unlocked:
      print red2("Aborting. Unable to close last VM session.")
      return 1
  
  # By now Kickstart should have completed and VM should be powered off

  # # Common DEBUG area
  # print "vm.state = %s" % enumElem('MachineState', vm.state)
  # print "last session.state = %s" % enumElem("SessionState", session.state)
  # return 1

  # Lets modify the VM so it boots off HDD, and clean things up
  (vmMuta, session) = openSession(vm, const.LockType_Write)
  vmMuta.detachDevice('SATA',  2, 0)                 # Detaching KS ISO file from DVD drive
  vmMuta.setBootOrder(1, const.DeviceType_HardDisk)  # Now make HDD primary boot device
  vmMuta.setBootOrder(2, const.DeviceType_Null)
  vmMuta.setBootOrder(3, const.DeviceType_Null)
  vmMuta.setBootOrder(4, const.DeviceType_Null)  
  progress = hddMedium.compact()                     # Compact disk medium
  while not progress.completed:
    time.sleep(0.1)
  dvdMedium.close()               # Close kickstart ISO file
  os.remove(isoFileKS)            # Also remove it
  closeSession(session)

  # Call this same function to create the OVA from the temp VM we just built
  print "\nCreating OVA %s" % imgName
  vmImgCreate([imgName, ksVMName, "-f1", "-f2"])
  vmDelete([ksVMName, "-f"])
  print "END   %s" % (time.strftime("%H:%M:%S", time.localtime()))
  return 0


def sedInPlace (filePath, fromRegex, toRegex, ignoreComments = True):
  if not os.path.isfile(filePath):
    print "File %s doesn't exist" % red2(filePath)
    return 1   
  with open(filePath, "r") as f:
    lines = f.readlines()
  with open(filePath, "w") as f:
    for line in lines:
      if ignoreComments and line[0] == "#":
        f.write(line)   # Leave comment lines alone
        continue
      f.write(re.sub(fromRegex, toRegex, line))
  return 0


def genFile(code, filename, mode):
  # Generate file from embedded DATA within this program file itself
  prog_name = os.path.abspath(__file__)
  if prog_name[-1] == 'c':
     prog_name = prog_name[:-1]
  os.system("grep '^" + code + "' " + prog_name + " | sed 's;" + code + ";;g' > " + filename)
  os.chmod(filename, mode)
  return 0


def house_keeping():
  # Ensure these 2 essential directories exist
  if not os.path.isdir(vmhome):
    os.makedirs(vmhome)
  if not os.path.isdir(vmhome + '/vmbin'):
    os.makedirs(vmhome + '/vmbin')

  # Generate essential files on every run to always keep them fresh
  genFile("#02=>", vmprikey, 0600)
  subprocess.call("ssh-keygen -f " + vmprikey + " -y > " + vmpubkey, shell=True)
  genFile("#03=>", vmksconf, 0644)
  genFile("#04=>", vmrootrc, 0644)
  genFile("#05=>", vmpreprc, 0755)
  genFile("#06=>", vmbootrc, 0755)

  # Initialized VirtualBox. Note global variables
  global vboxmgr, const, vbox
  vboxmgr = VirtualBoxManager(None, None)  # Init mgr with default style/parameters
  const   = vboxmgr.constants              # Constants handle
  vbox    = vboxmgr.getVirtualBox()        # IVirtualBox handle
  if int(vbox.APIVersion[0]) < 5:
    print red2("Error. VirtualBox 5.0+ is required.")
    sys.exit(1)
  vbox.systemProperties.defaultMachineFolder = vmhome  # Keep all VirtualBox files in vmhome


def parse_arguments(argv):
  # Define allowable command actions as a dictionary of anonymous functions. Note how we shift
  # argv by 2 when calling the command function so that running the program with:
  # 'vm ssh vmName hostname' will call the vmSSH function with args = ["vmName", "hostname"]
  action = {
    'usage':      lambda: vmUsage(),
    'list':       lambda: vmList(),
    'create':     lambda: vmCreate(argv[2:]),
    'del':        lambda: vmDelete(argv[2:]),
    'start':      lambda: vmStart(argv[2:]),
    'stop':       lambda: vmStop(argv[2:]),
    'ssh':        lambda: vmSSH(argv[2:]),
    'prov':       lambda: vmProvision(argv[2:]),
    'info':       lambda: vmInfo(argv[2:]),
    'mod':        lambda: vmMod(argv[2:]),
    'ip':         lambda: vmIp(argv[2:]),
    'netlist':    lambda: vmNetList(),
    'netadd':     lambda: vmNetAdd(argv[2:]),
    'netdel':     lambda: vmNetDel(argv[2:]),
    'imglist':    lambda: vmImgList(),
    'imgcreate':  lambda: vmImgCreate(argv[2:]),
    'imgdel':     lambda: vmImgDel(argv[2:]),
    'imgimp':     lambda: vmImgImport(argv[2:]),
  }
  if len(argv) < 2:
    cmd = "usage"
  else:
    cmd = argv[1]
  if cmd not in action:
    cmd = "usage"

  # Run given command 
  try:
    action[cmd]()
  except KeyboardInterrupt:
    action['interrupt'] = True
  except Exception, e:
    if vboxmgr.errIsOurXcptKind(e):
      print "%s: %s" % (vboxmgr.xcptToString(e), vboxmgr.xcptGetMessage(e))
    else:
      print "Error: %s" % red2(str(e))
      traceback.print_exc()


def main(args=None):
  """ Main program """

  house_keeping()
  parse_arguments(sys.argv)
  sys.exit(0)

  # Clean up and exit    
  del vboxmgr
  sys.exit(0)


if __name__ == '__main__':
  main()


# DATA
#01=># vm.conf
#01=># Running 'vm prov' in a directory with this file in it will automatically
#01=># provision the VMs defined here. Each VM requires its own section name,
#01=># which becomes the VM name. Then there are 6 other possible keys you can
#01=># define. Two of which are mandatory (image and netip). The other 4 (cpus,
#01=># memory, vmcopy, and vmrun) are optional. Lines starting with a hash(#)
#01=># are treated as comments. Spaces can only be used within double quotes (").
#01=># vmcopy and vmrun are perfect for copying/running bootstrapping scripts.
#01=>
#01=>#[dev1]
#01=>#image   = cos72.ova
#01=>#netip   = 10.11.12.2
#01=>#cpus    = 1
#01=>#memory  = 1024
#01=>#vmcopy  = "./local-host-file/puppet-bootstrap.sh /vmboot/puppet-bootstrap.sh"
#01=>#vmrun   = "/vmboot/puppet-bootstrap.sh"
#01=>
#01=>#[dev2]
#01=>#image   = cos72.ova
#01=>#netip   = 10.11.12.3

# SSH private key for managing VBox VMs
# WARNING: Hardcoded private keys like this is very poor security!
#02=>-----BEGIN RSA PRIVATE KEY-----
#02=>MIIEoQIBAAKCAQEAyIZo/WEpMT8006pKzqHKhNEAPITJCEWjLN+cGSg9snFXVljA
#02=>IQ9CtLo89PJvnfGj8I9VxXPxCUmC8gew/XXxQuExa0XhSSNYDEqMyOvlB8KSoYw8
#02=>tFwNAYaeHw4rbygIgOSn5+g1lLXEf+FPa5JJJAByoxvqXtxZhwiJP2BOkp/ULqsy
#02=>1UGbHFzGsYHkD8ukYINnr8Yob5K3GuvBSZkb4o02ErC0Tj9Xi52vxgSQEKNQs5BO
#02=>xzb4gtJ7ozArd11xrpmel02bH7mRfrB/Gpsfvb4WXRG9Kiat09T3XjceMAlcmMUG
#02=>QJD0ip1mgN3elTCGpon8K5ZRWGxrF7G8XqnGQQIBIwKCAQBKexENp77XxwT+KU78
#02=>SrjvgNQzvEqrTRC45Vc8i0odtRHPnU6tMY3OGUnXUru+UnAXhbIkxKn8Ip5Z5ZmC
#02=>tsdTWvUZNzZrn2nYrfnG+IhEtfvy3FEPyms7FL5jTmfndUT8rLNkw/ak8w54pCTQ
#02=>LwU5Qf6xnKeCUdgcNl7dBoOViyj8eourzUCY55JMZFDF7exKA6j2FXdUsl6O8zlZ
#02=>immjlbO6dSkZt203jyuFlV1YNG/13EjeihmvMDugnP2CP1qr9kUpGn1NfwdCVb2/
#02=>AJz+g8gvZflOIzYaEiaodEMJsGNA2sXuygOVSZy4ryc3iFezA4Bvk/3bLweNqlvj
#02=>yVSLAoGBAP7tjUErm9ciDzLnXe6+toV2E1e1D/a/z2t/GxbbxPYklAUeWaPLhcsZ
#02=>9B7aUx7BGeB+lPI5sP//hc8ouFTTgE3Y9nsgOjEY7HFIDSG1xrN+MnuY+ztNeDif
#02=>Jfs44vMdP32pAwJqgtKtg1KiILqx81XeMYhBynpwooISJTioW5FRAoGBAMleSirb
#02=>GrOZtrsj2s0Uz6LAtPpQfGaQp/5CVYYt/QlUUnR0fhgCaT8DduCrbhOJcmoo5V1K
#02=>EimEQPhAM6JFMpIuDBp+kQT7FKo1Rl6J+igId5N/jc72nm1kpYBfzGLlAqxU13jJ
#02=>ULXBU+QU5ZLrRESrTwZun9ytXvwR/O7HMCnxAoGBAPek755k4IfX8YHoEhsfqf39
#02=>rGPUdehijvq1/Q7kHmtz/YFQrtmhIuKOPZpQbgCeU6bhXX2XIPivFEWVRVm3g/Pa
#02=>FAKUVclLaVgaG2KTU09HZD2NS9M1UDcBAFMhUX50LwxbCjzcfxXNIHwod5DKH5U+
#02=>Pr7g01JeycAu4lRLxqprAoGASstAHovlWKbO18t9J5oD+p9ZKcYfk89UVx/z4WGJ
#02=>3uTOK0E2JizIAXZQudlGJIOCRLAarZ8rUT/AXDUafhmzsqNjlM/suLUHrO83ZPFr
#02=>izZYTLpZPj5YGgDPwfeyUJ40MWFXWL/NhVZvndvgPeJbL3LUNZbNqby84UiChJMg
#02=>hJsCgYA5KiUh42OZgHjez5SGvDBoBaOPwutk5O5ufESfgpzh3W0r6iA/dy+HesYV
#02=>7YDhwSXl7zQgWHKb76SE1/fQcBYOd4TcKzbq4IDU1+oibcOXRMOGkg6vdsXhAvdU
#02=>ADiALhM7Gqxc0eIMPSw4REhLiS2XNlTSL8fxPHMVJSIuPn+SXw==
#02=>-----END RSA PRIVATE KEY-----

#03=># ks.cfg: CentOS 7 Kickstart automated installation file
#03=>
#03=># GENERAL
#03=>install
#03=>text
#03=>cdrom
#03=>poweroff
#03=>unsupported_hardware
#03=>lang en_US.UTF-8
#03=>keyboard us
#03=>timezone --utc America/New_York
#03=>rootpw password
#03=>firewall --disabled
#03=>selinux --disabled
#03=>authconfig --useshadow --passalgo=sha512
#03=>
#03=># DISK
#03=>clearpart --all --drives=sda
#03=>zerombr 
#03=>part / --fstype=ext4 --grow --size=1 --asprimary
#03=># 'net.ifnames=0 biosdevname=0' disables CentOS 7 predictable network interface names
#03=>bootloader --location=mbr --driveorder=sda --append="nomodeset crashkernel=auto rhgb quiet net.ifnames=0 biosdevname=0" --timeout=0
#03=>
#03=># NETWORK
#03=># CentOS 7 now uses predictable interface names (old eth0 is now enp0s3 in VBox H/W), but we disabled in bootloader
#03=>network --onboot=yes --device=eth0 --noipv6 --bootproto=static --ip=10.0.2.15 --netmask=255.255.255.0 --gateway=10.0.2.2 --nameserver=10.0.2.3
#03=>network --onboot=yes --device=eth1 --noipv6 --bootproto=static --ip=10.12.13.2 --netmask=255.255.255.0
#03=>
#03=># PACKAGES
#03=>%packages --nobase --excludedocs
#03=>@core --nodefaults
#03=>-aic94xx-firmware*
#03=>-alsa-*
#03=>-btrfs-progs*
#03=>-firewalld
#03=>-iprutils
#03=>-ivtv*
#03=>-iwl*firmware
#03=>-mariadb-libs
#03=>-NetworkManager*
#03=>-parted
#03=>-wpa_supplicant
#03=>-xfsprogs
#03=>curl
#03=>iputils
#03=>vim-minimal
#03=>%end
#03=>
#03=># POST1
#03=>%post --nochroot --log=/mnt/sysimage/root/ks-post1.log
#03=>#!/bin/bash
#03=># ks-post1.sh
#03=># Copy essential files from ISO source to the new system. Note non-chrooted env
#03=>cp -va /run/install/repo/vmbin /mnt/sysimage/root/bin
#03=>%end
#03=>
#03=># POST2
#03=>%post --log=/root/ks-post2.log
#03=>#!/bin/bash
#03=># ks-post2.sh
#03=># Make all other post-installation updates
#03=>
#03=>echo "==> START `/bin/date +%H:%M:%S`"
#03=>
#03=>echo "==> Setting up root bin scripts, bashrc, vimrc, SSH keys, etc"
#03=>chmod -vR 755 /root/bin
#03=>chown -vR root:root /root/bin
#03=>rm -vrf /root/bin/TRANS.TBL
#03=>mv /root/bin/root.bashrc /root/.bashrc && chmod 644 /root/.bashrc
#03=>printf "\" .vimrc\nsyntax on\nhi comment ctermfg=blue\nau BufRead,BufNewFile *.pp setfiletype puppet\nset ruler\n" > /root/.vimrc
#03=>chown -vR root:root /root/.vimrc
#03=>mkdir /root/.ssh && chmod 700 /root/.ssh
#03=>mv /root/bin/vmkey.pub /root/.ssh/authorized_keys
#03=>mv /root/bin/vmboot /usr/sbin/
#03=>mv /root/bin/vmprep /usr/sbin/
#03=>chmod 644 /root/.ssh/authorized_keys
#03=>rm -rf /root/bin
#03=>
#03=>echo "==> Disabling SSH DNS reverse lookup"
#03=>sed -i "s;^.*UseDNS yes;UseDNS no;g" /etc/ssh/sshd_config
#03=>
#03=>echo "==> Installing other essential CentOS 7 packages"
#03=>rpm -ivh http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.3-1.el7.rf.x86_64.rpm
#03=>rpm -Uvh http://mirror.cs.princeton.edu/pub/mirrors/fedora-epel/7/x86_64/e/epel-release-7-6.noarch.rpm
#03=>yum -y install yum-utils
#03=>yum-config-manager --enable rpmforge-extras
#03=>yum -y install bind-utils bzip2 lsof nmap-ncat ntp ntpdate rsync sysstat tcpdump time
#03=>
#03=>echo "==> Refreshing all packages"
#03=>yum -y -x 'kernel*' update
#03=>
#03=>echo "==> Setup bootstrapping. Have /etc/rc.d/rc.local call vmboot"
#03=>chmod +x /etc/rc.d/rc.local
#03=>echo vmboot >> /etc/rc.d/rc.local
#03=>
#03=>echo "==> Help deduce disk size by only keeping English locales"
#03=>localedef --list-archive | grep -v -i ^en | xargs localedef --delete-from-archive
#03=>mv /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl
#03=>build-locale-archive
#03=>
#03=>echo "==> Preparing host for image creation"
#03=>vmprep
#03=>
#03=>echo "==> END `/bin/date +%H:%M:%S`"
#03=>%end

#04=># /root/.bashrc
#04=># Source global definitions
#04=>[[ -f /etc/bashrc ]] && source /etc/bashrc
#04=># User specific aliases and functions
#04=>alias rm='rm -i'
#04=>alias cp='cp -i'
#04=>alias mv='mv -i'
#04=>alias ls='ls --color'
#04=>alias ll='ls -ltr'
#04=>alias h='history'
#04=>[[ -x /usr/bin/vim ]] && alias vi='vim'
#04=># PS1 Prompt: Try friendlier puppet certname or default to system hostname
#04=>hName=`grep -v "^#" /etc/puppet/puppet.conf 2>/dev/null | grep " certname " | awk '{print $3}'`
#04=>[[ -z "$hName" ]] && hName=`hostname -s`
#04=>hName=${hName%%.*}
#04=>PS1="\[\033[01;31m\][\u@$hName \W]# \[\033[00;32m\]"

#05=>#!/bin/bash
#05=># vmprep
#05=># Preimaging cleanup
#05=>rm -rf /var/cache/yum /var/lib/yum
#05=>yum -y clean all
#05=>[[ "`which puppet 2>/dev/null`" ]] && SSLDIR=`puppet agent --configprint ssldir` && rm -rf $SSLDIR
#05=>for F in grubby dmesg boot.log maillog wtmp lastlog secure messages cron ; do
#05=>  [[ -e "/var/log/$F" ]] && >/var/log/$F
#05=>done
#05=>rm -rf /var/log/anaconda/* /var/log/audit/*
#05=>sed -i "/^HWADDR=/d" /etc/sysconfig/network-scripts/ifcfg-*
#05=>MARKER=/root/.clear_history
#05=>echo $MARKER > $MARKER
#05=>sed -i'' "/f \$HISTFILE/d" /root/.bash_logout
#05=>printf "[ -e $MARKER ] && history -c && rm -rf \$HISTFILE /root/.bash_history $MARKER\n" >> /root/.bash_logout
#05=># Ensure bash runs .bash_logout on exit and clears bash history
#05=>trap 'sh /root/.bash_logout' EXIT

#06=>#!/bin/bash
#06=># vmboot
#06=>LOGFILE=/root/`basename $0`.log
#06=>echo "Called as  : ${0}" | tee $LOGFILE
#06=>echo "Stopping network service ..." | tee -a $LOGFILE
#06=>systemctl stop network | tee -a $LOGFILE
#06=>echo "Mounting disk2 and applying hostname and IP address ..." | tee -a $LOGFILE
#06=>[[ -z "`lsblk -lp | grep '/dev/sdb1'`" ]] && echo "Fatal. Missing /dev/sdb1 disk2!" && exit 1
#06=>mkdir -pv /vmboot && mount -v /dev/sdb1 /vmboot
#06=>newHostname=`cat /vmboot/hostname.txt`
#06=>ipAddr=`cat /vmboot/ip.txt`
#06=>echo "Hostname   : $newHostname" | tee -a $LOGFILE
#06=>echo "IPAddress  : $ipAddr" | tee -a $LOGFILE
#06=>#nic0=enp0s3 nic1=enp0s8  # Use newer PNI device names?
#06=>nic0=eth0 nic1=eth1       # Stay with old NIC names for now
#06=>nic0File=/etc/sysconfig/network-scripts/ifcfg-$nic0
#06=>nic1File=/etc/sysconfig/network-scripts/ifcfg-$nic1
#06=>delval () { sed -i "/${2}=/d" ${1} ; }
#06=>setval () {
#06=>  [[ ! -e "${1}" ]] && touch ${1}
#06=>  if [[ -z "`grep ${2} ${1}`" ]]; then
#06=>    echo "${2}=\"${3}\"" >> ${1}
#06=>    return 0
#06=>  fi
#06=>  OLD=`grep "^${2}=" ${1} | awk -F'=' '{print $2}'`
#06=>  sed -i "s;${2}=$OLD;${2}=\"${3}\";g" ${1}
#06=>}
#06=>if [[ -n "$ipAddr" ]] ; then
#06=>  echo Configuring nic0 with VirtualBox standard NAT static IP settings
#06=>  setval $nic0File DEVICE $nic0
#06=>  setval $nic0File BOOTPROTO none
#06=>  setval $nic0File PEERDNS yes
#06=>  setval $nic0File DNS1 10.0.2.3
#06=>  setval $nic0File GATEWAY 10.0.2.2
#06=>  setval $nic0File IPADDR 10.0.2.15
#06=>  setval $nic0File NETMASK 255.255.255.0
#06=>  setval $nic0File IPV6INIT no
#06=>  setval $nic0File NM_CONTROLLED no
#06=>  setval $nic0File ONBOOT yes
#06=>  setval $nic0File TYPE Ethernet
#06=>  setval $nic0File HWADDR `cat /sys/class/net/$nic0/address`
#06=>  setval /etc/sysconfig/network GATEWAY 10.0.2.2
#06=>  echo "Bringing up '$nic0' ..." | tee -a $LOGFILE
#06=>  ifup $nic0 | tee -a $LOGFILE
#06=>  echo Configuring nic1 with provided hostonly IP
#06=>  touch $nic1File
#06=>  cat /dev/null > $nic1File
#06=>  setval $nic1File DEVICE $nic1
#06=>  setval $nic1File BOOTPROTO none
#06=>  delval $nic1File PEERDNS
#06=>  delval $nic1File DNS1
#06=>  delval $nic1File GATEWAY
#06=>  setval $nic1File IPADDR $ipAddr
#06=>  setval $nic1File NETMASK 255.255.255.0
#06=>  setval $nic1File IPV6INIT no
#06=>  setval $nic1File NM_CONTROLLED no
#06=>  setval $nic1File ONBOOT yes
#06=>  setval $nic1File TYPE Ethernet
#06=>  setval $nic1File HWADDR `cat /sys/class/net/$nic1/address`
#06=>  echo "Bringing up '$nic1' ..." | tee -a $LOGFILE
#06=>  ifup $nic1 | tee -a $LOGFILE
#06=>else
#06=>  echo "IP=$ipAddr" | tee -a $LOGFILE
#06=>  exit 1
#06=>fi
#06=>echo "Reloading and restarting network service ..." | tee -a $LOGFILE
#06=>systemctl stop network | tee -a $LOGFILE
#06=>systemctl reload network | tee -a $LOGFILE
#06=>systemctl start network | tee -a $LOGFILE
#06=>echo "Setting hostname to '$newHostname' ..." | tee -a $LOGFILE
#06=>hostnamectl set-hostname $newHostname | tee -a $LOGFILE
