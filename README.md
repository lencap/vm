# VM
A small utility to more easily manage [VirtualBox](https://www.virtualbox.org/) [CentOS](https://www.centos.org/) virtual machines from the __macOS__ command line. This `vm` utility is very similar to [`VBoxManage`](https://www.virtualbox.org/manual/ch08.html), but way simpler. It's like having a dedicated Vagrant program for __only__ managing Linux CentOS VMs on macOS.

Also leaving around original Bash versions for posterity. And there is also a __C__ language version in its initial development state, to learn more about VirtualBox C Program bindings. See [c folder](https://github.com/lencap/vm/tree/master/c).

TODO:
* Say more about the `prov` command, which can provision one or many VMs in the Vagrant style.
* Say more about the networking of these OVA and how the utility uses them. All VM have NIC1 set as NAT type for communicating out, and NIC2 as Host-Only to communicate with each other.
* Explain that specially packaged OVAs are required. See `vm imgdawn` for how to create them.

## Prerequisites
Tested on macos v10.15.2 with VirtualBox v6.1.0

## Installation
Either `brew install lencap/tools/vm` or `make install`

## Usage
```
Simple CentOS VM Manager v2.4.4
vm list                               List all VMs
vm create    <vmName> <imgName>       Create VM using imgName
vm del       <vmName> [f]             Delete VM. Force option
vm start     <vmName> [g]             Start VM. GUI option
vm stop      <vmName> [f]             Stop VM. Force option
vm ssh       <vmName> [<command>]     SSH into or optionally run command on VM
vm prov      [init]                   Provision VM(s) in vmconf file; init creates skeleton
vm info      <vmName>                 Dump VM details
vm mod       <vmName> <cpus> [<mem>]  Modify VM CPUs and memory. Memory defaults to 1024
vm ip        <vmName> <ip>            Set VM IP address
vm imglist                            List all available images
vm imgcreate <imgName> <vmName>       Create imgName from existing VM
vm imgdawn                            How-to create brand new OVA image with Hashicorp packer
vm imgimp    <imgFile>                Import image. Make available to this program
vm imgdel    <imgName> [f]            Delete image. Force option
vm netlist                            List available networks
vm netadd    <ip>                     Create new network
vm netdel    <vboxnetX>               Delete given network
```
