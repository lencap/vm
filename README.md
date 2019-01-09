## vm
A minimalist VirtualBox machine manager. 

## Usage

### Usage shell output
<pre><code>
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
</code></pre>

## Development notes
To test run the program as soon as you clone the code or as you make changes you can use `python -m vm` from the root of the working directory.
