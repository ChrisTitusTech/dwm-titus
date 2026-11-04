# dwm-titus 0.8.0 release preparation

Status: preparation in progress; no 0.8 tag, GitHub release or replacement
public image has been published by this workflow.

## Desktop changes

- Super+Tab opens the searchable window overview. Static thumbnails are
  captured once per opening, with icon/title fallback and cleanup on close.
- Appearance provides visual layout selection, master sizing and per-tag gaps.
- Optional floating-window titlebars provide move/close controls; defaults off.
- Optional Calendar and Weather widgets default off. Weather requests require
  an explicit location and Fetch; no automatic location lookup or refresh.

All four feature PRs (#425, #424, #423, #422) merged after local validation and
independent Codex review. The user verified the overview thumbnails in their
real X11 session. See CHANGELOG.md for the other changes since 0.7.2.

## Platform and Wi-Fi

Primary images: Fedora 45 Server Network Install 1.4, x86_64, separate standard
and NVIDIA variants. Fedora 44 existing-system and desktop compatibility remains
supported. No separate new Fedora 44 image set is planned.

Fedora 45 images use Thunar instead of Path, as the user selected after the
Fedora 45 COPR endpoint returned 404. That unavailable repository is omitted;
gaming packages use distribution/RPM Fusion sources. Fedora 44 retains its
COPR/Path availability. Thunar is the fresh-account default on both versions,
even with Path installed; existing user-selected MIME preferences are preserved.

Verified upstream source SHA-256:
`a1e916f139a05955b943cf183b020780cca9c399b02b8f5ec4354c9e5c1dff1a`.
Fedora 45 signing fingerprint:
`4F50A6114CD5C6976A7F1179655A4B02F577861E`.
The signed official checksum manifest and ISO digest were independently checked.

#368 is a release gate. Both images explicitly require NetworkManager-wifi,
wpa_supplicant and wireless-regdb. Capture checks the RPMs, Wi-Fi plugin and
libraries, supplicant and regulatory database, and records their versions.
Repeat these checks in installed VMs. Keep the issue open until both replacement
public downloads and their checksums are verified; old 0.7.2 downloads remain
unchanged by a source-only fix.

## Qualification record

Pending: final source gates on Fedora 45 and Fedora 44, both factory captures,
checksummed installer images, offline installation and first-session checks.
Record exact source commits, artifact sizes/hashes, firmware mode, variant,
package inventories, X11 behavior and any failed attempts here before release.

Physical NVIDIA acceleration, Secure Boot, physical radios, audio devices,
monitor hotplug and laptop suspend remain unqualified unless new evidence is
recorded. Virtual graphics and installed Wi-Fi packages do not prove those paths.
