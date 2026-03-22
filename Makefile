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
	mkdir -p ${USER_HOME}/.config/polybar
	cp -rf polybar/* ${USER_HOME}/.config/polybar/
	chmod +x ${USER_HOME}/.config/polybar/launch.sh
	chmod +x ${USER_HOME}/.config/polybar/scripts/dwm-tags.sh
	chmod +x ${USER_HOME}/.config/polybar/scripts/wallz/wallz.py
	chmod +x ${USER_HOME}/.config/polybar/scripts/weather/main.py
	chmod +x ${USER_HOME}/.config/polybar/scripts/weather/weather.sh
	mkdir -p ${DESTDIR}${PREFIX}/bin
	install -Dm755 scripts/* ${DESTDIR}${PREFIX}/bin/

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
