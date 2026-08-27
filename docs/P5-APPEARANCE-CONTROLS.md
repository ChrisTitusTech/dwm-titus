# Phase 5 Desktop Appearance Controls

## Scope

This `APPEARANCE-001` review boundary adds Settings controls for desktop font
and text scale, cursor and icon themes, GTK theme, and Qt platform theme. It
uses the already-merged personalization transaction backend and does not change
its apply/reset persistence or recovery contract. It adds one bounded repair
action for a malformed persisted override file. Panel-widget persistence and
accessibility remain later Phase 5 boundaries.

Managed-shell typography remains a separate control. Desktop application font
changes never replace `Theme.iconFontFamily`, so an ordinary Fontconfig family
cannot remove panel or menu glyphs.

## Model and UI Contract

The single root `AppearanceModel.qml` starts
`dwm-settings-personalization status` only while the Appearance pane is open.
It strictly accepts protocol version 1.0, exactly six unique selection records,
the provider and mutation records, and GTK/Qt delegation records. Closing the
pane stops pending status work. Existing file and inventory events schedule
bounded refreshes; no timer polls personalization state.

When managed X11 text scaling is active, one pane-scoped lifecycle watcher
waits for the verified `xsettingsd` process to exit. Loss or replacement of
the XSETTINGS owner therefore refreshes status without polling, and closing
Appearance stops the watcher. A startup race refreshes status once and then
suppresses further watcher attempts until the pane is reopened.
The same lifecycle record remains available for a stale managed owner after
the saved mode has returned to system-follow, so its eventual exit clears the
partial status without a manual refresh.

The status protocol also reports repair readiness. When the project-owned
override file is structurally safe but malformed, Settings can replace only
that persisted state with follow-source preferences. The repair uses the same
mutation and integration locks, journal, atomic publish, concurrent-edit hash
guard, and retained recovery data as other appearance transactions. It does
not rewrite live GSettings, xfconf, Xresources, or session environment values;
the now-unblocked apply and reset actions remain the explicit convergence path.
State beginning with a reserved, unsupported future personalization protocol
is preserved and is never offered to the destructive repair action.

Selectable font, cursor, icon, GTK, and Qt values come from the existing
pane-scoped `dwm-settings-appearance inventory` process. The UI limits long
lists to 24 entries and uses the backend's eight fixed desktop text-scale
steps. Apply is enabled only for an available candidate. Reset persists
`follow-system` for font, text scale, and icons or `follow-theme` for cursor,
GTK, and Qt. The status card keeps the effective value distinct from that saved
mode. The exact lowercase token `unknown` is reserved for malformed status and
is rejected consistently by inventory, mutation, transaction, and theme-reload
validation rather than being exposed as an asset choice.

The status protocol reports apply and reset readiness independently. In
particular, a missing optional XSETTINGS verifier disables text-scale Apply
while leaving system-follow Reset available.

For asset-backed choices, the displayed and aggregate state joins the current
and saved choices with the bounded inventory result, so a readable GSettings
value cannot hide a missing font, cursor, icon, GTK, or Qt asset. Mutation
readiness remains a separate action status and does not mislabel an otherwise
healthy read-only desktop. A system-follow font uses
the inventory's normalized family token rather than the full GSettings font
description when initializing the selector.
The 24-entry UI bound reserves entries for the effective and saved choices
before filling from discovery order, so truncation cannot preselect an
unrelated replacement. A failed or malformed status response remains
unavailable even when the independent asset inventory is healthy.

Theme, wallpaper, managed-shell font, and desktop personalization mutations
exclude one another in the root model. The helper remains the final argument
validator and transaction owner. Apply and reset stay disabled while a theme
preview or recovery transaction is active. Optional advanced GTK and Qt
buttons launch only the fixed delegated tools reported by the helper and
require its exact action-protocol acknowledgment before reporting that the
launch was requested. The asynchronous handoff never claims the editor opened;
when a tool is absent, Settings shows an explanatory capability-scoped status.

## Validation

Run:

```sh
scripts/run-tests make check-appearance
scripts/run-tests make check-quickshell-settings-xvfb
scripts/run-tests scripts/quickshell-qmllint --root config/quickshell
git diff --check
```

The static model contract covers fixed command wiring, strict protocol parsing,
candidate filtering, follow/reset actions, global action exclusion, and the
absence of a second inventory provider. The serial nested-X11 test opens
Appearance at 1280x800, waits for personalization readiness, applies `gtk3` as
the Qt backend, observes the effective and persisted values through the live
root model, resets to theme-follow, and retains the existing closed-window CPU
sample. Backend fixtures separately cover every capability, fresh-session
convergence, lock ordering, malformed state, missing tools, rollback failure,
concurrent edits, and exact preservation of unset GSettings keys.
Malformed-state repair additionally proves byte-for-byte preservation of every
other integration, refusal of a concurrent valid edit or unsafe hardlink, and
exact interrupted-state recovery.
The managed XSETTINGS fixture also proves that owner loss produces one
lifecycle event and that future personalization protocol data is preserved
byte for byte.
