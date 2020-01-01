// vm.c
// A simpler version of VBoxManage (Python version). Uses OVA files created with pacos.sh

#include "vm.h"

/** @todo
 * Our appologies for the 256+ missing return code checks in this sample file.
 *
 * We strongly recomment users of the VBoxCAPI to check all return codes!
 */

/**
 * Select between active event listener (defined) and passive event listener
 * (undefined). The active event listener case needs much more code, and
 * additionally requires a lot more platform dependent code.
 */
#undef USE_ACTIVE_EVENT_LISTENER


// Global constants and variables initialization
const char prgname[64] = "vm";
const char prgver[16]  = "75";
char cfgfile[64] = "";  
char svcurl[256] = "https://textbelt.com/text";
char svckey[256] = "textbelt";


int main(int argc, char *argv[])
{
  char buf[256];
  char tel[32];
  char msg[4096];
  char data[6000];

  // Print usage if less than 1 or more than 2 arguments
  if (argc < 2 || argc > 3) {
    PrintUsage();
  }

  // If the only one argument is "-y", try creating a skeleton file
  if (argc == 2) {
    if (!strcmp(argv[1], "-y")) {
      CreateSkeletonConfigFile();
      Die(0,"");
    }
    PrintUsage();
  }

  // We'll assume that the 2 arguments are tel and msg
  strcpy(tel, argv[1]);
  strcpy(msg, argv[2]);
  if (strlen(tel) > 10) {
    Die(1, "Error. CellPhoneNum cannot be greater than 10 chars.");
  }
  if (strlen(msg) > 4095) {
    Die(1, "Error. Message cannot be greater than 4096 chars.");
  }
  // Needs more error checking

  ProcessConfigFile();    // Get URL and Key

  // DEBUG
  //printf("URL : [%s]\nKEY : [%s]\nTEL : [%s]\nMSG : [%s]\n", svcurl, svckey, tel, msg);

  // Build data values
  strcpy(data, "key=");     strcat(data, svckey);  strcat(data, "&");
  strcat(data, "phone=");   strcat(data, tel);     strcat(data, "&");
  strcat(data, "message="); strcat(data, msg);
  //printf("DATA: [%s]\n", data);     // DEBUG

  CURLPostData(svcurl, data);

  Die(0, "");
}

// Usage
void PrintUsage(void)
{
  printf("Simple CentOS VM Manager %s\n", prgver);
  printf("%s ls                                  List all VMs\n", prgname);
  printf("%s create <vmName> <imgName>           Create VM from image\n", prgname);
  printf("%s del    <vmName> [-f]                Delete VM. Force option\n", prgname);
  printf("%s start  <vmName> [-gui]              Start VM. GUI option\n", prgname);
  printf("%s stop   <vmName> [-f]                Stop VM. Force option\n", prgname);
  printf("%s ssh    <vmName> [<command>]         SSH into or optionally run command on VM\n", prgname);
  printf("%s prov   [init]                       Provision VMs as per vmconf file; init creates new vmconf file\n", prgname);
  printf("%s info   <vmName>                     Dump VM details\n", prgname);
  printf("%s mod    <vmName> <cpus> [<memory>]   Modify VM CPUs and memory. Memory defaults to 1024\n", prgname);
  printf("%s ip     <vmName> <ip>                Set VM IP address\n", prgname);
  printf("%s netls                               List available networks\n", prgname);
  printf("%s netadd <ip>                         Create new network\n", prgname);
  printf("%s netdel <vboxnetX>                   Delete given network\n", prgname);
  // Should below be in a separate util (pacos)?
  printf("%s imgls                                              List all available images\n", prgname);
  printf("%s imgcreate <imgName> <ISOfile|vmName> [-f1] [-f2]   Create new image from vmName or ISO. Force imgName|vmName options\n", prgname);
  printf("%s imgdel <imgName> [-f]                              Delete image. Force option\n", prgname);
  printf("%s imgimp <imgFile>                                   Import image. Make available to this program", prgname);
  Die(0, "");
}
