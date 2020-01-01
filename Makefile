TARGET  := vm
VERSION := 2.2.6

.PHONY: default release install clean

default:
	ls

release:
	tar czf $(TARGET)-$(VERSION).tar.gz $(TARGET)
	shasum -a 256 $(TARGET)-$(VERSION).tar.gz

install:
	./install.sh $(TARGET)

clean:
	rm -f $(TARGET)-$(VERSION).tar.gz
