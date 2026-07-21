# Settings Capability Inventory

<!-- markdownlint-disable MD013 -->

This document is the Phase 1 `SET-001` inventory for the Settings platform.
It records the interfaces that exist before the unified Settings application
is introduced. It is an implementation map, not a promise that every listed
operation is ready to expose in Settings.

`SPEC.md` and `ROADMAP.md` remain authoritative. The completed application,
helper, authorization, packaging, and validation contracts are recorded in
`docs/SETTINGS-PLATFORM.md` and apply before new settings mutations are
implemented.

## Capability Classes

Every Settings operation uses exactly one primary class:

| Class | Meaning |
| --- | --- |
| Read-only | State is readable without changing user or system state. |
| User-session | The invoking user owns the mutation and no elevation is required. |
| Privileged | A system mutation requires confirmation and a narrow, installed, root-owned helper. |
| Delegated | A trusted service or platform tool owns the operation and its authorization. |
| Unsupported | No suitable provider contract exists yet. The UI must explain or hide it. |

An operation does not become safe for Settings merely because an existing
script can run it. QML may pass documented arguments to a fixed helper action,
but it must not construct shell commands or request elevation for repository,
XDG, or other user-writable helper copies.

## Planned Section Ownership

This table maps every planned Settings section to the current owner and the
provider work still required.

| Section | Current owner and state source | Current mutation path | Class coverage | Failure and fallback | Validation |
| --- | --- | --- | --- | --- | --- |
| Displays | `dwm-display-setup`, `dwm-display-profile`, and RandR state from `xrandr` | RandR preview/profile apply; generated Xorg fragment for persistence | Read-only, user-session, privileged | Report missing X11/RandR; unsupported drivers omit TearFree; persistence must remain unavailable without the future trusted boundary | `make check-display-profile check-display-setup`; nested X11 preview and rollback |
| Input | X11/libinput is installed on Fedora, but no Settings provider contract exists | None | Unsupported | Explain that device controls are not implemented; do not apply global guesses | Future provider unit tests plus nested X11 and real-device checks |
| Network and VPN | `dwm-quickshell-network` over NetworkManager's `nmcli`; event stream from `nmcli monitor` | NetworkManager connection activation/deactivation; `nm-connection-editor` for advanced flows | Read-only, delegated | `NET unavailable` when NetworkManager or `nmcli` is absent; hide the editor action when unavailable | `make check-quickshell-network`; NetworkManager runtime exercise |
| Bluetooth | `dwm-quickshell-controls` over `bluetoothctl` and the BlueZ daemon | BlueZ power, scan, pair/trust/connect, and disconnect operations | Read-only, delegated | `BT unavailable` when BlueZ tooling or an adapter is absent | `make check-quickshell-controls`; real adapter/device check |
| Audio and media | Native `Quickshell.Services.Pipewire` signals with `pactl` or `wpctl` fallback; `playerctl --follow` for media | PipeWire/WirePlumber volume, mute, and default sink; MPRIS media actions | Read-only, user-session | Show unavailable state when the session services or tools are absent; audio and media fail independently | `make check-quickshell-controls`; live PipeWire and MPRIS exercise |
| Power and session | `dwm-quickshell-controlcenter power-status`, `xset`, `gsettings`, light-locker state, and `PowerMenuModel.qml` | User `power.conf`, DPMS, lock policy; logind/systemd session actions | Read-only, user-session, delegated | Disable DPMS/lock controls when their commands or schemas are absent; leave system action authorization to logind | `make check-quickshell-controlcenter check-lock`; nested X11 and real-session checks |
| Defaults and autostart | `dwm-default-apps` over `xdg-settings`, `xdg-mime`, and XDG desktop entries; no settings-ready autostart provider | Browser and MIME writes owned by the user | Read-only, user-session, unsupported | Report missing XDG tools; terminal, file manager, and user-visible autostart controls remain unsupported | `make check-default-apps`; future autostart provider tests |
| Appearance and accessibility | `themes.toml`, `Theme.qml`, `dwm-quickshell-controlcenter`, `theme-apply.sh`, `feh`, and delegated `nwg-look` | User theme files and toolkit config; session wallpaper; external GTK tool | Read-only, user-session, delegated, unsupported | Missing themes/tools affect only their controls; fonts, cursors, notifications, wallpaper selection, and accessibility still need settings contracts | `make check-quickshell-controlcenter check-quickshell-qml`; live theme reload |
| System and diagnostics | `dwm-system-health` structured snapshots and the full-screen health window | Allowlisted user repairs; installed-helper privileged repairs; selected trusted-tool entry points | Read-only, user-session, privileged, delegated, unsupported | Authorization denial produces a restricted partial report; high-risk administration stays delegated or unsupported | `make check-system-health check-quickshell-health-xvfb` |

## Existing Operation Inventory

### Control Center and Shell

| Operations | Owner and interface | Class | Settings disposition |
| --- | --- | --- | --- |
| Open/close pages, show/hide panel widgets | `ControlCenterModel.qml` in-memory state | User-session | Reuse interaction patterns; persistence is not currently provided for widget visibility. |
| System summary, theme list, keybind list, power status | `dwm-quickshell-controlcenter info`, `themes`, `keybinds`, `power-status`; tab-separated records | Read-only | Keep as internal interfaces until a future owning phase versions their output and error contracts. |
| Restart Picom or Quickshell, toggle compositor, reload wallpaper | `dwm-quickshell-controlcenter action` with fixed action names | User-session | Keep allowlisted; surface missing-tool and process failures instead of unconditional success. |
| Dependency check and installer | Fixed Control Center actions launched in a terminal | Delegated | Keep as explicit delegated workflows, not background Settings mutations. |
| Open wallpaper folder or GTK settings | `xdg-open` or `nwg-look` through fixed actions | Delegated | Expose only when the target tool is available. |
| Restart NetworkManager | Legacy fixed action launches `sudo systemctl` in a terminal | Privileged | Do not reuse as a Settings provider. Route future use through the trusted health helper or another installed allowlisted helper. |
| Lock, logout, reboot, shutdown | `PowerMenuModel.qml` uses `dwm-lock`, `loginctl`, or systemd/logind | User-session for lock; delegated for logout/reboot/shutdown | Preserve confirmation for session-ending actions and rely on logind policy for authorization. |

`Commands.qml` currently limits QML to fixed helper names and argv actions.
The Settings application may reuse this pattern only for documented helper
contracts. It must not add a generic command runner or a generic elevated
action.

### Displays

| Operations | Owner and state/mutation path | Class | Failure and safety behavior |
| --- | --- | --- | --- |
| Profile directory/list/current/template | `dwm-display-profile`; XDG profile files and `xrandr --query` | Read-only | Missing profiles produce an empty list; missing RandR is an actionable error. |
| Detect outputs/modes/drivers/TearFree; show status | `dwm-display-setup detect` and `status` | Read-only | Driver-specific features are reported only when detected. |
| Generate an Xorg fragment | `dwm-display-setup generate PROFILE` | Read-only | Parses and validates an allowlisted profile grammar without installing it. |
| Apply a saved profile | `dwm-display-profile apply PROFILE` invokes `xrandr` with validated output names/options | User-session | Reject invalid profiles and disconnected outputs; failure leaves persistence unchanged. |
| Timed live preview | `dwm-display-setup preview PROFILE` captures the current RandR layout before apply | User-session | Reverts after timeout or rejection; reports rollback failure explicitly. |
| Wizard, persistent install, and rollback | `dwm-display-setup` writes the managed Xorg fragment and timestamped backups | Privileged | Existing terminal/sudo flow is not the final Settings boundary. Settings needs confirmation plus a root-owned allowlisted helper contract. |

### Network and Bluetooth

| Operations | Owner and interface | Class | Failure and lifecycle behavior |
| --- | --- | --- | --- |
| Network status, devices, profiles, Wi-Fi scan | `dwm-quickshell-network` machine-oriented `nmcli` fields | Read-only | Missing NetworkManager tooling yields unavailable state without affecting other sections. |
| Network change notifications | `dwm-quickshell-network monitor` using `nmcli monitor` | Read-only | The existing shared monitor serves the always-visible panel. A Settings-only watch must stop when its section closes. |
| Connect saved profile, connect Wi-Fi, disconnect device | Fixed `nmcli connection` and `device` actions | Delegated | NetworkManager owns policy and secrets. Passwords remain argv data and must not be logged or persisted by QML. |
| Hidden, enterprise, and advanced network editing | `nm-connection-editor` | Delegated | Hide the entry point when the tool is absent. |
| Bluetooth status and known device list | `dwm-quickshell-controls bluetooth-status` and `bluetooth-devices` | Read-only | Missing `bluetoothctl`, daemon, or adapter is an unavailable capability. |
| Scan, adapter power, pair/trust/connect, disconnect | Fixed `bluetoothctl` actions | Delegated | BlueZ owns device policy. Scan is bounded to eight seconds; failures must be attributed to the requested device/action. |

### Audio and Media

| Operations | Owner and interface | Class | Failure and lifecycle behavior |
| --- | --- | --- | --- |
| Default sink/source volume and mute | Native Quickshell PipeWire objects; `pactl`/`wpctl` snapshot fallback | Read-only | Native signals are preferred; no audio polling or repeated subscription processes. |
| Output device list and current default | `dwm-quickshell-controls output-devices` and `output-status` | Read-only | Output is unavailable when neither supported session interface responds. |
| Volume up/down/set, sink mute, default output | Fixed PipeWire/Pulse helper actions | User-session | Arguments are bounded; current streams move only when the selected backend supports it. |
| Microphone mute status | Native PipeWire source or helper fallback | Read-only | Microphone mutation and input-device selection are not implemented and remain unsupported. |
| Media state and event stream | `playerctl metadata` and `playerctl --follow` | Read-only | The existing shared stream serves panel controls; section-specific streams must be stopped on close. |
| Play/pause, previous, next | Fixed `playerctl` actions | User-session | Absent players or MPRIS support affect only media controls. |
| Per-application streams | No current provider contract | Unsupported | Add a PipeWire-native model in Phase 3; do not parse an unstable display format. |

### Power, Defaults, and Appearance

| Operations | Owner and interface | Class | Failure and safety behavior |
| --- | --- | --- | --- |
| DPMS and lock status | `dwm-quickshell-controlcenter power-status`; X11 and light-locker state | Read-only | Availability flags keep missing X11 or lock providers from breaking the section. |
| Enable/disable DPMS or auto-lock; set timeouts | Fixed power actions write user `power.conf` and apply via `xset`/`gsettings` | User-session | Values are bounded; helper failure must not be reported as saved. |
| Battery, power profiles, suspend policy, and lid policy | No settings-ready provider contract | Unsupported | Add stable system service providers in Phase 4 and distinguish readable state from privileged policy changes. |
| Browser/MIME state and browser candidates | `dwm-default-apps status` and `browsers` | Read-only | Missing XDG tools or invalid desktop entries are reported without inventing defaults. |
| Set browser or MIME handler | `dwm-default-apps set-browser` and `set-mime` | User-session | Desktop IDs and MIME arguments are validated before XDG writes. |
| Default terminal, file manager, and autostart entries | No settings-ready provider contract | Unsupported | Preserve current configuration and XDG overrides until a provider is defined. |
| Theme list and active theme | `themes.toml`, `Theme.qml`, and Control Center helper records | Read-only | Missing or invalid user state falls back to managed defaults without overwriting the user file. |
| Select theme and apply toolkit/terminal/cursor settings | `theme-set`, hot reload, and `theme-apply.sh` user-file writes | User-session | A future contract must report partial toolkit failures and define preview/reset behavior. |
| Random wallpaper | Fixed `feh` action over the user wallpaper directory | User-session | Missing tools, directory, or images are isolated failures. A selected-wallpaper provider is not yet available. |
| GTK configuration tool | `nwg-look` | Delegated | Optional entry point only. |
| Fonts, icons, notification policy, and accessibility | No settings-ready provider contract | Unsupported | Add by Phase 5 with explicit preview, reset, and rollback behavior. |

### System Health and Administration

| Operations | Owner and interface | Class | Failure and safety behavior |
| --- | --- | --- | --- |
| Session health snapshot | `dwm-system-health scan-user`; tab-separated typed records | Read-only | Runs on demand and stops when the health window closes. Individual probes report restricted, warning, or unavailable state. |
| Current-boot logs, failed system services, SMART state | `scan-privileged` selects non-interactive sudo or polkit plus a trusted installed helper | Read-only with privileged authorization | Denial or cancellation leaves the user snapshot visible and labels coverage incomplete. |
| Copy/export bounded evidence | `share-evidence` to X11 clipboard or private non-overwriting user file | User-session | Only the two documented evidence IDs are accepted. |
| Restart desktop/audio components; manage failed user services | `repair-user` fixed allowlist | User-session | Every repair requires UI confirmation; service operations are accepted only for currently failed `.service` units. |
| Manage failed system services; restart NetworkManager/Bluetooth; repair time sync | `repair-privileged` to root-owned installed helper, then fixed `repair-system` allowlist | Privileged | No repository/XDG helper may be elevated. Denial preserves readable health state. |
| Updates, users, printers, locale/timezone, software sources | No unified provider; some future actions may open trusted Fedora tools | Delegated or unsupported | Phase 6 must choose a stable service/tool per operation and keep high-risk administration out of QML. |
| Partitions, arbitrary services, firewall policy | Explicitly outside the current helper allowlist | Unsupported | Delegate to trusted administration tools unless a later specification defines a narrow contract. |

## Platform Provider Matrix

Package names remain owned by `scripts/dwm-packages.sh`. This document names
package profiles and runtime capabilities so future Settings code does not
duplicate distro-specific lists.

| Provider capability | Fedora path | Secondary-platform behavior |
| --- | --- | --- |
| Quickshell Settings frontend | `rhel:desktop` supplies Quickshell on Fedora | Arch maps Quickshell in `arch:desktop`. The Debian map does not currently supply it, so the Settings UI is unsupported there unless a compatible Quickshell is installed separately; core dwm remains usable. |
| X11 display state | `rhel:x11` supplies the RandR/X11 tools | `arch:x11` and `debian:x11` supply family equivalents. TearFree remains driver-dependent everywhere. |
| NetworkManager | `rhel:desktop-optional`; enabled by the Fedora image | Arch and Debian optional profiles provide NetworkManager. Without it, the provider reports unavailable and other sections continue. |
| BlueZ | `rhel:desktop` plus the Fedora image service/package set | Arch and Debian desktop profiles provide their BlueZ equivalents. Adapter absence is a runtime unsupported state. |
| PipeWire/WirePlumber and controls | `rhel:desktop`; included by the Fedora image | Arch and Debian desktop profiles provide family equivalents. Helpers fall back between supported session commands. |
| DPMS and auto-lock | X11 tools plus `rhel:desktop` light-locker and GLib settings | Arch and Debian desktop profiles provide equivalents. Missing schemas or locker disable only lock controls. |
| Defaults | `rhel:runtime-required` XDG utilities | Arch and Debian required profiles provide equivalents. |
| Themes and GTK integration | `rhel:theme`, `rhel:theme-gtk`, and optional tool profiles | Family theme profiles provide available equivalents; missing optional theme packages do not disable Settings. |
| Polkit authorization | Fedora desktop/image installs a polkit agent; health helper can use a trusted system install | Other desktop profiles provide a polkit agent where available. Without an agent or trusted helper, privileged capabilities are restricted while read-only state remains available. |
| System health | Portable helper probes plus Fedora/systemd providers where present | The helper detects Debian, Arch, and RHEL families and emits partial/restricted records for missing commands, services, hardware, or authorization. |

## Phase 1 Constraints Derived From the Inventory

- There is no reusable generic privilege interface. The health helper is the
  only current trusted-helper pattern and its allowlist must not be widened by
  accepting arbitrary commands.
- The display installer's terminal `sudo` flow and the Control Center's legacy
  NetworkManager restart are not Settings provider contracts.
- Existing event streams used by persistent panel widgets may stay shared.
  Watches created only for a Settings section must start on section activation
  and stop on close.
- Provider failures must be per section. Missing Quickshell, NetworkManager,
  BlueZ, PipeWire, X11, or a Fedora-only tool must not damage the core session.
- The Phase 1 discovery output follows the versioned contract in
  `docs/SETTINGS-PLATFORM.md`. Other current tab-separated interfaces remain
  inventory inputs, not automatically stable public APIs.
- No existing or planned operation requires passwordless broad `sudo`, and no
  QML component is assigned ownership of an elevated command.
