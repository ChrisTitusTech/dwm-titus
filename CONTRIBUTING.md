# Contributing

Thanks for helping improve dwm-titus. Changes should preserve the small X11
window-manager core, existing user workflows, the Fedora-first desktop target,
and the supported core install on Debian, Arch, Fedora, and RHEL families.

## Before You Start

- Read `AGENTS.md` for repository conventions, `SPEC.md` for product scope,
  `ROADMAP.md` for phase outcomes, and `TASKS.md` for active work.
- Search existing issues and pull requests before starting overlapping work.
- Keep durable requirements in `SPEC.md`; do not copy future roadmap phases
  into `TASKS.md` before they become active.
- Do not commit `config.h`, build products, release artifacts, ISO images, or
  generated mdBook output.

## Development Setup

Install the build dependencies for your distribution, then run:

```sh
make clean
make
make check
```

Use `./install.sh --dry-run --non-interactive --profile core` to inspect the
dependency plan without changing the system.

## Validation

Run the smallest relevant checks while developing and the aggregate gate before
submitting a pull request.

| Change | Required validation |
| --- | --- |
| C or build configuration | `make clean && make`, then `make check` |
| Shell or installer | `make check-shell check-format` and focused tests |
| X11 behavior | `make check-xvfb-runtime check-monitor-tags` |
| Quickshell QML | `make check-quickshell-qml` plus real or nested X11 runtime validation |
| Documentation | `mdbook build docs && mdbook test docs` |
| Installer or package mapping | `make check-container-smoke` |
| Fedora Kickstart or ISO | `make check-kickstart` plus a recorded Anaconda install |
| Release automation | `make release-check` and a dry run of the release helper |

Container and X11 checks require their documented host tools. If a required
environment is unavailable, state exactly what was not tested in the pull
request instead of claiming universal validation.

## Change Guidelines

- Preserve the C99 style and avoid new mandatory dependencies unless they are
  available across all supported families.
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
validation, supported-platform coverage, and remaining risk. Screenshots are
useful for visible UI changes, but do not replace runtime validation.
