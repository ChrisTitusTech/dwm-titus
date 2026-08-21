# Phase 3 Audio Evidence

## Scope

This evidence qualifies `AUDIO-001`, `AUDIO-002`, and the audio portion of
`CA-VALIDATE` on Fedora Linux 44 x86_64 in the active managed X11 session.
Hardware serials and stable device identifiers are intentionally omitted.

## Automated Validation

The helper fixtures cover multiple outputs, a non-monitor input, monitor-source
filtering, an application stream, no-audio state, malformed JSON, bounded
percentages, action arguments, and subscription startup. The source contract
covers native-first selection, the one-shot three-second fallback grace period,
source and mutation generations, fallback recovery, one shared root model, and
Settings lifecycle.

The following gates passed from managed disposable workspaces:

- `scripts/run-tests make clean all`
- `scripts/run-tests`
- ShellCheck and shfmt for the changed helper and tests
- `scripts/quickshell-qmllint --root config/quickshell`

QML lint retained only the existing `PanelTooltip` incomplete-type and
`RunningAppsArea` property warnings. The full suite passed its nested-X11,
packaging, staged-install, preservation, and release checks.

## Live PipeWire Qualification

Native `Quickshell.Services.Pipewire` initialized successfully. Audio Settings
reported three outputs, four non-monitor inputs, and no stream before playback.
Changing the default output volume externally from 30 to 31 percent updated the
panel model without reopening Settings; the value then returned to the exact
30-percent baseline. The default microphone was muted and unmuted through the
fixed helper, and both the Settings model and panel returned to the original
unmuted state.

A temporary silent FFmpeg playback stream appeared in Settings. Its fixed
stream identity accepted a 42-percent volume change and mute action, after which
the exact process was terminated and the stream count returned to zero. No
audio fallback subscription was present while native PipeWire was healthy.

## Lifecycle and Idle Qualification

After a managed Quickshell restart, the shell held exactly one parent-bound
NetworkManager monitor and one parent-bound media subscription. Every Settings
section was opened in sequence and the window was closed. There were no scans,
audio fallback subscriptions, or application streams left afterward.

The 30-second closed baseline and the 30-second sample after the complete
open/close cycle each measured 0.000 percent of one CPU for Quickshell, for a
0.000 percentage-point delta against the 0.5-point limit.

## Remaining Hardware Limits

The active host has no Wi-Fi adapter, so real association and authentication
remain fixture-qualified. The real Bluetooth adapter and discovery paths were
qualified, but pairing recovery remains fixture-qualified because no
sacrificial device was available. These limitations are connectivity hardware
limits and do not reduce the completed real PipeWire audio qualification.
