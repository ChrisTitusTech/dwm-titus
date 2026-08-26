# Phase 5 Managed Font Controls

## Scope

This `APPEARANCE-001` review boundary adds managed-shell font family and text
scale persistence. Cursor, icon, GTK, and Qt mutations remain in the next
toolkit-owned boundary so this change does not mix shell-owned state with
external application configuration.

## Contract

`dwm-settings-font` owns only
`${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/font.conf`. The version 1.0 file
contains one exact Fontconfig family and one of `0.80`, `0.90`, `1.00`, `1.10`,
`1.25`, or `1.50`. Missing or malformed state keeps the previous shell
contract: MesloLGS Nerd Font Mono at 100 percent.

Selections must resolve to the exact requested family while covering the basic
printable interface character set. The MesloLGS Nerd Font Mono, MesloLGS Nerd
Font, and MesloLGS NF names are treated as equivalent aliases. Icon-only fonts
are therefore rejected even when Fontconfig can discover them.

The helper exposes `status`, `mutation-ready`, `preview`, `keep`, `revert`,
`abandon`, `apply`, and `reset`. Writes are serialized, atomic, mode-preserving,
and restricted to current-user regular files and directories. Preview stores
the exact prior bytes and mode, arms an independent 5-120 second watchdog, and
restores only while the preview hash still matches. An external edit therefore
becomes an explicit failed preview instead of being overwritten. The deadline
uses boot-aware monotonic uptime, and persisted watchdog identity includes the
boot ID so a reused process ID after reboot is never signaled.

Atomic replacement uses GNU `mv --exchange --no-copy`, available in coreutils
9.5 and newer; the Fedora 44 qualification base supplies a compatible version.
`mutation-ready` keeps the controls unavailable when the exchange operation is
not supported by the installed command or filesystem.

The root Appearance model watches the managed file and preview marker. It
updates `Theme.qml` without polling and applies the family and scale to every
managed shell surface. The icon family remains fixed to the shipped Nerd Font,
so selecting an ordinary interface font cannot remove icon glyphs.

## Validation

Run:

```sh
scripts/run-tests make check-appearance
scripts/run-tests make check-quickshell-settings-xvfb
scripts/run-tests tests/test-quickshell-appearance-model.sh
shellcheck scripts/dwm-settings-font tests/test-dwm-settings-font.sh
shfmt -d scripts/dwm-settings-font tests/test-dwm-settings-font.sh
```

Focused fixtures cover invalid families and scales, exact family validation,
mode preservation, apply, reset, keep, explicit and timed rollback, watchdog
lock isolation, frozen-clock exit, reboot-safe process identity, malformed
state, external-change refusal, and symlink rejection. The nested-X11 test
proves file-event convergence, live type-scale updates, preview countdown,
revert, reset, and the existing closed-window CPU sample.
