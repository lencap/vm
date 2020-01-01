TARGET        := vm
VERSION       := 75
PATH_SDK      = ./sdk
CAPI_INC      = -I$(PATH_SDK)/bindings/c/include
ifeq ($(BUILD_PLATFORM),win)
PLATFORM_INC  = -I$(PATH_SDK)/bindings/mscom/include
PLATFORM_LIB  = $(PATH_SDK)/bindings/mscom/lib
else
PLATFORM_INC  = -I$(PATH_SDK)/bindings/xpcom/include
PLATFORM_LIB  = $(PATH_SDK)/bindings/xpcom/lib
endif
GLUE_DIR      = $(PATH_SDK)/bindings/c/glue
GLUE_INC      = -I$(GLUE_DIR)
CC            = gcc
CFLAGS        = -g -Wall
LDFLAGS       = -ldl -lpthread
#LDFLAGS       = -ldl -lpthread -lcurl
.PHONY: default all release clean install
default:
        ls -l $(PATH_SDK)
all: $(TARGET) 
clean:
        rm -f $(TARGET) $(TARGET).o VBoxCAPIGlue.o VirtualBox_i.o
$(TARGET): $(TARGET).o VBoxCAPIGlue.o VirtualBox_i.o
        $(CC) -o $@ $^ $(LDFLAGS)
$(TARGET).o: $(TARGET).c
        $(CC) $(CFLAGS) $(CAPI_INC) $(PLATFORM_INC) $(GLUE_INC) -o $@ -c $<
VBoxCAPIGlue.o: $(GLUE_DIR)/VBoxCAPIGlue.c
        $(CC) $(CFLAGS) $(CAPI_INC) $(PLATFORM_INC) $(GLUE_INC) -o $@ -c $<
VirtualBox_i.o: $(PLATFORM_LIB)/VirtualBox_i.c
        $(CC) $(CFLAGS) $(CAPI_INC) $(PLATFORM_INC) $(GLUE_INC) -o $@ -c $<
release:
	tar czf $(TARGET)-$(VERSION).tar.gz $(TARGET)
	shasum -a 256 $(TARGET)-$(VERSION).tar.gz
install:
	./install.sh $(TARGET)
