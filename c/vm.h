// vm.h

#include "VBoxCAPIGlue.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#ifndef WIN32
# include <signal.h>
# include <unistd.h>
# include <sys/poll.h>
#endif
#ifdef IPRT_INCLUDED_cdefs_h
# error "not supposed to involve any IPRT or VBox headers here."
#endif

#include <curl/curl.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include "ini.h"

// Defines
// #define  MENUTEXT          (BLACK + (LIGHTGRAY <<4))
// #define  K_ESC             (0x011B)
// #define  lengthof(x)       ((sizeof(x))/(sizeof(x[0]))) 

// Global constants and variables declaration
extern const char prgname[64];
extern const char prgver[16];
extern char cfgfile[64]; 
extern char svcurl[256];
extern char svckey[256];

// Types
// typedef unsigned char       BYTE;     // unsigned 8-bit number
// typedef unsigned int        WORD;     // unsigned 16-bit number
// typedef unsigned long       DWORD;    // unsigned 32-bit number
// typedef enum {FALSE, TRUE}  BOOL;

// Functions prototypes
void PrintUsage(void);
void Die(int code, char * msg);
void ProcessConfigFile(void);
void CreateSkeletonConfigFile(void);
void CURLPostData(char * url, char * data);