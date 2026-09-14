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
      After logout/login and managed sync, live receipts/files match, Quickshell
      IPC responds with four tray items, and running dwm matches the installation.
- [x] Complete independent local Codex review with no remaining actionable
      findings; address CodeRabbit feedback and repeat affected checks.
      Final coverage includes 50 backend tests, 40 privileged-helper tests,
      real service lifetime/readiness and hostile-build sandbox checks, plus the
      full repository gate. Hosted review fixes are being revalidated on PR #318.
- [x] Publish implementation commit `c4ba100` and verify its remote head; open
      ready-for-review [PR #318](https://github.com/ChrisTitusTech/dwm-titus/pull/318)
      with exact evidence and limitations. No unresolved review threads were
      present at publication; optional hosted CodeRabbit review was pending.
      No merge was performed.
