# VM
A simple utility to manage [VirtualBox](https://www.virtualbox.org/) Linux VMs from the command line. This `vm` utility is similar to VirtualBox's own [`VBoxManage`](https://www.virtualbox.org/manual/ch08.html) utility, but far simpler. It manages __only__ Linux VMs, and only on __macOS__.

## Todo
- Allow easy switching/update of username and ssh key
- Allow direct file transfer
- Allow multiple vmcopy and vmrun
- Document the code a little better

## Prerequisites
* Virtual machines created and managed by this utility __must__ be based on OVA files created from repo https://github.com/lencap/osimages. Run `vm imgpack` for how to create them. 
* Tested on macOS v10.15.4 with VirtualBox v6.1.2

## Provisioning VMs
The `vm prov` command provisions VMs automatically based on a simple configuration file.

You can create as sample skeleton config file by running `vm prov c`. This default file will be named `vm.conf`, which the `vm prov` command will read and follow to provision things accordingly.

Alternatively, you can rename the file as you wish, to have multiple of these provisioning config files in your repo, which you can then provision as `vm prov myprov.conf`, and so on.

## Networking Modes
You can set up VMs with in different types of networking modes; either the default __HostOnly__ mode, or the optional __Bridged__ mode.

HostOnly networking, as used in most local VM configurations, sets up NIC1 as NAT for external traffic, and NIC2 as HostOnly for intra-VM traffic.

Bridged networking allows you to use a local LAN, static IP address, and host a service on your host machine. __IMPORTANT__: For this to work 1) you need local host __administrator privileges__, and 2) be allowed to assign STATIC IP ADDRESSES on your local network.

## Installation
Either `brew install lencap/tools/vm` or `make install`

## Usage
```
Simple Linux VM Manager v263
vm list                                   List all VMs
vm create    <vmName> <[ovaFile|imgName>  Create VM form given ovaFile, or imgName
vm del       <vmName> [f]                 Delete VM. Force option
vm start     <vmName> [g]                 Start VM. GUI option
vm stop      <vmName> [f]                 Stop VM. Force option
vm ssh       <vmName> [<command>]         SSH into or optionally run command on VM
vm prov      [<vmConf>|c]                 Provision VM(s) in vm.conf, or optional given file; Create skeleton file option
vm info      <vmName>                     Dump subset of all VM details for common troubleshooting
vm mod       <vmName> <cpus> [<mem>]      Modify VM CPUs and memory. Memory defaults to 1024
vm ip        <vmName> <ip>                Set VM IP address
vm imglist                                List all available images
vm imgcreate <imgName> <vmName>           Create imgName from existing VM
vm imgpack                                How-to create brand new OVA image with Hashicorp packer
vm imgimp    <imgFile>                    Import image. Make available to this program
vm imgdel    <imgName> [f]                Delete image. Force option
vm nettype   <vmName> <ho[bri]>           Set NIC type to Bridge as option; default is always HostOnly
vm netlist                                List available HostOnly networks
vm netadd    <ip>                         Create new HostOnly network
vm netdel    <vboxnetX>                   Delete given HostOnly network
```
