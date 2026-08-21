#!/usr/bin/env bash
set -euo pipefail

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd
)
helper=$repo/scripts/install-gearlever
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mock_bin=$work/bin
state=$work/state
log=$work/flatpak.log
mime_log=$work/xdg-mime.log
mkdir -p "$mock_bin" "$state"

cat >"$mock_bin/flatpak" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$MOCK_FLATPAK_LOG"

case $1 in
info)
	case $2 in
	--user) test -f "$MOCK_FLATPAK_STATE/user-app" ;;
	--system) test -f "$MOCK_FLATPAK_STATE/system-app" ;;
	*) exit 2 ;;
	esac
	;;
remotes)
	if [[ -f $MOCK_FLATPAK_STATE/user-remote ]]; then
		printf 'flathub\t%s\n' "${MOCK_FLATPAK_REMOTE_URL:-https://dl.flathub.org/repo/}"
	fi
	;;
remote-add)
	touch "$MOCK_FLATPAK_STATE/user-remote"
	;;
install)
	if [[ ${MOCK_FLATPAK_INSTALL_FAIL:-false} == true ]]; then
		exit 1
	fi
	touch "$MOCK_FLATPAK_STATE/user-app"
	;;
*) exit 2 ;;
esac
MOCK
chmod +x "$mock_bin/flatpak"

cat >"$mock_bin/xdg-mime" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$MOCK_XDG_MIME_LOG"
case $1 in
query)
	if [[ -f $MOCK_FLATPAK_STATE/mime-default ]]; then
		printf '%s\n' it.mijorus.gearlever.desktop
	fi
	;;
default)
	[[ $2 == it.mijorus.gearlever.desktop ]]
	[[ $3 == application/vnd.appimage ]]
	touch "$MOCK_FLATPAK_STATE/mime-default"
	;;
*) exit 2 ;;
esac
MOCK
chmod +x "$mock_bin/xdg-mime"

run_helper() {
	PATH="$mock_bin:$PATH" \
		MOCK_FLATPAK_LOG="$log" \
		MOCK_FLATPAK_STATE="$state" \
		MOCK_XDG_MIME_LOG="$mime_log" \
		bash "$helper"
}

run_helper >"$work/install.out"
grep -Fqx 'remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' "$log"
grep -Fqx 'install --user --noninteractive flathub it.mijorus.gearlever' "$log"
grep -Fqx 'default it.mijorus.gearlever.desktop application/vnd.appimage' "$mime_log"
grep -Fq 'Gear Lever is ready.' "$work/install.out"

before=$(wc -l <"$log")
run_helper >"$work/idempotent.out"
after=$(wc -l <"$log")
if ((after != before + 1)); then
	printf 'Idempotent Gear Lever setup unexpectedly changed Flatpak state.\n' >&2
	exit 1
fi
grep -Fq 'Gear Lever is already installed for' "$work/idempotent.out"

rm -f "$state/user-app" "$state/user-remote"
touch "$state/system-app"
: >"$log"
run_helper >"$work/system.out"
grep -Fqx 'info --user it.mijorus.gearlever' "$log"
grep -Fqx 'info --system it.mijorus.gearlever' "$log"
if grep -Eq '^(remote-add|install) ' "$log"; then
	printf 'Gear Lever setup duplicated an existing system installation.\n' >&2
	exit 1
fi
grep -Fq 'Gear Lever is already installed system-wide.' "$work/system.out"

rm -f "$state/system-app" "$state/mime-default"
touch "$state/user-remote"
if PATH="$mock_bin:$PATH" \
	MOCK_FLATPAK_LOG="$log" \
	MOCK_FLATPAK_STATE="$state" \
	MOCK_FLATPAK_REMOTE_URL=https://example.invalid/repo/ \
	MOCK_XDG_MIME_LOG="$mime_log" \
	bash "$helper" >"$work/untrusted.out" 2>"$work/untrusted.err"; then
	printf 'Gear Lever setup trusted a non-official Flathub remote.\n' >&2
	exit 1
fi
grep -Fq 'Refusing non-official user Flathub remote URL' "$work/untrusted.err"

touch "$state/user-remote"
if PATH="$mock_bin:$PATH" \
	MOCK_FLATPAK_LOG="$log" \
	MOCK_FLATPAK_STATE="$state" \
	MOCK_XDG_MIME_LOG="$mime_log" \
	MOCK_FLATPAK_INSTALL_FAIL=true \
	bash "$helper" >"$work/failure.out" 2>"$work/failure.err"; then
	printf 'Gear Lever setup ignored a failed Flatpak install.\n' >&2
	exit 1
fi

"$repo/install.sh" --dry-run --non-interactive --profile recommended \
	>"$work/install-plan.out"
grep -Fq 'Gear Lever: user-scoped Flathub install (it.mijorus.gearlever)' \
	"$work/install-plan.out"

printf '%s\n' 'Gear Lever setup: PASS'
