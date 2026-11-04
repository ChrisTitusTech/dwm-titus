# Fedora 0.8 Roadmap

## Current scope

The four desktop features are implemented in PRs #424, #425, #422 and #423.
On 2026-11-04, the user verified PR #425's static thumbnails and authorized
merging all four PRs, addressing #368, and preparing the 0.8 release. Fedora 45 is the primary ISO base for 0.8; retain
Fedora 44 compatibility, as the user explicitly selected.

## Integration and release sequence

1. Merge #425 after recorded local review, tests and user acceptance.
2. Integrate updated main into each remaining feature PR; resolve conflicts,
   validate their combined native/QML behavior, complete independent review,
   and merge #424 (layout controls), #423 (floating titlebars), and #422
   (calendar/weather).
3. Address #368 by checking the Wi-Fi package contract in newly built images,
   including NetworkManager's Wi-Fi plugin, supplicant and regulatory database.
   Source fixes do not repair the published v0.7.2 ISO.
4. Prepare v0.8.0 source, changelog, release notes, checksummed artifacts and
   Fedora 45 image qualification evidence, with Fedora 44 compatibility checks
   and the intentionally updated SPEC.md platform contract.

Record exact tested commits, reused unchanged evidence and hardware limitations.
Do not describe an unbuilt or unqualified image as fixed or released. Preparing
release artifacts does not replace publishing and verifying the new downloads.
