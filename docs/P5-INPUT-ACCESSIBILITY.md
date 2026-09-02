# Phase 5 XKB Input Accessibility

## Scope

This `ACCESSIBILITY-001` review boundary adds practical session-wide X11 input
accessibility controls without moving desktop policy into dwm or adding a
poller. The existing Input Settings pane exposes accessibility shortcuts,
sticky keys, slow keys, bounce keys, and mouse keys through Fedora's `xkbset`.

## Provider Contract

`dwm-settings-input discover` keeps `input-protocol 1` and appends one fixed
device record with key `accessx`, XID `session`, and kind `accessibility`. Its
five boolean setting records are sourced from one `LC_ALL=C xkbset q` snapshot.
An unavailable or incomplete query leaves ordinary XInput discovery intact and
emits an explanatory unsupported record for this group.

Mutation accepts only the five named settings and boolean values. Each maps to
one fixed `xkbset` option; callers cannot supply an arbitrary option or command.
The existing mutation lock and 15-second preview capture the live XKB value,
automatically restore it on timeout, and retain recovery state if rollback
fails. Keep stores the value and its first captured baseline in the existing
user-owned `input-settings.conf`. Reset restores that baseline and removes only
the selected record. Session startup replays kept values idempotently.

`xkbset` is part of the Fedora X11 and source-update package profiles and both
Kickstart variants. Capability discovery advertises the mutation only after
bounded managed input discovery and a responsive XKB query. Missing XInput and
missing or unresponsive XKB tooling have distinct unavailable details.

## UI and Lifecycle

The generic Input Settings card renders the session group without a second QML
model or provider. Every toggle is keyboard-focusable and has a setting-specific
accessible description. The card explains preview, persistence, and login
behavior. Refresh is explicit; the feature adds no idle timer. Udev continues
to drive physical-device refresh and replay, while the session-scoped AccessX
state refreshes after each action or an explicit pane refresh.

## Validation

Focused validation covers discovery, every fixed record, missing tooling,
preview/revert, failed apply cleanup, keep, session replay, reset, provider
capability isolation, Fedora package mapping, Kickstart parity, QML lint, and a
nested-X11 Settings run. A real-session preview/revert must additionally prove
that the selected XKB state changes and returns to its exact starting value.
