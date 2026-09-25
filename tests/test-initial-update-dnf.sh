#!/bin/bash
# Real DNF confirmation against signed fixture RPMs, only in a disposable container.
set -euo pipefail
[[ $(id -u) == 0 && -f /.dockerenv && ${DWM_DISPOSABLE_DNF_TEST:-} == 1 ]] || {
	echo 'Run only in a disposable Fedora container with DWM_DISPOSABLE_DNF_TEST=1.' >&2
	exit 2
}
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GNUPGHOME=$work/gnupg
mkdir -m 700 "$GNUPGHOME"
gpg --batch --passphrase '' --quick-gen-key 'DNF test fixture' ed25519 sign 0
key=$(gpg --with-colons --list-keys | awk -F: '$1 == "fpr" {print $10; exit}')
gpg --armor --export "$key" >"$work/key.asc"
rpm --import "$work/key.asc"
mkdir -p "$work/rpmbuild"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} "$work/repo"
for version in 1 2; do
	cat >"$work/rpmbuild/SPECS/fixture.spec" <<EOF
Name: dwm-dnf-test-fixture
Version: $version
Release: 1
Summary: Disposable initial update test fixture
License: MIT
BuildArch: noarch
%description
Disposable test fixture.
%install
mkdir -p %{buildroot}/usr/share/dwm-dnf-test
printf '%s\n' '$version' > %{buildroot}/usr/share/dwm-dnf-test/version
%files
/usr/share/dwm-dnf-test/version
EOF
	rpmbuild --define "_topdir $work/rpmbuild" -bb "$work/rpmbuild/SPECS/fixture.spec"
	rpmsign --define "_openpgp_sign_id $key" --addsign "$work/rpmbuild/RPMS/noarch/dwm-dnf-test-fixture-$version-1.noarch.rpm"
done
cp "$work/rpmbuild/RPMS/noarch/dwm-dnf-test-fixture-2-1.noarch.rpm" "$work/repo/"
createrepo_c "$work/repo"
mkdir "$work/repos"
cat >"$work/repos/fixture.repo" <<EOF
[fixture]
name=Signed DNF fixture
baseurl=file://$work/repo
enabled=1
pkg_gpgcheck=1
gpgkey=file://$work/key.asc
EOF
install -Dm644 "$repo/config/dnf/40-dwm-titus.conf" /usr/share/dnf5/libdnf.conf.d/40-dwm-titus.conf
for command in update upgrade; do
	rpm -U --oldpackage --replacepkgs "$work/rpmbuild/RPMS/noarch/dwm-dnf-test-fixture-1-1.noarch.rpm"
	set +e
	printf 'n\n' | dnf --setopt="reposdir=$work/repos" --setopt="cachedir=$work/cache" "$command" >"$work/no.log" 2>&1
	status=$?
	set -e
	cat "$work/no.log"
	[[ $status != 0 ]]
	[[ $(rpm -q --qf '%{VERSION}' dwm-dnf-test-fixture) == 1 ]]
	grep -F '[Y/n]' "$work/no.log"
	printf '\n' | dnf --setopt="reposdir=$work/repos" --setopt="cachedir=$work/cache" "$command" >"$work/yes.log" 2>&1
	cat "$work/yes.log"
	[[ $(rpm -q --qf '%{VERSION}' dwm-dnf-test-fixture) == 2 ]]
	printf 'PASS: dnf %s rejects No and accepts Enter with signed packages.\n' "$command"
done
# The main configuration must still override the shipped distribution file.
cp /etc/dnf/dnf.conf "$work/dnf.conf"
printf '[main]\ndefaultyes=False\n' >/etc/dnf/dnf.conf
dnf --dump-main-config | grep -Fx 'defaultyes = 0'
cp "$work/dnf.conf" /etc/dnf/dnf.conf
# Exercise cancellation and retry through the real installed privileged entry
# point as well, with a real TTY and the same signed fixture repository.
rpm -U --oldpackage --replacepkgs "$work/rpmbuild/RPMS/noarch/dwm-dnf-test-fixture-1-1.noarch.rpm"
python3 - "$repo" "$work/repos" <<'PY'
import fcntl
import os
from pathlib import Path
import pty
import subprocess
import sys

source, repos = map(Path, sys.argv[1:])
helper = Path('/usr/local/libexec/dwm-titus/dwm-initial-update-root')
helper.parent.mkdir(parents=True, exist_ok=True)
helper.write_text((source / 'scripts/dwm-initial-update-root').read_text().replace('@PREFIX@', '/usr/local'))
helper.chmod(0o755)
state = Path('/var/lib/dwm-titus/initial-update')
state.mkdir(parents=True, exist_ok=True)
(state / 'pending.json').write_text('{}\n')
complete = state / 'complete.json'
complete.unlink(missing_ok=True)
config = Path('/etc/dnf/dnf.conf')
original = config.read_bytes()

def run(answer):
    master, slave = pty.openpty()
    try:
        os.write(master, answer.encode())
        result = subprocess.run([str(helper), 'run'], stdin=slave, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=240)
        print(result.stdout, flush=True)
        return result.returncode
    finally:
        os.close(master)
        os.close(slave)

try:
    config.write_text('[main]\nreposdir=' + str(repos) + '\n')
    with (state / 'lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert run('n\n') != 0 and not complete.exists()
    config.write_text('[main]\nreposdir=' + str(repos) + '\ndefaultyes=False\n')
    assert run('\n') != 0 and not complete.exists(), 'Explicit administrator No-default must win'
    config.write_text('[main]\nreposdir=' + str(repos) + '\n')
    assert run('n\n') != 0 and not complete.exists()
    assert subprocess.check_output(['rpm', '-q', '--qf', '%{VERSION}', 'dwm-dnf-test-fixture']) == b'1'
    assert run('\n') == 0 and complete.exists()
    assert subprocess.check_output(['rpm', '-q', '--qf', '%{VERSION}', 'dwm-dnf-test-fixture']) == b'2'
finally:
    config.write_bytes(original)
print('PASS: helper contention/cancellation leaves no completion; signed upgrade retry records success')
PY
