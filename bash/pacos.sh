#!/bin/bash
# pacos.sh
# List, create, delete, and import CentOS VirtualBox OVA images to be 
# used by vm.sh

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

VMINSKEY="$HOME/.vm/vmkeyinstall"
VMKICKCF="$HOME/.vm/ks.cfg"
VBGAINST="$HOME/.vm/vbgainstall"
VMROOTRC="$HOME/.vm/root.bashrc"
VMPREIMG="$HOME/.vm/preimgprep"
VMPOSTKS="$HOME/.vm/vmpostks"
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
grep '^#03=>' $0 | sed 's;^#03=>;;g' > $VMINSKEY && chmod 755 $VMINSKEY
grep '^#06=>' $0 | sed 's;^#06=>;;g' > $VMKICKCF && chmod 644 $VMKICKCF
grep '^#07=>' $0 | sed 's;^#07=>;;g' > $VBGAINST && chmod 755 $VBGAINST
grep '^#08=>' $0 | sed 's;^#08=>;;g' > $VMROOTRC && chmod 644 $VMROOTRC
grep '^#09=>' $0 | sed 's;^#09=>;;g' > $VMPREIMG && chmod 755 $VMPREIMG
grep '^#10=>' $0 | sed 's;^#10=>;;g' > $VMPOSTKS && chmod 755 $VMPOSTKS

grep '^#11=>' $0 | sed 's;^#11=>;;g' > $VMPOSTCF && chmod 755 $VMPOSTCF
grep '^#14=>' $0 | sed 's;^#14=>;;g' > $VMSETNET && chmod 755 $VMSETNET


ova_usage () {
   printf "Usage:\n" 
   printf "$PRG list                                             List all available OVA files\n"
   printf "$PRG create <ovaname> [<vmname|ISOfile>] [-f1] [-f2]  Create new OVA. From VM vmname|ISO option. Force ovaname|vmname options\n"
   printf "$PRG del    <ovaname> [-f]                            Delete OVA. Force option\n"
   printf "$PRG imp    <ovafile>                                 Import OVA file to make available to this program\n"
   printf "Running VirtualBox `$VM -v`\n"
}


isvm_guest_additions_up () {
   GACHK=`$VM guestcontrol $1 stat /tmp --username=$VMUSER --password=$VMPWD 2>&1 | grep -ioe "is a directory" | tr '[A-Z]' '[a-z]'`
   [[ "$GACHK" == "is a directory" ]] && echo "yes" || echo "no"
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
      printf "%-30s%-5s%-6s%-10s%-10s%-15s%s\n" "NAME" "CPU" "MEM" "STATE" "NET" "IP" "PORTFWD"
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
         printf "%-30s%-5s%-6s%-10s%-10s%-15s%s\n" "$NAME" "$CPU" "$MEM" "$STATE" "$NET" "$IP" "$FWD"
      done
   else
      PrintExit "No VMs to list"
   fi
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

   printf "==> [$NAME] Waiting for VM to power on\n"
   if [[ "$GUI" == "-gui" ]]; then
      $VM startvm $NAME > /dev/null 2>&1
   else
      $VM startvm $NAME --type headless > /dev/null 2>&1
   fi
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


vm_del () {
   NAME=$1 FORCE=$2
   [[ ! "$NAME" ]] && PrintExit "Usage: $PRG destroy <vmname>"
   [[ "`echo $(doesvm_exists $NAME)`" == "no" ]] && PrintExit "[$NAME] VM doesn't exist"
   [[ -z "$FORCE" || "$FORCE" != "-f" ]] && PromptYN "Sure you want to destroy $NAME? Y/N "
   [[ "`echo $(isvm_running $NAME)`" == "yes" ]] && stop_vm $NAME -f
   $VM unregistervm $NAME --delete > /dev/null 2>&1
   printf "==> [$NAME] Deleted.\n"
   return 0
}


ova_list () {
   cd "$OVADIR"
   [[ "`ls -1 *.ova 2>&1`" =~ "No such file" ]] && PrintExit "No OVA files to list"
   printf "%-20s%-54s%-8s%s\n" "NAME" "FILE" "SIZE" "DISK"
   for F in `ls -1 *.ova 2>&1` ; do
      SIZE=`ls -lh $F | awk '{print $5}'`
      DISK=`tar tf $F | grep "\.[vV].*[dD].*$"`
      printf "%-20s%-54s%-8s%s\n" "$F" "$OVADIR/$F" "$SIZE" "$DISK"
   done
   return 0
}


ova_create () {
   NAME=$1 VMNAME=$2
   FORCE1=`echo "$2 $3 $4" | grep -op "\-f1"`
   FORCE2=`echo "$2 $3 $4" | grep -op "\-f2"`
   [[ -z "$NAME" ]] && PrintExit "Usage: $PRG ovacreate <ovaname> <ISOfile|vmname> [-f1] [-f2]"
   [[ "${NAME:(-4)}" != ".ova" ]] && PrintExit "OVA name *must* end with '.ova'"
   [[ -f "$OVADIR/$NAME" && "$FORCE1" != "-f1" ]] && PromptYN "OVA '$NAME' already exists. Overwrite it? Y/N "

   # Create OVA from provided VMNAME, if it exists
   if [[ -n "$VMNAME" && "$VMNAME" != "-f1" && "$VMNAME" != "-f2" && "${VMNAME:(-4)}" != ".iso" ]]; then
      [[ "`echo $(doesvm_exists $VMNAME)`" == "no" ]] && PrintExit "[$VMNAME] VM doesn't exist"
      [[ "$FORCE2" != "-f2" ]] && PromptYN "Did you run /root/bin/preimgprep on $VMNAME yet? Y/N "
      [[ "`echo $(isvm_running $VMNAME)`" == "yes" ]] && PrintExit "[$VMNAME] VM needs to be poweroff for this"
      printf "==> Creating $NAME from VM $VMNAME\n"
      [[ -e "$OVADIR/$NAME" ]] && rm -f "$OVADIR/$NAME"
      $VM export $VMNAME -o "$OVADIR/$NAME" --ovf20 > /dev/null 2>&1
      return 0
   fi

   # Create OVA from a Kickstart installation of CentOS using provided ISO file
   ISOFILE=$VMNAME
   [[ ! -e "$ISOFILE" ]] && PrintExit "'$ISOFILE' doesn't exist."
   [[ -z "`file $ISOFILE | awk -F':' '{print $2}' | grep ISO`" ]] && PrintExit "'$ISOFILE' doesn't appear to be an ISO file."
   MKISOFS=/opt/local/bin/mkisofs
   if [[ ! -x "$MKISOFS" ]]; then
      printf "==> ${RED2}Can't find $MKISOFS, which is required to proceed. Note, this tool isn't native${NC}\n"
      printf "==> ${RED2}to Mac OS X, so you'll need to install it with 'sudo port install cdrtools' or equivalent.${NC}\n"
      exit 1
   fi

   printf "==> ${PURPLE2}Creating $NAME can take about 10 to 20 minutes depending on below activities:\n"
   printf "    Remastering '${ISOFILE##*/}' to do our own special OS unattended installation.\n"
   printf "    Create a temporary VM using above ISO.\n"
   printf "    Create OVA from that VM.${NC}\n"
   PromptYN "==> You really want to proceed with all this? Y/N "

   VMNAME=${NAME%.*} 
   if [[ "`echo $(doesvm_exists $VMNAME)`" == "yes" ]]; then
      PrintExit "A VM named '$VMNAME' already exists, which is problematic. Please use a different name for your OVA."
   fi

   printf "==> START `date +%H:%M:%S`\n"

   # Important: We're doing all this from VBHOME directory!
   STARTDIR=`pwd`
   cd "$VBHOME/" 
   [[ "$?" != "0" ]] && PrintExit "Error cd'ing to '$VBHOME/'"

   ISOFILE_KS="${ISOFILE##*/}"            # use only basename
   ISOFILE_KS="${ISOFILE_KS%.*}-KS.iso"
   printf "==> [$VMNAME] Creating $ISOFILE_KS from original CentOS ISO\n"

   # Mac OS X trix to mount the hybrid ISO file now being used by most distros.
   # The simpler 'hdiutil mount -quiet $ISOFILE 2>&1' used to work but not no mo'
   mkdir isomount
   DISKMOUNTED1=`diskutil list | grep -c "dev/disk"`
   LASTDISK1=`diskutil list | grep "dev/disk" | sort | tail -1`
   ISOFILE="$(cd "$(dirname "../$ISOFILE")"; pwd)/${ISOFILE##*/}"  # OS X trix to get abs path, since readlink -e isn't supported
   hdiutil attach -quiet -noverify -nomount "$ISOFILE" 2>&1 
   [[ "$?" != "0" ]] && PrintExit "Error mounting $ISOFILE"
   DISKMOUNTED2=`diskutil list | grep -c "dev/disk"`
   LASTDISK2=`diskutil list | grep "dev/disk" | sort | tail -1`
   [[ "$DISKMOUNTED1" == "$DISKMOUNTED2" || "$LASTDISK1" == "$LASTDISK2" ]] && PrintExit "Error mounting $ISOFILE"
   mount_cd9660 $LASTDISK2 isomount
   [[ "$?" != "0" ]] && PrintExit "Error unmounting $ISOFILE"

   # Duplicate ISO content 
   TMPDIR="tmp$$"
   mkdir -p $TMPDIR/vmbin
   cp -a isomount/. $TMPDIR/
   chmod -R 777 $TMPDIR

   # Below command also used to work alone, but not no more
   # 'hdiutil unmount -quiet isomount 2>&1'
   umount isomount
   diskutil eject /dev/disk2 > /dev/null 2>&1
   [[ "$?" != "0" ]] && PrintExit "Error unmounting $ISOFILE"
   rmdir isomount

   # Modify existing isolinux.cfg file
   # Reduce prompt wait time and point to our own /vmbin/ks.cfg file 
   sed -i '' -e "s/^default.*$/default ks/g ; s/^.*prompt.*$/prompt 0/g ; s/^timeout.*$/timeout 0/g" $TMPDIR/isolinux/isolinux.cfg
   printf "label ks\n  kernel vmlinuz\n  append ks=cdrom:/vmbin/ks.cfg initrd=initrd.img\n" >> $TMPDIR/isolinux/isolinux.cfg  

   # Copy all essential files to this new ISO
   cp -a $VMCFHOME/. $TMPDIR/vmbin/

   # Use root password defined in this program
   sed -i '' -e "s;^rootpw password;rootpw $VMPWD;g" $TMPDIR/vmbin/ks.cfg

   # Put a copy of the GuestAdditions ISO in the VM, to be installed post Kickstart build
   GAISO=`$VM list systemproperties | grep "^Default Guest Additions ISO:"` ; GAISO="/${GAISO#*/}"
   [[ -e "$GAISO" ]] && cp $GAISO $TMPDIR/vmbin/ || printf "==> ${YELLOW2}Warning. Missing Guest Addition ISO${NC}\n"

   # Create new Kickstart ISO
   cd $TMPDIR/
   $MKISOFS -quiet -o ../$ISOFILE_KS -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -R -J -T . 2>&1
   [[ "$?" != "0" ]] && PrintExit "Error creating $ISOFILE_KS"
   cd $STARTDIR > /dev/null
   # Remove temp dir
   rm -rf "$VBHOME/$TMPDIR"

   printf "==> [$VMNAME] Creating basic VM with 1 cpu, 1GB mem, 8GB disk, and nat networking\n"

   RESULT=`$VM createvm --name "$VMNAME" --ostype "RedHat_64" --register 2>&1`
   [[ ! "$RESULT" =~ "created and registered" ]] && PrintExit "Error creating $VMNAME"
   mod_vm $VMNAME 1 1024 > /dev/null
   net_vm $VMNAME nat > /dev/null
   $VM modifyvm $VMNAME --natdnsproxy1 on --natdnshostresolver1 on
   # Make CDROM primary boot device, so we can do unattended ISO installation below
   $VM modifyvm $VMNAME --ioapic on --boot1 dvd --boot2 disk --boot3 none --boot4 none --biosbootmenu disabled
   RESULT=`$VM createhd --filename "$VBHOME/$VMNAME/$VMNAME-disk1.vdi" --size $VMDISKSIZE --format VDI 2>&1`
   [[ ! "$RESULT" =~ "Disk image created" ]] && PrintExit "Error creating 8GB disk file"
   $VM storagectl "$VMNAME" --name "IDE" --add ide --controller PIIX4 --portcount 2 --hostiocache off --bootable on
   $VM storagectl "$VMNAME" --name "SATA" --add sata --controller IntelAHCI --portcount 1 --hostiocache off --bootable on
   $VM storageattach "$VMNAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$VBHOME/$VMNAME/$VMNAME-disk1.vdi"

   printf "==> [$VMNAME] Attaching new $ISOFILE_KS to CDROM drive\n"
   $VM storageattach "$VMNAME" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "$VBHOME/$ISOFILE_KS"

   printf "==> [$VMNAME] Performing CentOS kickstart unattended installation. Please wait...\n"
   #vm_start $VMNAME > /dev/null
   vm_start $VMNAME -gui > /dev/null  # DEBUG
   chkvm_waitup $VMNAME 300 60        # Wait at most 5 min for VM to come up and Kickstart installation to start
   chkvm_waitshutdown $VMNAME 1200 60 # Wait at most 20 min for VM to poweroff after Kickstart completes

   # Remove temp kickstart ISO
   rm -rf "$VBHOME/$ISOFILE_KS"
   printf "==> Kickstart completed, and VM is powered off. Now detaching CDROM drive\n"
   $VM storageattach "$VMNAME" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium none
   $VM modifyvm $VMNAME --ioapic on --boot1 disk --boot2 none --boot3 none --boot4 none --biosbootmenu disabled

   # Compact the disk
   $VM modifyhd "$VBHOME/$VMNAME/$VMNAME-disk1.vdi" --compact > /dev/null 2>&1

   # Call this same function to create the OVA from the temp VM we've just built
   ova_create ${NAME}.ova $VMNAME -f1 -f2
   vm_del $VMNAME -f
   printf "==> Created ${NAME}.ova\n"
   printf "==> END   `date +%H:%M:%S`\n"
   return 0
}


ova_del () {
   NAME=$1 FORCE=$2
   [[ -z "$NAME" ]] && PrintExit "Usage: $PRG del <ovaname> [-f]"
   cd "$OVADIR"
   [[ ! -f "$NAME" ]] && PrintExit "Error. No such OVA file."
   [[ -z "$FORCE" || "$FORCE" != "-f" ]] && PromptYN "Sure you want to delete $NAME? Y/N "
   rm -f $NAME
   printf "==> Deleted $NAME\n" 
   return 0
}


ova_imp () {
   OVAFILE=$1
   [[ -z "$OVAFILE" ]] && PrintExit "Usage: $PRG imp <ovafile>"
   OVA=${OVAFILE##*/}
   [[ -e "$OVADIR/$OVA" ]] && PrintExit "OVA '$OVA' exists already."
   [[ "${OVA:(-4)}" != ".ova" ]] && PrintExit "OVA name *must* end in '.ova'"
   [[ "`tar tf \"$OVAFILE\" 2>&1 | grep -c ovf`" != "1" ]] && PrintExit "'$OVAFILE' is not an OVA file."
   cp "$OVAFILE" "$OVADIR/"
   printf "==> OVA '$OVA' is now available to this program.\n"
   return 0
}


# Perform defined function or print usage
if [[ "`type -t ova_${1}`" == "function" ]]; then
   ova_${1} "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
else
   ova_usage
fi

exit 0


# DATA
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
#03=>#!/bin/bash
#03=># vmkeyinstall
#03=>mkdir /root/.ssh
#03=>chmod 700 /root/.ssh
#03=>if [[ -n "$1" && -e "$1"  ]]; then
#03=>   cp $1 /root/.ssh/authorized_keys
#03=>   [[ ! "$?" == "0" ]] && printf "Error: cp $1 /root/.ssh/authorized_keys\n" && exit 1
#03=>else   
#03=>   cp /media/sf_vmcfg/vmkey.pub /root/.ssh/authorized_keys
#03=>   [[ ! "$?" == "0" ]] && printf "Error: cp /media/sf_vmcfg/vmkey.pub /root/.ssh/authorized_keys\n" && exit 1
#03=>fi
#03=>chmod 644 /root/.ssh/authorized_keys
#03=>exit 0
#
#06=># ks.cfg
#06=>text
#06=>install
#06=>cdrom
#06=>unsupported_hardware
#06=>lang en_US.UTF-8
#06=>keyboard us
#06=>network --onboot=yes --device=eth0 --noipv6 --bootproto=static --ip=10.0.2.15 --netmask=255.255.255.0 --gateway=10.0.2.2 --nameserver=10.0.2.3
#06=>rootpw password
#06=>firewall --disabled
#06=>authconfig --useshadow --passalgo=sha512
#06=>selinux --disabled
#06=>timezone --utc America/New_York
#06=>clearpart --all --drives=sda
#06=>zerombr 
#06=>part /boot --fstype=ext4 --size=500
#06=>part pv.01 --grow --size=1
#06=>volgroup VolGroup --pesize=4096 pv.01
#06=>logvol / --fstype=ext4 --name=lv_root --vgname=VolGroup --grow --size=1024 --maxsize=51200
#06=>logvol swap --name=lv_swap --vgname=VolGroup --grow --size=1228 --maxsize=1228
#06=>bootloader --location=mbr --driveorder=sda --append="nomodeset crashkernel=auto rhgb quiet"
#06=>poweroff
#06=>%packages --nobase
#06=>@core
#06=>binutils
#06=>make
#06=>%end
#06=>#
#06=>%post --nochroot --log=/mnt/sysimage/root/ks-post1.log
#06=># CentOS 6: DVD is mounted on /mnt/source
#06=># CentOS 7: DVD is mounted on /run/install/repo
#06=>echo Copying essential scripts from /run/install/repo/vmbin/ to /mnt/sysimage/root/bin/
#06=>mkdir -vp /mnt/sysimage/root/bin
#06=>cp -va /run/install/repo/vmbin/. /mnt/sysimage/root/bin/
#06=>%end
#06=>%post --log=/root/ks-post2.log
#06=>echo Executing special /root/bin/vmpostks script
#06=>/root/bin/vmpostks
#06=>%end
#
#07=>#!/bin/bash
#07=># vbgainstall
#07=>printf "==> Installing VirtualBox Guest Additions\n"
#07=>ISO=/root/bin/VBoxGuestAdditions.iso
#07=>[[ ! -f "$ISO" ]] && printf "==> Error. Can't find $ISO\n" && exit 1
#07=>cd /root/
#07=>printf "==> First ensure gcc, make, dkms, and kernel-dev packages are installed\n"
#07=>PKGINSTALL="yum -y install kernel-devel-$(uname -r)"
#07=>[[ -! -e "/etc/redhat-release" ]] && PKGINSTALL="apt-get -y install"
#07=>$PKGINSTALL gcc make dkms
#07=>[[ ! -d /media/dvd ]] && mkdir /media/dvd
#07=>mount -t iso9660 -o loop $ISO /media/dvd
#07=>/media/dvd/VBoxLinuxAdditions.run
#07=>umount /media/dvd
#07=>printf "==> Done installing VirtualBox Guest Additions\n"
#07=>exit 0
#
#08=># /root/.bashrc
#08=>
#08=># Source global definitions
#08=>if [ -f /etc/bashrc ]; then
#08=>        . /etc/bashrc
#08=>fi
#08=>
#08=># User specific aliases and functions
#08=>alias rm='rm -i'
#08=>alias cp='cp -i'
#08=>alias mv='mv -i'
#08=>
#08=>alias ls='ls --color'
#08=>alias ll='ls -ltr'
#08=>alias h='history'
#08=>alias vi='vim'
#08=>
#08=>export PATH=$PATH:$HOME/bin
#08=>
#08=># PS1 Prompt: Use friendly base hostname of certname, else use system hostname
#08=>HNAME=`grep -v "^#" /etc/puppet/puppet.conf | grep " certname " | awk '{print $3}'`
#08=>[[ -z "$HNAME" ]] && HNAME=`hostname -s`
#08=>HNAME=${HNAME%%.*}
#08=>[[ "`whoami`" != "root" ]] && PS1="[\u@$HNAME \W]\$ " || PS1="\[\033[01;31m\][\u@$HNAME \W]# \[\033[00;32m\]"
#
#09=>#!/bin/bash
#09=># preimgprep
#09=># Clean up yum
#09=>rm -rf /var/cache/yum /var/lib/yum
#09=>yum -y clean all
#09=># Clean up Puppet client, if configured
#09=>PP=/usr/bin/puppet
#09=>[[ -x "$PP" ]] && SSLDIR=`$PP agent --configprint ssldir` && rm -rf $SSLDIR
#09=># Stop special services, if configured
#09=>SERVICES="newrelic-sysmond nrpe mcollective"
#09=>for S in $SERVICES ; do
#09=>   [[ ! "`service $S status 2>&1`" =~ "unrecognized" ]] && service $S stop
#09=>done
#09=># Zero out common /var/log files
#09=>LOGFILES="secure messages yum.log mcollective.log maillog wtmp btmp cron newrelic/nrsysmond.log"
#09=>for F in $LOGFILE ; do
#09=>   [[ -e "/var/log/$F" ]] && >/var/log/$F
#09=>done
#09=># Reset all MAC addresses and remove 70-persistent-net.rules file
#09=>sed -i "/^HWADDR=/d" /etc/sysconfig/network-scripts/ifcfg-eth*
#09=>rm -rf /etc/udev/rules.d/70-persistent-net.rules
#09=># Ensure .bash_logout will clear history
#09=>MARKER=/root/.clear_history
#09=>echo $MARKER > $MARKER
#09=>sed -i'' "/f \$HISTFILE/d" /root/.bash_logout
#09=>printf "[ -e $MARKER ] && history -c && rm -rf \$HISTFILE /root/.bash_history $MARKER\n" >> /root/.bash_logout
#09=># Ensure bash runs .bash_logout on exit
#09=>trap 'sh /root/.bash_logout' EXIT
#09=>exit 0
#
#10=>#!/bin/bash
#10=># vmpostks
#10=>printf "==> START `/bin/date +%H:%M:%S`\n\n"
#10=>printf "==> Ensuring all vmpostks scripts  are executable\n"
#10=>/bin/chmod -vR 755 /root/bin ; /bin/chown -vR root:root /root/bin
#10=>/bin/rm -vrf /root/bin/TRANS.TBL
#10=>printf "==> Setting up root PS1\n"
#10=>cp /root/bin/root.bashrc /root/.bashrc ; chmod 644 /root/.bashrc
#10=>printf "==> Installing root SSH key\n"
#10=>/root/bin/vmkeyinstall /root/bin/vmkey.pub
#10=>printf "==> Disabling DNS reverse lookup for SSH\n"
#10=>sed -i "s;^.*UseDNS yes;UseDNS no;g" /etc/ssh/sshd_config
#10=>printf "==> Creating root .vimrc\n"
#10=>printf "\" .vimrc\nsyntax on\nhi comment ctermfg=blue\nau BufRead,BufNewFile *.pp setfiletype puppet\nset ruler\n" > /root/.vimrc
#10=>/bin/chown -vR root:root /root/.vimrc
#10=>
#10=>printf "==> Restarting nework services\n"
#10=>systemctl restart network.service
#10=>
#10=>printf "==> Installing other essential packages\n"
#10=>/bin/rpm -ivh http://yum.puppetlabs.com/el/7/products/x86_64/puppetlabs-release-7-11.noarch.rpm
#10=>/bin/rpm -ivh http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.3-1.el7.rf.x86_64.rpm
#10=>/bin/rpm -Uvh http://mirror.pnl.gov/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
#10=>/usr/bin/yum -y install yum-utils yum-presto
#10=>/usr/bin/yum-config-manager --enable rpmforge-extras
#10=>/usr/bin/yum -y install puppet sysstat bind-utils ftp lsof mailx ntp ntpdate
#10=>/usr/bin/yum -y install rsync screen strace tcpdump telnet time wget vim qt bzip2 nfs-utils
#10=>#/usr/bin/yum -y install gcc patch libgomp glibc-headers glibc-devel dkms autoconf kernel-headers-$(uname -r) kernel-devel-$(uname -r)
#10=>
#10=>printf "==> Refresh all packages\n"
#10=>/usr/bin/yum -y update
#10=>
#10=># Install VirtualBox GuestAdditions
#10=>/root/bin/vbgainstall
#10=>
#10=>printf "==> Preparing host for image creation\n"
#10=>/root/bin/preimgprep
#10=>printf "\n==> END `/bin/date +%H:%M:%S`\n"
#10=>exit 0
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
