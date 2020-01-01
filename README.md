# VirtualBox Tools
A small utility to better manage [VirtualBox](https://www.virtualbox.org/) [CentOS](https://www.centos.org/) virtual machines from the __macos__ command line. This `vm` utility is very similar to [`VBoxManage`](https://www.virtualbox.org/manual/ch08.html), but way simpler. It's like having a dedicated Vagrant program for only managing Linux CentOS VMs.

All leaving around original Bash version for posterity.

There is also a __C__ language version being developed, to learn more about VirtualBox C Program bindings. See [c folder](https://github.com/lencap/vboxtools/tree/master/c).

TODO:
* Say how the utility aims to __not__ rely on VirtualBox Guest Addition, by using a small 1MB secondary disk to temporarily store the VM Name and IP address during during provisioning and to manage it.
* Say more about the `prov` command, which provisions one many VMs in the Vagrant style.
* Say more about the networking of these OVA and how the utility uses them.
* Explain that specially packaged OVAs are required, and what program to use (`pacos`?).
* Ensure we're still using `$HOME/VirtualBox VMs` as `defaultMachineFolder`.

## Prerequisites
Tested on macos v10.15.2 with VirtualBox v6.1.0

## Installation
The prefered install method is to:

`brew install lencap/tools/vm`

but you can also install with:

`make install`

## Usage
```
Simple CentOS VM Manager v2.2.5
vm ls                                 List all VMs
vm create <vmName> <imgName>          Create VM from image
vm del    <vmName> [-f]               Delete VM. Force option
vm start  <vmName> [-gui]             Start VM. GUI option
vm stop   <vmName> [-f]               Stop VM. Force option
vm ssh    <vmName> [<command>]        SSH into or optionally run command on VM
vm prov   [init]                      Provision VMs as per vmconf file. Use init to create basic file
vm info   <vmName>                    Dump VM details
vm mod    <vmName> <cpus> [<memory>]  Modify VM CPUs and memory. Memory defaults to 1024
vm ip     <vmName> <ip>               Set VM IP address
vm netls                              List available networks
vm netadd <ip>                        Create new network
vm netdel <vboxnetX>                  Delete given network
vm imgls                                              List all available images
vm imgcreate <imgName> <ISOfile|vmName> [-f1] [-f2]   Create new image from vmName or ISO. Force imgName|vmName options
vm imgdel <imgName> [-f]                              Delete image. Force option
vm imgimp <imgFile>                                   Import image. Make available to this program
```
