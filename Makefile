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
DATADIR   ?= ${PREFIX}/share
SYSTEMDUSERDIR ?= ${PREFIX}/lib/systemd/user
VICINAE_APPDIR ?= ${PREFIX}/lib/dwm-titus/vicinae
VICINAE_SOURCE_DIR ?=
CAPITAINE_DARK_THEME = Capitaine-Cursors
CAPITAINE_LIGHT_THEME = Capitaine-Cursors-White
CAPITAINE_LICENSE_DIR = ${DATADIR}/licenses/dwm-titus/capitaine-cursors

SRC = drw.c dwm.c util.c tomlparser.c
OBJ = ${SRC:.c=.o}

INSTALL_COMMANDS = \
	scripts/active-audio \
	scripts/check-deps.sh \
	scripts/disable-powersaving \
	scripts/dwm-controlcenter \
	scripts/dwm-default-apps \
	scripts/dwm-diagnostics \
	scripts/dwm-display-profile \
	scripts/dwm-keybinds \
	scripts/dwm-polkit \
	scripts/dwm-packages.sh \
	scripts/dwm-screenshot \
	scripts/dwm-terminal \
	scripts/dwm-utils.sh \
	scripts/nvidia-gpu \
	scripts/nvidia-suspend-test.sh \
	scripts/nvidia-temp \
	scripts/pkg-scan.py \
	scripts/power-management.sh \
	scripts/protonrestart \
	scripts/theme-apply.sh \
	scripts/webapp-create \
	scripts/webapp-launch \
	scripts/xdg-enable-autostart.sh \
	scripts/xscreensaver-setup.sh
INSTALL_COMMAND_NAMES = $(notdir ${INSTALL_COMMANDS})

RELEASE_NAME = dwm-titus-${VERSION}
RELEASE_ARCHIVE = release/${RELEASE_NAME}.tar.gz
SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct 2>/dev/null || printf '0')

all: dwm

.c.o:
	${CC} ${CPPFLAGS} ${CFLAGS} -c $<

${OBJ}: config.h config.mk

config.h:
	cp config.def.h $@

dwm: check-build-deps ${OBJ}
	${CC} -o $@ ${OBJ} ${LDFLAGS} ${LDLIBS}

check-build-deps:
	@command -v "${PKG_CONFIG}" >/dev/null 2>&1 || { \
		echo "Missing required command: ${PKG_CONFIG}" >&2; \
		exit 1; \
	}
	@missing="$$(for module in ${PKG_MODULES}; do \
		"${PKG_CONFIG}" --exists "$$module" || printf '%s ' "$$module"; \
	done)"; \
	if [ -n "$$missing" ]; then \
		echo "Missing required pkg-config modules: $$missing" >&2; \
		echo "Run ./install.sh or install the matching development packages." >&2; \
		exit 1; \
	fi

clean:
	rm -f dwm ${OBJ} *.orig *.rej

native:
	$(MAKE) clean
	$(MAKE) OPTIMISATIONS="${NATIVE_OPTIMISATIONS}" all

install: install-system
	if [ -z "${DESTDIR}" ]; then \
		$(MAKE) install-user; \
	else \
		echo "==> DESTDIR set; skipping user configuration."; \
	fi

install-system: all install-vicinae install-cursors
	@echo ""
	@echo "==> Installing system files..."
	install -Dm755 dwm ${DESTDIR}${PREFIX}/bin/dwm
	sed "s/VERSION/${VERSION}/g" dwm.1 | install -Dm644 /dev/stdin ${DESTDIR}${MANPREFIX}/man1/dwm.1
	sed "s|@PREFIX@|${PREFIX}|g" dwm.desktop | \
		install -Dm644 /dev/stdin ${DESTDIR}${XSESSIONSDIR}/dwm.desktop
	@echo "==> Installing scripts to PATH..."
	for f in ${INSTALL_COMMANDS}; do \
		install -Dm755 "$$f" ${DESTDIR}${PREFIX}/bin/$$(basename "$$f"); \
	done

install-cursors:
	@echo "==> Installing Capitaine cursor themes..."
	rm -rf \
		"${DESTDIR}${DATADIR}/icons/${CAPITAINE_DARK_THEME}" \
		"${DESTDIR}${DATADIR}/icons/${CAPITAINE_LIGHT_THEME}"
	mkdir -p "${DESTDIR}${DATADIR}/icons"
	cp -a "assets/cursors/${CAPITAINE_DARK_THEME}" \
		"${DESTDIR}${DATADIR}/icons/"
	cp -a "assets/cursors/${CAPITAINE_LIGHT_THEME}" \
		"${DESTDIR}${DATADIR}/icons/"
	install -Dm644 assets/cursors/COPYING \
		"${DESTDIR}${CAPITAINE_LICENSE_DIR}/COPYING"

install-vicinae:
	@if [ -z "${VICINAE_SOURCE_DIR}" ]; then \
		echo "Vicinae source not provided; skipping Vicinae."; \
	elif [ "$$(uname -m)" != x86_64 ]; then \
		echo "Vicinae AppImage is x86_64-only; skipping it on $$(uname -m)." >&2; \
	elif [ ! -x "${VICINAE_SOURCE_DIR}/AppRun" ] || \
		[ ! -x "${VICINAE_SOURCE_DIR}/usr/bin/vicinae" ]; then \
		echo "Vicinae source is not a complete AppImage extraction: ${VICINAE_SOURCE_DIR}" >&2; \
		exit 1; \
	else \
		echo "==> Installing Vicinae..."; \
		rm -rf "${DESTDIR}${VICINAE_APPDIR}"; \
		mkdir -p "${DESTDIR}${VICINAE_APPDIR}"; \
		cp -a "${VICINAE_SOURCE_DIR}/." "${DESTDIR}${VICINAE_APPDIR}/"; \
		sed "s|@VICINAE_APPDIR@|${VICINAE_APPDIR}|g" packaging/vicinae | \
			install -Dm755 /dev/stdin "${DESTDIR}${PREFIX}/bin/vicinae"; \
		sed "s|@PREFIX@|${PREFIX}|g" packaging/vicinae.service | \
			install -Dm644 /dev/stdin \
				"${DESTDIR}${SYSTEMDUSERDIR}/vicinae.service"; \
		install -Dm644 "${VICINAE_SOURCE_DIR}/usr/share/applications/vicinae.desktop" \
			"${DESTDIR}${DATADIR}/applications/vicinae.desktop"; \
		install -Dm644 "${VICINAE_SOURCE_DIR}/usr/share/applications/vicinae-url-handler.desktop" \
			"${DESTDIR}${DATADIR}/applications/vicinae-url-handler.desktop"; \
		install -Dm644 \
			"${VICINAE_SOURCE_DIR}/usr/share/icons/hicolor/512x512/apps/vicinae.png" \
			"${DESTDIR}${DATADIR}/icons/hicolor/512x512/apps/vicinae.png"; \
	fi

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
		${DESTDIR}${PREFIX}/bin/vicinae \
		${DESTDIR}${MANPREFIX}/man1/dwm.1 \
		${DESTDIR}${XSESSIONSDIR}/dwm.desktop \
		${DESTDIR}${SYSTEMDUSERDIR}/vicinae.service \
		${DESTDIR}${DATADIR}/applications/vicinae.desktop \
		${DESTDIR}${DATADIR}/applications/vicinae-url-handler.desktop \
		${DESTDIR}${DATADIR}/icons/hicolor/512x512/apps/vicinae.png
	rm -rf ${DESTDIR}${VICINAE_APPDIR}
	rm -rf \
		"${DESTDIR}${DATADIR}/icons/${CAPITAINE_DARK_THEME}" \
		"${DESTDIR}${DATADIR}/icons/${CAPITAINE_LIGHT_THEME}" \
		"${DESTDIR}${CAPITAINE_LICENSE_DIR}"
	for name in ${INSTALL_COMMAND_NAMES}; do \
		rm -f ${DESTDIR}${PREFIX}/bin/$$name; \
	done

release: dwm
	@work="$$(mktemp -d)"; \
	trap 'rm -rf "$$work"' EXIT; \
	root="$$work/${RELEASE_NAME}"; \
	mkdir -p "$$root" release; \
	install -Dm755 dwm "$$root/dwm"; \
	install -Dm644 scripts/.xinitrc "$$root/.xinitrc"; \
	sed "s|@PREFIX@|${PREFIX}|g" dwm.desktop > "$$root/dwm.desktop"; \
	cp -a assets config scripts "$$root/"; \
	find "$$root" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +; \
	tar --sort=name \
		--mtime="@${SOURCE_DATE_EPOCH}" \
		--owner=0 --group=0 --numeric-owner \
		--format=ustar \
		-C "$$work" -cf - "${RELEASE_NAME}" | gzip -n > "${RELEASE_ARCHIVE}"; \
	echo "==> Created ${RELEASE_ARCHIVE}"

check-shell:
	shellcheck install.sh install-arm.sh scripts/dwm-default-apps scripts/dwm-diagnostics scripts/dwm-display-profile scripts/dwm-terminal scripts/*.sh tests/*.sh debug/*.sh \
		config/polybar/*.sh config/polybar/scripts/*.sh \
		config/polybar/scripts/weather/*.sh config/rofi/*.sh

check-format:
	shfmt -d install.sh install-arm.sh scripts/dwm-default-apps scripts/dwm-diagnostics scripts/dwm-display-profile scripts/dwm-terminal scripts/*.sh tests/*.sh

check-session-guards:
	tests/test-autostart.sh

check-build-config:
	tests/test-configure-build.sh

check-terminal:
	tests/test-dwm-terminal.sh

check-default-apps:
	tests/test-dwm-default-apps.sh

check-display-profile:
	tests/test-dwm-display-profile.sh

check-diagnostics:
	tests/test-dwm-diagnostics.sh

check-polybar-capabilities:
	tests/test-polybar-capabilities.sh

check-install: all
	@set -eu; \
	stage="$$(mktemp -d)"; \
	trap 'rm -rf "$$stage"' EXIT; \
	$(MAKE) install-system \
		DESTDIR="$$stage" PREFIX=/usr XSESSIONSDIR=/usr/share/xsessions; \
	test -x "$$stage/usr/bin/dwm"; \
	test -x "$$stage/usr/bin/dwm-controlcenter"; \
	test -f "$$stage/usr/share/man/man1/dwm.1"; \
	test -f "$$stage/usr/share/xsessions/dwm.desktop"; \
	grep -Fqx 'Exec=/usr/bin/dwm' \
		"$$stage/usr/share/xsessions/dwm.desktop"; \
	echo "==> Staged install validated."

check-install-manifest: all
	@set -eu; \
	stage="$$(mktemp -d)"; \
	before="$$(mktemp)"; \
	after="$$(mktemp)"; \
	actual="$$(mktemp)"; \
	expected="$$(mktemp)"; \
	trap 'rm -rf "$$stage" "$$before" "$$after" "$$actual" "$$expected"' EXIT; \
	install -Dm644 /dev/null "$$stage/pre-existing"; \
	find "$$stage" \( -type f -o -type l \) -printf '%P\n' | sort > "$$before"; \
	$(MAKE) install-system \
		DESTDIR="$$stage" PREFIX=/usr XSESSIONSDIR=/usr/share/xsessions \
		VICINAE_SOURCE_DIR=; \
	{ \
		printf '%s\n' \
			pre-existing \
			usr/bin/dwm \
			usr/share/man/man1/dwm.1 \
			usr/share/xsessions/dwm.desktop; \
		for name in ${INSTALL_COMMAND_NAMES}; do \
			printf 'usr/bin/%s\n' "$$name"; \
		done; \
		find "assets/cursors/${CAPITAINE_DARK_THEME}" \
			\( -type f -o -type l \) \
			-printf 'usr/share/icons/${CAPITAINE_DARK_THEME}/%P\n'; \
		find "assets/cursors/${CAPITAINE_LIGHT_THEME}" \
			\( -type f -o -type l \) \
			-printf 'usr/share/icons/${CAPITAINE_LIGHT_THEME}/%P\n'; \
		printf '%s\n' \
			usr/share/licenses/dwm-titus/capitaine-cursors/COPYING; \
	} | sort > "$$expected"; \
	find "$$stage" \( -type f -o -type l \) -printf '%P\n' | sort > "$$actual"; \
	cmp "$$expected" "$$actual"; \
	for name in dwm ${INSTALL_COMMAND_NAMES}; do \
		test -f "$$stage/usr/bin/$$name"; \
	done; \
	test -f "$$stage/usr/share/icons/${CAPITAINE_DARK_THEME}/cursors/default"; \
	test -f "$$stage/usr/share/icons/${CAPITAINE_LIGHT_THEME}/cursors/default"; \
	$(MAKE) uninstall \
		DESTDIR="$$stage" PREFIX=/usr XSESSIONSDIR=/usr/share/xsessions \
		VICINAE_SOURCE_DIR=; \
	find "$$stage" \( -type f -o -type l \) -printf '%P\n' | sort > "$$after"; \
	cmp "$$before" "$$after"; \
	echo "==> Install manifest and uninstall symmetry validated."

check-vicinae-install: all
	@set -eu; \
	if [ "$$(uname -m)" != x86_64 ]; then \
		echo "==> Skipping x86_64 Vicinae install validation on $$(uname -m)."; \
		exit 0; \
	fi; \
	work="$$(mktemp -d)"; \
	trap 'rm -rf "$$work"' EXIT; \
	source="$$work/source"; \
	stage="$$work/stage"; \
	install -Dm755 packaging/vicinae "$$source/AppRun"; \
	install -Dm755 packaging/vicinae "$$source/usr/bin/vicinae"; \
	install -Dm644 dwm.desktop \
		"$$source/usr/share/applications/vicinae.desktop"; \
	install -Dm644 dwm.desktop \
		"$$source/usr/share/applications/vicinae-url-handler.desktop"; \
	install -Dm644 packaging/vicinae \
		"$$source/usr/share/icons/hicolor/512x512/apps/vicinae.png"; \
	$(MAKE) install-system \
		DESTDIR="$$stage" PREFIX=/usr XSESSIONSDIR=/usr/share/xsessions \
		VICINAE_SOURCE_DIR="$$source"; \
	test -x "$$stage/usr/bin/vicinae"; \
	test -x "$$stage/usr/lib/dwm-titus/vicinae/AppRun"; \
	test -f "$$stage/usr/lib/systemd/user/vicinae.service"; \
	grep -Fqx 'ExecStart=/usr/bin/vicinae server --replace' \
		"$$stage/usr/lib/systemd/user/vicinae.service"; \
	echo "==> Vicinae staged install validated."

check-container-smoke:
	tests/test-container-smoke.sh

release-check: all
	@set -eu; \
	first="$$(mktemp)"; \
	listing="$$(mktemp)"; \
	trap 'rm -f "$$first" "$$listing"' EXIT; \
	$(MAKE) release; \
	test -f "${RELEASE_ARCHIVE}"; \
	cp "${RELEASE_ARCHIVE}" "$$first"; \
	$(MAKE) release; \
	cmp "$$first" "${RELEASE_ARCHIVE}"; \
	tar -tzf "${RELEASE_ARCHIVE}" > "$$listing"; \
	grep -Fqx '${RELEASE_NAME}/dwm' "$$listing"; \
	grep -Fqx '${RELEASE_NAME}/dwm.desktop' "$$listing"; \
	grep -Fqx '${RELEASE_NAME}/.xinitrc' "$$listing"; \
	grep -Fqx '${RELEASE_NAME}/config/' "$$listing"; \
	grep -Fqx '${RELEASE_NAME}/scripts/' "$$listing"; \
	grep -Fqx '${RELEASE_NAME}/assets/' "$$listing"; \
	if grep -Eq '(^|/)config\.h$$|\.o$$' "$$listing"; then \
		echo "Release archive contains local configuration or object files." >&2; \
		exit 1; \
	fi; \
	tar -xOzf "${RELEASE_ARCHIVE}" '${RELEASE_NAME}/dwm.desktop' | \
		grep -Fqx 'Exec=${PREFIX}/bin/dwm'; \
	echo "==> Release archive validated."

check:
	$(MAKE) clean
	$(MAKE) all
	$(MAKE) check-shell
	$(MAKE) check-format
	$(MAKE) check-build-config
	$(MAKE) check-default-apps
	$(MAKE) check-diagnostics
	$(MAKE) check-display-profile
	$(MAKE) check-polybar-capabilities
	$(MAKE) check-terminal
	$(MAKE) check-session-guards
	$(MAKE) check-install
	$(MAKE) check-install-manifest
	$(MAKE) check-vicinae-install
	$(MAKE) release-check

.PHONY: all check check-build-config check-build-deps check-default-apps \
	check-container-smoke \
	check-display-profile check-format check-install \
	check-install-manifest check-polybar-capabilities check-session-guards \
	check-shell check-diagnostics \
	check-terminal check-vicinae-install clean install install-system install-user \
	install-cursors install-vicinae native release release-check uninstall
