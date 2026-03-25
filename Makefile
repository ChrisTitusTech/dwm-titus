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
	test -f ${USER_HOME}/.xinitrc || install -Dm644 scripts/.xinitrc ${USER_HOME}/.xinitrc
	# Setup Local Repo Directory
	mkdir -p ${DATA_DIR}
	if [ "$$(realpath .)" != "$$(realpath ${DATA_DIR})" ]; then \
		cp -rf . ${DATA_DIR}/; \
	fi

	# Configs: copy all config subdirs
	for dir in config/*/; do \
		cp -rfL --remove-destination "$$dir" ${CFG_DIR}/$$(basename "$$dir"); \
	done
	# Scripts to PATH
	for f in scripts/*; do \
		case "$$(basename $$f)" in autostart*) continue;; esac; \
		install -Dm755 "$$f" ${DESTDIR}${PREFIX}/bin/$$(basename $$f); \
	done
	
	# Setup User Config if they don't exist
	mkdir -p ${CFG_DIR}/dwm-titus
	test -f ${CFG_DIR}/dwm-titus/hotkeys.toml || install -Dm644 config/hotkeys.toml ${CFG_DIR}/dwm-titus/hotkeys.toml
	test -f ${CFG_DIR}/dwm-titus/themes.toml  || install -Dm644 config/themes.toml  ${CFG_DIR}/dwm-titus/themes.toml
	test -f ${CFG_DIR}/dwm-titus/window-rules.toml || install -Dm644 config/window-rules.toml ${CFG_DIR}/dwm-titus/window-rules.toml
	# Fix ownership + permissions
	find ${DATA_DIR} ${CFG_DIR}/polybar -name '*.sh' -o -name '*.py' | xargs -r chmod +x
	for dir in config/*/; do chown -R ${OWNER}: "${CFG_DIR}/$$(basename $$dir)"; done
	chown -R ${OWNER}: ${DATA_DIR}
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
