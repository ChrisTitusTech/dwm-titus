# Audio Provider Protocol

## Purpose

`dwm-quickshell-controls audio-snapshot` provides a bounded, versioned snapshot
of the PipeWire PulseAudio compatibility interface for the root-scoped
Quickshell controls model. Native `Quickshell.Services.Pipewire` signals remain
authoritative for the default output, default input, volume, and mute state.
The snapshot supplies the output, non-monitor input, and application-stream
inventories used by Settings.

## Records

Records are tab-separated. Descriptions are normalized so embedded tabs and
newlines cannot create additional fields. Consumers require the protocol major
version and required fields, ignore unknown record types and trailing fields,
and clear the owning inventory when required records are malformed.

```text
audio-protocol  1  0
provider        audio  STATE  ACCESS  DETAIL
audio-output    NAME   DESCRIPTION  DEFAULT  MUTED  PERCENT
audio-input     NAME   DESCRIPTION  DEFAULT  MUTED  PERCENT
audio-stream    INDEX  APPLICATION  DESCRIPTION  MUTED  PERCENT
```

`STATE` is `available`, `restricted`, or `unavailable`. `ACCESS` describes the
read-only or delegated user-session boundary. Boolean fields use `yes` or `no`,
and percentages are bounded to 0 through 100. Monitor sources are excluded from
the input inventory. Provider and action commands use three- or fifteen-second
bounds respectively.

## Event and Fallback Contract

The shared controls model uses native PipeWire signals whenever its default
sink is ready. If native initialization has not completed after one non-repeating
three-second grace period while the panel or Audio Settings is open, it starts
one parent-bound `pactl subscribe` fallback. Every source transition increments
a generation; events from an older generation are ignored. Native recovery
stops the fallback, and closing the last consumer stops its grace timer and
fallback process. A stopped fallback is retried after a bounded three-second
delay rather than by polling.

All mutations are serialized, tagged with their UI origin and a monotonic
generation, and applied only when the completing generation is current. Model
updates do not invoke actions, so echoed native events update both surfaces
without feeding a second mutation back to PipeWire.

## Failure Boundaries

Missing `pactl` or `jq`, a service loss, timeout, or malformed JSON produces an
audio-only unavailable record. Malformed protocol values clear audio inventory
instead of retaining stale success. Media and Bluetooth state use independent
provider paths and remain available when audio fails.
