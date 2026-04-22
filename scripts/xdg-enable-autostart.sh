#!/usr/bin/env bash
# xdg-enable-autostart.sh — Enable XDG autostart for standalone window managers
# Window managers like DWM, i3, bspwm, etc. don't activate the systemd
# graphical-session.target, so XDG autostart .desktop files never run.
# This script creates the necessary systemd user service and wires up the
# environment so that ~/.config/autostart/ and /etc/xdg/autostart/ entries
# are launched on login.
set -euo pipefail

# Use real grep, not rg alias
grep() { command grep "$@"; }

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "  ${CYAN}[INFO]${RESET} $1"; }
pass()  { echo -e "  ${GREEN}[ OK ]${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $1"; }
fail()  { echo -e "  ${RED}[FAIL]${RESET} $1"; }
header(){ echo -e "\n${BOLD}=== $1 ===${RESET}"; }

SERVICE_NAME="wm-graphical-session"
SERVICE_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SERVICE_DIR}/${SERVICE_NAME}.service"

# ─── Pre-flight checks ───────────────────────────────────────────────────────
header "Pre-flight Checks"

if ! command -v systemctl &>/dev/null; then
    fail "systemctl not found — this script requires systemd"
    exit 1
fi
pass "systemd available"

if ! systemctl --user status &>/dev/null 2>&1; then
    fail "systemd user session not running (is lingering enabled or are you in a login session?)"
    exit 1
fi
pass "systemd user session active"

# Check that the targets exist
for target in graphical-session.target xdg-desktop-autostart.target; do
    if systemctl --user cat "$target" &>/dev/null 2>&1; then
        pass "$target found"
    else
        fail "$target not found — systemd version may be too old (need 246+)"
        exit 1
    fi
done

# ─── Current state ───────────────────────────────────────────────────────────
header "Current State"

GS_STATE=$(systemctl --user is-active graphical-session.target 2>/dev/null || echo "inactive")
XDG_STATE=$(systemctl --user is-active xdg-desktop-autostart.target 2>/dev/null || echo "inactive")
info "graphical-session.target: ${GS_STATE}"
info "xdg-desktop-autostart.target: ${XDG_STATE}"

if [[ "$GS_STATE" == "active" && "$XDG_STATE" == "active" ]]; then
    pass "XDG autostart is already active"
    echo ""
    read -rp "  Re-install anyway? [y/N] " REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        echo "  Nothing to do."
        exit 0
    fi
fi

# ─── Detect autostart entries ────────────────────────────────────────────────
header "Autostart Entries"

USER_ENTRIES=0
SYSTEM_ENTRIES=0
if [[ -d "${HOME}/.config/autostart" ]]; then
    USER_ENTRIES=$(find "${HOME}/.config/autostart" -name '*.desktop' 2>/dev/null | wc -l)
fi
if [[ -d "/etc/xdg/autostart" ]]; then
    SYSTEM_ENTRIES=$(find /etc/xdg/autostart -name '*.desktop' 2>/dev/null | wc -l)
fi
info "User autostart entries (~/.config/autostart/): ${USER_ENTRIES}"
info "System autostart entries (/etc/xdg/autostart/): ${SYSTEM_ENTRIES}"

if [[ $USER_ENTRIES -gt 0 ]]; then
    find "${HOME}/.config/autostart" -name '*.desktop' -printf '    %f\n' 2>/dev/null
fi

# ─── Create systemd user service ─────────────────────────────────────────────
header "Installing Systemd User Service"

mkdir -p "$SERVICE_DIR"

if [[ -f "$SERVICE_FILE" ]]; then
    warn "Service file already exists: ${SERVICE_FILE}"
    info "Overwriting with updated version"
fi

cat > "$SERVICE_FILE" << 'UNIT'
[Unit]
Description=Window Manager Graphical Session (XDG Autostart)
Documentation=man:systemd.special(7)
BindsTo=graphical-session.target
Wants=graphical-session.target xdg-desktop-autostart.target
After=basic.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true

[Install]
WantedBy=default.target
UNIT

pass "Created ${SERVICE_FILE}"

# ─── Enable the service ──────────────────────────────────────────────────────
header "Enabling Service"

systemctl --user daemon-reload
pass "Reloaded systemd user daemon"

systemctl --user enable "$SERVICE_NAME.service" 2>/dev/null
pass "Enabled ${SERVICE_NAME}.service"

# ─── Activate now if in a graphical session ──────────────────────────────────
header "Activating"

if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    # Export display environment to systemd
    EXPORT_VARS=(DISPLAY)
    [[ -n "${XAUTHORITY:-}" ]] && EXPORT_VARS+=(XAUTHORITY)
    [[ -n "${WAYLAND_DISPLAY:-}" ]] && EXPORT_VARS+=(WAYLAND_DISPLAY)
    [[ -n "${XDG_CURRENT_DESKTOP:-}" ]] && EXPORT_VARS+=(XDG_CURRENT_DESKTOP)
    [[ -n "${XDG_SESSION_TYPE:-}" ]] && EXPORT_VARS+=(XDG_SESSION_TYPE)

    systemctl --user import-environment "${EXPORT_VARS[@]}"
    pass "Imported environment: ${EXPORT_VARS[*]}"

    if command -v dbus-update-activation-environment &>/dev/null; then
        dbus-update-activation-environment --systemd "${EXPORT_VARS[@]}" 2>/dev/null || true
        pass "Updated D-Bus activation environment"
    fi

    systemctl --user start "$SERVICE_NAME.service" 2>/dev/null || true
    pass "Started ${SERVICE_NAME}.service"
else
    info "No graphical session detected — service will activate on next login"
fi

# ─── Detect xinitrc and offer to patch it ─────────────────────────────────────
header "Shell Startup Integration"

ENV_SNIPPET='# Export display env to systemd user session (needed for XDG autostart)
systemctl --user import-environment DISPLAY XAUTHORITY 2>/dev/null
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY 2>/dev/null'

XINITRC_PATHS=(
    "${HOME}/.xinitrc"
    "${HOME}/.local/share/dwm-dohc/.xinitrc"
    "${HOME}/.config/X11/xinitrc"
)

PATCHED=false
for rc in "${XINITRC_PATHS[@]}"; do
    if [[ -f "$rc" ]]; then
        info "Found xinitrc: ${rc}"
        if grep -q "import-environment DISPLAY" "$rc" 2>/dev/null; then
            pass "Environment export already present in ${rc}"
            PATCHED=true
        else
            echo ""
            read -rp "  Add environment export to ${rc}? [Y/n] " REPLY
            if [[ ! "$REPLY" =~ ^[Nn]$ ]]; then
                # Insert after the shebang line
                SHEBANG=$(head -1 "$rc")
                if [[ "$SHEBANG" == "#!"* ]]; then
                    # Insert after shebang and any immediate blank line
                    LINENUM=2
                    while IFS= read -r line; do
                        if [[ -z "$line" ]]; then
                            LINENUM=$((LINENUM + 1))
                        else
                            break
                        fi
                    done < <(tail -n +2 "$rc")
                    {
                        head -n $((LINENUM - 1)) "$rc"
                        echo ""
                        echo "$ENV_SNIPPET"
                        echo ""
                        tail -n +"$LINENUM" "$rc"
                    } > "${rc}.tmp"
                    mv "${rc}.tmp" "$rc"
                    chmod +x "$rc"
                else
                    # No shebang, prepend
                    {
                        echo "$ENV_SNIPPET"
                        echo ""
                        cat "$rc"
                    } > "${rc}.tmp"
                    mv "${rc}.tmp" "$rc"
                fi
                pass "Patched ${rc}"
                PATCHED=true
            fi
        fi
    fi
done

if [[ "$PATCHED" == false ]]; then
    warn "No xinitrc found to patch"
    info "If you use a xinitrc or session script, add these lines before your WM exec:"
    echo ""
    echo -e "  ${CYAN}${ENV_SNIPPET}${RESET}"
    echo ""
fi

# ─── Verify ──────────────────────────────────────────────────────────────────
header "Verification"

GS_FINAL=$(systemctl --user is-active graphical-session.target 2>/dev/null || echo "inactive")
XDG_FINAL=$(systemctl --user is-active xdg-desktop-autostart.target 2>/dev/null || echo "inactive")
SVC_FINAL=$(systemctl --user is-active "$SERVICE_NAME.service" 2>/dev/null || echo "inactive")
SVC_ENABLED=$(systemctl --user is-enabled "$SERVICE_NAME.service" 2>/dev/null || echo "disabled")

info "${SERVICE_NAME}.service: ${SVC_FINAL} (${SVC_ENABLED})"
info "graphical-session.target: ${GS_FINAL}"
info "xdg-desktop-autostart.target: ${XDG_FINAL}"

# List which autostart services systemd generated
GENERATED=$(systemctl --user list-unit-files --type=service 2>/dev/null | grep "@autostart" | wc -l)
if [[ $GENERATED -gt 0 ]]; then
    info "Systemd generated ${GENERATED} autostart service(s):"
    systemctl --user list-unit-files --type=service 2>/dev/null | grep "@autostart" | while read -r unit state _; do
        STATUS=$(systemctl --user is-active "$unit" 2>/dev/null || echo "inactive")
        if [[ "$STATUS" == "active" || "$STATUS" == "inactive" ]]; then
            SHORT=$(echo "$unit" | sed 's/app-//;s/@autostart.service//;s/\\x2d/-/g')
            echo "    ${SHORT} (${STATUS})"
        fi
    done
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  XDG Autostart Setup Complete${RESET}"
echo -e "${BOLD}════════════════════════════════════════════════════════════${RESET}"
if [[ "$GS_FINAL" == "active" ]]; then
    echo -e "  ${GREEN}XDG autostart is active and will persist across logins.${RESET}"
else
    echo -e "  ${YELLOW}Service installed and enabled — will activate on next login.${RESET}"
fi
echo ""
echo -e "  Manage autostart apps by adding/removing .desktop files in:"
echo -e "    ${CYAN}~/.config/autostart/${RESET}"
echo ""
echo -e "  To disable:  ${CYAN}systemctl --user disable ${SERVICE_NAME}.service${RESET}"
echo -e "  To remove:   ${CYAN}rm ${SERVICE_FILE} && systemctl --user daemon-reload${RESET}"
echo ""
