# VM
A simple utility to manage [VirtualBox](https://www.virtualbox.org/) Linux VMs from the __macOS__ command line. This `vm` utility is similar to VirtualBox's own [`VBoxManage`](https://www.virtualbox.org/manual/ch08.html) utility, but far simpler. It's a bit like having a dedicated Vagrant for managing __only__ Linux VMs on __macOS__.

There are other bits and pieces in this repo. There's an original Bash versions for posterity. Also a __C__ language version still being developed, to learn more about VirtualBox C bindings. See [c folder](https://github.com/lencap/vm/tree/master/c).

## Todo
- Allow easy switching/update of username and ssh key
- Allow direct file transfer
- Allow multiple vmcopy and vmrun
- Finish C version?
- Document the code a little better
- Say more about the networking of these VMs. Like other similiar utilities, it sets NIC1 as NAT type for communicating out and NIC2 as Host-Only to communicate with each other.
- Explain that specially packaged OVAs are required. See `vm imgpack` for how to create them, etc

## Provissioning VMs
The `vm prov` command provisions VMs automatically based on a simple configuration file. This is the Vagrant similarity.

You can create as sample skeleton config file by running `vm prov c`. This default file will be named `vm.conf`, which the `vm prov` command will read and follow to provision things accordingly.

Alternatively, you can rename the file as you wish, to have multiple of these provisioning config files in your repo, which you can then provision as `vm prov myprov.conf`, and so on.

## Prerequisites
Tested on macOS v10.15.3 with VirtualBox v6.1.2

## Installation
Either `brew install lencap/tools/vm` or `make install`

## Usage
```
Simple Linux VM Manager v2.6.1
vm list                                   List all VMs
vm create    <vmName> <[ovaFile|imgName>  Create VM form given ovaFile, or imgName
vm del       <vmName> [f]                 Delete VM. Force option
vm start     <vmName> [g]                 Start VM. GUI option
vm stop      <vmName> [f]                 Stop VM. Force option
vm ssh       <vmName> [<command>]         SSH into or optionally run command on VM
vm prov      [<vmConf>|c]                 Provision VM(s) in vm.conf, or optional given file; Create skeleton file option
vm info      <vmName>                     Dump VM details
vm mod       <vmName> <cpus> [<mem>]      Modify VM CPUs and memory. Memory defaults to 1024
vm ip        <vmName> <ip>                Set VM IP address
vm imglist                                List all available images
vm imgcreate <imgName> <vmName>           Create imgName from existing VM
vm imgpack                                How-to create brand new OVA image with Hashicorp packer
vm imgimp    <imgFile>                    Import image. Make available to this program
vm imgdel    <imgName> [f]                Delete image. Force option
vm netlist                                List available networks
vm netadd    <ip>                         Create new network
vm netdel    <vboxnetX>                   Delete given network
```
