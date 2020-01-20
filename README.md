# VM
A small utility to more easily manage [VirtualBox](https://www.virtualbox.org/) [CentOS](https://www.centos.org/) virtual machines from the __macOS__ command line. This `vm` utility is very similar to [`VBoxManage`](https://www.virtualbox.org/manual/ch08.html), but way simpler. It's like having a dedicated Vagrant program for __only__ managing Linux CentOS VMs on macOS.

Also leaving around original Bash versions for posterity. And there is also a __C__ language version in its initial development stages, to learn more about VirtualBox C Program bindings. See [c folder](https://github.com/lencap/vm/tree/master/c).

## Todo
- Allow easy switching of user and ssh key?
- Finish C version?
- Document the code a bit more?
- Say more about the `prov` command, which can provision one or multiple VMs in a style similar to Vagrant.
- Say more about the networking of these VMs. Like other similiar utilities, it sets NIC1 as NAT type for communicating out and NIC2 as Host-Only to communicate with each other.
- Explain that specially packaged OVAs are required. See `vm imgpack` for how to create them, etc

## Prerequisites
Tested on macos v10.15.2 with VirtualBox v6.1.0

## Installation
Either `brew install lencap/tools/vm` or `make install`

## Usage
```
Simple CentOS VM Manager v2.5.0
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
vm imgpack                            How-to create brand new OVA image with Hashicorp packer
vm imgimp    <imgFile>                Import image. Make available to this program
vm imgdel    <imgName> [f]            Delete image. Force option
vm netlist                            List available networks
vm netadd    <ip>                     Create new network
vm netdel    <vboxnetX>               Delete given network
```
