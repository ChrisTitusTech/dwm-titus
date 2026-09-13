# Active Tasks

## Desktop updates in System Settings

Approved plan: add a first-position System card that checks official main and
installed file parity, updates through confirmation and progress, and preserves
personal settings. Implementation and PR publication are authorized; no merge.
See [DESKTOP-UPDATES.md](docs/DESKTOP-UPDATES.md) for the current interface and
recovery contract. Previous Phase 8 evidence is retained in its implementation
plan and qualification documents.

- [x] Create `codex/desktop-updates` from verified current `origin/main` with a
      clean initial worktree.
- [x] Add system/user installation receipts and cached upstream/file checks.
- [x] Stage builds, bind updates to confirmed revisions, and install system files
      through a root-owned fixed-layout helper with polkit authorization.
- [x] Add the first System card, confirmation, progress, search terms, operation
      interlocks, and durable worker observation.
- [x] Add retained backups, interruption handling, and explicit recovery that
      rejects later conflicting changes.
- [x] Complete worker, GUI, privilege, Fedora build/install, and full repository
      validation; reconcile failures before claiming success.
- [x] Verify the new complete shell in nested X11 and save visual evidence
      (`docs/evidence/desktop-updates.png`); closed CPU was 0.000% over 10 seconds.
      Live files and receipts are synchronized, but activation is deferred until
      logout/login because the running dwm differs. Live activation is unverified.
- [x] Complete independent local Codex review with no remaining actionable
      findings; address CodeRabbit feedback and repeat affected checks.
      Final coverage includes 24 backend tests, 14 privileged-helper tests,
      real service lifetime/readiness checks, and the full repository gate.
- [ ] Commit, push, verify the remote head, and open a ready-for-review PR with
      exact evidence and limitations.
