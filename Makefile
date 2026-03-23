# dwm - dynamic window manager
# See LICENSE file for copyright and license details.

include config.mk

# Detect home directory of the installing user (handles non-standard home paths)
USER_HOME ?= $(shell getent passwd $(or $(SUDO_USER),$(USER)) 2>/dev/null | cut -d: -f6)

SRC = drw.c dwm.c util.c
OBJ = ${SRC:.c=.o}

all: dwm

.c.o:
	${CC} -c ${CFLAGS} $<

${OBJ}: config.h config.mk

config.h:
	cp config.def.h $@

dwm: ${OBJ}
	${CC} -o $@ ${OBJ} ${LDFLAGS}

clean:
	rm -f dwm ${OBJ} *.orig *.rej

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	install -Dm755 dwm ${DESTDIR}${PREFIX}/bin/dwm
	mkdir -p ${DESTDIR}${MANPREFIX}/man1
	sed "s/VERSION/${VERSION}/g" < dwm.1 > ${DESTDIR}${MANPREFIX}/man1/dwm.1
	chmod 644 ${DESTDIR}${MANPREFIX}/man1/dwm.1
	mkdir -p /usr/share/xsessions/
	test -f /usr/share/xsessions/dwm.desktop || install -Dm644 dwm.desktop /usr/share/xsessions/
	test -f ${USER_HOME}/.xinitrc || install -Dm644 .xinitrc ${USER_HOME}/.xinitrc
	# Copy repo to ~/.local/share/dwm-titus/ for future rebuilds (skip if already there)
	@if [ "$$(cd . && pwd -P)" != "$$(cd ${USER_HOME}/.local/share/dwm-titus 2>/dev/null && pwd -P)" ]; then \
		mkdir -p ${USER_HOME}/.local/share/dwm-titus; \
		tar -cf - --exclude='.git' --exclude='*.o' . | tar -xf - -C ${USER_HOME}/.local/share/dwm-titus/; \
	fi
	# Install polybar configs
	mkdir -p ${USER_HOME}/.config/polybar
	cp -rf polybar/* ${USER_HOME}/.config/polybar/
	find ${USER_HOME}/.config/polybar -name '*.sh' -exec chmod +x {} +
	find ${USER_HOME}/.config/polybar -name '*.py' -exec chmod +x {} +
	# Install rofi configs
	mkdir -p ${USER_HOME}/.config/rofi/themes
	for f in config/rofi/themes/*.rasi; do \
		install -m644 "$$f" ${USER_HOME}/.config/rofi/themes/$$(basename $$f); \
	done
	# Install all scripts to PATH (except autostart scripts which stay in the repo copy)
	for f in scripts/*; do \
		case "$$(basename $$f)" in autostart*) continue;; esac; \
		install -Dm755 "$$f" ${DESTDIR}${PREFIX}/bin/$$(basename $$f); \
	done
	# Set permissions on repo copy
	find ${USER_HOME}/.local/share/dwm-titus -name '*.sh' -exec chmod +x {} +
	find ${USER_HOME}/.local/share/dwm-titus -name '*.py' -exec chmod +x {} +
	chown -R $(or ${SUDO_USER},${USER}): ${USER_HOME}/.local/share/dwm-titus ${USER_HOME}/.config/polybar ${USER_HOME}/.config/rofi

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/dwm \
		${DESTDIR}${MANPREFIX}/man1/dwm.1 \
		${DESTDIR}/usr/share/xsessions/dwm.desktop

release: dwm
	mkdir -p release
	cp -f dwm release/
	cp -f dwm.desktop release/
	cp -f .xinitrc release/
	cp -rf polybar release/
	cp -rf scripts release/
	tar -czf release/Omitus-${VERSION}.tar.gz -C release dwm dwm.desktop .xinitrc polybar scripts

.PHONY: all clean install uninstall release
