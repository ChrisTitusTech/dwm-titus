# Desktop Update Roadmap

## Current scope

Add a complete desktop source update workflow at the top of Settings > System.
The user approved implementation and a new ready-for-review PR on 2026-09-13.
Merge and release are outside this change.

Phase 8 performance and fresh-install qualification remains complete within its
recorded environment. Preserve its evidence in [P8-IMPLEMENTATION-PLAN.md](docs/P8-IMPLEMENTATION-PLAN.md)
and [P8-QUALIFICATION.md](docs/P8-QUALIFICATION.md). Earlier outcomes remain in
[COMPLETED-ROADMAP-20260911.md](docs/COMPLETED-ROADMAP-20260911.md).

## Desktop updates

1. Record installed revisions and managed file hashes; detect upstream changes,
   file drift, unsupported sources, and incomplete installations.
2. Build a confirmed revision without elevation and stage the full managed
   installation. Authorize only the root-owned manifest's system-file layout.
3. Display update discovery, confirmation, streamed progress, retained results,
   and restart guidance in the first System card.
4. Preserve personal configuration and recover interrupted replacement without
   overwriting newer installations or subsequent user changes.
5. Validate focused worker and UI scenarios, privileged boundaries in a disposable
   Fedora container, complete repository gates, and the actual managed X11 shell.
6. Complete independent review, address findings, publish the branch, and open a
   ready-for-review PR with validation evidence and any explicit runtime limits.

Exit: checks distinguish outdated source from stale installed files; a confirmed
update is backed up, staged, verified, and visible across Settings closure;
installation and activation are reported separately; recovery and authorization
failure are tested; the PR contains the required local review and validation.
