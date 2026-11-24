SHELL := /bin/sh
SUDO_ASKPASS ?= /usr/bin/unified-askpass

.PHONY: package install clean

package:
	makepkg --cleanbuild --clean --force

install: package
	SUDO_ASKPASS="$(SUDO_ASKPASS)" sudo -A pacman -U --needed --noconfirm \
		./i586-elf32-minix-binutils-*.pkg.tar.*

clean:
	rm -rf pkg src
