# Issue 346 DNF defaults validation

Date: 2026-09-24

## Audit result

The fresh standard image used Fedora 44 x86_64, DNF5 5.4.5.0, BIOS firmware,
and kernel 6.19.10-300.fc44.x86_64. Before this change its effective values were:

```text
defaultyes = 0
fastestmirror = 0
max_downloads_per_mirror = 3
max_parallel_downloads = 3
gpgcheck = 1
sslverify = 1
```

The shipped dwm-titus drop-in changes only `defaultyes`. It does not override
Fedora's mirror selection, download concurrency, signature verification, or
TLS verification defaults.

## Download measurements

The same six Fedora packages were downloaded into a new temporary directory for
each run: Firefox, LibreOffice Core, kernel-core, GCC, Qt 6 Core, and Mesa DRI.
Each completed set contained 324,015,214 bytes. Repository metadata was warmed
once before measurement. No package transaction, update, or upgrade ran.

| `max_parallel_downloads` | Elapsed seconds |
| ---: | ---: |
| 3 | 29.038 |
| 10 | 44.391 |
| 10 | 43.547 |
| 3 | 31.957 |
| 6 | 62.283 |
| 3 | 32.390 |

These results support retaining Fedora's default of three on this network. They
do not establish a universal optimum across locations or mirrors. Issue #347
owns any later network-specific mirror or throughput selection.

## Prompt and preservation validation

On the fresh Fedora 44 VM, the installed candidate reported `defaultyes = 1`
and retained `assumeyes = 0`, `fastestmirror = 0`, `gpgcheck = 1`,
`sslverify = 1`, `max_downloads_per_mirror = 3`, and
`max_parallel_downloads = 3` through `dnf5 --dump-main-config`.

`printf '\n' | dnf5 --setopt=cachedir=<temporary-directory> install
--downloadonly sl` accepted the `Is this ok [Y/n]:` prompt and downloaded the
17 KiB RPM to the private cache. `printf 'n\n' | dnf5
--setopt=cachedir=<temporary-directory> install --downloadonly cowsay` exited
with status 1 and reported `Operation aborted by the user.` The two commands
made no RPM transaction. The installed RPM inventory and hashes of
`/etc/dnf/dnf.conf` plus all `/etc/dnf/libdnf5.conf.d` files matched before and
after. The temporary distribution drop-in was removed after the test.

Repeated staged source installation is covered by `make check-install-manifest`.
The file still needs confirmation in rebuilt standard and NVIDIA image
artifacts; neither image was rebuilt for this focused validation.
