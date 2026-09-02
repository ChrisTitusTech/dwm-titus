# Phase 5 Accessibility Capability Contract

## Scope

This `ACCESSIBILITY-001` review boundary replaces the generic accessibility
placeholder in Settings discovery with five independently truthful capability
records. It originally defined the read-only contract only. Later review
boundaries added Settings controls and persistent contrast, reduced-motion,
input, and notification policy.

Subsequent `ACCESSIBILITY-001` boundaries added managed-shell contrast and
motion policy plus dedicated Settings controls. The table below reflects the
current provider contract while the validation evidence remains scoped to the
original capability boundary.

The records use the existing `settings-protocol 1` capability shape and appear
in the Appearance section:

| Capability | Provider | Current contract |
| --- | --- | --- |
| `accessibility-text-scale` | `dwm-settings-personalization` | Publishes the exact `available`, `partial`, or `unavailable` state and detail from one complete version 1 `text-size` selection. |
| `accessibility-contrast` | `dwm-accessibility-settings` | `available` only when one bounded, complete version 1 status reports safe mutation readiness; otherwise `unavailable`. |
| `accessibility-reduced-motion` | `dwm-accessibility-settings` | `available` only when one bounded, complete version 1 status reports safe mutation readiness; otherwise `unavailable`. |
| `accessibility-notifications` | `dwm-notifications` or `dbus` | `available` only when the session notification owner's machine-readable PID resolves to Quickshell running the managed configuration. An unrelated owner is `partial`; no owner is `unavailable`. Settings watches the D-Bus ownership signal while Appearance is open and refreshes this capability when the owner changes. |
| `accessibility-input` | `dwm-settings-input` | `available` when bounded managed input discovery and `xkbset q` both succeed; missing or unresponsive XInput or XKB tooling reports the scoped `unavailable` reason. |

## Failure Isolation

Discovery gives the personalization status request a five-second TERM deadline
and escalates to KILL after one additional second. It accepts text-scale state
only when the first record is exactly
`personalization-protocol<TAB>1<TAB>0`, exactly
one valid six-field `text-size` selection is present, and exactly one
`complete<TAB>status` record is last. Records are tab-delimited. Available or partial selections require a
live value, every selection requires a persisted mode and detail, and an
unavailable selection may have an empty live value. A missing or unresponsive
helper and incomplete, duplicate, or unsupported output make only text scaling
unavailable. All emitted fields still pass through the existing
settings-protocol field sanitizer.

Contrast and motion discovery independently validates the managed
accessibility helper's state, two setting records, mutation readiness, and
terminal completion. Unknown version 1 record types are ignored. Missing,
unresponsive, malformed, future-version, or unsafe state makes only those two
capabilities unavailable.

The original capability boundary added no QML object, timer, subscription,
state file, package, privileged helper, or mutation action. Later boundaries
own the event-driven model, persistent Settings controls, fixed XKB actions
documented in `P5-INPUT-ACCESSIBILITY.md`, and notification policy documented
in `P5-NOTIFICATION-POLICY.md`.

## Validation Evidence

The exact continuation working tree passed on Fedora 44. The historical
documentation build has since been replaced by the current Astro validation
shown here:

```text
shellcheck scripts/dwm-settings-provider tests/test-settings.sh
shfmt -d scripts/dwm-settings-provider tests/test-settings.sh
tests/test-settings.sh
scripts/run-tests make clean all
scripts/run-tests
shellcheck install.sh scripts/*.sh tests/*.sh
shfmt -d install.sh scripts/*.sh tests/*.sh
npm --prefix docs ci
npm --prefix docs run build
git diff --check
```

The focused contract covers all five healthy records, exactly five emitted
accessibility records, missing or unresponsive input tooling, unresponsive and missing
personalization providers, incomplete or duplicate responses, empty required
fields, unsupported persisted modes, the valid unavailable state with no live
scale, and both present and missing notification D-Bus owners. The full suite
passed its clean build, nested-X11 Settings workflow, repeated install, release
archive, and managed-workspace cleanup. The nested-X11 sample measured a 0.000
percentage-point CPU delta. Hosted exact-head evidence is recorded before this
boundary is merged.

No logout or login is required for this read-only protocol boundary. A manual
Settings smoke test is useful after installation but is not required before
review because the existing capability-card renderer is unchanged.
