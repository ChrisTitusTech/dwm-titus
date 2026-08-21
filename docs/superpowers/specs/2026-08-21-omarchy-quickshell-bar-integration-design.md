# Omarchy Quickshell Bar Integration Design

## Purpose

Integrate an Omarchy-inspired Quickshell bar and its Bluetooth, Network, and
Volume panel presentation into dwm-titus while preserving dwm-titus's Fedora
X11 architecture, managed Quickshell process, existing desktop surfaces, and
installation lifecycle.

The integration is developed and reviewed on the `qs-integ` branch. It must be
self-contained in the dwm-titus repository and must not depend on an installed
Omarchy system.

## Architectural Boundary

The implementation remains inside dwm-titus's existing managed Quickshell
process and configuration tree.

- Retain the existing dwm-titus `ShellRoot`, X11 state provider, models, IPC
  handlers, startup path, installer, and process ownership.
- Retain the existing Control Center, launcher, Settings, notifications, power
  menu, and `RunningAppsArea`.
- Adapt only the required Omarchy bar and panel presentation patterns.
- Extend dwm-titus models and helpers only where required by the approved
  behavior.
- Do not import the Omarchy plugin host, `shell.json` configuration system, or
  unrelated plugins and services.
- Do not depend on `/usr/share/omarchy`, Omarchy commands, Hyprland, Arch Linux,
  Wayland layer-shell behavior, or `wl-copy`.
- Preserve one managed Quickshell process for the entire dwm-titus session.
- Attribute adapted upstream code and retain all applicable license notices.

## Bar Window and Desktop Geometry

The bar retains dwm-titus's current X11 panel contract.

- Keep one top-anchored `PanelWindow` per active monitor.
- Keep the existing 30 px panel height and 30 px exclusive zone.
- Preserve the existing X11 dock/window classification and dwm window rules.
- Tiled, floating, and maximized applications must not occupy or cover the
  reserved bar region.
- Preserve the existing fullscreen exception behavior.
- Do not adopt Omarchy's Hyprland-specific surface or positioning behavior.

## Bar Layout

The bar has exactly three zones in this order.

### Left

1. CTT logo. Left-click opens the existing dwm-titus Control Center.
2. Workspaces.
   - The primary monitor always displays workspaces 1 through 9.
   - Secondary monitors retain their monitor-local workspace sets.

### Center

The center contains only the clock.

- Format: `ddd, d MMM HH:mm`
- Time is 24-hour.
- The clock has no left-click, right-click, middle-click, or wheel action.
- There is no language indicator or alternative center widget.

### Right

1. Existing dwm-titus `RunningAppsArea`
2. Bluetooth
3. Network
4. Volume

The system tray, active-window title, status segments, battery, power widget,
and every other existing bar module are removed from the bar layout. Their
underlying non-bar functionality remains unchanged unless this specification
explicitly says otherwise.

## Bar Appearance and Interaction

Use the resolved palette from Abs's running Omarchy Tokyo Night shell:

- Background: `#1a1b26`
- Foreground and inactive: `#a9b1d6`
- Active and accent: `#7aa2f7`
- Urgent and attention: `#f7768e`

Every text label and glyph rendered inside the bar is exactly 11 px, except
the Network and Volume glyphs, which are 14 px. Panel typography is not
constrained to 11 px and follows the adapted Omarchy panel scale.

No bar item exposes a hover tooltip. This applies to the logo, workspaces,
clock, running applications, Bluetooth, Network, and Volume. Panel-internal
labels and accessible descriptions remain allowed.

## Dynamic Network Bar Icon

The Network module owns the required network glyphs locally and updates from
NetworkManager state changes.

- Connected wired/LAN interface: Ethernet icon
- Otherwise connected Wi-Fi: signal-strength-dependent Wi-Fi icon
- Otherwise: disconnected-network icon
- When wired and Wi-Fi are both connected, wired takes priority, matching
  Omarchy's current default-route behavior.

The panel continues to expose relevant wired and wireless information.

## Dynamic Volume Bar Icon

The Volume module owns its mute, low, medium, and high glyph definitions
locally. It updates immediately after bar-wheel input, panel-slider input,
mute actions, and external PipeWire state changes.

- Muted or 0 percent: mute icon, even when PipeWire's mute flag is false
- 1 through 33 percent: low-volume icon
- 34 through 66 percent: medium-volume icon
- 67 percent and above: high-volume icon

Scrolling upward over the Volume module raises volume. Scrolling downward
lowers volume. Existing bounded volume-step behavior remains the authority for
the amount changed.

## Shared Panel Contract

Bluetooth, Network, and Volume adapt the current Omarchy panel visual language
and interaction design to dwm-titus's existing X11 models and helpers.

- Remove decorative subtitle or rotating status phrases from all three panels.
- Remove the phrase components from layout completely; do not retain hidden
  rows, margins, or placeholders.
- Give every panel a continuous 1 px border using `#7aa2f7`.
- Anchor each panel to its corresponding bar module.
- Opening one panel closes the other two.
- Escape and an outside click close the active panel under X11.
- Derive each panel's width and height independently from its real content.
- Short content produces a compact panel without unused regions.
- Width must preserve actual controls, names, metrics, and state labels without
  clipping.
- Cap panel height to the usable screen area. If a dynamic device or network
  list exceeds the remaining height, only that list scrolls; the header and
  primary controls remain fixed.
- Recalculate popup anchoring after dimensions change.

Missing services and empty lists must produce compact, explicit states rather
than breaking the shell or leaving blank fixed-size surfaces. Failed actions
must clear busy state, keep the panel usable, and display a specific inline
error.

## Network Panel

The Network panel preserves the approved portion of Omarchy's current layout
and behavior.

### Included

- Dynamic wired, Wi-Fi, and disconnected state
- Current connection header and connection details
- Gateway and IP address
- Ping latency and packet loss
- Current receiving and sending rates
- Downloaded and uploaded totals
- Wi-Fi enable and disable control
- Known Networks and Other Networks sections
- Network scanning
- Signal and security state
- Connect, disconnect, and forget actions
- Password and enterprise credential flows
- Keyboard and pointer interaction
- Compact empty, offline, and unavailable states

### Explicitly excluded

- Decorative connection subtitle/status phrase such as `ROUTING CRUMBS`
- Wi-Fi QR/barcode button and all QR functionality
- Network speed-test button and all speed-test functionality
- Entire DNS Provider section and all DNS-changing functionality

The excluded items must not reserve any layout space. Known Networks moves
directly below the retained connection information and separator.

Network state changes should be event-driven through NetworkManager where
possible. Bounded periodic sampling is allowed only for throughput, traffic
totals, latency, and packet loss. Sampling processes must not overlap.

## Bluetooth Panel

The Bluetooth panel preserves Omarchy-equivalent device presentation and
Bluetooth management while using dwm-titus's existing BlueZ-facing helper and
model boundary.

- Preserve power, scan, pair, trust, connect, disconnect, device-state, and
  supported battery information.
- Remove the decorative subtitle/status phrase and its layout space.
- Handle unavailable adapters and empty device lists compactly.
- Do not introduce an Omarchy or Wayland-specific Bluetooth dependency.

## Volume Panel

The Volume panel preserves Omarchy-equivalent audio presentation and supported
controls while using dwm-titus's existing PipeWire/WirePlumber boundary.

- Preserve output volume, mute, slider, output-device selection, microphone,
  and existing media controls.
- Remove the decorative subtitle/status phrase and its layout space.
- Keep bar-wheel and panel-slider state synchronized with external audio
  changes.
- Handle missing audio services and empty device lists compactly.

## Update Model and Resource Use

- Prefer Quickshell service signals, D-Bus state, NetworkManager monitoring,
  PipeWire events, BlueZ events, X properties, and long-lived bounded watch
  streams over polling.
- Poll only inherently sampled network metrics and the minute clock.
- Do not run overlapping timer-triggered processes.
- Do not retain hidden heavyweight models solely for the bar.
- The complete managed Quickshell process must remain near idle when panels and
  launcher surfaces are closed.

## Delivery Phases

### Phase 1: Bar Integration and Geometry

Implement the final bar layout, reserved X11 geometry, colors, 11 px bar
typography, tooltip removal, workspace rules, running applications, dynamic
Network and Volume icons, volume wheel behavior, and links to the existing
dwm-titus panels.

Phase 1 is accepted only after layout, multi-monitor behavior, application
reservation, fullscreen behavior, Control Center launch, running applications,
dynamic icons, single-process ownership, and idle resource use are verified.

### Phase 2: Omarchy-Style Panels

Adapt the Bluetooth, Network, and Volume panels, remove their subtitle phrases,
apply the 1 px borders, implement adaptive sizing and bounded list scrolling,
and complete the approved behavior and Network exclusions.

Phase 2 is accepted only after all actions, state transitions, popup anchoring,
mutual exclusion, short and long lists, small-screen behavior, multi-monitor
behavior, credentials, external service changes, and failure states are
verified.

### Phase 3: Hardening and Owner Handoff

Resolve integration defects found by real X11 testing, complete dependency and
installer declarations, add attribution, update documentation, and produce
owner-facing installation and acceptance instructions. New feature ideas are
outside this phase and require separate follow-up scope.

## Validation Contract

Every phase uses test-first changes and runs the smallest focused tests before
the relevant broader suite.

- Source and fixture tests for state parsing and layout contracts
- QML lint through `scripts/quickshell-qmllint --root config/quickshell`
- Existing affected Quickshell tests
- New nested-X11 tests for bar and popup behavior
- Manual real-X11 visual and interaction acceptance
- Single managed Quickshell process verification
- Near-idle process verification while transient surfaces are closed

Final validation includes:

```sh
scripts/run-tests make clean all
scripts/run-tests
```

Installer or package-map changes also require staged installation and both
Kickstart variants' package validation. Static and nested-X11 checks do not
replace the final real-session acceptance pass.

## Dependencies

Existing runtime dependencies reused by the integration include Quickshell,
NetworkManager, BlueZ, PipeWire, PipeWire PulseAudio compatibility,
WirePlumber, `pulseaudio-utils`, D-Bus/X11 utilities, and the configured Nerd
Font support.

New runtime capabilities to declare explicitly:

- `iproute` for `ip`, route, gateway, address, and interface information
- `iputils` for bounded `ping` latency and packet-loss sampling

Development and test dependencies required for the planned validation:

- `qt6-qtdeclarative-devel`
- `xorg-x11-server-Xvfb`
- `ShellCheck`
- `shfmt`

The shared Fedora package map, standard Kickstart, NVIDIA Kickstart,
dependency checker, and documentation must agree on any package classified as
required. The integration adds no QR, speed-test, DNS-management, Omarchy, or
Hyprland dependency.

## Owner Handoff

The final branch handoff must include:

- Exact dependency classifications and installation command
- File and behavior summary by phase
- Attribution and licensing information
- Automated test commands and results
- Real-X11 test procedure and observed results
- Known limitations, if any
- Rollback instructions that restore the previous managed Quickshell tree

Only the `qs-integ` branch is pushed for review and testing. No production or
current Omarchy configuration is modified as part of this integration.
