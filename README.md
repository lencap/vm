# VM
A small [VirtualBox](https://www.virtualbox.org/) command line front-end utility to manage Linux VMs on __macOS__.

It's similar to VirtualBox's own [`VBoxManage`](https://www.virtualbox.org/manual/ch08.html), but limited to only those functions I find myself needing 99% of the time when I'm working with Linux VMs. In addition, it allows the automated provisioning of one or multiple VMs, like a poor-man and much more destitute Vagrant 😀

Things to keep in mind:

- Again, __only__ Linux VMs, and only on __macOS__
- Still a work in progress, so expect to resolve some issues by manually hopping back on the VirtualBox GUI
- Constructive comments and suggestions are always welcome

## Prerequisites
* Virtual machines created and managed by this utility __must__ be based on OVA files created by using repo https://github.com/lencap/osimages. Run `vm imgpack` for some information on how to do that. 
* Tested on macOS v10.15.4 with VirtualBox v6.1.6

## Provisioning VMs
The `vm prov` command provisions VMs automatically based on a simple configuration file.

You can create a sample skeleton config file by running `vm prov c`. By default, this file will be named `vm.conf`, which the `vm prov` command will read and follow to provision things accordingly. But you can name the file whatever you wish, so you can then have multiple of these provisioning config files in your repo, which you can then provision as `vm prov myprov1.conf`, and so on.

## Networking Modes
Two networking modes are supported: The default __HostOnly__ mode, or the optional and experimental __Bridged__ mode.

HostOnly networking, as used in most local VM configurations, sets up NIC1 as NAT for external traffic, and NIC2 as HostOnly for intra-VM traffic. This is usually the most popular mode, as it allows one to set up a mini network of VMs for whatever work one is doing.  

Bridged networking allows one use the local LAN, with a static IP address for each VM, all running from your own host machine. This option allows others on the same LAN to access services running on your VMs. __IMPORTANT__: For this to work A) you need local host __administrator privileges__, and B) you need to be allowed to assign STATIC IP ADDRESSES on your local network. This mode is not as popular, but can be useful in some unique settings.

## Installation Options
- `brew install lencap/tools/vm` to use latest Homebrew release
- `make install` to place `vm` under `/usr/local/bin/`

## Usage
```
$vm
Simple Linux VM Manager v265
vm list                                   List all VMs
vm create    <vmName> <[ovaFile|imgName>  Create VM form given ovaFile, or imgName
vm del       <vmName> [f]                 Delete VM. Force option
vm start     <vmName> [g]                 Start VM. GUI option
vm stop      <vmName> [f]                 Stop VM. Force option
vm ssh       <vmName> [<command>]         SSH into or optionally run command on VM
vm prov      [<vmConf>|c]                 Provision VMs in given vmConf file; Create skeleton file option
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
