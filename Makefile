# dwm - dynamic window manager
# See LICENSE file for copyright and license details.

.SILENT:

include config.mk

OWNER ?= $(or $(SUDO_USER),$(USER))
USER_HOME ?= $(shell getent passwd "${OWNER}" 2>/dev/null | cut -d: -f6)
XDG_CONFIG_HOME ?= ${USER_HOME}/.config
XDG_DATA_HOME ?= ${USER_HOME}/.local/share
DATA_DIR  := ${XDG_DATA_HOME}/dwm-titus
CFG_DIR   := ${XDG_CONFIG_HOME}
DATADIR   ?= ${PREFIX}/share
SYSTEMDUSERDIR ?= ${PREFIX}/lib/systemd/user
CAPITAINE_DARK_THEME = Capitaine-Cursors
CAPITAINE_LIGHT_THEME = Capitaine-Cursors-White
CAPITAINE_LICENSE_DIR = ${DATADIR}/licenses/dwm-titus/capitaine-cursors
run_managed_test = if [ -n "$${DWM_TEST_WORKSPACE:-}" ] && [ -n "$${DWM_TEST_RUNNER_TOKEN:-}" ] && [ "$${TMPDIR:-}" = "$${DWM_TEST_WORKSPACE}" ] && [ -f "$${DWM_TEST_WORKSPACE}/.runner" ] && [ ! -L "$${DWM_TEST_WORKSPACE}/.runner" ] && [ "$$(cat "$${DWM_TEST_WORKSPACE}/.runner" 2>/dev/null)" = "$${DWM_TEST_RUNNER_TOKEN}" ]; then $(1); else scripts/run-tests $(1); fi

SRC = drw.c dwm.c util.c tomlparser.c
OBJ = ${SRC:.c=.o}

INSTALL_COMMANDS = \
	scripts/active-audio \
	scripts/dwm-accessibility-settings \
	scripts/check-deps.sh \
	scripts/disable-powersaving \
	scripts/dwm-controlcenter \
	scripts/dwm-default-apps \
	scripts/dwm-diagnostics \
	scripts/dwm-display-profile \
	scripts/dwm-display-setup \
	scripts/dwm-keybinds \
	scripts/dwm-lock \
	scripts/dwm-lock-watch \
	scripts/dwm-panel-settings \
	scripts/dwm-quickshell-launcher \
	scripts/dwm-quickshell-controls \
	scripts/dwm-quickshell-controlcenter \
	scripts/dwm-quickshell-network \
	scripts/dwm-quickshell-pointer \
	scripts/dwm-quickshell-state \
	scripts/dwm-quickshell-version-check \
	scripts/dwm-status \
	scripts/dwm-system-health \
	scripts/dwm-polkit \
	scripts/dwm-packages.sh \
	scripts/dwm-titus-release \
	scripts/dwm-screenshot \
	scripts/dwm-settings \
	scripts/dwm-settings-display \
	scripts/dwm-settings-input \
	scripts/dwm-settings-appearance \
	scripts/dwm-settings-font \
	scripts/dwm-settings-personalization \
	scripts/dwm-settings-wallpaper \
	scripts/dwm-settings-theme \
	scripts/dwm-settings-provider \
	scripts/dwm-session-launch \
	scripts/dwm-xsettings \
	scripts/dwm-terminal \
	scripts/dwm-utils.sh \
	scripts/dwm-xdg-autostart \
	scripts/install-gearlever \
	scripts/install-herdr \
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
PRIVILEGED_HELPERS = scripts/dwm-settings-display-root
PRIVILEGED_HELPER_DIR = ${PREFIX}/libexec/dwm-titus

RELEASE_NAME = dwm-titus-${VERSION}
RELEASE_ARCHIVE = release/${RELEASE_NAME}.tar.gz
SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct 2>/dev/null || printf '0')

all: dwm

.c.o:
	${CC} ${CPPFLAGS} ${CFLAGS} -c $<

${OBJ}: config.h config.mk Makefile
drw.o: drw.h util.h
dwm.o: drw.h util.h tomlparser.h
util.o: util.h
tomlparser.o: tomlparser.h

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

install:
	if [ -z "${DESTDIR}" ] && [ "$$(id -u)" -eq 0 ] && \
		{ [ -z "${OWNER}" ] || [ "${OWNER}" = root ]; }; then \
		echo "Refusing to install user files as root. Run install-user as the target user." >&2; \
		exit 1; \
	fi
	if [ "$$(id -u)" -eq 0 ] && [ -n "${OWNER}" ] && [ "${OWNER}" != root ]; then \
		test -n "${USER_HOME}" || { echo "USER_HOME could not be determined." >&2; exit 1; }; \
		command -v runuser >/dev/null 2>&1 || { \
			echo "runuser is required to build user-owned sources without root privileges." >&2; \
			exit 1; \
		}; \
		runuser -u "${OWNER}" -- env HOME="${USER_HOME}" $(MAKE) all; \
	else \
		$(MAKE) all; \
	fi
	$(MAKE) install-system
	if [ -z "${DESTDIR}" ]; then \
		if [ "$$(id -u)" -eq 0 ]; then \
			target_user="${OWNER}"; \
			if [ -z "$$target_user" ] || [ "$$target_user" = root ]; then \
				echo "Refusing to install user files as root. Run install-user as the target user." >&2; \
				exit 1; \
			fi; \
			command -v runuser >/dev/null 2>&1 || { \
				echo "runuser is required to install user files without root privileges." >&2; \
				exit 1; \
			}; \
			target_uid="$$(id -u "$$target_user")"; \
			runuser -u "$$target_user" -- env -u DBUS_SESSION_BUS_ADDRESS \
				HOME="${USER_HOME}" XDG_RUNTIME_DIR="/run/user/$$target_uid" \
				$(MAKE) install-user \
				USER_HOME="${USER_HOME}" OWNER="$$target_user" \
				XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" \
				XDG_DATA_HOME="${XDG_DATA_HOME}"; \
		else \
			$(MAKE) install-user; \
		fi; \
	else \
		echo "==> DESTDIR set; skipping user configuration."; \
	fi

install-system:
	@test -x dwm || { echo "dwm is not built. Run make before install-system." >&2; exit 1; }
	@for input in ${SRC} ${OBJ} drw.h util.h tomlparser.h config.h config.mk Makefile; do \
		test -e "$$input" || { echo "dwm build input is missing: $$input. Run make before install-system." >&2; exit 1; }; \
		test ! "$$input" -nt dwm || { echo "dwm is stale. Run make before install-system." >&2; exit 1; }; \
	done
	$(MAKE) install-cursors
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
	@echo "==> Installing privileged helpers..."
	for f in ${PRIVILEGED_HELPERS}; do \
		sed "s|@PREFIX@|${PREFIX}|g" "$$f" | \
			install -Dm755 /dev/stdin ${DESTDIR}${PRIVILEGED_HELPER_DIR}/$$(basename "$$f"); \
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

install-user:
	@test -n "${USER_HOME}" || { echo "USER_HOME could not be determined." >&2; exit 1; }
	@test "$$(id -u)" -ne 0 || { echo "Refusing to install user files as root. Run install-user as the target user." >&2; exit 1; }
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
		cp -a --no-preserve=ownership config scripts "${DATA_DIR}/"; \
	fi
	@echo "==> Seeding application config without overwriting user files..."
	mkdir -p ${CFG_DIR}
	for dir in config/*/; do \
		b=$$(basename "$$dir"); \
		if [ "$$b" = quickshell ]; then \
			continue; \
		fi; \
		dst=${CFG_DIR}/$$b; \
		if [ -L "$$dst" ]; then \
			echo "  Preserving symlink $$dst"; \
			continue; \
		fi; \
		mkdir -p "$$dst"; \
		cp -aL -n --no-preserve=ownership "$$dir"/. "$$dst"/; \
	done
	@echo "==> Seeding dwm-scoped XDG autostart overrides..."
	HOME="${USER_HOME}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" \
		XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS}" \
		scripts/seed-autostart-overrides.sh
	@echo "==> Replacing managed Quickshell config..."
	test -n "${CFG_DIR}"
	rm -rf "${CFG_DIR}/quickshell"
	mkdir -p "${CFG_DIR}/quickshell"
	cp -aL --no-preserve=ownership config/quickshell/. "${CFG_DIR}/quickshell"/
	@echo "==> Seeding user config (skipping existing files)..."
	mkdir -p ${CFG_DIR}/dwm-titus
	test -f ${CFG_DIR}/dwm-titus/hotkeys.toml || install -Dm644 config/hotkeys.toml ${CFG_DIR}/dwm-titus/hotkeys.toml
	test -f ${CFG_DIR}/dwm-titus/themes.toml  || install -Dm644 config/themes.toml  ${CFG_DIR}/dwm-titus/themes.toml
	test -f ${CFG_DIR}/dwm-titus/window-rules.toml || install -Dm644 config/window-rules.toml ${CFG_DIR}/dwm-titus/window-rules.toml
	@echo "==> Migrating legacy graphical-session startup..."
	HOME="${USER_HOME}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME}" scripts/migrate-graphical-session.sh
	@echo "==> Installing Meslo font aliases..."
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
	@echo "==> Fixing executable permissions..."
	find ${DATA_DIR} \( -name '*.sh' -o -name '*.py' \) -print0 | xargs -0 -r chmod +x
	for dir in config/*/; do \
		b=$$(basename $$dir); \
		if [ ! -L "${CFG_DIR}/$$b" ]; then \
			find "${CFG_DIR}/$$b" \( -name '*.sh' -o -name '*.py' \) -print0 2>/dev/null | xargs -0 -r chmod +x; \
		fi; \
	done
	@echo ""
	@echo "  dwm installed successfully."
	@echo "  Log out and select 'dwm', or start with: startx"
	@echo ""

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/dwm \
		${DESTDIR}${MANPREFIX}/man1/dwm.1 \
		${DESTDIR}${XSESSIONSDIR}/dwm.desktop
	rm -rf \
		"${DESTDIR}${DATADIR}/icons/${CAPITAINE_DARK_THEME}" \
		"${DESTDIR}${DATADIR}/icons/${CAPITAINE_LIGHT_THEME}" \
		"${DESTDIR}${CAPITAINE_LICENSE_DIR}"
	for name in ${INSTALL_COMMAND_NAMES}; do \
		rm -f ${DESTDIR}${PREFIX}/bin/$$name; \
	done
	rm -f ${DESTDIR}${PRIVILEGED_HELPER_DIR}/dwm-settings-display-root

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
	shellcheck install.sh scripts/dwm-accessibility-settings scripts/dwm-default-apps scripts/dwm-diagnostics scripts/dwm-display-profile scripts/dwm-display-setup scripts/dwm-lock scripts/dwm-lock-watch scripts/dwm-keybinds scripts/dwm-panel-settings scripts/dwm-quickshell-launcher scripts/dwm-quickshell-controls scripts/dwm-quickshell-controlcenter scripts/dwm-quickshell-network scripts/dwm-quickshell-pointer scripts/dwm-quickshell-state scripts/dwm-quickshell-version-check scripts/dwm-settings scripts/dwm-settings-appearance scripts/dwm-settings-font scripts/dwm-settings-personalization scripts/dwm-settings-wallpaper scripts/dwm-settings-theme scripts/dwm-settings-provider scripts/dwm-session-launch scripts/dwm-status scripts/dwm-system-health scripts/dwm-terminal scripts/dwm-xdg-autostart scripts/dwm-xsettings scripts/install-herdr scripts/quickshell-qmllint scripts/run-tests scripts/webapp-launch scripts/*.sh tests/*.sh

check-format:
	shfmt -d install.sh scripts/dwm-accessibility-settings scripts/dwm-default-apps scripts/dwm-diagnostics scripts/dwm-display-profile scripts/dwm-display-setup scripts/dwm-lock scripts/dwm-lock-watch scripts/dwm-keybinds scripts/dwm-panel-settings scripts/dwm-quickshell-launcher scripts/dwm-quickshell-controls scripts/dwm-quickshell-controlcenter scripts/dwm-quickshell-network scripts/dwm-quickshell-pointer scripts/dwm-quickshell-state scripts/dwm-quickshell-version-check scripts/dwm-settings scripts/dwm-settings-appearance scripts/dwm-settings-font scripts/dwm-settings-personalization scripts/dwm-settings-wallpaper scripts/dwm-settings-theme scripts/dwm-settings-provider scripts/dwm-session-launch scripts/dwm-status scripts/dwm-system-health scripts/dwm-terminal scripts/dwm-xdg-autostart scripts/dwm-xsettings scripts/install-herdr scripts/quickshell-qmllint scripts/run-tests scripts/webapp-launch scripts/*.sh tests/*.sh

check-session-guards:
	tests/test-autostart.sh
	tests/test-autostop.sh

check-session-migration:
	tests/test-graphical-session-migration.sh

check-webapp-launch:
	tests/test-webapp-launch.sh

check-screenshot:
	tests/test-dwm-screenshot.sh

check-release-helper:
	tests/test-release-helper.sh

check-xvfb-runtime: all
	tests/test-xvfb-runtime.sh

check-build-config:
	tests/test-configure-build.sh

check-dev-sync-install:
	tests/test-dev-sync-install.sh

check-terminal:
	tests/test-dwm-terminal.sh

check-gearlever-install:
	tests/test-install-gearlever.sh

check-herdr-install:
	tests/test-install-herdr.sh

check-lock:
	tests/test-dwm-lock.sh

check-default-apps:
	tests/test-dwm-default-apps.sh

check-xdg-autostart:
	tests/test-dwm-xdg-autostart.sh

check-display-profile:
	tests/test-dwm-display-profile.sh

check-display-setup:
	tests/test-dwm-display-setup.sh

check-diagnostics:
	tests/test-dwm-diagnostics.sh

check-status:
	tests/test-dwm-status.sh

check-monitor-tags:
	tests/test-monitor-tag-switching.sh

check-quickshell-launcher:
	tests/test-quickshell-launcher.sh

check-quickshell-network:
	tests/test-quickshell-network.sh

check-quickshell-connectivity:
	tests/test-quickshell-connectivity.sh

check-quickshell-controls:
	tests/test-quickshell-controls.sh

check-quickshell-audio:
	tests/test-quickshell-audio.sh

check-quickshell-controlcenter:
	tests/test-quickshell-controlcenter.sh

check-quickshell-power-backend:
	tests/test-quickshell-power-backend.sh

check-quickshell-power-model:
	tests/test-quickshell-power-model.sh

check-quickshell-power: check-quickshell-power-backend check-quickshell-power-model

check-quickshell-session-actions:
	tests/test-quickshell-session-actions.sh

check-quickshell-defaults-model:
	tests/test-quickshell-defaults-model.sh

check-quickshell-appearance-model:
	tests/test-quickshell-appearance-model.sh

check-quickshell-design-system:
	tests/test-quickshell-design-system.sh

check-quickshell-large-surfaces:
	tests/test-quickshell-large-surfaces.sh

check-quickshell-large-surfaces-xvfb: all
	status=0; tests/test-quickshell-large-surfaces-xvfb.sh || status=$$?; \
		if [ "$$status" -eq 77 ]; then exit 0; fi; \
		exit "$$status"

check-quickshell-panel-menus:
	tests/test-quickshell-panel-menus.sh

check-quickshell-panel-settings:
	tests/test-quickshell-panel-settings.sh

check-accessibility:
	tests/test-dwm-accessibility-settings.sh
	tests/test-quickshell-accessibility.sh

check-quickshell-command-menu:
	tests/test-quickshell-command-menu.sh

check-quickshell-notifications:
	tests/test-quickshell-notifications.sh

check-quickshell-tray:
	tests/test-quickshell-tray.sh

check-quickshell-health-xvfb:
	tests/test-quickshell-health-xvfb.sh

check-quickshell-qml:
	scripts/quickshell-qmllint --root config/quickshell

check-system-health:
	tests/test-system-health.sh

check-settings:
	tests/test-settings.sh
	tests/test-settings-input.sh

check-appearance:
	tests/test-dwm-settings-appearance.sh
	tests/test-dwm-settings-appearance-inventory.sh
	tests/test-dwm-settings-font.sh
	tests/test-dwm-settings-personalization.sh
	tests/test-dwm-settings-wallpaper.sh
	tests/test-dwm-settings-theme.sh
	tests/test-dwm-xsettings.sh

check-phase5-optional-components:
	tests/test-dwm-settings-appearance.sh
	tests/test-dwm-settings-appearance-inventory.sh
	tests/test-dwm-settings-personalization.sh
	tests/test-dwm-settings-wallpaper.sh
	tests/test-quickshell-appearance-model.sh
	tests/test-quickshell-controlcenter.sh

check-quickshell-settings-xvfb: all
	tests/test-quickshell-settings-xvfb.sh

check-lightdm-config:
	tests/test-lightdm-config.sh

check-kickstart:
	for ks in dwm-fedora.ks dwm-fedora-nvidia.ks; do \
		ksvalidator "$$ks"; \
		awk 'BEGIN { bad = 0 } \
			/^[[:space:]]*#/ { next } \
			/(^user[[:space:]]|^rootpw[[:space:]]|--hostname=|\/home\/titus|America\/Chicago|^initial-setup$$|^firstboot[[:space:]]+--enable)/ { \
				print "Personal kickstart default remains in '"$$ks"': " $$0 > "/dev/stderr"; \
				bad = 1; \
			} \
			END { exit bad }' "$$ks"; \
		grep -Fqx 'firstboot --disable' "$$ks"; \
	done
	tests/test-kickstart-variants.sh
	$(MAKE) check-fedora-iso-builder

check-fedora-iso-builder:
	tests/test-fedora-iso-builder.sh

check-fedora-platform:
	@$(call run_managed_test,tests/test-fedora-platform.sh)

check-fedora-packages:
	tests/test-fedora-packages.sh

check-install: check-install-manifest

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
		DESTDIR="$$stage" PREFIX=/usr XSESSIONSDIR=/usr/share/xsessions; \
	{ \
		printf '%s\n' \
			pre-existing \
			usr/bin/dwm \
			usr/libexec/dwm-titus/dwm-settings-display-root \
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
		test -x "$$stage/usr/bin/$$name"; \
	done; \
	test -x "$$stage/usr/libexec/dwm-titus/dwm-settings-display-root"; \
	grep -Fqx 'Exec=/usr/bin/dwm' \
		"$$stage/usr/share/xsessions/dwm.desktop"; \
	test -f "$$stage/usr/share/icons/${CAPITAINE_DARK_THEME}/cursors/default"; \
	test -f "$$stage/usr/share/icons/${CAPITAINE_LIGHT_THEME}/cursors/default"; \
	$(MAKE) uninstall \
		DESTDIR="$$stage" PREFIX=/usr XSESSIONSDIR=/usr/share/xsessions; \
	find "$$stage" \( -type f -o -type l \) -printf '%P\n' | sort > "$$after"; \
	cmp "$$before" "$$after"; \
	echo "==> Install manifest and uninstall symmetry validated."

check-install-preservation:
	tests/test-install-preservation.sh

check-test-runner:
	@$(call run_managed_test,tests/test-run-tests.sh)

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
	$(MAKE) check-fedora-platform
	$(MAKE) check-dev-sync-install
	$(MAKE) check-default-apps
	$(MAKE) check-xdg-autostart
	$(MAKE) check-diagnostics
	$(MAKE) check-status
	$(MAKE) check-display-profile
	$(MAKE) check-display-setup
	$(MAKE) check-monitor-tags
	$(MAKE) check-quickshell-launcher
	$(MAKE) check-quickshell-controls
	$(MAKE) check-quickshell-audio
	$(MAKE) check-quickshell-controlcenter
	$(MAKE) check-quickshell-power-backend
	$(MAKE) check-quickshell-power-model
	$(MAKE) check-quickshell-session-actions
	$(MAKE) check-quickshell-defaults-model
	$(MAKE) check-quickshell-appearance-model
	$(MAKE) check-quickshell-settings-xvfb
	$(MAKE) check-quickshell-design-system
	$(MAKE) check-quickshell-large-surfaces
	$(MAKE) check-quickshell-large-surfaces-xvfb
	$(MAKE) check-quickshell-panel-menus
	$(MAKE) check-quickshell-panel-settings
	$(MAKE) check-accessibility
	$(MAKE) check-quickshell-command-menu
	$(MAKE) check-quickshell-qml
	$(MAKE) check-quickshell-notifications
	$(MAKE) check-quickshell-tray
	$(MAKE) check-system-health
	$(MAKE) check-settings
	$(MAKE) check-appearance
	$(MAKE) check-quickshell-network
	$(MAKE) check-quickshell-connectivity
	$(MAKE) check-terminal
	$(MAKE) check-gearlever-install
	$(MAKE) check-herdr-install
	$(MAKE) check-lock
	$(MAKE) check-session-guards
	$(MAKE) check-session-migration
	$(MAKE) check-webapp-launch
	$(MAKE) check-screenshot
	$(MAKE) check-release-helper
	$(MAKE) check-kickstart
	$(MAKE) check-fedora-packages
	$(MAKE) check-install
	$(MAKE) check-install-preservation
	$(MAKE) check-test-runner
	$(MAKE) check-lightdm-config
	$(MAKE) release-check

.PHONY: clean all check check-accessibility check-appearance check-phase5-optional-components check-build-config check-build-deps check-default-apps check-xdg-autostart check-dev-sync-install \
	check-test-runner \
	check-display-profile check-display-setup check-fedora-iso-builder check-fedora-packages check-fedora-platform check-format check-install \
	check-gearlever-install check-herdr-install check-install-manifest check-install-preservation check-kickstart check-lock \
	check-session-guards check-session-migration check-screenshot check-release-helper check-shell check-webapp-launch check-diagnostics check-status check-system-health check-settings \
	check-quickshell-launcher check-quickshell-controls check-quickshell-audio check-quickshell-controlcenter check-quickshell-power check-quickshell-power-backend check-quickshell-power-model check-quickshell-session-actions check-quickshell-defaults-model check-quickshell-appearance-model check-quickshell-design-system check-quickshell-large-surfaces check-quickshell-large-surfaces-xvfb check-quickshell-panel-menus check-quickshell-panel-settings check-quickshell-command-menu check-quickshell-notifications check-quickshell-tray check-quickshell-health-xvfb check-quickshell-settings-xvfb check-quickshell-network check-quickshell-connectivity check-quickshell-qml check-lightdm-config check-terminal check-xvfb-runtime install install-system install-user \
	install-cursors native release release-check uninstall
