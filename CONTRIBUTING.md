# Contributing

Thanks for helping improve dwm-titus. Changes should preserve the small X11
window-manager core, existing user workflows, and the Fedora-only desktop
target. Fedora Linux is the sole supported distribution.

## Before You Start

- Read `AGENTS.md` for repository conventions, `SPEC.md` for product scope,
  `ROADMAP.md` for phase outcomes, and `TASKS.md` for active work.
- Search existing issues and pull requests before starting overlapping work.
- Keep durable requirements in `SPEC.md`; do not copy future roadmap phases
  into `TASKS.md` before they become active.
- Do not commit `config.h`, build products, release artifacts, ISO images, or
  generated Astro output.

## Development Setup

On the supported Fedora release, install the repository's Fedora build
dependencies, then run:

```sh
make clean
make
scripts/run-tests
```

Use `./install.sh --dry-run --non-interactive --profile core` to inspect the
dependency plan without changing the system.

## Validation

Run the smallest relevant checks while developing and the aggregate gate before
submitting a pull request.

| Change | Required validation |
| --- | --- |
| C or build configuration | `scripts/run-tests make clean all`, then `scripts/run-tests` |
| Shell or installer | `scripts/run-tests make check-shell check-format` and focused tests |
| X11 behavior | `scripts/run-tests make check-xvfb-runtime check-monitor-tags` |
| Settings loading, search, and section navigation | `scripts/run-tests make check-quickshell-settings-responsiveness-xvfb` plus the full Settings runtime gate |
| Quickshell QML | `scripts/run-tests make check-quickshell-qml` plus real or nested X11 runtime validation |
| System update UI | `scripts/run-tests tests/test-quickshell-update-ui-xvfb.sh` for the focused native fixture, plus configured QML lint |
| Documentation | `npm --prefix docs ci`, then `npm --prefix docs run build` |
| Installer or package mapping | `scripts/run-tests make check-fedora-packages` on Fedora 44 |
| Fedora Kickstart or ISO | `scripts/run-tests make check-kickstart` plus all evidence required by [SPEC.md Section 9.4](SPEC.md#94-fedora-image-validation) |
| Release automation | `scripts/run-tests make release-check` and a dry run of the release helper |

Fedora package, VM, and X11 checks require their documented host tools. If a
required environment is unavailable, state exactly what was not tested in the
pull request instead of claiming universal validation.

## Change Guidelines

- Preserve the C99 style and avoid new mandatory dependencies unless they are
  available on supported Fedora releases.
- Keep POSIX scripts under `#!/bin/sh`; use Bash only for scripts that need Bash
  features.
- Preserve existing `config.h`, XDG user configuration, and `.xinitrc` files.
- Keep Quickshell integrations event-driven when a signal, stream, watch, IPC,
  or service API exists.
- Update user documentation, migration notes, and `CHANGELOG.md` when behavior,
  commands, dependencies, or defaults change.
- Add focused regression coverage for bug fixes.

## Pull Requests

Use a focused branch and describe the problem, root cause, behavior change,
validation, Fedora coverage, and remaining risk. Screenshots are useful for
visible UI changes, but do not replace runtime validation.

## Local Review Loop

Use the supported Fedora host or a disposable Fedora 44 container. Complete
validation before pushing so fixes do not require another hosted CI run:

1. Fetch the intended base and integrate it before the final full gate. Run
   the smallest affected checks while editing, then `scripts/run-tests` and
   the applicable extra checks in the table above. The aggregate gate includes
   the clean build, configured QML lint, nested Settings tests, package map,
   installer preservation, and release validation. Run
   `scripts/run-tests make check-xvfb-runtime` for the native dwm smoke test.
   Privileged display-helper changes additionally require
   `DWM_SECURITY_CONTAINER=1 scripts/run-tests tests/test-settings-display-security.sh`
   as root inside a disposable container, never on the host.
2. Run `git diff --check` and an independent `codex review --base origin/main`
   for the complete PR diff (substitute the verified base for stacked work).
   For unpublished edits, use `codex review --uncommitted`. Let the review
   finish; review instances report findings without starting nested reviews.
3. Verify findings, fix actionable defects, rerun affected checks, and repeat
   review until clean. Reuse passing evidence for unchanged code. Base
   integration or broad changes require a fresh full relevant gate.
4. Record the final commit, exact passing commands, reused evidence, runtime
   environment, and any gaps in the PR. Push once the loop is clean, verify
   the remote head, and inspect unresolved review threads before merging.

Give the reviewer the evidence before starting it. A short local evidence file
should name the base and reviewed tree/commit, changed paths, exact commands,
exit results, log paths, runtime environment, and any coverage reused from an
unchanged base. Keep logs outside the checkout. Use a custom review prompt when
passing evidence (the CLI does not combine a custom prompt with `--base` or
`--uncommitted`):

```sh
codex review 'Review the complete diff against origin/main, including uncommitted
and untracked changes. Read /absolute/path/to/local-evidence.md first. Reuse its
passing evidence where the code and assumptions are unchanged. Run additional
checks when a finding, changed behavior, or coverage gap requires them. Report
findings directly; do not launch nested reviews.'
```

After a fix, update the evidence and review the affected diff and its integration
with the original change. A repeated long native suite is necessary only when
the fix invalidates its evidence. Do not substitute a focused test for unrun
required coverage; the new responsiveness target accelerates iteration while
the existing Settings suite still validates real providers and interactions.

Local validation and independent Codex review are the normal merge gate.
Automatic build/test and documentation workflows run after merges to `main`;
CodeQL also runs weekly. Hosted workflows remain available through manual
dispatch when extra coverage is needed. Optional hosted checks and review bots
do not block a locally verified change. Required branch-protection rules still
apply; investigate known failures and fill required validation gaps before
merging. A post-merge failure needs prompt investigation and a fix or rollback.
