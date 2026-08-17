#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT

test_root=$work/root
process_is_live() {
	local pid=$1 process_stat process_state

	kill -0 "$pid" 2>/dev/null || return 1
	if [[ -r /proc/$pid/stat ]]; then
		process_stat=$(<"/proc/$pid/stat")
		process_state=${process_stat#*) }
		process_state=${process_state%% *}
		[[ $process_state != Z ]]
	fi
}

assert_workspace_removed() {
	local output=$1 root=$2 label=$3 workspace
	workspace=$(sed -n 's/^==> Test workspace: //p' "$output" | sed -n '1p')
	if [[ -z $workspace || $workspace != "$root"/dwm-titus-tests.* ]]; then
		printf '%s run did not report a workspace below its test root.\n' "$label" >&2
		exit 1
	fi
	if [[ -e $workspace ]]; then
		printf '%s run left its reported workspace behind: %s\n' "$label" "$workspace" >&2
		exit 1
	fi
	if [[ ! -d $root ]]; then
		printf '%s run removed its test root: %s\n' "$label" "$root" >&2
		exit 1
	fi
}

mkdir "$work/init-bin"
cat >"$work/init-bin/od" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$work/init-bin/od"
if DWM_TEST_TMP_ROOT=$work/init-root PATH="$work/init-bin:$PATH" \
	"$repo/scripts/run-tests" true >"$work/init.out" 2>"$work/init.err"; then
	printf 'Test runner unexpectedly survived token-generation failure.\n' >&2
	exit 1
fi
if find "$work/init-root" -mindepth 1 -print -quit | grep -q .; then
	printf 'Initialization failure left a test workspace behind.\n' >&2
	exit 1
fi

success_out=$work/success.out
# Expansion is intentionally deferred to the child shell.
# shellcheck disable=SC2016
DWM_TEST_TMP_ROOT=$test_root "$repo/scripts/run-tests" \
	bash -e -c 'test "$TMPDIR" != /tmp; touch "$TMPDIR/marker"' >"$success_out"
assert_workspace_removed "$success_out" "$test_root" Successful
if find "$test_root" -mindepth 1 -print -quit | grep -q .; then
	printf 'Successful test run left temporary files behind.\n' >&2
	exit 1
fi

descendant_out=$work/descendant.out
# Expansion is intentionally deferred to the child shell.
# shellcheck disable=SC2016
DWM_TEST_TMP_ROOT=$work/descendant-root "$repo/scripts/run-tests" \
	bash -c '(trap "" TERM; exec sleep 300) & printf "descendant=%s\n" "$!"' \
	>"$descendant_out"
descendant_pid=$(sed -n 's/^descendant=//p' "$descendant_out")
if [[ -z $descendant_pid ]] || process_is_live "$descendant_pid"; then
	printf 'Successful test run left a descendant process alive: %s.\n' \
		"${descendant_pid:-unknown}" >&2
	[[ -z $descendant_pid ]] || kill -KILL "$descendant_pid" 2>/dev/null || true
	exit 1
fi
assert_workspace_removed "$descendant_out" "$work/descendant-root" Descendant

failure_out=$work/failure.out
# Expansion is intentionally deferred to the child shell.
# shellcheck disable=SC2016
if DWM_TEST_TMP_ROOT=$test_root "$repo/scripts/run-tests" \
	bash -c 'touch "$TMPDIR/failure-marker"; exit 9' >"$failure_out"; then
	printf 'Failing test command unexpectedly succeeded.\n' >&2
	exit 1
fi
assert_workspace_removed "$failure_out" "$test_root" Failed
if find "$test_root" -mindepth 1 -print -quit | grep -q .; then
	printf 'Failed test run left temporary files behind.\n' >&2
	exit 1
fi

interrupt_root=$work/interrupt-root
interrupt_out=$work/interrupt.out
# Expansion is intentionally deferred to the child shell.
# shellcheck disable=SC2016
env DWM_TEST_TMP_ROOT="$interrupt_root" "$repo/scripts/run-tests" \
	bash -c 'printf "%s\n" "$$" >"$TMPDIR/child.pid"; trap "exit 0" TERM; (trap "" TERM; exec sleep 300) & printf "%s\n" "$!" >"$TMPDIR/grandchild.pid"; mkdir -p "$TMPDIR/qualification"; touch "$TMPDIR/ready" "$TMPDIR/qualification/disk"; wait' \
	>"$interrupt_out" 2>&1 &
runner_pid=$!
ready=
child_pid=
for _ in {1..100}; do
	ready=$(find "$interrupt_root" -type f -name ready -print -quit 2>/dev/null || true)
	[[ -z $ready ]] || break
	sleep 0.05
done
if [[ -z $ready ]]; then
	kill -TERM -- "$runner_pid" 2>/dev/null || true
	wait "$runner_pid" 2>/dev/null || true
	printf 'Interrupted test run did not become ready.\n' >&2
	exit 1
fi
child_pid=$(cat "${ready%/ready}/child.pid")
grandchild_pid=$(cat "${ready%/ready}/grandchild.pid")
kill -TERM -- "$runner_pid"
if wait "$runner_pid"; then
	printf 'Interrupted test run unexpectedly succeeded.\n' >&2
	exit 1
else
	runner_status=$?
fi
if [[ $runner_status -ne 143 ]]; then
	printf 'Interrupted test run exited with %s instead of 143.\n' "$runner_status" >&2
	exit 1
fi
if process_is_live "$child_pid"; then
	printf 'Interrupted test run left its child process alive: %s.\n' "$child_pid" >&2
	kill -KILL "$child_pid" 2>/dev/null || true
	exit 1
fi
if process_is_live "$grandchild_pid"; then
	printf 'Interrupted test run left its grandchild process alive: %s.\n' "$grandchild_pid" >&2
	kill -KILL "$grandchild_pid" 2>/dev/null || true
	exit 1
fi
assert_workspace_removed "$interrupt_out" "$interrupt_root" Interrupted
if find "$interrupt_root" -mindepth 1 -print -quit | grep -q .; then
	printf 'Interrupted test run left temporary files behind.\n' >&2
	exit 1
fi

for unsafe_root in / // /tmp /tmp/..; do
	if DWM_TEST_TMP_ROOT=$unsafe_root "$repo/scripts/run-tests" true 2>"$work/unsafe.err"; then
		printf 'Test runner accepted an unsafe root alias: %s\n' "$unsafe_root" >&2
		exit 1
	fi
	grep -Fq 'Refusing unsafe DWM_TEST_TMP_ROOT' "$work/unsafe.err"
done

existing_root=$work/existing-root
mkdir -m 0750 "$existing_root"
DWM_TEST_TMP_ROOT=$existing_root "$repo/scripts/run-tests" true >"$work/existing.out"
assert_workspace_removed "$work/existing.out" "$existing_root" Existing-root
if [[ $(stat -c %a "$existing_root") != 750 ]]; then
	printf 'Test runner changed the existing test-root mode.\n' >&2
	exit 1
fi

stale_marker_out=$work/stale-marker.out
mkdir "$work/stale-workspace" "$work/stale-tmp"
DWM_TEST_WORKSPACE=$work/stale-workspace TMPDIR=$work/stale-tmp \
	DWM_TEST_TMP_ROOT=$work/stale-marker-root \
	make -s -C "$repo" check-fedora-platform >"$stale_marker_out"
grep -Fq '==> Test workspace: ' "$stale_marker_out"
grep -Fq 'Fedora-only platform contract: PASS' "$stale_marker_out"

forged_marker_out=$work/forged-marker.out
mkdir "$work/forged-workspace"
printf '%s\n' forged >"$work/forged-workspace/.runner"
DWM_TEST_WORKSPACE=$work/forged-workspace TMPDIR=$work/forged-workspace \
	DWM_TEST_RUNNER_TOKEN=wrong DWM_TEST_TMP_ROOT=$work/forged-marker-root \
	make -s -C "$repo" check-fedora-platform >"$forged_marker_out"
grep -Fq '==> Test workspace: ' "$forged_marker_out"
grep -Fq 'Fedora-only platform contract: PASS' "$forged_marker_out"

link_root=$work/link-root
ln -s "$test_root" "$link_root"
if DWM_TEST_TMP_ROOT=$link_root "$repo/scripts/run-tests" true 2>"$work/symlink.err"; then
	printf 'Test runner accepted a symbolic-link root.\n' >&2
	exit 1
fi
grep -Fq 'Refusing symbolic-link test root' "$work/symlink.err"

printf 'Managed test workspace: PASS\n'
