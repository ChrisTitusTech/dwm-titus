# Phase 3 Connectivity Evidence

## Scope

This evidence qualifies `CONN-001`, `NET-001`, and `BT-001` on Fedora Linux 44
x86_64 in the active managed X11 session. Network and Bluetooth state is shared
between the panel and Settings by one root-scoped model per provider. No
Settings pane owns a duplicate long-lived monitor.

## Automated Validation

The connectivity suites cover protocol compatibility, malformed and unavailable
providers, action failures, stable Bluetooth identities, bounded commands,
secret-file cleanup, and Settings lifecycle. The full repository build and test
commands passed from a clean managed test workspace before merge.

The monitor lifecycle test kills the owning shell process and verifies that the
helper and its `nmcli monitor` child both terminate. The same parent-bound
lifecycle is used by the media watcher.

## Live Network Qualification

NetworkManager reported the active Ethernet connection
`3519b659-6ec0-47e0-aa59-aa566e5bcaae` on `enp6s0`, plus the externally managed
`virbr0` bridge. Opening Network Settings exposed three devices and the saved
profiles through the shared model. A bounded rescan completed without changing
the active connection set.

This machine has no Wi-Fi adapter. The real Wi-Fi scan therefore completed with
an empty result, and Wi-Fi association, password authentication, and cancellation
could only be qualified by fixtures and helper tests. Enterprise, hidden, and
VPN editing remains explicitly delegated to NetworkManager's trusted editor.

## Live Bluetooth Qualification

BlueZ exposed adapter `/org/bluez/hci0` at `08:B4:D2:6A:D9:8D`. A bounded
eight-second discovery completed successfully and left the adapter with
`Discovering=false`. The paired and trusted Xbox Wireless Controller retained
canonical address `68:6C:E6:6E:D6:8A` and remained disconnected. Discovery also
found transient nearby devices without changing their paired or trusted state.

The real adapter, discovery, and known-device paths are qualified. Pairing a new
device and recovering a failed pairing were not performed because no sacrificial
device was available; those paths remain covered by stable-identity fixtures and
action-failure tests.

## Process and Live-Install Qualification

The final development synchronization created rollback backup
`20260821T214412Z-756866` and verified every managed file before restarting the
managed Quickshell instance. A subsequent deliberate restart removed the former
NetworkManager and media watcher children and created exactly one current
`nmcli monitor` and one current `playerctl --follow` child. No discovery process
or scan remained after closing the owning operation.
