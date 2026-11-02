# Clipboard history privacy

## Policy and limits

The optional history backend is `dwm-clipboard-observer`. It remains inactive
unless a frontend explicitly starts it after the user enables history. It has
no history file and never saves text itself. Capture and persistence are
separate opt-ins. Installing this backend does not enable either.

Ordinary browser and terminal copies are eligible. The maintainer explicitly
chose this behavior after reviewing the limitation: **unmarked password-manager
extension copies can look identical to ordinary browser text and may enter
history**. The same limitation applies to terminal selections containing
secrets and detached generic clipboard helpers that have lost their origin.
This must be disclosed before users enable capture. A marker or source check
cannot guarantee exclusion of all passwords.

Identifiable native password-manager applications are excluded even without
markers. This includes executable names identifying Bitwarden, KeePass,
KeePassXC, KeePassX, 1Password, Proton Pass, NordPass, Enpass, Dashlane, LastPass,
Keeper Desktop, and named CLI clients such as bw, rbw, pass, gopass and kpcli.
Bounded launch metadata detects interpreter-hosted clients such as
`mono /path/KeePass.exe`, `node /usr/bin/bw`, or `perl /usr/bin/kpcli`.
Unrecognized interpreter options fail closed rather than risk mistaking an
option operand for the application entrypoint. Bounded same-user parent ancestry
also rejects helpers still descended from a detected manager. Unknown source
identity fails closed. Application names are best-effort identification: renamed
executables, detached helpers and applications not identified by this policy
may evade source exclusion. `dwm-clipboard-observer --policy` prints the limit.

This does not prevent normal copying and pasting. The observer does not own,
clear or replace the system clipboard. It simply declines to retain content.
It observes CLIPBOARD only; selecting text into PRIMARY is not captured.

X11 cannot preserve original provenance after text is pasted into another
application and copied again. This policy does not defend against a hostile
client in the same X11 session or detect secrets by examining their contents.
No password-pattern heuristic or user-window-title guess is used.

## Verification before payload access

1. Subscribe to XFixes ownership events, without polling. Ignore the clipboard
   that already existed when the observer started. Subscription initialization
   discards startup events before the ready record; no timestamp cutoff remains.
2. Ask XRes 1.2 for the owner's local client PID. Never trust `_NET_WM_PID`,
   `WM_CLASS`, a window title or focused application as proof of origin.
3. Verify same-user `/proc` identity, executable inode and process start time;
   inspect the bounded executable/launch metadata and parent ancestry. Unknown,
   unreadable, excessive-depth and password-manager sources are rejected.
4. Request only bounded TARGETS metadata. Reject any advertised sensitive
   marker, including `x-kde-passwordManagerHint`, regardless of its value.
5. Only then request UTF8_STRING, capped at 65,536 bytes. Reject INCR, partial,
   malformed, invalid UTF-8 and oversized replies. Selection requests and
   polled replies have a one-second deadline; the frontend also bounds startup.
6. Recheck owner, process identity and event generation before emitting text.
   Repeated ownership notifications from the same window invalidate stale
   reads. Use a fresh requestor window per transaction to reject late replies.

The observer emits one ASCII JSON object per stdout line: a startup
`{"event":"ready","protocol":1}` record, followed only by admitted
`{"event":"text","text":"..."}` records. Unicode is escaped without loss.
It prints no clipboard data or launch arguments to stderr. Core dumps are
disabled. The frontend must bound protocol buffering, reject malformed records,
stop on disabled capture, and never use a raw clipboard listener as fallback.
No text is emitted for denied sources. Missing extensions or unsupported
displays make startup fail with a generic explanation.

## Upstream behavior

Verified source snapshots:

- [Bitwarden desktop](https://github.com/bitwarden/clients/blob/1dc3ab751779234d3e974afb9108223a0b285213/apps/desktop/src/platform/main/clipboard.main.ts)
  passes a password flag into native clipboard handling;
  [its Linux implementation](https://github.com/bitwarden/clients/blob/1dc3ab751779234d3e974afb9108223a0b285213/apps/desktop/desktop_native/core/src/clipboard/arboard_backend.rs)
  requests history exclusion.
- [Bitwarden's browser implementation](https://github.com/bitwarden/clients/blob/1dc3ab751779234d3e974afb9108223a0b285213/apps/browser/src/platform/services/browser-clipboard.service.ts)
  can use plain clipboard text or textarea copying without sensitivity metadata.
- [KeePassXC](https://github.com/keepassxreboot/keepassxc/blob/ba7473c0bbb14364325cbc15cce2ecb6b72a72f9/src/gui/Clipboard.cpp)
  advertises `x-kde-passwordManagerHint=secret` on Unix.

## Validation

`scripts/run-tests make check-clipboard-observer` runs native Xvfb owners and
tests normal browser/terminal admission, native manager exclusions, marker
rejection before text access, forged process properties, same-owner changes,
timeouts, oversized and INCR transfers, and missing XRes. No real vault or
credentials are used. Native protocol fixtures establish policy behavior;
they do not claim every released Bitwarden/KeePass/browser package was manually
exercised.
