# Phase 5 Theme Transaction Evidence

## Scope

This record qualifies the second Phase 5 review boundary: the user-session
theme transaction helper. The shared root QML model and Settings Appearance
pane remain outside this change and belong to the next pull request.

## Action Contract

`dwm-settings-theme` emits `appearance-action-protocol` version 1.0 records for
these fixed actions:

- `preview TOKEN SECONDS THEME`
- `keep TOKEN`
- `revert TOKEN`
- `abandon TOKEN`
- `preview-status [TOKEN]`
- `apply THEME`
- `reset`
- `recovery-status`
- `recover`

The separate `mutation-ready` action is a read-only capability probe. It emits
no protocol records and returns success only when the source can safely support
the complete mutation contract.

Preview timeouts are limited to 1 through 99 seconds. Tokens and theme names
use bounded allowlisted grammars. Only a complete theme accepted by the
read-only `dwm-settings-appearance` provider can be selected. Structural parser
errors prevent mutation.

## Transaction and Recovery Behavior

The helper serializes changes with a per-user runtime lock. It rejects a
symlinked, foreign-owned, hard-linked, non-regular, oversized, or unsafe-path
user theme file. A same-directory temporary file is prepared and hashed before
its atomic rename. Existing file mode, comments, custom theme definitions, and
unrelated settings are retained.

Settings advertises mutation controls only when the read-only `mutation-ready`
probe confirms that the user theme path is safely writable and the managed
reset source is available. An unsafe source remains readable but is reported
as a partial, read-only capability.

Before a persistent apply or reset, the exact prior file and mode are stored in
a private state directory. A failed integration apply restores that baseline.
If both apply and immediate rollback integration fail, the journal remains for
an explicit retry. Recovery accepts only the recorded proposed or baseline
hash, so a later external edit is never overwritten.

A preview stores the exact theme and persistent integration-file baselines in
private durable state and launches a bounded watchdog. Automatic reloads remain
runtime-only until the helper records the integration after-state. Once ready,
automatic reloads may update those tracked files transactionally but still
defer untracked DConf, Xfconf, Xresources, and activation-environment mutations.
A confirmed preview or committed apply then performs normal live convergence;
rollback therefore does not need to guess at or replace pre-existing live
settings. Session startup re-arms or
expires that journal, so logout or reboot cannot silently confirm a preview.
Keep commits the preview only when the file still has the expected hash and no
rollback failure is recorded. Revert and timeout restore the original terminal,
GTK, Qt, cursor, environment, and theme files byte-for-byte, including modes and
originally absent files. External changes retain an attributed failed-preview
record instead of being replaced. If the external edit is intentional, abandon
clears only the stale journal and leaves that edit untouched.

DWM's asynchronous integration reloads honor the restored source hash and stay
runtime-only during a bounded 30-second rollback window. A different valid
source clears that hash-specific guard immediately. Manual applies bypass the
guard, so repeated or delayed queued reloads cannot undo the exact transaction
restore or permanently suppress later repair work. Baseline capture and restore
share the integration writer lock, and atomic-exchange support is proven on the
theme and every integration filesystem before mutation. If a crash interrupts
integration output before its after-state is known, recovery proceeds only when
every tracked file still matches its baseline; otherwise it retains the journal
instead of inferring ownership and overwriting a possible later user edit.

Reset selects the valid active theme from the managed theme source while
preserving the user's other content. If no user file exists, apply creates one
from the managed source; preview rollback restores the original absence.
`theme-apply.sh` can read the managed source directly when the user file is
absent.

The existing Control Center `theme-set` command now delegates to this helper
and keeps its legacy output for current QML callers.

## Automated Evidence

The focused fixtures cover:

- Exact action protocol records and active-theme convergence.
- Comment, custom-section, unrelated-content, and mode preservation.
- Invalid target rejection without a write.
- Preview keep, explicit revert, automatic timeout, and status.
- Exact integration-file restoration after a preview, including custom content,
  modes, and files that were initially absent.
- Transactional suppression of untracked live settings until confirmation.
- Refusal to confirm a preview after its integration rollback failed.
- Durable preview resume plus orphan-reservation cleanup.
- External-change refusal, explicit abandon, and released claim state.
- Serialized integration writes under concurrent hot-reload calls.
- Managed-default reset and initially absent user configuration.
- Apply failure rollback followed by a successful recovery retry.
- Simulated process death after the atomic write and explicit recovery.
- User-theme symlink and hard-link refusal.
- Managed-source fallback in `theme-apply.sh`.
- Existing Control Center and Settings capability discovery compatibility.

Run:

```sh
scripts/run-tests make check-appearance
scripts/run-tests make check-settings
scripts/run-tests make check-quickshell-controlcenter
shellcheck scripts/autostart.sh scripts/dwm-settings-theme scripts/theme-apply.sh \
  tests/test-autostart.sh tests/test-dwm-settings-theme.sh
shfmt -d scripts/autostart.sh scripts/dwm-settings-theme scripts/theme-apply.sh \
  tests/test-autostart.sh tests/test-dwm-settings-theme.sh
```

## Real-Session Evidence

On Fedora 44 under the active LightDM X11 session (`DISPLAY=:0`), a three-second
Nord-to-Dracula preview appeared as the selected provider theme and then timed
out to Nord. The original `themes.toml` SHA-256 and mode `600` were restored.
Persistent Dracula apply, Nord apply, and managed-default reset each converged;
the DWM session log recorded the corresponding theme reloads. Preview and
recovery status both ended empty. A safeguarded snapshot confirmed byte-exact
restoration, including modes and originally absent paths, across all 12 theme,
terminal, toolkit, cursor, and environment files touched by the integration.
