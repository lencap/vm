# vmctl
A minimalist Linux [CentOS](https://www.centos.org/) [VirtualBox](https://www.virtualbox.org/) virtual machine managing utility that substitutes [`VBoxManage`](https://www.virtualbox.org/manual/ch08.html) to make the most commonly used commands easily accessible.

# Prerequisites
Tested on Apple macOS v10.14.2.

  * VirtualBox v6.0.0+
  * Create OVA files using https://github.com/lencap/packer-virtualbox

# Usage
```
Simple CentOS VM Manager v2.2.5
vm list                                               List all VMs
vm create <vmName> <imgName>                          Create VM from image
vm del <vmName> [-f]                                  Delete VM. Force option
vm start <vmName> [-gui]                              Start VM. GUI option
vm stop <vmName> [-f]                                 Stop VM. Force option
vm ssh <vmName> [<command>]                           SSH into or optionally run command on VM
vm prov [init]                                        Provision VMs as per vmconf file. Use init to create basic file
vm info <vmName>                                      Dump VM details
vm mod <vmName> <cpus> [<memory>]                     Modify VM CPUs and memory. Memory defaults to 1024
vm ip <vmName> <ip>                                   Set VM IP address
vm netlist                                            List available networks
vm netadd <ip>                                        Create new network
vm netdel <vboxnetX>                                  Delete given network
vm imglist                                            List all available images
vm imgcreate <imgName> <ISOfile|vmName> [-f1] [-f2]   Create new image from vmName or ISO. Force imgName|vmName options
vm imgdel <imgName> [-f]                              Delete image. Force option
vm imgimp <imgFile>                                   Import image. Make available to this program
```

# Development notes
Test run from root of working directory with: `python -m vm`
