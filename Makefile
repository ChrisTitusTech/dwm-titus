# dwm - dynamic window manager
# See LICENSE file for copyright and license details.

.SILENT:

include config.mk

USER_HOME ?= $(shell getent passwd $(or $(SUDO_USER),$(USER)) 2>/dev/null | cut -d: -f6)
OWNER     := $(or $(SUDO_USER),$(USER))
XDG_CONFIG_HOME ?= ${USER_HOME}/.config
XDG_DATA_HOME ?= ${USER_HOME}/.local/share
DATA_DIR  := ${XDG_DATA_HOME}/dwm-titus
CFG_DIR   := ${XDG_CONFIG_HOME}

SRC = drw.c dwm.c util.c tomlparser.c
OBJ = ${SRC:.c=.o}

all: dwm

.c.o:
	${CC} ${CPPFLAGS} ${CFLAGS} -c $<

${OBJ}: config.h config.mk

config.h:
	cp config.def.h $@

dwm: ${OBJ}
	${CC} -o $@ ${OBJ} ${LDFLAGS} ${LDLIBS}

clean:
	rm -f dwm ${OBJ} *.orig *.rej

install: install-system
	if [ -z "${DESTDIR}" ]; then \
		$(MAKE) install-user; \
	else \
		echo "==> DESTDIR set; skipping user configuration."; \
	fi

install-system: all
	@echo ""
	@echo "==> Installing system files..."
	install -Dm755 dwm ${DESTDIR}${PREFIX}/bin/dwm
	sed "s/VERSION/${VERSION}/g" dwm.1 | install -Dm644 /dev/stdin ${DESTDIR}${MANPREFIX}/man1/dwm.1
	install -Dm644 dwm.desktop ${DESTDIR}${XSESSIONSDIR}/dwm.desktop
	@echo "==> Installing scripts to PATH..."
	for f in scripts/*; do \
		case "$$(basename "$$f")" in autostart*) continue;; esac; \
		install -Dm755 "$$f" ${DESTDIR}${PREFIX}/bin/$$(basename "$$f"); \
	done

install-user:
	@test -n "${USER_HOME}" || { echo "USER_HOME could not be determined." >&2; exit 1; }
	@echo "==> Installing user files for ${OWNER}..."
	if [ ! -e "${USER_HOME}/.xinitrc" ]; then \
		install -Dm644 scripts/.xinitrc "${USER_HOME}/.xinitrc"; \
	else \
		echo "  Preserving existing ${USER_HOME}/.xinitrc"; \
	fi
	@echo "==> Syncing local repo to data dir..."
	mkdir -p ${DATA_DIR}
	if [ "$$(realpath .)" != "$$(realpath ${DATA_DIR})" ]; then \
		rm -rf "${DATA_DIR}/config" "${DATA_DIR}/scripts"; \
		cp -a config scripts "${DATA_DIR}/"; \
	fi
	@echo "==> Seeding application config without overwriting user files..."
	mkdir -p ${CFG_DIR}
	for dir in config/*/; do \
		dst=${CFG_DIR}/$$(basename "$$dir"); \
		if [ -L "$$dst" ]; then \
			echo "  Preserving symlink $$dst"; \
			continue; \
		fi; \
		mkdir -p "$$dst"; \
		cp -aL -n "$$dir"/. "$$dst"/; \
	done
	@echo "==> Seeding user config (skipping existing files)..."
	mkdir -p ${CFG_DIR}/dwm-titus
	test -f ${CFG_DIR}/dwm-titus/hotkeys.toml || install -Dm644 config/hotkeys.toml ${CFG_DIR}/dwm-titus/hotkeys.toml
	test -f ${CFG_DIR}/dwm-titus/themes.toml  || install -Dm644 config/themes.toml  ${CFG_DIR}/dwm-titus/themes.toml
	test -f ${CFG_DIR}/dwm-titus/window-rules.toml || install -Dm644 config/window-rules.toml ${CFG_DIR}/dwm-titus/window-rules.toml
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
	find ${DATA_DIR} \( -name '*.sh' -o -name '*.py' \) -print0 | xargs -0 -r chmod +x
	for dir in config/*/; do \
		b=$$(basename $$dir); \
		if [ ! -L "${CFG_DIR}/$$b" ]; then \
			find "${CFG_DIR}/$$b" \( -name '*.sh' -o -name '*.py' \) -print0 2>/dev/null | xargs -0 -r chmod +x; \
			chown -R ${OWNER}: "${CFG_DIR}/$$b"; \
		fi; \
	done
	chown -R ${OWNER}: ${CFG_DIR}/fontconfig 2>/dev/null || true
	chown -R ${OWNER}: ${DATA_DIR}
	if [ -e "${USER_HOME}/.xinitrc" ]; then chown ${OWNER}: "${USER_HOME}/.xinitrc"; fi
	@echo ""
	@echo "  dwm installed successfully."
	@echo "  Log out and select 'dwm', or start with: startx"
	@echo ""

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/dwm \
		${DESTDIR}${MANPREFIX}/man1/dwm.1 \
		${DESTDIR}${XSESSIONSDIR}/dwm.desktop
	for f in scripts/*; do \
		case "$$(basename "$$f")" in autostart*) continue;; esac; \
		rm -f ${DESTDIR}${PREFIX}/bin/$$(basename "$$f"); \
	done

release: dwm
	mkdir -p release
	cp -f dwm dwm.desktop scripts/.xinitrc release/
	cp -rf config scripts release/
	tar -czf release/Omitus-${VERSION}.tar.gz -C release dwm dwm.desktop .xinitrc config scripts

.PHONY: all clean install install-system install-user uninstall release
