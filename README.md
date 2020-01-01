# VirtualBox Tools
A small utility to better manage [VirtualBox](https://www.virtualbox.org/) [CentOS](https://www.centos.org/) virtual machines from the __macos__ command line. This `vm` utility is very similar to [`VBoxManage`](https://www.virtualbox.org/manual/ch08.html), but way simpler. It's like having a dedicated Vagrant programm for only managing Linux CentOS VMs.

Included here is the original Bash version or posterity.

There's a __C__ language version being developed, to learn more about VirtualBox C Program bindings. See `c` folder.

TODO:
* Explain that specially packages OVAs are required, and what program to use (`pacos`?).
* Ensure we're still using `$HOME/VirtualBox VMs` as `defaultMachineFolder`.

## Prerequisites
Tested on macos v10.15.2 with VirtualBox v6.1.0

## Installation
Either locally with:

`make install`

or with Homebrew:

`brew install lencap/tools/vm`

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
