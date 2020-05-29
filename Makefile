TARGET  := vm
VERSION := 268

.PHONY: default release install clean

default:
	ls

release:
	tar czf $(TARGET)-$(VERSION).tar.gz $(TARGET)
	shasum -a 256 $(TARGET)-$(VERSION).tar.gz

install:
	install $(TARGET) /usr/local/bin/$(TARGET)

clean:
	rm -f $(TARGET)-*.tar.gz
