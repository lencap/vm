# VirtualBox Tools
Small utilities to better manage [VirtualBox](https://www.virtualbox.org/) [CentOS](https://www.centos.org/) virtual machines from the __macos__ command line.

The `vm` utility is very similar to [`VBoxManage`](https://www.virtualbox.org/manual/ch08.html), but way simpler. It's like having a dedicated Vagrant binary for only managing Linux CentOS VMs.

The `pacos` utility is used to create Linux CentOS images that `vm` can then use. 

## Prerequisites
Tested on macos v10.15.2 with VirtualBox v6.1.0

# Usage
```
Simple CentOS VM Manager v2.2.5
vm ls                                      List all VMs
vm mk <vm-name> <ova-name>                 Create VM from OVA
vm del <vm-name> [-f]                      Delete VM. Force option
vm start <vm-name> [-gui]                  Start VM. GUI option
vm stop <vm-name> [-f]                     Stop VM. Force option
vm ssh <vm-name> [<command>]               SSH into or optionally run command on VM
vm prov [init]                             Provision VMs as per vm.conf file. Use init to create basic file
vm info <vm-name>                          Dump VM details
vm mod <vm-name> <cpus> [<memory>]         Modify VM CPUs and memory. Memory defaults to 1024
vm ip <vm-name> <ip>                       Set VM IP address
vm netls                                   List available networks
vm netadd <ip>                             Create new network
vm netdel <vboxnetX>                       Delete given network
vm ovals                                   List all available OVA images
vm ovaadd <ova-file>                       Import image. Make available to this program
vm ovadel <ova-name> [-f]                  Delete image. Force option
```

# Development Notes
Test run with: `./vm`
