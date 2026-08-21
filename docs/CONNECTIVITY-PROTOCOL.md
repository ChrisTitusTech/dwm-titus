# Connectivity Provider Protocol

The shared Network and Bluetooth models consume tab-separated, append-only
records from `dwm-quickshell-network snapshot` and
`dwm-quickshell-controls bluetooth-snapshot`. The first record must be:

```text
connectivity-protocol<TAB>1<TAB>minor
```

Consumers require major version `1`, ignore the minor version, ignore unknown
record types, and ignore trailing fields. They reject a missing header, another
major version, or a known record missing a required field. Empty required
fields use `-`; record text must not contain tabs or newlines.

## Common record

`provider` requires domain, availability, capability class, and detail:

```text
provider<TAB>network|bluetooth<TAB>available|restricted|unavailable<TAB>read-only|delegated<TAB>detail
```

Availability describes readable state. The capability class independently
states whether Settings is only reading state or may request a fixed action.
A provider failure affects only its owning Settings section.

## Network records

- `network-device`: interface, type, state, active connection.
- `network-profile`: name, UUID, NetworkManager type, active yes/no, interface.
- `wifi-network`: active marker, BSSID, SSID, signal, security, channel,
  interface.

NetworkManager state uses explicit `nmcli --terse --escape yes -f ...` fields.
Wi-Fi scans are bounded to 10 seconds, profile and Wi-Fi activation to 90
seconds, and disconnect/forget to 15 seconds. Hidden, enterprise, advanced, and
VPN editing remains delegated to `nm-connection-editor`.

Secured Wi-Fi secrets cross the QML/helper boundary only on stdin. The helper
creates a mode-0600 `nmcli --passwd-file`, clears the QML value after writing,
and removes the file on success, failure, timeout, cancellation, or signal.

## Bluetooth records

- `bluetooth-support`: daemon, adapter, or operations; state; detail.
- `bluetooth-adapter`: object path, address, alias, powered, discovering,
  pairable.
- `bluetooth-device`: object path, canonical address, alias, paired, trusted,
  connected, adapter object path.

Bluetooth state comes from BlueZ `ObjectManager.GetManagedObjects` through
`busctl --json=short`; `jq` transforms that D-Bus JSON into the protocol. Fixed
actions use `bluetoothctl`, validate a canonical device address, and preserve
that identity through progress and failure state. Discovery is bounded and
always requests `scan off` during normal exit, failure, cancellation, or a
signal.

## Lifecycle

The panel and Settings receive the same root-scoped Network and Bluetooth
models. One root NetworkManager monitor and one root BlueZ D-Bus monitor drive
shared refreshes. Settings does not add another long-lived monitor. Closing a
Settings section terminates only its own scan or action; closing the shell also
terminates the root subscriptions. The long-lived shell helpers bind their
child commands to the originating Quickshell process identity (PID plus process
start time), so even an ungraceful shell exit cannot leave an `nmcli monitor`
or media subscription behind.
