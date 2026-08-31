# Phase 5 Accessibility Capability Contract

## Scope

This `ACCESSIBILITY-001` review boundary replaces the generic accessibility
placeholder in Settings discovery with five independently truthful capability
records. It defines the read-only contract only. Settings controls, persistent
contrast and reduced-motion state, and notification-policy mutation remain
separate review boundaries.

The records use the existing `settings-protocol 1` capability shape and appear
in the Appearance section:

| Capability | Provider | Current contract |
| --- | --- | --- |
| `accessibility-text-scale` | `dwm-settings-personalization` | Publishes the exact `available`, `partial`, or `unavailable` state and detail from one complete version 1 `text-size` selection. |
| `accessibility-contrast` | `quickshell-theme` | `partial`: semantic colors exist, but a dedicated high-contrast policy is not configured. |
| `accessibility-reduced-motion` | `quickshell-theme` | `unsupported`: managed animations do not yet expose a reduced-motion policy. |
| `accessibility-notifications` | `quickshell-notifications` | `partial`: D-Bus ownership and history exist, but notification policy controls are not configured. |
| `accessibility-input` | `x11` | `partial` when the managed input provider and `xinput` exist; otherwise `unavailable`. |

## Failure Isolation

Discovery gives the personalization status request a five-second TERM deadline
and escalates to KILL after one additional second. It accepts text-scale state
only when the first record is exactly `personalization-protocol 1 0`, exactly
one valid six-field `text-size` selection is present, and exactly one
`complete status` record is last. Available or partial selections require a
live value, every selection requires a persisted mode and detail, and an
unavailable selection may have an empty live value. A missing or unresponsive
helper and incomplete, duplicate, or unsupported output make only text scaling
unavailable. All emitted fields still pass through the existing
settings-protocol field sanitizer.

The boundary adds no QML object, timer, subscription, state file, package,
privileged helper, or mutation action. The existing generic capability-card
path renders the new records without changing shell lifecycle behavior.

## Validation Evidence

The exact continuation working tree passed on Fedora 44:

```text
shellcheck scripts/dwm-settings-provider tests/test-settings.sh
shfmt -d scripts/dwm-settings-provider tests/test-settings.sh
tests/test-settings.sh
scripts/run-tests make clean all
scripts/run-tests
shellcheck install.sh scripts/*.sh tests/*.sh
shfmt -d install.sh scripts/*.sh tests/*.sh
mdbook build docs --dest-dir <temporary-output>
git diff --check
```

The focused contract covers all five healthy records, exactly five emitted
accessibility records, missing input tooling, unresponsive and missing
personalization providers, incomplete or duplicate responses, empty required
fields, and the valid unavailable state with no live scale. The full suite
passed its clean build, nested-X11 Settings workflow, repeated install, release
archive, and managed-workspace cleanup. The nested-X11 sample measured a 0.067
percentage-point CPU delta. Hosted exact-head evidence is recorded before this
boundary is merged.

No logout or login is required for this read-only protocol boundary. A manual
Settings smoke test is useful after installation but is not required before
review because the existing capability-card renderer is unchanged.
