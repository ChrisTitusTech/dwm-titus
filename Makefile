# dwm - dynamic window manager
# See LICENSE file for copyright and license details.

include config.mk

USER_HOME ?= $(shell getent passwd $(or $(SUDO_USER),$(USER)) 2>/dev/null | cut -d: -f6)
OWNER     := $(or $(SUDO_USER),$(USER))
DATA_DIR  := ${USER_HOME}/.local/share/dwm-titus
CFG_DIR   := ${USER_HOME}/.config

SRC = drw.c dwm.c util.c tomlparser.c
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
	# Binary + man page
	install -Dm755 dwm ${DESTDIR}${PREFIX}/bin/dwm
	sed "s/VERSION/${VERSION}/g" dwm.1 | install -Dm644 /dev/stdin ${DESTDIR}${MANPREFIX}/man1/dwm.1
	# Session entry + xinitrc
	test -f /usr/share/xsessions/dwm.desktop || install -Dm644 dwm.desktop /usr/share/xsessions/
	test -f ${USER_HOME}/.xinitrc || install -Dm644 .xinitrc ${USER_HOME}/.xinitrc
	# Repo copy for future rebuilds
	@if [ "$$(cd . && pwd -P)" != "$$(cd ${DATA_DIR} 2>/dev/null && pwd -P)" ]; then \
		mkdir -p ${DATA_DIR}; \
		tar -cf - --exclude='.git' --exclude='*.o' . | tar -xf - -C ${DATA_DIR}/; \
	fi
	# Configs: polybar, rofi, dwm-titus TOML symlinks
	mkdir -p ${CFG_DIR}/polybar
	cp -rf config/polybar/* ${CFG_DIR}/polybar/
	for f in config/rofi/themes/*.rasi; do install -Dm644 "$$f" ${CFG_DIR}/rofi/themes/$$(basename $$f); done
	mkdir -p ${CFG_DIR}/dwm-titus
	ln -sf ${DATA_DIR}/config/hotkeys.toml ${CFG_DIR}/dwm-titus/hotkeys.toml
	ln -sf ${DATA_DIR}/config/themes.toml  ${CFG_DIR}/dwm-titus/themes.toml
	# Scripts to PATH (skip autostart scripts)
	for f in scripts/*; do \
		case "$$(basename $$f)" in autostart*) continue;; esac; \
		install -Dm755 "$$f" ${DESTDIR}${PREFIX}/bin/$$(basename $$f); \
	done
	# Fix ownership + permissions
	find ${DATA_DIR} ${CFG_DIR}/polybar -name '*.sh' -o -name '*.py' | xargs -r chmod +x
	chown -R ${OWNER}: ${DATA_DIR} ${CFG_DIR}/polybar ${CFG_DIR}/rofi ${CFG_DIR}/dwm-titus
	chown ${OWNER}: ${USER_HOME}/.xinitrc 2>/dev/null || true

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/dwm \
		${DESTDIR}${MANPREFIX}/man1/dwm.1 \
		/usr/share/xsessions/dwm.desktop

release: dwm
	mkdir -p release
	cp -f dwm dwm.desktop .xinitrc release/
	cp -rf config scripts release/
	tar -czf release/Omitus-${VERSION}.tar.gz -C release dwm dwm.desktop .xinitrc config scripts

.PHONY: all clean install uninstall release
