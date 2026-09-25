# Initial Fedora update and DNF defaults

Version 0.7.2 adds an initial package update to new standard and NVIDIA images.
The compressed installation and first desktop login still work offline.

After a repository responds with valid metadata, a desktop dialog offers to
open the update terminal. Choose **Later** to defer until another login, or run
`dwm-initial-update` whenever ready. The terminal requests administrator
authorization through polkit, measures mirrors, validates every enabled
repository, and displays DNF's proposed upgrade. Enter accepts the `[Y/n]`
prompt; `n` cancels. Nothing automatically reboots the machine.

The helper installs only updates from already enabled repositories. It does not
enable repositories, change image variants, install NVIDIA drivers on the
standard variant, or change Settings' PackageKit authorization/security checks.
Close other package managers before retrying a lock failure. Repository errors,
cancelled authorization, interrupted downloads and failed transactions leave
the initial update pending. Retry with `dwm-initial-update`; use DNF's normal
recovery tools if an RPM transaction was interrupted.

Successful completion is recorded system-wide in
`/var/lib/dwm-titus/initial-update/complete.json`. Subsequent logins, reconnects
and other users do not repeat the offer. Only fresh image provisioning creates
`pending.json`; updating an existing desktop from source does not opt it in.
The watcher reacts to NetworkManager changes and performs one bounded retry
every five minutes because repository recovery has no client-side event. It
does not block session startup and permits only one probe at a time.

## Mirror selection

The root-owned installed helper reads effective repository configuration using
Fedora's `python3-libdnf5`, including variable substitution and overrides. It
never elevates a repository checkout or accepts caller-supplied commands,
repository paths, destinations or package names.

Before the first upgrade, it samples up to three HTTPS mirrors per repository
within a 90-second overall budget. It measures connection time and actual
primary-metadata download throughput (up to 1 MiB per sample, five seconds per
request). Metalink samples must match the metadata's SHA-256/SHA-512 hash. Only
mirrors supplied by the configured repository service are candidates. Small
metadata files, failures, fixed endpoints, and custom authenticated/proxy/TLS
transports keep their existing defaults.
Connectivity checks for custom transports use DNF itself, with a bounded
metadata refresh, so proxy and client-certificate settings are honored without
copying credentials into command arguments. Administrator-only credentials may
still require starting `dwm-initial-update` manually for authorization.

Mirrors are ranked by TCP connection time plus the estimated payload time for
a fixed 1 MiB transfer. Payload throughput excludes connection and server-wait
time to avoid counting connection latency twice. This is a comparison heuristic,
not a full TLS/server-response prediction. At least a 10% reduction in this
estimate can promote a mirror for this operation.
Temporary metalinks retain their verification data and every fallback mirror;
temporary mirrorlists retain the original list. Nothing stores a builder's
preferred server in a released image or permanently pins a user's repository.
DNF retains package and repository signature checks. All enabled repositories
must pass a bounded metadata refresh; failed optimized selections retry with
the original repository settings. A failed transaction remains retryable, and
the temporary selection is removed when the helper exits.

Sample measurements are saved without URLs or credentials in
`/var/lib/dwm-titus/initial-update/measurements.json`. These are short metadata
samples, not a promise of sustained package speed. For read-only measurements:

```sh
/usr/local/libexec/dwm-titus/dwm-initial-update-root measure
```

## DNF configuration audit

The working Fedora 44 installation was audited on 2026-09-24 with DNF5/libdnf5
5.4.4.0, `dnf5 --dump-main-config`, and the effective repository configuration
from libdnf5. Its explicit `/etc/dnf/dnf.conf` settings were `defaultyes=True`,
`fastestmirror=True`, and `enabled=1`. No user main drop-ins or repository
overrides were present. Effective `assumeyes=False`, `max_parallel_downloads=3`,
`minrate=1000`, and `timeout=30` matched defaults. Fedora's distribution drop-in
set `best=False`, `pkg_gpgcheck=True`, and `skip_if_unavailable=True`.

The installer provisions `/usr/share/dnf5/libdnf.conf.d/40-dwm-titus.conf` only
when that path does not exist. The chosen defaults are:

| Setting | Shipped value | Reason |
| --- | --- | --- |
| `defaultyes` | `True` | Enter accepts while an explicit No still cancels. |
| `assumeyes` | `False` | Keep transaction confirmation interactive. |
| `fastestmirror` | `False` | Preserve the service's ordering; measure throughput for the initial update. |

`enabled=1` is already the normal repository default and is not an optimization;
it is not copied. Parallel downloads, minimum rate, timeout, and signature
settings retain Fedora defaults. The initial updater alone uses bounded
repository timeouts/retries and disables skipping unavailable repositories so
partial repository access cannot falsely complete the initial update.

[DNF5's configuration reference](https://dnf5.readthedocs.io/en/stable/dnf5.conf.5.html)
documents that `fastestmirror` selects by TCP latency, overriding geographic and
bandwidth-aware service ordering. It also documents main/drop-in precedence:
`/etc/dnf/dnf.conf` wins over distribution defaults. Existing administrator
settings and repository-specific overrides remain intact. To change the prompt:

```ini
# /etc/dnf/dnf.conf (merge into the existing [main] section)
[main]
defaultyes=False
```

To mask all dwm-titus DNF defaults without changing the installed file:

```sh
sudo install -Dm644 /dev/null /etc/dnf/libdnf5.conf.d/40-dwm-titus.conf
dnf5 --dump-main-config
```

Remove only that empty mask to restore the distribution drop-in. Existing
configuration files are never replaced and no duplicate entries are appended.
The defaults are provisioned during factory installation before capture, so
end-user offline installation inherits them along with fastfetch.

Existing systems receive the distribution defaults when rerunning
`./install.sh`. A Settings desktop source update refreshes the helpers but does
not change system DNF policy or arm the fresh-install offer.

## Validation commands

Run the normal focused, image and repository checks through the managed runner:

```sh
scripts/run-tests make check-initial-update
scripts/run-tests make check-kickstart check-fedora-packages check-install-manifest
scripts/run-tests make clean all
scripts/run-tests
```

The real signed-RPM/TTY tests intentionally require a disposable Fedora 44
Docker container and the explicit `DWM_DISPOSABLE_DNF_TEST=1` environment flag.
They create fixture packages and temporary DNF policy in that container; never
run them on an installed desktop. Install `python3-libdnf5`, `rpm-build`,
`rpm-sign`, `createrepo_c`, and `gnupg2` there, mount the checkout read-only at
`/src`, and run:

```sh
export DWM_TEST_TMP_ROOT=/var/tmp/dwm-tests
DWM_DISPOSABLE_DNF_TEST=1 /src/scripts/run-tests bash /src/tests/test-initial-update-dnf.sh
DWM_DISPOSABLE_DNF_TEST=1 /src/scripts/run-tests python3 /src/tests/test-initial-update-root.py
DWM_DISPOSABLE_DNF_TEST=1 /src/scripts/run-tests python3 /src/tests/test-initial-update-proxy.py
```

Container checks do not replace the complete offline-install and first-boot
contract in [SPEC.md Section 9.4](../SPEC.md#94-fedora-image-validation).

See the [0.7.2 qualification record](INITIAL-UPDATE-QUALIFICATION.md) for measured
results, fresh offline installation, failure/retry and reboot evidence, and
remaining hardware-validation limits.

Connectivity probes try up to three distinct fallback endpoints per repository
within the existing 45-second overall deadline. One unavailable first mirror
does not suppress an otherwise reachable repository.

Uninstall removes an unchanged DNF defaults file only when the installer created
it and recorded ownership. Preexisting files, administrator modifications, and
symlink replacements are preserved. The ownership record lives under
`/var/lib/dwm-titus/dnf-defaults/`.

HTTP intranet mirrors, local file repositories, and custom transports use a
bounded native DNF connectivity probe with their configured policy. They remain
ineligible for the HTTPS-only mirror optimizer.

Failed HTTPS probes or mirror discovery also fall back to native DNF within
the shared deadline, including mixed lists with a reachable HTTP fallback.

The 45-second probe budget is shared across the remaining repositories so a
stalled first repository cannot consume every later repository's opportunity.
The defaults lifecycle helper is installed under the configured prefix's
`libexec/dwm-titus/` directory before elevation. Defaults and their ownership
record are staged completely before publication; failed writes roll back.
