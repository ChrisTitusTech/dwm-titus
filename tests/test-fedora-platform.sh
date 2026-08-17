#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT

snapshot_tree() {
	local root=$1 output=$2
	{
		find "$root" -printf 'entry\t%P\t%y\t%m\t%s\t%l\n'
		find "$root" -type f -exec sha256sum {} + |
			sed "s#  $root/#  #"
	} | sort >"$output"
}

cat >"$work/fedora" <<'EOF'
ID=fedora
PRETTY_NAME="Fedora Linux 44"
EOF
cat >"$work/unsupported" <<'EOF'
ID=example
ID_LIKE="rhel"
PRETTY_NAME="Unsupported Linux"
EOF

fedora_family=$(DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/fedora" bash -c \
	'. "$1"; printf "%s" "$DISTRO_FAMILY"' sh "$repo/scripts/dwm-utils.sh")
[[ $fedora_family == fedora ]]

unsupported_family=$(DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/unsupported" bash -c \
	'. "$1"; printf "%s" "$DISTRO_FAMILY"' sh "$repo/scripts/dwm-utils.sh")
[[ $unsupported_family == unknown ]]

mkdir -p "$work/bin" "$work/unsupported-home"
for command_name in chmod chown cp curl dnf git install ln make mkdir mv rm sudo systemctl tee touch unzip usermod; do
	cat >"$work/bin/$command_name" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "${0##*/}" "$*" >>"${DWM_MUTATION_LOG:?}"
exit 99
EOF
done
/usr/bin/chmod +x "$work/bin/"*
snapshot_tree "$work/unsupported-home" "$work/home.before"
set +e
DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/unsupported" \
	DWM_MUTATION_LOG="$work/mutations.log" HOME="$work/unsupported-home" \
	PATH="$work/bin:$PATH" "$repo/install.sh" \
	--non-interactive --profile core >"$work/install-rejection.out" 2>&1
install_status=$?
set -e
if [[ $install_status -ne 1 ]]; then
	printf 'Unsupported installer exited with %s instead of 1.\n' "$install_status" >&2
	exit 1
fi
grep -Fq 'Unsupported distribution: Unsupported Linux' "$work/install-rejection.out"
grep -Fq 'dwm-titus supports Fedora only.' "$work/install-rejection.out"
if [[ -e $work/mutations.log ]]; then
	printf 'Unsupported installer attempted a package or system mutation.\n' >&2
	exit 1
fi
snapshot_tree "$work/unsupported-home" "$work/home.after"
cmp "$work/home.before" "$work/home.after"

# Expansion is intentionally deferred to the child shell.
# shellcheck disable=SC2016
host_family=$(env -u DWM_TEST_MODE DWM_OS_RELEASE="$work/unsupported" bash -c \
	'. "$1"; printf "%s" "$DISTRO_FAMILY"' sh "$repo/scripts/dwm-utils.sh")
[[ $host_family == fedora ]]

root_package_command=$(DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/fedora" bash -c \
	'. "$1"; printf "%s" "$PKG_CMD"' sh "$repo/scripts/dwm-utils.sh")
if [[ $EUID -eq 0 ]]; then
	[[ $root_package_command == 'dnf install -y' ]]
else
	[[ $root_package_command == 'sudo dnf install -y' ]]
fi

set +e
snapshot_tree "$work/unsupported-home" "$work/screensaver-home.before"
DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/unsupported" \
	DWM_MUTATION_LOG="$work/mutations.log" HOME="$work/unsupported-home" \
	PATH="$work/bin:$PATH" "$repo/scripts/xscreensaver-setup.sh" \
	>"$work/xscreensaver-rejection.out" 2>&1
screensaver_status=$?
set -e
if [[ $screensaver_status -ne 1 ]]; then
	printf 'Unsupported screensaver setup exited with %s instead of 1.\n' \
		"$screensaver_status" >&2
	exit 1
fi
grep -Fq 'dwm-titus supports Fedora only.' "$work/xscreensaver-rejection.out"
snapshot_tree "$work/unsupported-home" "$work/screensaver-home.after"
if [[ -e $work/mutations.log ]] ||
	! cmp "$work/screensaver-home.before" "$work/screensaver-home.after"; then
	printf 'Unsupported screensaver setup attempted a mutation.\n' >&2
	exit 1
fi

if grep -ERq 'setenforce|/etc/selinux/config|(^|[[:space:]])(sudo[[:space:]]+)?chcon([[:space:]]|$)|semanage[[:space:]]+fcontext' \
	"$repo/install.sh" "$repo/scripts"; then
	printf 'Existing-system tools must not change host SELinux policy or assign file contexts.\n' >&2
	exit 1
fi
# restorecon is intentionally allowed for files these tools install: it applies
# the host policy's existing label and does not alter that policy.

printf 'Fedora-only platform contract: PASS\n'
