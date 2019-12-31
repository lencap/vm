#!/bin/bash
# vm.sh
# A simpler version of VBoxManage (Bash version). Uses OVA files created with pacos.sh

VER="72"
PRG=`basename $0`
RED2="$(tput bold; tput setaf 1)" YELLOW2="$(tput bold; tput setaf 3)"
BLUE2="$(tput bold; tput setaf 4)" PURPLE2="$(tput bold; tput setaf 5)"
NC="$(tput sgr0)"
VM=`which VBoxManage`
PrintExit () { printf "==> ${RED2}${1}${NC}\n" ; exit 1 ; }
[[ ! -x "$VM" ]] && PrintExit "No VBoxManage binary. Is VirtualBox installed?"
VBHOME=`$VM list systemproperties | grep "^Default machine folder:"` ; VBHOME="/${VBHOME#*/}"
[[ "$VBHOME" == "/" ]] && PrintExit "Error with 'Default machine folder'"
OVADIR=$VBHOME
VMCFHOME="$HOME/.vm"
VMPRIKEY="$HOME/.vm/vmkey"
VMPUBKEY="$HOME/.vm/vmkey.pub"
VMPOSTCF="$HOME/.vm/vmpostcfg"
VMSETNET="$HOME/.vm/vmsetnet"
VMCONFIG=vmconfig
VMSFHOME=vmshare
VMSFCFG=vmcfg
VMDISKSIZE=8192
VBNICTYPE=virtio   # or '82545EM'
VMUSER=root
VMPWD=password

# Always create these special files from the embeded DATA at the end of this file
[[ ! -d "$VMCFHOME" ]] && mkdir $VMCFHOME
grep '^#02=>' $0 | sed 's;^#02=>;;g' > $VMPRIKEY && chmod 600 $VMPRIKEY
ssh-keygen -f $VMPRIKEY -y > $VMPUBKEY
grep '^#11=>' $0 | sed 's;^#11=>;;g' > $VMPOSTCF && chmod 755 $VMPOSTCF
grep '^#14=>' $0 | sed 's;^#14=>;;g' > $VMSETNET && chmod 755 $VMSETNET


vm_usage () {
   printf "Usage:\n" 
   printf "$PRG list                                                  List all VMs\n"
   printf "$PRG create    <vmname> <ovaname>                          Create VM\n"
   printf "$PRG del       <vmname> [-f]                               Delete VM. Force option\n"
   printf "$PRG start     <vmname> [-gui]                             Start VM. GUI option\n"
   printf "$PRG stop      <vmname> [-f]                               Stop VM. Force option\n"
   printf "$PRG ssh       <vmname> [<command>]                        SSH into VM. Command option\n"
   printf "$PRG provision [init]                                      Provision VM as per $VMCONFIG file\n"
   printf "$PRG net       <vmname> <hostonly|nat|bridged> [ip]        Set VM networking type\n"
   printf "$PRG mod       <vmname> <cpus> <memory>                    Modify VM cpus and memory. cpus(1-4) mem (512-4096)\n"
   printf "$PRG holist                                                List all hostonly networks\n"
   printf "$PRG hoadd     <ip>                                        Create next vboxnetN hostonly net\n"
   printf "$PRG hodel     <vboxnetX>                                  Delete given hostonly net\n"
   printf "$PRG sflist    <vmname>                                    List VM shared folders\n"
   printf "$PRG sfadd     <vmname> <SFName> <AbsolutePathOnThisHost>  Map shared folder to /media/sf_SFNAME on VM\n"
   printf "$PRG sfdel     <vmname> <SFName>                           Delete shared folder on VM\n"
   printf "$PRG info      <vmname>                                    List additional VM details\n"
   printf "Running VirtualBox `$VM -v`\n"
}


chkvm_net_status () {
   # chkvm_net_status only checks nic1
   STATE=`$VM guestproperty get $1 /VirtualBox/GuestInfo/Net/0/Status | grep -i '^value:' | awk '{print $2}' | tr '[A-Z]' '[a-z]'`
   [[ "$STATE" == "up" ]] && echo "up" || echo "down"
   return 0
}


isvm_running () {
   STATE=`$VM showvminfo $1 --machinereadable | grep 'VMState=' | awk -F'=' '{print $2}' | sed 's;";;g'`
   [[ "$STATE" == "running" ]] && echo "yes" || echo "no"
   return 0
}


doesvm_exists () {
   STATE=`$VM showvminfo $1 --machinereadable 2>&1 | grep -c 'Could not find a registered machine'`
   [[ "$STATE" == "0" ]] && echo "yes" || echo "no"
   return 0
}


PromptYN () {
   MSG=$1
   read -p "$MSG" -n 1 && [[ ! $REPLY =~ ^[Yy]$ ]] && printf "\n" && exit 1
   printf "\n"
   return 0 
}


vm_list () {
   LIST=`$VM list vms | awk '{print $1}' | sed 's;";;g' | tr '\n' ' '`
   if [[ "$LIST" ]]; then
      printf "%-30s%-5s%-6s%-12s%-10s%-15s%s\n" "NAME" "CPU" "MEM" "STATE" "NET" "IP" "PORTFWD"
      for NAME in $LIST ; do
         INFO=`$VM showvminfo $NAME --machinereadable`
         STATE=`echo "$INFO" | grep 'VMState=' | awk -F'=' '{print $2}' | sed 's;";;g'`
         NET=`echo "$INFO" | grep 'nic2=' | awk -F'=' '{print $2}' | sed 's;";;g' | tr [A-Z] [a-z]`
         CPU=`echo "$INFO" | grep 'cpus=' | awk -F'=' '{print $2}'`
         MEM=`echo "$INFO" | grep 'memory=' | awk -F'=' '{print $2}'`
         [[ -z "$NET" || "$NET" != "hostonly"  ]] && NET=`echo "$INFO" | grep 'nic1=' | awk -F'=' '{print $2}' | sed 's;";;g'`
         FWD=`echo "$INFO" | grep 'Forward.*=' | awk -F'=' '{print $2}' | tr '\n' ' '`
         [[ -z "$FWD" ]] && FWD="\"none\""
         IP="`$VM guestproperty get $NAME /VirtualBox/GuestInfo/Net/0/V4/IP | grep -i '^value:' | awk '{print $2}'`"
         [[ "$NET" == "nat" ]] && IP="10.0.2.15"
         [[ "$NET" == "bridged" && "$STATE" == "poweroff" ]] && IP="-"
         [[ "$IP" == "No value set!" ]] && IP="-"
         [[ "$NET" == "hostonly" ]] && IP="`$VM guestproperty get $NAME /VirtualBox/GuestInfo/Net/1/V4/IP | grep -i '^value:' | awk '{print $2}'`"
         printf "%-30s%-5s%-6s%-12s%-10s%-15s%s\n" "$NAME" "$CPU" "$MEM" "$STATE" "$NET" "$IP" "$FWD"
      done
   else
      PrintExit "No VMs to list"
   fi
   return 0
}


vm_create () {
   NAME=$1 OVA=$2
   [[ -z "$NAME" || -z "$OVA" ]] && PrintExit "Usage: $PRG create <vmname> <ovaname>"
   [[ "`echo $(doesvm_exists $NAME)`" == "yes" ]] && PrintExit "[$NAME] Already exists"
   OVAFILE=$OVADIR/$OVA
   [[ ! -e "$OVAFILE" ]] && PrintExit "OVA $OVA doesn't exist. See available ones: $PRG ovalist"

   printf "==> [$NAME] Creating VM. Please wait...\n"

   # Read vital OVA settings, since these can change from image to image
   # Create (import) with 1CPU, 1024M RAM, and ignore sound & USB from original OVA 
   OVACFG=`$VM import "$OVAFILE" -n 2>&1`
   [[ `echo "$OVACFG" | grep -i error` ]] && PrintExit "[$NAME] Error with OVA $OVA"
   
   DISK=`echo "$OVACFG" | grep -i "Hard disk image" | awk -F':' '{print $1}' | tr -d ' '`
   USB=`echo "$OVACFG" | grep -i "USB controller" | awk -F':' '{print $1}' | tr -d ' '`
   SOUND=`echo "$OVACFG" | grep -i "Sound card" | awk -F':' '{print $1}' | tr -d ' '`
   OPTS="--vsys 0 --vmname $NAME --cpus 1 --memory 1024" 
   [[ "$USB" ]] && OPTS="$OPTS --vsys 0 --unit $USB --ignore"
   [[ "$SOUND" ]] && OPTS="$OPTS --vsys 0 --unit $SOUND --ignore"
   $VM import "$OVAFILE" $OPTS --vsys 0 --unit $DISK --disk "$VBHOME/$NAME/$NAME-disk1.vdi" > /dev/null 2>&1

   # Confirm VM was created
   [[ "`echo $(doesvm_exists $NAME)`" == "no" ]] && PrintExit "[$NAME] Error creating VM"

   # Remove these forwarded ports if they existed in that OVA
   $VM modifyvm $NAME --natpf1 delete sshportfwd > /dev/null 2>&1
   $VM modifyvm $NAME --natpf1 delete ssh > /dev/null 2>&1

   # Make HDD the only bootable device
   $VM modifyvm $NAME --ioapic on --boot1 disk --boot2 none --boot3 none --boot4 none --biosbootmenu disabled

   # Find next available SSH forwarding port. Default = 2222
   SSHPORT=2222
   while [[ `$VM list --long vms | grep "host port = $SSHPORT"` ]]; do ((SSHPORT++)) ; done
   # Set default networking to nat, using valid SSH port
   $VM modifyvm $NAME --nic1 nat --nictype1 $VBNICTYPE --natpf1 ssh,tcp,,$SSHPORT,,22

   # Set default shared folder $VMCFHOME to ease SSH keys mgmt, and so on
   $VM sharedfolder add $NAME --name $VMSFCFG --hostpath "$VMCFHOME" --automount

   # If created with 'provision' command, set default shared folder to current working directory
   [[ -e "$VMCONFIG" ]] && $VM sharedfolder add $NAME --name $VMSFHOME --hostpath "`pwd`" --automount 

   printf "==> [$NAME] Created\n"
   return 0
}


chkvm_waitup () {
   NAME=$1 MAX=$2 TURN=$3
   # Wait for VM NAME to come up. Give it MAX seconds. New line of dots after TURN dots
   [[ -z "$MAX" ]] && MAX=120
   [[ -z "$TURN" ]] && TURN=60
   OLDTIME=`date +%s` LAP=1
   printf "==> "
   # Consider the VM being DOWN while isvm_running functions returns 'no'
   while [[ "`echo $(isvm_running $NAME)`" == "no" ]]; do
      printf "." ; sleep 1
      [[ "`expr $(date +%s) - $OLDTIME`" -ge "$MAX" ]] && break
      ! (( LAP++ % TURN )) && printf "\n==> "
   done
   printf "\n"
   return 0
}


chkvm_waitshutdown () {
   NAME=$1 MAX=$2 TURN=$3
   # Wait for VM NAME to shutdown up. Give it MAX seconds. New line of dots after TURN dots
   [[ -z "$MAX" ]] && MAX=120
   [[ -z "$TURN" ]] && TURN=60
   OLDTIME=`date +%s` LAP=1
   printf "==> "
   # Consider the VM as still up/running while isvm_running function returns 'yes'
   while [[ "`echo $(isvm_running $NAME)`" == "yes" ]]; do
      printf "." ; sleep 1
      [[ "`expr $(date +%s) - $OLDTIME`" -ge "$MAX" ]] && break
      ! (( LAP++ % TURN )) && printf "\n==> "
   done
   printf "\n"
   return 0
}


vm_start () {
   NAME=$1 GUI=$2
   [[ -z "$NAME" ]] && PrintExit "Usage: $PRG start <vmname> [-gui]"
   [[ "`echo $(doesvm_exists $NAME)`" == "no" ]] && PrintExit "[$NAME] VM doesn't exist"
   [[ "`echo $(isvm_running $NAME)`" == "yes" ]] && PrintExit "[$NAME] VM is already running"

   printf "==> [$NAME] Waiting for VM to come up\n"
   [[ "$GUI" == "-gui" ]] && $VM startvm $NAME > /dev/null 2>&1 || $VM startvm $NAME --type headless > /dev/null 2>&1

   # Let's give it at most 120 seconds to boot, else declare it unreachable
   chkvm_waitup $NAME 120 60

      if [[ "`echo $(isvm_guest_additions_up $NAME)`" == "yes" ]]; then

      # Run vmpostcfg to set up SSH login, update hostname and networking, etc
      # NOTE: The $VMHOMECFG/* files are used globally by ALL VMs, so
      #       we *MUST* use copies of them if we need to modify them
      cp $VMPOSTCF ${VMPOSTCF}_${NAME} ; chmod 755 ${VMPOSTCF}_${NAME}

      # IMPORTANT: Adding the hostname to the vmpostcfg script file here
      # NOTE: Again that we're modifying a copy of the global VMHOMECFG file
      sed -i '' -e "s;^hostnamectl set-hostname MYVMNAME;hostnamectl set-hostname $NAME;g" ${VMPOSTCF}_${NAME}

      # Ensure vmpostcfg will set up networking
      IPNIC2="`$VM guestproperty get $NAME /VirtualBox/GuestInfo/Net/1/V4/IP | grep -i '^value:' | awk '{print $2}'`"
      NET=`echo $(vm_list | grep ^$NAME | awk '{print $5}')`
      [[ "$NET" != "hostonly" ]] && IPNIC2=
      printf "/media/sf_vmcfg/vmsetnet $NET $IPNIC2\n" >> ${VMPOSTCF}_${NAME}

      # Runing the script within the VM
      $VM guestcontrol $NAME exec --image /media/sf_${VMSFCFG}/vmpostcfg_${NAME} --username $VMUSER --password $VMPWD --wait-exit --wait-stdout
      rm -f ${VMPOSTCF}_${NAME}
   else
      printf "==> [$NAME] ${RED2}Error. Guest Additions services not available. Please fix.${NC}\n"
   fi 
   printf "==> [$NAME] Started\n"
   return 0
}


vm_stop () {
   NAME=$1 FORCE=$2
   [[ -z "$NAME" ]] && PrintExit "Usage: $PRG stop <vmname>" 
   [[ "`echo $(doesvm_exists $NAME)`" == "no" ]] && PrintExit "[$NAME] VM doesn't exist"
   [[ "`echo $(isvm_running $NAME)`" == "no" ]] && PrintExit "[$NAME] VM is not running"

   [[ -z "$FORCE" || "$FORCE" != "-f" ]] && PromptYN "Sure you want to STOP $NAME? Y/N "
 
   printf "==> [$NAME] Stopping VM. Please wait.\n"
   vm_ssh $NAME poweroff > /dev/null 2>&1
   chkvm_waitshutdown $NAME 3 60

   # Explicit poweroff, in case above wasn't thorough enough
   $VM controlvm $NAME poweroff > /dev/null 2>&1
   printf "==> [$NAME] Stopped\n"

   # VBox bug: ensure processes are really killed after poweroff
   PID=`/bin/ps auxwww | grep "VBoxHeadles[s] --comment $NAME --startvm" | awk '{print $2}'`
   [[ -n "$PID" ]] && kill -9 $PID

   return 0
}


vm_ssh () {
   NAME=$1 COMMAND=$2
   [[ ! "$NAME" ]] && PrintExit "Usage: $PRG ssh <vmname> [<command>]"
   [[ "`echo $(doesvm_exists $NAME)`" == "no" ]] && PrintExit "[$NAME] VM doesn't exist"
   [[ "`echo $(isvm_running $NAME)`" == "no" ]] && PrintExit "[$NAME] VM is not running"

   SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $VMPRIKEY"
   
   VMDETAILS=`echo "$(vm_list)" | grep $NAME`
   NET=`echo "$VMDETAILS" | awk '{print $5}'`
   IP=`echo "$VMDETAILS" | awk '{print $6}'`
   SSHPORT=`echo "$VMDETAILS" | grep -oE ",[0-9]+,,22\"" | awk -F',' '{print $2}'`
   TARGET="root@${IP}"
   [[ "$IP" == "10.0.2.15" ]] && TARGET="-p$SSHPORT root@localhost"

   # See if SSH is actually available
   #nc -z localhost 2222 > /dev/null
   #$? == 0 It's open

   # If no command given then do interactive logon, else run command
   if [[ -z "$COMMAND" ]]; then
      exec $SSH $TARGET 
   else
      $SSH $TARGET "$COMMAND"
      return $?
   fi
}


vm_del () {
   NAME=$1 FORCE=$2
   [[ ! "$NAME" ]] && PrintExit "Usage: $PRG destroy <vmname>"
   [[ "`echo $(doesvm_exists $NAME)`" == "no" ]] && PrintExit "[$NAME] VM doesn't exist"
   [[ -z "$FORCE" || "$FORCE" != "-f" ]] && PromptYN "Sure you want to destroy $NAME? Y/N "
   [[ "`echo $(isvm_running $NAME)`" == "yes" ]] && vm_stop $NAME -f
   $VM unregistervm $NAME --delete > /dev/null 2>&1
   printf "==> [$NAME] Deleted.\n"
   return 0
}


vm_provision () {
   # A valid vmconfig file is expected in current working directory
   if [[ ! -s "$VMCONFIG" ]]; then
      [[ "$1" == "init" ]] && grep '^#01=>' $0 | sed 's;^#01=>;;g' > $VMCONFIG && printf "==> Created $VMCONFIG file.\n" && exit 0
      PrintExit "Empty/missing $VMCONFIG file. Do '$PRG provision init' to create a template of one"
   fi

   # Slurp in vmconfig file parameters
   CFG=`grep -v "^ *#" $VMCONFIG | grep -v "^ *$"`
   [[ -z "$CFG" ]] && PrintExit "Error. $VMCONFIG has no parameters defined"
   VMCNT=`echo "$CFG" | grep "^vm[0-9].name" | grep -c .`
   [[ "$VMCNT" < "1" ]] && PrintExit "Error. At least one vmN.name must be defined in $VMCONFIG"
   VMCNT=`echo "$CFG" | grep "^vm[0-9].ova" | grep -c .`
   [[ "$VMCNT" < "1" ]] && PrintExit "Error. At least one vmN.ova must be defined in $VMCONFIG"

   # Parse vmconfig parameters for each defined VM, starting with vm1
   N=1
   while [[ `echo "$CFG" | grep "^vm${N}.name"` ]]; do

      # Provisioning consists of FOUR (4) easy steps that grab and apply specific vmconfig file parameters.
      #
      # Steps 1 and 2 will leave an existing VM running if its a) named and b) configured exactly as
      # defined in vmconfig. If it's configured differently, then it will stop it, modify it, then 
      # restart it. If the VM doesn't exist then the process is to simply create a new one as per
      # vmconfig file

      # 1. BASIC PARAMETERS
      # Get the 6 possible entries for this VM (error out on duplicates defs)
      NAME=`echo "$CFG" | grep "^vm${N}.name" | grep -c .`
      [[ "$NAME" > "1" ]] && PrintExit "[$NAME] Error. Duplicate vm${N}.name found in $VMCONFIG"
      NAME=`echo "$CFG" | grep "^vm${N}.name" | awk -F'=' '{print $2}' | sed 's/^ *//'` 

      # We can announce this step in the process now that we have $NAME 
      printf "==> [$NAME] Provisioning as per $VMCONFIG file. Please wait...\n"

      OVA=`echo "$CFG" | grep "^vm${N}.ova" | grep -c .` 
      [[ "$OVA" > "1" ]] && PrintExit "[$NAME] Error. Duplicate vm${N}.ova found in $VMCONFIG"
      OVA=`echo "$CFG" | grep "^vm${N}.ova" | awk -F'=' '{print $2}' | sed 's/^ *//'` 
      OVAFILE=$OVADIR/$OVA
      [[ ! -e "$OVAFILE" ]] && PrintExit "[$NAME] Error. OVA file '$OVAFILE' not found"

      # NOTE: We're deliberately ignoring VMs built with OVAs not created with this program.
      #       If there are issues, then the user can always create an OVA with this program.

      CPU=`echo "$CFG" | grep "^vm${N}.cpus" | grep -c .`
      [[ "$CPU" > "1" ]] && PrintExit "[$NAME] Error. Duplicate vm${N}.cpus found in $VMCONFIG"
      CPU=`echo "$CFG" | grep "^vm${N}.cpus" | awk -F'=' '{print $2}' | sed 's/^ *//' | sed 's/ *$//'` 
      [[ -z "$CPU" ]] && CPU=1

      MEM=`echo "$CFG" | grep "^vm${N}.memory" | grep -c .`
      [[ "$MEM" > "1" ]] && PrintExit "[$NAME] Error. Duplicate vm${N}.memory found in $VMCONFIG"
      MEM=`echo "$CFG" | grep "^vm${N}.memory" | awk -F'=' '{print $2}' | sed 's/^ *//' | sed 's/ *$//'` 
      [[ -z "$MEM" ]] && MEM=1024

      NET=`echo "$CFG" | grep "^vm${N}.nettype" | grep -c .`
      [[ "$NET" > "1" ]] && PrintExit "[$NAME] Error. Duplicate vm${N}.nettype found in $VMCONFIG"
      NET=`echo "$CFG" | grep "^vm${N}.nettype" | awk -F'=' '{print $2}' | sed 's/^ *//' | sed 's/ *$//'` 
      [[ -z "$NET" ]] && NET=nat

      IP=`echo "$CFG" | grep "^vm${N}.netip" | grep -c .`
      [[ "$IP" > "1" ]] && PrintExit "[$NAME] Error. Duplicate vm${N}.netip found in $VMCONFIG"
      IP=`echo "$CFG" | grep "^vm${N}.netip" | awk -F'=' '{print $2}' | sed 's/^ *//' | sed 's/ *$//'` 
      [[ -z "$IP" && "$NET" == "hostonly" ]] && PrintExit "[$NAME] Error. Need vm${N}.netip value when vm${N}.nettype=$NET"

      # 2. SHARED FOLDERS
      # Get list of all shared folder definitions, and check for duplicates
      SFLIST=`echo "$CFG" | grep "^vm${N}.sf[0-9][0-9]" | awk '{print $1}' | tr '\n' ' ' `
      for I in $SFLIST ; do
         SF=`echo "$CFG" | grep "^$I " | grep -c .`
         [[ "$SF" > "1" ]] && PrintExit "[$NAME] Error. Duplicate $I found in $VMCONFIG"
      done

      # To save time, validate provisioner command right here
      VMPP=`echo "$CFG" | grep "^vm[0-9].provisioner" | grep -c .`
      [[ "$VMPP" > "1" ]] && PrintExit "[$NAME] Error. Duplicate vm${N}.provisioner found in $VMCONFIG"
      [[ "$VMPP" < "1" ]] && printf "==> [$NAME] ${YELLOW2}Warning. No vm${N}.provisioner found in $VMCONFIG${NC}\n"
      VMPPCMD=`echo "$CFG" | grep "^vm[0-9].provisioner" | awk -F'=' '{print $2}' | sed 's/^ *//' | sed 's/ *$//'`
      if [[ -z "$VMPPCMD" || "${VMPPCMD:0:1}" != '"' || "${VMPPCMD:(-1)}" != '"' ]]; then
         PrintExit "[$NAME] Error. Parameter vm${N}.provisioner is malformed in $VMCONFIG"
      fi
      # Remove leading/trailing quotes
      VMPPCMD=${VMPPCMD%?} VMPPCMD=${VMPPCMD#?}

      # Note, basic parameters and shared folders updates can only be applied when the VM
      # is powered off, which is why we're clumping their checks/updates together. If the
      # VM is running and it's already configured as per vmconfig then we want to leave it
      # alone

      # Ensure VM exists and is configured as per vmconfig
      if [[ "`echo $(doesvm_exists $NAME)`" == "yes" ]]; then
         CFG0=`echo "$(vm_list)" | grep $NAME`
         CPU0=`echo "$CFG0" | awk '{print $2}'` 
         MEM0=`echo "$CFG0" | awk '{print $3}'` 
         NET0=`echo "$CFG0" | awk '{print $5}'` 
         IP0=`echo "$CFG0" | awk '{print $6}'` 
         # Assume VM is configured as per vmconfig, then go thru each item to disprove that
         SAME=true
         [[ "$CPU0" != "$CPU" ]] && SAME=false
         [[ "$MEM0" != "$MEM" ]] && SAME=false
         [[ "$NET0" != "$NET" ]] && SAME=false
         [[ "$IP0" != "$IP" && "$NET" == "hostonly" ]] && SAME=false
         # Check if special shared folder vmN.sf0Y is configured
         SFCFG0=`echo "$(vm_sflist $NAME)"`
         [[ -z `echo "$SFCFG0" | grep "^vmshare " | awk '{print $3}'` ]] && SAME=false
         # Check each vmconfig shared folders for correct format and whether it's already defined on VM
         for I in $SFLIST ; do
            SF=`echo "$CFG" | grep "^$I " | awk -F'"' '{print $2}' | awk '{print $1}'`
            [[ -z "$SF" ]] && PrintExit "[$NAME] Error. Parameter $I is malformed in $VMCONFIG"
            [[ -z `echo "$SFCFG0" | grep "^$SF " | awk '{print $3}'` ]] && SAME=false
         done    

         if [[ "$SAME" == "true" ]]; then
            printf "==> [$NAME] Basic parameters and shared folders are already configured as per $VMCONFIG file\n"  
            [[ "`echo $(isvm_running $NAME)`" == "no" ]] && vm_start $NAME
         else
            printf "==> [$NAME] Updating basic parameters and shared folders as per values in $VMCONFIG file\n"  
            [[ "`echo $(isvm_running $NAME)`" == "yes" ]] && vm_stop $NAME -f
            vm_mod $NAME $CPU $MEM
            vm_sfadd $NAME $VMSFHOME "`pwd`" 
            # Add all vmconfig defined shared folders
            for I in $SFLIST ; do 
               SFNAME=`echo "$CFG" | grep "^$I " | awk -F'"' '{print $2}' | awk '{print $1}'`
               SFPATH=`echo "$CFG" | grep "^$I " | awk -F'=' '{print $2}' | tr -d '"' | awk '{print $2}'`
               [[ ! -d "$SFPATH" ]] && PrintExit "[$NAME] Error. Can't find host path '$SFPATH' for $I in $VMCONFIG"
               vm_sfadd $NAME $SFNAME "$SFPATH"
            done
            vm_net $NAME $NET $IP
            vm_start $NAME
         fi
      else
         printf "==> [$NAME] Creating VM as per values in $VMCONFIG\n"
         vm_create $NAME $OVA
         # Add all vmconfig defined shared folders
         for I in $SFLIST ; do
            SFNAME=`echo "$CFG" | grep "^$I " | awk -F'"' '{print $2}' | awk '{print $1}'`
            SFPATH=`echo "$CFG" | grep "^$I " | awk -F'=' '{print $2}' | tr -d '"' | awk '{print $2}'`
            [[ ! -d "$SFPATH" ]] && PrintExit "[$NAME] Error. Can't find host path '$SFPATH' for $I in $VMCONFIG"
            vm_sfadd $NAME $SFNAME "$SFPATH"
         done
         vm_net $NAME $NET $IP
         vm_start $NAME
      fi 

      # Note, from here on the machine is running, so Step 3 and 4 can be done with SSH commands.

      # 3. SETUP SYMLINKS
      # Get list of all symlink definitions in vmconfig and configure them 
      SMLIST=`echo "$CFG" | grep "^vm${N}.symlink[0-9][0-9]" | awk '{print $1}' | tr '\n' ' ' `
      for I in $SMLIST ; do
         # Check for duplicates
         SM=`echo "$CFG" | grep "^$I " | grep -c .`
         [[ "$SM" > "1" ]] && PrintExit "[$NAME] Error. Duplicate $I found in $VMCONFIG"
         # Check for malformed ones
         SMSOURCE=`echo "$CFG" | grep "^$I " | awk -F'"' '{print $2}' | awk '{print $1}'`
         [[ -z "$SMSOURCE" ]] && PrintExit "[$NAME] Error. Parameter $I is malformed in $VMCONFIG"
         SMTARGET=`echo "$CFG" | grep "^$I " | awk -F'=' '{print $2}' | tr -d '"' | awk '{print $2}'`

         # Create symlink ONLY if it doesn't exists as required
         if [[ "`vm_ssh $NAME \"readlink $SMSOURCE\"`" == "$SMTARGET" ]]; then 
            printf "==> [$NAME] $I already exists\n"
         else
            # Ensure SMSOURCE's basedir exists
            BASEDIR=${SMSOURCE%/*} ; [[ -z "$BASEDIR" ]] && BASEDIR=/
            vm_ssh $NAME "[[ ! -d $BASEDIR ]] && mkdir -p $BASEDIR"
            # If SMSOURCE already exist back it up to SMSOURCE.$$ and delete original
            vm_ssh $NAME "cd $BASEDIR ; [[ -d \"$SMSOURCE\" || -f \"$SMSOURCE\" ]] && cp -a \"$SMSOURCE\" \"${SMSOURCE}.$$\" && rm -rf \"$SMSOURCE\""
            # Create symlink
            vm_ssh $NAME "ln -snf $SMTARGET $SMSOURCE"
            [[ ! "$?" == "0" ]] && PrintExit "[$NAME] Error creating $I"
            printf "==> [$NAME] Created $I : $SMTARGET -> $SMSOURCE\n"
         fi

         # Warn if the actual target reference doesn't exist
         vm_ssh $NAME "test -e $SMTARGET"
         [[ ! "$?" == "0" ]] && printf "==> [$NAME] ${YELLOW2}Warning $I : There's nothing under $SMTARGET${NC}\n"
      done

      # 4. RUN PROVISIONER
      # SSH into VM and run the provisioner command  
      printf "%s\n" "==> [$NAME] Running : ${BLUE2}${VMPPCMD}${NC}"
      vm_ssh $NAME "$VMPPCMD"

      ((N++))   # Advance to next defined VM
   done
   return 0
}


vm_holist () {
   # Grab output of 'VBoxManage list hostonlyifs' and table only the values we care for
   LIST1=`$VM list hostonlyifs | egrep -v "^(GUID:|IPV6Address:|IPV6NetworkM|HardwareAdd|MediumType|VBoxNetwor)"`
   # Mac's BSD sed can't insert '\n', so we're forced to use this messy way of new-lining after each 'Up ' in the temp list
   LIST=`echo "$LIST1" | awk '{print $2}' | tr '\n' ' ' | sed "s;Up  v;Up=v;g" | tr '=' '\n'`
   if [[ "$LIST" && "$LIST" != " " ]]; then
      printf "%-20s%-12s%-16s%-16s%s\n" "NAME" "DHCP" "IP" "NETMASK" "STATUS"
      echo "$LIST" | awk '{printf "%-20s%-12s%-16s%-16s%s\n", $1, $2, $3, $4, $5}'
   else
      PrintExit "No hostonly networks to list "
   fi
   return 0
}


vm_hoadd () {
   IP=$1
   USAGE="Usage: $PRG hoadd <ip>\n"
   IP=`echo $IP | awk -F'.' '$0 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ && $1 < 256 && $2 < 256 && $3 < 256 && $4 == 1'`
   [[ ! "$IP" ]] && PrintExit "Error. A valid IP, ending in '1', is mandatory to add a hostonly vboxnet"
   HOLIST=`echo "$(vm_holist)" | tail -n +2`
   VNET=`echo "$HOLIST" | grep $IP | awk '{print $1}'`
   [[ "$VNET" ]] && PrintExit "Error. That IP address is already used by '$VNET'"
   VNET=`$VM hostonlyif create 2>&1 | tail -1 | awk '{print $2}'`
   VNET=${VNET%?} ; VNET=${VNET#?}    # Remove leading/trailing single quote
   [[ -z "$VNET" ]] && PrintExit "Error creating vboxnet '$VNET'"
   $VM hostonlyif ipconfig $VNET --ip=$IP --netmask=255.255.255.0
   printf "==> Added $VNET with IP $IP\n"
   return 0
}


vm_hodel () {
   VNET=$1
   [[ -z "$1" ]] && PrintExit "Usage: $PRG hodel <vmboxnetX>"
   EXISTS=`echo "$(vm_holist)" | tail -n +2 | grep "^$VNET "`
   [[ "$EXISTS" ]] && $VM hostonlyif remove $VNET > /dev/null 2>&1 || PrintExit "$VNET doesn't exist"
   printf "==> Deleted $VNET\n"
   return 0
}


vm_mod () {
   NAME=$1 CPU=$2 MEM=$3
   USAGE="Usage: $PRG mod <vmname> <cpus> <memory>\n"
   [[ -z "$NAME" ]] && PrintExit "$USAGE"
   [[ -z "$CPU" && -z "$MEM" ]] && PrintExit "$USAGE"
   # Use 1CPU and 1024M RAM as default if weird values are given
   [[ -z "$CPU" || "$CPU" -lt "1" || "$CPU" -gt "4" ]] && CPU=1
   [[ -z "$MEM" || "$MEM" -lt "512" || "$MEM" -gt "4096" ]] && MEM=1024
   [[ "`echo $(doesvm_exists $NAME)`" == "no" ]] && PrintExit "[$NAME] VM doesn't exist"
   [[ "`echo $(isvm_running $NAME)`" == "yes" ]] && PrintExit "[$NAME] VM needs to be poweroff for this"
   $VM modifyvm $NAME --cpus $CPU --memory $MEM
   printf "==> [$NAME] Updated cpus to $CPU and memory to $MEM\n"
   return 0
}


vm_net () {
   NAME=$1 TYPE=$2 IP=$3
   USAGE="Usage: $PRG net <vmname> <hostonly|nat|bridged> [ip]\n"
   [[ -z "$NAME" ]] && PrintExit "$USAGE"
   [[ "`echo $TYPE | egrep -c 'hostonly|nat|bridged'`" == "0" ]] && PrintExit "$USAGE"
   [[ "`echo $(doesvm_exists $NAME)`" == "no" ]] && PrintExit "[$NAME] VM doesn't exist"
   [[ "`echo $(isvm_running $NAME)`" == "yes" ]] && PrintExit "[$NAME] VM needs to be poweroff for this"

   if [[ "$TYPE" == "bridged" ]]; then
      BRIDGENET="`$VM list bridgedifs | grep en0 | grep '^Name:' | sed \"s/Name:            //\"`"
      [[ ! "$BRIDGENET" ]] && PrintExit "Can't determine 'en0' interface on this host"
      $VM modifyvm $NAME --nic1 bridged --bridgeadapter1 "$BRIDGENET" --nictype1 $VBNICTYPE
      printf "==> [$NAME] Configured nic1 to use '$BRIDGENET' for bridged networking\n"
      # BRIDGE networking uses nic1 only, so ensure nic2 is not defined
      $VM modifyvm $NAME --nic2 none
   elif [[ "$TYPE" == "hostonly" ]]; then
      IP=`echo $IP | awk -F'.' '$0 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ && $1 < 256 && $2 < 256 && $3 < 256 && $4 < 256'`
      [[ ! "$IP" ]] && PrintExit "[$NAME] A valid IP is mandatory for hostonly networking."
      [[ "`echo $IP | awk -F'.' '$4 == 1'`" ]] && PrintExit "[$NAME] IP ending .1 is reserved for the vboxnet itself."

      HOLIST=`echo "$(vm_holist)" | tail -n +2`
      # If 1st 3 octects of IP match existing vboxnet, then use that vboxnet
      VNET=`echo "$HOLIST" | grep "${IP%.*}" | head -1 | awk '{print $1}'`
      OTHERVM=`echo "$(vm_list)" | tail -n +2 | grep -v $NAME | grep $IP | awk '{print $1}'`
      [[ "$OTHERVM" ]] && PrintExit "[$NAME] Error. IP $IP is taken by $OTHERVM"
      # Else we need to create a new vboxnet
      if [[ -z "$VNET" ]]; then
         VNET=`$VM hostonlyif create 2>&1 | tail -1 | awk '{print $2}'`
         VNET=${VNET%?} ; VNET=${VNET#?}    # Remove leading/trailing single quote
         [[ -z "$VNET" ]] && PrintExit "Error creating vboxnet '$VNET'"
         # Assign host machine the 1st IP in this vboxnet
         $VM hostonlyif ipconfig $VNET --ip=${IP%.*}.1 --netmask=255.255.255.0
      fi
      # Need updated list for error checking VDHCP and VSTAT below
      HOLIST=`echo "$(vm_holist)" | tail -n +2`
      VDHCP=`echo "$HOLIST" | grep $VNET | awk '{print $2}'`
      VSTAT=`echo "$HOLIST" | grep $VNET | awk '{print $5}'`
      [[ "$VDHCP" != "Disabled" && "$VSTAT" != "Up" ]] && PrintExit "Error with $VNET: DHCP = $VDHCP, STATUS = $VSTAT"
      $VM modifyvm $NAME --nic2 hostonly --hostonlyadapter2 $VNET --nictype2 $VBNICTYPE 
      printf "==> [$NAME] Configured nic1 to use hostonly networking with IP $IP\n"
      $VM guestproperty set $NAME /VirtualBox/GuestInfo/Net/1/V4/IP $IP    # Note the */Net/1* for eth1, not eth0

      # HOSTONLY networking uses *BOTH* nic2 *AND* nic1 (nic1 with NAT for routing outside access)
      $VM modifyvm $NAME --nic1 nat --nictype1 $VBNICTYPE 
      $VM modifyvm $NAME --natpf1 delete ssh > /dev/null 2>&1  # Null output, since it may not be defined

      # Note that configuring this nic2/IP on the VM is actually done by the vm_start function

   elif [[ "$TYPE" == "nat" ]]; then
      SSHPORT0=`echo "$(vm_list)" | grep $NAME | grep -oE ",[0-9]+,,22\"" | awk -F',' '{print $2}'`
      # Use existing SSHPORT if available
      if [[ "$SSHPORT0" =~ "22" ]]; then 
         SSHPORT=$SSHPORT0
      else
         # Find next available SSH forwarding port. Default = 2222
         SSHPORT=2222
         while [[ `$VM list --long vms | grep "host port = $SSHPORT"` ]]; do
            ((SSHPORT++))
         done
      fi 
      $VM modifyvm $NAME --nic1 nat --nictype1 $VBNICTYPE
      printf "==> [$NAME] Configured nic1 to use nat networking\n"
      $VM modifyvm $NAME --natpf1 delete ssh > /dev/null 2>&1  # Null output, since it may not be defined
      $VM modifyvm $NAME --natpf1 ssh,tcp,,$SSHPORT,,22

      # NAT networking uses nic1 only, so ensure nic2 is not defined
      $VM modifyvm $NAME --nic2 none
   fi
   return 0
}


vm_sfadd () {
   NAME=$1 SFNAME=$2 SFPATH=$3
   [[ -z "$SFPATH" || -z "$SFNAME" || -z "$NAME" ]] && PrintExit "Usage: $PRG sfadd <vmname> <SFName> <AbsolutePathOnThisHost>"
   [[ "`echo $(doesvm_exists $NAME)`" == "no" ]] && PrintExit "[$NAME] VM doesn't exist"
   [[ "`echo $(isvm_running $NAME)`" == "yes" ]] && PrintExit "[$NAME] VM needs to be poweroff for this"

   [[ ! -d "$SFPATH" ]] && PrintExit "Cant find '$SFPATH' on this host"

   # Leave as is if it already exists
   EXISTS=`echo "$(vm_sflist $NAME)" | grep ^$SFNAME | awk '{print $3}'`
   [[ "$SFPATH" == "$EXISTS" ]] && printf "==> [$NAME] Shared folder $SFNAME is already defined. Ignoring.\n" && return 0 

   $VM sharedfolder add $NAME --name $SFNAME --hostpath "$SFPATH" --automount
   printf "==> [$NAME] Directory '$SFPATH' mapped to '/media/sf_$SFNAME'\n"
   return 0
}


vm_sfdel () {
   NAME=$1 SFNAME=$2
   [[ -z "$SFNAME" || -z "$NAME" ]] && PrintExit "Usage: $PRG sfdel <vmname> <SFName>"
   [[ "`echo $(doesvm_exists $NAME)`" == "no" ]] && PrintExit "[$NAME] VM doesn't exist"
   [[ "`echo $(isvm_running $NAME)`" == "yes" ]] && PrintExit "[$NAME] VM needs to be poweroff for this"
   $VM sharedfolder remove $NAME --name $SFNAME
   printf "==> [$NAME] Deleted shared folder '$SFNAME'\n"
   return 0
}


vm_sflist () {
   NAME=$1
   [[ ! "$NAME" ]] && PrintExit "Usage: $PRG sflist <vmname>"
   [[ "`echo $(doesvm_exists $NAME)`" == "no" ]] && PrintExit "[$NAME] VM doesn't exist"

   CFG="$VBHOME/$NAME/$NAME.vbox"
   [[ ! -e "$CFG" ]] && PrintExit "[$NAME] Cant find '$CFG' file"
   SFLIST=`grep "<SharedFolder " "$CFG"`
   [[ -z "$SFLIST" ]] && PrintExit "[$NAME] No shared folders to list"

   echo "$SFLIST" | while read LINE ; do
      SFNAME=`echo $LINE | awk -F'=' '{print $2}' | awk -F'"' '{print $2}'`
      SFPATH=`echo $LINE | awk -F'=' '{print $3}' | awk -F'"' '{print $2}'`
      printf "%-20s%-30s%s\n" "$SFNAME" "/media/sf_$SFNAME" "$SFPATH"
   done
   return 0
}


vm_info () {
   NAME=$1
   [[ ! "$NAME" ]] && PrintExit "Usage: $PRG info <vmname>"
   [[ "`echo $(doesvm_exists $NAME)`" == "no" ]] && PrintExit "[$NAME] VM doesn't exist"
   $VM showvminfo $NAME --details --machinereadable | awk -F'=' '{printf "%-50s%s\n", $1, $2}'
   printf "\n"
   $VM guestproperty enumerate $NAME | sort | awk '{printf "%-50s%s\n", $2, $4}'
   return 0
}


# Perform defined function or print usage
if [[ "`type -t vm_${1}`" == "function" ]]; then
   vm_${1} "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
else
   vm_usage
fi

exit 0


# DATA
#01=># vmconfig
#01=># Used by vm when invoked as 'vm provision`. You can define one to nine VMs
#01=># here and it will create and provision them accordingly. Parameters vm1.*
#01=># define the first VM, parameters vm2.* define the second one, and so on.
#01=>#
#01=># Lines starting with a hash(#) are treated as comments. Do NOT use spaces in
#01=># values, unless you quoted(") them. Use at least one(1) space round the equal
#01=># sign (=).
#01=>#
#01=># Parameters vmN.name and vmN.ova are mandatory, while all others are optional,
#01=># except where noted. This sample config will create virtual machines dev27 and
#01=># dev28.mydoamin.vm. The vm1.provisioner is just an example for doing Puppet,
#01=># but it can be any shell command. Uncomment these values and try things out.
#01=>#
#01=># Main parameters
#01=>#vm1.name        = dev27.mydomain.vm
#01=>#vm1.ova         = centos70.ova
#01=>#vm1.cpus        = 2
#01=>#vm1.memory      = 2048
#01=>#vm1.nettype     = hostonly
#01=>#vm1.netip       = 10.20.30.40
#01=>#
#01=># Shared folders (optional, except were noted)
#01=># All shared folders point to /media/sf_SFNAME within the VM. Note, that sf0X
#01=># and sf0Y are *always* created. See 'vm sfadd' command for more info.
#01=>#vm1.sf0X        = "vmcfg       /Users/user1/.vm"
#01=>#vm1.sf0Y        = "vmshare     <CURRENT_WORKING_DIRECTORY>"
#01=>#vm1.sf01        = "baseproject /Users/user1/baseproject"
#01=>#
#01=># Symlinks (optional)
#01=># Belows symlinks are almost essential when provisioning with Puppet
#01=>#vm1.symlink01   = "/media/sf_vmshare         /vmshare"
#01=>#vm1.symlink02   = "/vmshare/puppet/modules   /etc/puppet/modules"
#01=>#vm1.symlink03   = "/vmshare/hieradata        /etc/puppet/hieradata"
#01=>#vm1.symlink04   = "/vmshare/puppet/manifests /etc/puppet/manifests"
#01=>#
#01=># Provisioner command (optional)
#01=>#vm1.provisioner = "puppet apply --verbose --hiera_config /vmshare/puppet/hiera.yaml --environment local --modulepath '/vmshare/puppet/modules' --detailed-exitcodes /vmshare/puppet/manifests/localdevbox.pp"
#01=>#
#01=>#
#01=>#vm2.name        = dev28.mydomain.vm
#01=>#vm2.nettype     = hostonly
#01=>#vm2.netip       = 10.20.30.41
#
# Very INSECURE SSH private key for managing VBox VMs
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
#
#11=>#!/bin/bash
#11=># vmpostcfg
#11=># IMPORTANT: The vm start function will replace MYVMNAME with provided name
#11=>hostnamectl set-hostname MYVMNAME
#
#14=>#!/bin/bash
#14=># vmsetnet
#14=>NET=$1 IP=$2
#14=>ETH0=/etc/sysconfig/network-scripts/ifcfg-eth0
#14=>ETH1=/etc/sysconfig/network-scripts/ifcfg-eth1
#14=>delval () {
#14=>   CFG=$1 PARAM=$2
#14=>   sed -i "/$PARAM=/d" $CFG
#14=>   return 0
#14=>}
#14=>setval () {
#14=>   CFG=$1 PARAM=$2 VAL=$3
#14=>   [[ ! -e "$CFG" ]] && return 1
#14=>   OLD=`grep "^$PARAM=" $CFG | awk -F'=' '{print $2}'`
#14=>   sed -i "s;$PARAM=$OLD;$PARAM=\"$3\";g" $CFG
#14=>   [[ -z "`grep $PARAM $CFG`" ]] && echo "$PARAM=\"$3\"" >> $CFG
#14=>}
#14=>if [[ "$NET" == "nat" ]] ; then
#14=>   # Configure eth0 with VirtualBox standard static IP settings
#14=>   setval $ETH0 DEVICE eth0
#14=>   setval $ETH0 BOOTPROTO static
#14=>   setval $ETH0 DNS1 10.0.2.3
#14=>   setval $ETH0 GATEWAY 10.0.2.2
#14=>   setval $ETH0 IPADDR 10.0.2.15
#14=>   setval $ETH0 NETMASK 255.255.255.0
#14=>   setval $ETH0 IPV6INIT no
#14=>   setval $ETH0 NM_CONTROLLED yes
#14=>   setval $ETH0 ONBOOT yes
#14=>   setval $ETH0 TYPE Ethernet
#14=>   setval /etc/sysconfig/network GATEWAY 10.0.2.2
#14=>   ifup eth0 > /dev/null
#14=>   [[ -e "$ETH1" ]] && rm -f $ETH1 && ifdown eth1 > /dev/null
#14=>elif [[ "$NET" == "hostonly" && -n "$IP" ]] ; then
#14=>   # Configure eth0 with VirtualBox standard static IP settings
#14=>   setval $ETH0 DEVICE eth0
#14=>   setval $ETH0 BOOTPROTO static
#14=>   setval $ETH0 DNS1 10.0.2.3
#14=>   setval $ETH0 GATEWAY 10.0.2.2
#14=>   setval $ETH0 IPADDR 10.0.2.15
#14=>   setval $ETH0 NETMASK 255.255.255.0
#14=>   setval $ETH0 IPV6INIT no
#14=>   setval $ETH0 NM_CONTROLLED yes
#14=>   setval $ETH0 ONBOOT yes
#14=>   setval $ETH0 TYPE Ethernet
#14=>   setval /etc/sysconfig/network GATEWAY 10.0.2.2
#14=>   ifup eth0 > /dev/null
#14=>   # Configure eth1 with provided hostonly IP
#14=>   cp /dev/null > $ETH1
#14=>   setval $ETH1 DEVICE eth1
#14=>   setval $ETH1 BOOTPROTO static
#14=>   delval $ETH1 DNS1
#14=>   delval $ETH1 GATEWAY
#14=>   setval $ETH1 IPADDR $IP
#14=>   setval $ETH1 NETMASK 255.255.255.0
#14=>   setval $ETH1 IPV6INIT no
#14=>   setval $ETH1 NM_CONTROLLED yes
#14=>   setval $ETH1 ONBOOT yes
#14=>   setval $ETH1 TYPE Ethernet
#14=>   ifup eth1 > /dev/null
#14=>elif [[ "$NET" == "bridged" ]] ; then
#14=>   setval $ETH0 DEVICE eth0
#14=>   setval $ETH0 BOOTPROTO dhcp
#14=>   delval $ETH0 DNS1
#14=>   delval $ETH0 GATEWAY
#14=>   delval $ETH0 IPADDR
#14=>   delval $ETH0 NETMASK
#14=>   setval $ETH0 IPV6INIT no
#14=>   setval $ETH0 NM_CONTROLLED yes
#14=>   setval $ETH0 ONBOOT yes
#14=>   setval $ETH0 TYPE Ethernet
#14=>   delval /etc/sysconfig/network GATEWAY
#14=>   rm -f /etc/resolv.conf
#14=>   ifup eth0 > /dev/null
#14=>   [[ -e "$ETH1" ]] && rm -f $ETH1 && ifdown eth1 > /dev/null
#14=>else
#14=>   exit 1
#14=>fi
#14=>service network restart > /dev/null
#14=>exit 0
#
