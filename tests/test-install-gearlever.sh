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
	[[ ${MOCK_FLATPAK_QUERY_FAIL:-false} != true ]] || exit 1
	if [[ -f $MOCK_FLATPAK_STATE/${2#--}-remote ]]; then
		printf 'flathub\t%s\t%s\n' "${MOCK_FLATPAK_REMOTE_URL:-https://dl.flathub.org/repo/}" "${MOCK_FLATPAK_OPTIONS:-}"
	fi
	;;
remote-add)
	[[ ${MOCK_FLATPAK_ADD_FAIL:-false} != true ]] || exit 1
	[[ ${MOCK_FLATPAK_ADD_NOOP:-false} != true ]] || exit 0
	touch "$MOCK_FLATPAK_STATE/${2#--}-remote"
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
if ((after != before + 2)); then
	printf 'Idempotent Gear Lever setup unexpectedly changed Flatpak state.\n' >&2
	exit 1
fi
grep -Fq 'Gear Lever is already installed for' "$work/idempotent.out"

rm -f "$state/user-app" "$state/user-remote"
touch "$state/system-app" "$state/system-remote"
: >"$log"
MOCK_FLATPAK_ADD_FAIL=true run_helper >"$work/system.out"
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

# Failed prerequisite commands and disabled remotes must never reach install.
for failure in query add postcheck disabled unsigned; do
	rm -f "$state/user-app" "$state/system-app" "$state/user-remote"
	: >"$log"
	query_fail=false
	add_fail=false
	add_noop=false
	options=
	case $failure in
	query) query_fail=true ;;
	add) add_fail=true ;;
	postcheck) add_noop=true ;;
	disabled | unsigned)
		touch "$state/user-remote"
		options=disabled
		[[ $failure != unsigned ]] || options=no-gpg-verify
		;;
	esac
	if MOCK_FLATPAK_QUERY_FAIL=$query_fail MOCK_FLATPAK_ADD_FAIL=$add_fail \
		MOCK_FLATPAK_ADD_NOOP=$add_noop MOCK_FLATPAK_OPTIONS=$options run_helper >"$work/$failure.out" 2>&1; then
		printf 'Gear Lever ignored %s prerequisite failure.\n' "$failure" >&2
		exit 1
	fi
	if grep -q '^install ' "$log"; then
		printf 'Gear Lever installed despite %s prerequisite failure.\n' "$failure" >&2
		exit 1
	fi
done

# A helper failure must also abort the already-installed app branches.
for scope in user system; do
	rm -f "$state/user-app" "$state/system-app"
	touch "$state/$scope-app" "$state/$scope-remote"
	if MOCK_FLATPAK_QUERY_FAIL=true run_helper >"$work/$scope-query-failure.out" 2>&1; then
		printf 'Existing %s app ignored a failed prerequisite.\n' "$scope" >&2
		exit 1
	fi
	if grep -q 'already installed' "$work/$scope-query-failure.out"; then
		printf 'Existing %s app reported success after a failed prerequisite.\n' "$scope" >&2
		exit 1
	fi
done

mkdir -p "$work/empty-bin"
if PATH="$work/empty-bin" /bin/bash "$repo/scripts/dwm-flatpak-setup" --user \
	>"$work/missing.out" 2>&1; then
	printf 'Flatpak setup ignored a missing Flatpak executable.\n' >&2
	exit 1
fi
grep -Fq 'requires the Fedora flatpak package' "$work/missing.out"

# The shared helper also prepares the factory-image system scope.
rm -f "$state/user-remote" "$state/system-remote"
: >"$log"
PATH="$mock_bin:$PATH" MOCK_FLATPAK_LOG="$log" MOCK_FLATPAK_STATE="$state" \
	"$repo/scripts/dwm-flatpak-setup" --system
grep -Fqx 'remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' "$log"
grep -Fqx 'remotes --system --show-disabled --columns=name,url,options' "$log"

"$repo/install.sh" --dry-run --non-interactive --profile recommended \
	>"$work/install-plan.out"
grep -Fq 'Gear Lever: user-scoped Flathub install (it.mijorus.gearlever)' \
	"$work/install-plan.out"

printf '%s\n' 'Gear Lever setup: PASS'
