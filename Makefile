# dwm - dynamic window manager
# See LICENSE file for copyright and license details.

.SILENT:

include config.mk

USER_HOME ?= $(shell getent passwd $(or $(SUDO_USER),$(USER)) 2>/dev/null | cut -d: -f6)
OWNER     := $(or $(SUDO_USER),$(USER))
DATA_DIR  := ${USER_HOME}/.local/share/dwm-dohc
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
	@echo ""
	@echo "==> Installing dwm binary and man page..."
	install -Dm755 dwm ${DESTDIR}${PREFIX}/bin/dwm
	sed "s/VERSION/${VERSION}/g" dwm.1 | install -Dm644 /dev/stdin ${DESTDIR}${MANPREFIX}/man1/dwm.1
	@echo "==> Setting up X session entries..."
	if [ ! -d /usr/share/xsessions ]; then \
		mkdir -p /usr/share/xsessions; \
	fi
	install -Dm644 dwm.desktop /usr/share/xsessions/
	install -Dm644 scripts/.xinitrc ${USER_HOME}/.xinitrc
	@echo "==> Syncing local repo to data dir..."
	mkdir -p ${DATA_DIR}
	if [ "$$(realpath .)" != "$$(realpath ${DATA_DIR})" ]; then \
		cp -rf . ${DATA_DIR}/; \
	fi
	@echo "==> Installing config directories..."
	for dir in config/*/; do \
		dst=${CFG_DIR}/$$(basename "$$dir"); \
		[ -L "$$dst" ] && rm -f "$$dst"; \
		cp -rfL --remove-destination "$$dir" "$$dst"; \
	done
	@echo "==> Installing scripts to PATH..."
	for f in scripts/*; do \
		case "$$(basename $$f)" in autostart*) continue;; esac; \
		install -Dm755 "$$f" ${DESTDIR}${PREFIX}/bin/$$(basename $$f); \
	done
	@echo "==> Seeding user config (skipping existing files)..."
	mkdir -p ${CFG_DIR}/dwm-dohc
	test -f ${CFG_DIR}/dwm-dohc/hotkeys.toml || install -Dm644 config/hotkeys.toml ${CFG_DIR}/dwm-dohc/hotkeys.toml
	test -f ${CFG_DIR}/dwm-dohc/themes.toml  || install -Dm644 config/themes.toml  ${CFG_DIR}/dwm-dohc/themes.toml
	test -f ${CFG_DIR}/dwm-dohc/window-rules.toml || install -Dm644 config/window-rules.toml ${CFG_DIR}/dwm-dohc/window-rules.toml
	@echo "==> Installing font aliases for cross-distro naming..."
	mkdir -p ${CFG_DIR}/fontconfig/conf.d
	if [ ! -f ${CFG_DIR}/fontconfig/conf.d/50-meslolgs-nerd-font-aliases.conf ]; then \
		{ \
			printf '%s\n' '<?xml version="1.0"?>'; \
			printf '%s\n' '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">'; \
			printf '%s\n' '<fontconfig>'; \
			printf '%s\n' '  <alias>'; \
			printf '%s\n' '    <family>MesloLGS NF</family>'; \
			printf '%s\n' '    <prefer>'; \
			printf '%s\n' '      <family>MesloLGS Nerd Font</family>'; \
			printf '%s\n' '      <family>MesloLGS Nerd Font Mono</family>'; \
			printf '%s\n' '    </prefer>'; \
			printf '%s\n' '  </alias>'; \
			printf '%s\n' '  <alias>'; \
			printf '%s\n' '    <family>MesloLGS Nerd Font</family>'; \
			printf '%s\n' '    <prefer>'; \
			printf '%s\n' '      <family>MesloLGS NF</family>'; \
			printf '%s\n' '      <family>MesloLGS Nerd Font Mono</family>'; \
			printf '%s\n' '    </prefer>'; \
			printf '%s\n' '  </alias>'; \
			printf '%s\n' '  <alias>'; \
			printf '%s\n' '    <family>MesloLGS Nerd Font Mono</family>'; \
			printf '%s\n' '    <prefer>'; \
			printf '%s\n' '      <family>MesloLGS NF</family>'; \
			printf '%s\n' '      <family>MesloLGS Nerd Font</family>'; \
			printf '%s\n' '    </prefer>'; \
			printf '%s\n' '  </alias>'; \
			printf '%s\n' '</fontconfig>'; \
		} > ${CFG_DIR}/fontconfig/conf.d/50-meslolgs-nerd-font-aliases.conf; \
	else \
		echo "  Preserving existing Meslo font alias file."; \
	fi
	fc-cache -f >/dev/null 2>&1 || true
	@echo "==> Fixing ownership and permissions..."
	find ${DATA_DIR} -name '*.sh' -o -name '*.py' | xargs -r chmod +x
	for dir in config/*/; do \
		b=$$(basename $$dir); \
		find "${CFG_DIR}/$$b" -name '*.sh' -o -name '*.py' 2>/dev/null | xargs -r chmod +x; \
		chown -R ${OWNER}: "${CFG_DIR}/$$b"; \
	done
	chown -R ${OWNER}: ${CFG_DIR}/fontconfig 2>/dev/null || true
	chown -R ${OWNER}: ${DATA_DIR} && chown ${OWNER}: ${USER_HOME}/.xinitrc 2>/dev/null || true
	@echo ""
	@echo "  dwm installed successfully."
	@echo "  Log out and select 'dwm', or start with: startx"
	@echo ""

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
