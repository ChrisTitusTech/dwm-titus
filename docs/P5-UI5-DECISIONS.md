# Phase 5 UI-5 Candidate Decisions

Date: 2026-09-02

## Decision Boundary

UI-5 is an optional experience-integration boundary, not a Phase 5 exit
criterion. A candidate is adopted only when it has a defined product consumer,
an X11-native event source, explicit data ownership, a bounded lifecycle and
privacy model, and a justified Fedora package impact. An adopted candidate
would be implemented and qualified in its own pull request before final Phase 5
validation.

This inventory adopts no candidate. It therefore adds no provider, resident
process, stored user data, dependency, command surface, IPC name, keybinding,
or X11 surface. Existing focus, click-away, stacking, monitor selection, and
closed-shell idle behavior remain unchanged.

## Candidate Inventory

| Candidate | Decision | Evaluation | Reconsideration gate |
| --- | --- | --- | --- |
| Event-driven clipboard history | Defer | A correct X11 implementation needs a long-lived selection observer or owner, bounded text and image retention, explicit exclusions and clear-all behavior, and a policy for password managers and other sensitive selections. The existing `xclip` screenshot transfer is a short-lived clipboard owner, not a safe history backend. The privacy and lifecycle contract is larger than an optional Phase 5 surface. | Reconsider only with an opt-in retention specification, sensitive-data exclusions, bounded storage and image sizes, a complete deletion contract, and a separately reviewable event-driven X11 backend. |
| Emoji and symbol picker | Reject | The current roadmap defines no desktop workflow that requires a managed picker. Shipping Unicode search data, clipboard injection, focus restoration, and update policy would create a new product and package contract for convenience behavior already available through applications. | Reconsider only if a future accessibility or input requirement names a consumer and cannot be satisfied by a delegated Fedora application. |
| Reminder or timer overlay | Defer | Reliable reminders require persistent scheduling, restart and missed-event behavior, timezone-change handling, and notification delivery ownership. Those responsibilities are not presentation-only and do not belong in the Phase 5 personalization boundary. | Reconsider in a future phase only after a durable scheduling and recovery contract is specified independently of Quickshell surface lifetime. |
| General image picker | Reject | Phase 5 already provides a bounded wallpaper candidate chooser for its defined image consumer. A generic picker has no additional approved consumer and would duplicate file filtering, preview, focus, and lifecycle behavior without completing an exit criterion. | Reconsider only when a named workflow needs reusable image selection and the existing wallpaper contract cannot serve it. |

## Adopted Set and Qualification

The adopted set is empty. Consequently there is no UI-5 implementation or
package-install boundary to qualify, and the requirements for adopted-feature
source, helper, lifecycle, nested-X11, package, and privacy tests are not
applicable. The repository's existing full-suite, QML, X11, and closed-idle
gates remain authoritative for proving this documentation-only decision does
not disturb existing shell behavior.

Deferred candidates are not Phase 6 commitments. Reopening one requires an
explicit roadmap decision and the independent pre-implementation evaluation
described above. Rejected candidates remain outside the product plan unless a
new requirement supplies a concrete consumer and acceptance criteria.
