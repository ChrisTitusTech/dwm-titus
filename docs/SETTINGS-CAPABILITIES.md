# Settings Capability Inventory

<!-- markdownlint-disable MD013 -->

This document is the Settings capability inventory. It records the platform,
display, input, connectivity, audio, and power providers built on the unified
Settings surface. It is an implementation map of current and delegated
interfaces, not a promise that every listed operation is ready to expose in
Settings.

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

Unsupported is a capability status, not an operation class. It means no suitable
provider contract exists yet, so the UI must explain or hide the capability.

Provider records use `available` for complete readable state, `partial` for a
usable incomplete result, `restricted` when the owning interface is reachable
but policy or permissions deny that specific read, `unavailable` when an
expected interface cannot be reached, and `unsupported` when no source exists.
A restricted individual record may therefore have an unknown value; capability
aggregation preserves and displays any readable sibling records rather than
treating the entire section as unreadable. Mutation authorization denial is the
separate terminal `permission-denied` operation/error state and never changes a
previously readable provider status.

An operation does not become safe for Settings merely because an existing
script can run it. QML may pass documented arguments to a fixed helper action,
but it must not construct shell commands or request elevation for repository,
XDG, or other user-writable helper copies.

## Planned Section Ownership

This table maps every planned Settings section to the current owner and the
provider work still required.

| Section | Current owner and state source | Current mutation path | Class coverage | Failure and fallback | Validation |
| --- | --- | --- | --- | --- | --- |
| Displays | `dwm-settings-display` over `dwm-display-setup` and RandR state from `xrandr` | Complete timed RandR preview, named profiles, and allowlisted managed-fragment install/rollback | Read-only, user-session, privileged | Malformed or missing RandR fails only Displays; unsupported drivers report anti-tearing unavailable; persistence is restricted without the installed helper and polkit | `make check-display-setup check-settings check-quickshell-settings-xvfb`; real multi-monitor preview/rollback and Xorg restart |
| Input | `dwm-settings-input` owns XInput/libinput, `setxkbmap`, `xkbset`, and udev hotplug state | Timed per-device and session-wide AccessX preview, reset, XDG persistence, idempotent session-start apply, and debounced hotplug replay | Read-only, user-session | Unsupported properties are reported per stable device; disconnects and missing XKB tooling are isolated without affecting other devices or sections | `make check-settings check-quickshell-settings-xvfb`; representative real keyboard/pointer checks |
| Network and VPN | `dwm-quickshell-network` over NetworkManager's `nmcli`; event stream from `nmcli monitor` | NetworkManager connection activation/deactivation; `nm-connection-editor` for advanced flows | Read-only, delegated | `NET unavailable` when NetworkManager or `nmcli` is absent; hide the editor action when unavailable | `make check-quickshell-network`; NetworkManager runtime exercise |
| Bluetooth | `dwm-quickshell-controls` over `bluetoothctl` and the BlueZ daemon | BlueZ power, scan, pair/trust/connect, and disconnect operations | Read-only, delegated | `BT unavailable` when BlueZ tooling or an adapter is absent | `make check-quickshell-controls`; real adapter/device check |
| Audio and media | Native `Quickshell.Services.Pipewire` signals with a versioned `pactl` inventory fallback; `playerctl --follow` for media | Output/input defaults, volume and mute, application streams, and MPRIS media actions | Read-only, user-session | Native signals remain authoritative; audio inventory, media, and Bluetooth fail independently | `make check-quickshell-controls check-quickshell-audio`; live PipeWire and MPRIS exercise |
| Power and session | Shared Power and session-action models over versioned helper records, UPower, Power Profiles D-Bus, logind, `xset`, `gsettings`, and light-locker | Delegated profile and session actions; user `power.conf`, DPMS, and lock policy; cleanup-aware DWM logout | Read-only, user-session, delegated | Capabilities fail independently; destructive actions share confirmation, origin attribution, overlap rejection, and exact accepted-result checks | `make check-quickshell-power check-quickshell-session-actions check-quickshell-controlcenter check-lock check-quickshell-settings-xvfb`; real X11 and available hardware/service checks |
| Defaults and autostart | Versioned `dwm-default-apps` and `dwm-xdg-autostart` providers over XDG tools and desktop entries | Browser, terminal, file-manager, MIME, and next-login autostart overrides with verified recovery | Read-only, user-session | Invalid entries fail per item; mutations reject unsafe paths, preserve unrelated state, verify convergence, and never edit vendor files | `make check-default-apps check-terminal check-xdg-autostart check-quickshell-defaults-model check-quickshell-settings-xvfb` |
| Appearance and accessibility | Versioned appearance, personalization, panel, managed-shell accessibility and notification policy, and `settings-protocol 1` capability records; consumes the shared Input backend's XKB capability and state | User theme, wallpaper, managed-shell typography, desktop personalization, contrast and motion policy, notification Do Not Disturb and popup duration, Input-owned XKB accessibility controls, and shared panel-widget state; transactional toolkit config; external GTK and Qt tools | Read-only, user-session, delegated | Invalid or unavailable providers are attributed per capability; an external notification owner leaves managed policy controls read-only | `make check-appearance check-settings check-quickshell-panel-settings check-accessibility check-quickshell-notifications check-quickshell-controlcenter check-quickshell-qml`; nested-X11 appearance, accessibility persistence, notification delivery/history, and live toolkit reload |
| System and diagnostics | `dwm-system-health` structured snapshots plus the Phase 6 `dwm-system-management` provider contract | Allowlisted health repairs, PackageKit updates, systemd regional actions, and trusted Fedora entry points | Read-only, user-session, privileged, delegated | Authorization denial preserves readable state; PackageKit owns update cancellation; unsupported status is explicit and high-risk administration stays delegated | Current: `make check-system-health check-quickshell-health-xvfb`; pending Phase 6: `make check-system-management check-quickshell-system-management check-quickshell-settings-xvfb` |

## Existing Operation Inventory

### Control Center and Shell

| Operations | Owner and interface | Class | Settings disposition |
| --- | --- | --- | --- |
| Open/close pages, show/hide panel widgets | One root `PanelSettingsModel.qml` over versioned `dwm-panel-settings` state; Control Center delegates to it | User-session | Workspace, volume, Bluetooth, network, and power visibility is shared by every monitor and Settings. Absent or invalid state safely reads as all-on; atomic set/reset refuses unsafe or concurrent replacement. |
| System summary, theme list, keybind list, power status | `dwm-quickshell-controlcenter info`, `themes`, `keybinds`, `power-status`; tab-separated records | Read-only | Keep as internal interfaces until a future owning phase versions their output and error contracts. |
| Restart Picom or Quickshell, toggle compositor, reload wallpaper | `dwm-quickshell-controlcenter action` with fixed action names | User-session | Keep allowlisted; surface missing-tool and process failures instead of unconditional success. |
| Dependency check and installer | Fixed Control Center actions launched in a terminal | Delegated | Keep as explicit delegated workflows, not background Settings mutations. |
| Open wallpaper folder or GTK settings | `xdg-open` or `nwg-look` through fixed actions | Delegated | Expose only when the target tool is available. |
| Restart NetworkManager | Legacy fixed action launches `sudo systemctl` in a terminal | Privileged | Do not reuse as a Settings provider. Route future use through the trusted health helper or another installed allowlisted helper. |
| Lock, logout, suspend, reboot, shutdown | One root `PowerMenuModel.qml` uses the fixed `session-action` helper protocol | User-session for lock/logout; delegated for suspend/reboot/shutdown | Panel and Settings share confirmation, progress, failures, and overlap rejection. Logout signals only the verified current DWM so normal autostop cleanup runs. |

`Commands.qml` currently limits QML to fixed helper names and argv actions.
The Settings application may reuse this pattern only for documented helper
contracts. It must not add a generic command runner or a generic elevated
action.

### Displays

| Operations | Owner and state/mutation path | Class | Failure and safety behavior |
| --- | --- | --- | --- |
| Profile directory/list/current/template | `dwm-display-profile`; XDG profile files and `xrandr --query` | Read-only | Missing profiles produce an empty list; missing RandR is an actionable error. |
| Detect outputs, modes, drivers, TearFree, and NVIDIA Full Composition Pipeline; show status | `dwm-display-setup detect`, `capabilities`, and `status` | Read-only | Driver-specific features are reported only when the kernel and Xorg drivers are compatible. |
| Generate an Xorg fragment | `dwm-display-setup generate PROFILE` | Read-only | Parses and validates an allowlisted profile grammar without installing it. |
| Apply a saved profile | `dwm-display-profile apply PROFILE` invokes `xrandr` with validated output names/options | User-session | Reject invalid profiles and disconnected outputs; failure leaves persistence unchanged. |
| Timed live preview | `dwm-display-setup preview PROFILE` captures the current RandR layout before apply | User-session | Reverts after timeout or rejection; reports rollback failure explicitly. |
| Settings discovery and profile preview | `dwm-settings-display` version 1 records and section-owned udev watch | Read-only and user-session | QML passes structured argv only; validation and RandR policy stay in `dwm-display-setup`. Apply failure and timeout restore the captured layout. |
| Persistent install and rollback | `dwm-settings-display-root` writes only the managed Xorg fragment through `pkexec` | Privileged | Requires confirmation, an exact installed libexec path, root ownership, non-writable files, structured records, and a safe caller Xauthority. Denial leaves readable state available. |

### Input

| Operations | Owner and state/mutation path | Class | Failure and safety behavior |
| --- | --- | --- | --- |
| Device/property discovery | `dwm-settings-input discover`; XInput properties plus udev serial/path identity | Read-only | Whitespace and punctuation are tab-safe. Missing acceleration, scrolling, tapping, or per-device repeat is an explicit device-scoped unsupported record. |
| XKB accessibility discovery | One fixed session-scoped `accessx` group from bounded `xkbset q` output | Read-only | Missing or unresponsive `xkbset` produces one explanatory group-scoped unsupported record without hiding ordinary XInput devices. |
| Hotplug watch | `udevadm monitor --subsystem-match=input` for Settings refresh and session replay | Read-only and user-session | Section-owned UI discovery stops on section change; the session watcher debounces add/change events, idempotently reapplies saved values, and exits with its owning dwm process. |
| Preview and persistence | Fixed `preview`, `keep`, `revert`, and `apply-saved` actions | User-session | Every action re-resolves the stable identity. `revert` and preview timeout restore the value captured when that preview started; disconnected devices cannot redirect a change to another XInput ID. Devices without a stable udev or physical sysfs identity remain session-only. |
| XKB accessibility mutation | Fixed allowlist for accessibility shortcuts, sticky keys, slow keys, bounce keys, and mouse keys through `xkbset` | User-session | The same timed preview captures the current live XKB value. `keep` persists the choice, session startup replays it, and the separate `reset` action restores the baseline captured before the first kept override without accepting arbitrary `xkbset` options. |
| Reset | Fixed `reset` action | User-session | Without creating a preview token, restores the saved baseline (or the current driver default before any override) and removes the persisted override. |

### Network and Bluetooth

| Operations | Owner and interface | Class | Failure and lifecycle behavior |
| --- | --- | --- | --- |
| Network status, devices, profiles, Wi-Fi scan | Versioned `dwm-quickshell-network snapshot` records from machine-oriented `nmcli` fields | Read-only | Missing NetworkManager tooling yields unavailable state without affecting other sections. |
| Network change notifications | `dwm-quickshell-network monitor` using `nmcli monitor` | Read-only | The existing shared monitor serves the always-visible panel. A Settings-only watch must stop when its section closes. |
| Connect saved profile, connect Wi-Fi, disconnect device | Fixed `nmcli connection` and `device` actions | Delegated | NetworkManager owns policy and secrets. QML clears passwords after passing them over helper stdin; the helper selects WPA, WPA3, or WEP settings from scan data, uses a mode-0600 temporary `passwd-file`, removes it after activation, and never puts the secret on argv. |
| Hidden, enterprise, and advanced network editing | `nm-connection-editor` | Delegated | Hide the entry point when the tool is absent. |
| Bluetooth status and known device list | Versioned `bluetooth-snapshot` records from BlueZ ObjectManager D-Bus JSON | Read-only | Daemon, adapter, and operation support are reported separately. |
| Scan, adapter power, pair/trust/connect, disconnect, remove | Fixed `bluetoothctl` actions | Delegated | BlueZ owns device policy. Scan is bounded to eight seconds and explicitly stopped; failures retain the canonical requested address. |

### Audio and Media

| Operations | Owner and interface | Class | Failure and lifecycle behavior |
| --- | --- | --- | --- |
| Default sink/source volume and mute | Native Quickshell PipeWire objects; `pactl`/`wpctl` snapshot fallback | Read-only | Native signals are preferred; no audio polling or repeated subscription processes. |
| Output device list and current default | `dwm-quickshell-controls output-devices` and `output-status` | Read-only | Output is unavailable when neither supported session interface responds. |
| Volume up/down/set, sink mute, default output | Fixed PipeWire/Pulse helper actions | User-session | Arguments are bounded; current streams move only when the selected backend supports it. |
| Microphone status, volume, mute, and input-device selection | Native Quickshell PipeWire source with bounded helper fallback | User-session | Native signals are preferred; mutations are generation-checked and failures remain attributed to Audio. |
| Media state and event stream | `playerctl metadata` and `playerctl --follow` | Read-only | The existing shared stream serves panel controls; section-specific streams must be stopped on close. |
| Play/pause, previous, next | Fixed `playerctl` actions | User-session | Absent players or MPRIS support affect only media controls. |
| Per-application stream volume and mute | Native Quickshell PipeWire stream objects with bounded helper fallback | User-session | Active streams are signal-driven; missing stream support affects only the application-stream list. |

### Power, Defaults, and Appearance

| Operations | Owner and interface | Class | Failure and safety behavior |
| --- | --- | --- | --- |
| DPMS and lock status | Versioned Control Center snapshot over X11 and light-locker state | Read-only | Availability flags keep missing X11 or lock providers from breaking the section. |
| Enable/disable DPMS or auto-lock; set timeouts | Fixed power actions apply through bounded `xset`/`gsettings`, then atomically replace user `power.conf` | User-session | Values are restricted to 60 through 86400 seconds; apply or persistence failure restores prior state and is not reported as saved. |
| Battery and external power | Aggregate UPower display-device and manager properties | Read-only | No battery is an explicit hardware-absent record; it does not hide profile, DPMS, lock, suspend, or lid state. |
| Power profiles | Power Profiles D-Bus properties and fixed allowlisted `ActiveProfile` mutation | Read-only and delegated | Missing service disables profile selection only; the service and polkit retain authorization ownership. |
| Suspend and lid capability | systemd-logind `CanSuspend` and effective lid-policy properties plus UPower lid state | Read-only and delegated | Suspend is exposed through the shared confirmed session model only when available; persistent lid policy remains read-only. |
| Browser, terminal, file-manager, and MIME state/candidates | `dwm-default-apps snapshot` version 1.0 | Read-only | Missing tools and invalid desktop entries fail per role or MIME without inventing defaults. |
| Set or restore an application default | Fixed `set-role`, `set-mime`, `reset-role`, and `reset-mime` actions | User-session | Exact selected associations or the terminal variable change transactionally; recovery refuses to overwrite later external edits. |
| XDG autostart entries | `dwm-xdg-autostart` version 1.0 snapshot/watch and fixed set/reset actions | Read-only and user-session | Vendor files are immutable; user overrides are revision-checked, backed up, atomic, and next-login only. Session-critical changes require confirmation. |
| Theme list and active theme | `dwm-settings-appearance snapshot` version 1.0 over `themes.toml`; `Theme.qml` remains the live shell adapter | Read-only | Missing, duplicate, malformed, or incomplete themes produce typed errors and a deterministic valid recovery theme without modifying the user file. |
| Select theme and apply toolkit/terminal/cursor settings | `dwm-settings-theme` action protocol version 1.0 plus hot reload and `theme-apply.sh` | User-session | A read-only readiness probe hides mutation controls for unsafe or non-mutable sources. Preview rolls back automatically unless kept; apply and reset are atomic, serialized, and rollback-capable. Interrupted recovery and external changes are hash guarded. Partial integration state remains visible through the read-only appearance snapshot. |
| Wallpaper | `dwm-settings-wallpaper` persisted selection and fit mode, the Settings Appearance pane, plus the existing randomize action | User-session | Candidate selection, fit, preview, keep, revert, apply, and reset share one root model. Preview rollback is bounded; missing or undecodable saved images fall back to the random-fill session default; missing Feh, directory, or images remain isolated failures. |
| Managed shell font and text scale | `dwm-settings-font` action protocol version 1.0, Fontconfig exact-family validation with equivalent MesloLGS aliases, `Theme.qml`, and the root Appearance model | User-session | The dedicated mode-preserving `font.conf` owns only the managed shell family and one of six bounded scales. Preview rollback is watchdog-backed and hash-guarded; malformed state falls back to Meslo at 100 percent, while the icon font remains fixed so ordinary fonts cannot remove shell glyphs. GTK and Qt font policy remains outside this slice. |
| Font, text scale, cursor, icon, GTK, and Qt choices | The root Appearance model consumes the pane-scoped bounded inventory and `dwm-settings-personalization`; fixed apply/reset actions delegate to `dwm-settings-theme`, `theme-apply.sh` consumes versioned persisted overrides, and `dwm-xsettings` owns the generated X11 text-scale channel | User-session | Settings reports the effective value and persisted override or follow mode separately, caps long candidate lists, and globally excludes overlapping appearance actions. The existing theme mutation and integration locks serialize every output. Hash-guarded publish and durable recovery preserve unrelated or concurrent edits. A malformed but structurally safe override file has an explicit transaction-backed repair that resets only persisted preferences and preserves every other live integration. A scoped `xsettingsd` instance exposes verified fixed-point DPI to native GTK applications, refuses to displace an existing XSETTINGS owner, and is stopped on system-follow reset; cursor, GTK, and Qt reset to explicit theme-follow behavior, while font, text scale, and icons reset to system-follow behavior. |
| Panel widget visibility | One root `PanelSettingsModel.qml` and fixed `dwm-panel-settings` status/set/reset protocols over `panel-widgets.conf` | User-session | The former implicit all-on session state migrates without a write. All monitors, Control Center, and Settings consume the same values. Malformed or unsupported state is preserved and presented as safe all-on defaults until an explicit set/reset atomically repairs it; unsafe files are never replaced. |
| Advanced GTK and Qt editing | Settings exposes fixed `delegate gtk\|qt` actions for an installed trusted editor | Delegated | The button is hidden and an explanatory optional-capability card is shown when no supported editor is installed. Advanced editor state remains externally owned and is not interpreted as a Settings transaction. |
| GTK configuration tool | `nwg-look` | Delegated | Optional entry point only. |
| Wallpaper, font, cursor, icon, GTK, Qt, and compositor asset state | `dwm-settings-appearance inventory` version 1.0 plus pane-scoped asset and Picom watchers | Read-only | Candidate output and watch coverage are bounded; missing tools or assets degrade only their capability. Managed-shell font controls are available, and desktop personalization mutations are exposed through a separate backend contract. |
| Notification and accessibility capability discovery | Five `settings-protocol 1` records derived from bounded personalization, managed accessibility policy, notification-owner identity, XInput, and XKB probes | Read-only and user-session | Text scaling reflects the complete versioned personalization record. High contrast, reduced motion, XKB access, Do Not Disturb, and bounded popup duration expose persistent keyboard-focusable mutations. Notification controls are enabled only when the machine-readable D-Bus owner PID resolves to Quickshell running the managed configuration. |

The Phase 5 appearance snapshot is append-only within protocol version 1. It
starts with `appearance-protocol<TAB>1<TAB>0` and emits provider, source,
active-theme, theme, semantic-color, integration, and capability-scoped error
records. It is read-only. The active record distinguishes the user's selected
theme from the resolved recovery theme, so later UI work can explain invalid
state without overwriting comments, custom themes, file mode, or unrelated
configuration. GTK, Qt, cursor, terminal, and compositor integration failures
remain independent records and do not suppress valid theme inventory. A
snapshot returns status 3 after emitting its records when no valid theme can be
resolved; partial snapshots and isolated integration failures return status 0.
Inventory enforces the DWM parser's 512-entry ceiling and the exact section
header grammar shared by the current QML and toolkit consumers. A trailing
comment on a section header is therefore a typed compatibility error until all
live consumers support it consistently. Arrays and inline tables are rejected
conservatively because they are outside the appearance snapshot grammar.

```text
appearance-protocol<TAB>major<TAB>minor
provider<TAB>id<TAB>status<TAB>class<TAB>detail
source<TAB>user|managed|none<TAB>path|unavailable
active<TAB>selected<TAB>resolved<TAB>selected|recovery|unresolved
theme<TAB>name<TAB>selection<TAB>validity<TAB>dark-mode<TAB>gtk-theme<TAB>detail
color<TAB>semantic-role<TAB>#RRGGBB<TAB>source-key
integration<TAB>id<TAB>status<TAB>value<TAB>detail
error<TAB>capability<TAB>code<TAB>detail
```

### System Health and Administration

| Operations | Owner and interface | Class | Failure and safety behavior |
| --- | --- | --- | --- |
| Session health snapshot | `dwm-system-health scan-user`; tab-separated typed records | Read-only | Runs on demand and stops when the health window closes. Individual probes report restricted, warning, or unavailable state. |
| Current-boot logs, failed system services, SMART state | `scan-privileged` selects non-interactive sudo or polkit plus a trusted installed helper | Read-only with privileged authorization | Denial or cancellation leaves the user snapshot visible and labels coverage incomplete. |
| Copy/export bounded evidence | `share-evidence` to X11 clipboard or private non-overwriting user file | User-session | Only the two documented evidence IDs are accepted. |
| Restart desktop/audio components; manage failed user services | `repair-user` fixed allowlist | User-session | Every repair requires UI confirmation; service operations are accepted only for currently failed `.service` units. |
| Manage failed system services; restart NetworkManager/Bluetooth; repair time sync | `repair-privileged` to root-owned installed helper, then fixed `repair-system` allowlist | Privileged | No repository/XDG helper may be elevated. Denial preserves readable health state. |
| Fedora updates | Phase 6 `dwm-system-management` over the PackageKit 1.x D-Bus/GLib API and Fedora DNF5 backend | Read-only and delegated | Passive discovery never refreshes metadata. Confirmed PackageKit transactions expose progress, typed failure, restart guidance, and cancellation only while `AllowCancel` is true. |
| Date, timezone, NTP, and locale | `org.freedesktop.timedate1` and `org.freedesktop.locale1` properties and fixed methods | Read-only and delegated | systemd and polkit own authorization. Denial leaves the current properties visible. Manual timestamps, NTP servers, RTC mode, and keyboard layout are not accepted. |
| Users | AccountsService properties; fixed `lxqt-admin-user` and terminal `passwd` entry points | Read-only and delegated | QML never carries a password or constructs account arguments. Missing delegated tools do not hide the read-only account summary. |
| Printers | CUPS availability; fixed `system-config-printer` entry point | Read-only and delegated | CUPS and the trusted Fedora tool own printer discovery, authentication, jobs, queues, and cancellation. |
| Software sources | PackageKit repository records; fixed `dnfdragora` entry point | Read-only and delegated | Settings does not accept a repository identifier for mutation. Missing `dnfdragora` leaves repository state readable. |
| Partitions, arbitrary services, firewall policy | Explicitly outside the current helper allowlist | Delegated | The capability is unsupported until a later specification defines a narrow contract; use trusted administration tools. |

## Fedora Provider Matrix

Package names remain owned by `scripts/dwm-packages.sh`. This document names
package profiles and runtime capabilities so future Settings code does not
duplicate Fedora package lists.

| Provider capability | Fedora path | Missing capability behavior |
| --- | --- | --- |
| Quickshell Settings frontend | `fedora:desktop` | Missing Quickshell makes the Settings UI unavailable. |
| X11 display state | `fedora:x11` | Missing RandR tools disable display controls. TearFree and NVIDIA composition remain driver-dependent. |
| NetworkManager | `fedora:desktop-optional`; enabled by the Fedora image | Missing service reports unavailable while other sections continue. |
| BlueZ and D-Bus JSON parsing | `bluez`, `systemd`, and `jq` from `fedora:desktop` plus the image service/package set | Adapter absence is a runtime unsupported state. |
| PipeWire/WirePlumber and controls | `fedora:desktop`; included by the image | Missing session services report unavailable. |
| UPower, Power Profiles, and D-Bus monitoring | `upower`, `power-profiles-daemon`, and `dbus-tools` in `fedora:desktop`; included by the Fedora image | Existing installs retain any provider of `ppd-service`; missing battery hardware or profile service disables only the corresponding Power controls. |
| DPMS and auto-lock | X11 tools plus `fedora:desktop` | Missing schemas or locker disable only lock controls. |
| Defaults and autostart | `xdg-utils` from `fedora:runtime-required`; `inotify-tools` from `fedora:desktop` | Missing XDG utilities disable only default-application controls; missing inotify keeps snapshots/actions usable but disables live refresh. |
| Themes and GTK integration | `fedora:theme`, `fedora:theme-gtk`, and optional profiles | Missing optional theme packages do not disable Settings. |
| Polkit authorization | Fedora desktop/image polkit agent and trusted helper | Missing authorization leaves read-only state available. |
| System health | Fedora/systemd providers | Missing commands, services, hardware, or authorization emit partial or restricted records. |
| Phase 6 updates | `PackageKit`, `PackageKit-glib`, and `python3-gobject` from `fedora:system-management`; included by `fedora:recommended` and the Fedora image | Missing PackageKit disables updates only and provides installation guidance; DNF or `pkcon` terminal output is never parsed as provider state. |
| Phase 6 delegated administration | `accountsservice`, `cups`, and `system-config-printer` from `fedora:system-management`; `lxqt-admin` and `dnfdragora` from `fedora:system-management-optional` | Service absence preserves unrelated state; optional delegated tools expose unavailable entry points with exact package guidance. |

## Settings Constraints Derived From the Inventory

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
- Settings discovery follows the versioned contract in
  `docs/SETTINGS-PLATFORM.md`. Connectivity, audio, and power use their own
  documented versioned protocols; other tab-separated interfaces remain
  inventory inputs, not automatically stable public APIs.
- No existing or planned operation requires passwordless broad `sudo`, and no
  QML component is assigned ownership of an elevated command.
- The complete Phase 6 ownership, cancellation, audit, recovery, and exclusion
  decisions are recorded in `docs/P6-SYSTEM-MANAGEMENT.md`.
