#!/usr/bin/env bash
set -euo pipefail

# Default-release cases must not inherit the caller's compatibility selection.
unset DWM_TEST_FEDORA_RELEASE

# Disposable fixture repositories must not spawn background Git maintenance
# that races their removal or rewrites the host-immutability snapshot.
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=gc.auto GIT_CONFIG_VALUE_0=0
export GIT_CONFIG_KEY_1=maintenance.auto GIT_CONFIG_VALUE_1=false

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ -x $repo/scripts/run-tests-podman ]] || {
	printf 'Missing executable scripts/run-tests-podman\n' >&2
	exit 1
}
[[ -f $repo/tests/containers/fedora-45/Containerfile ]] || {
	printf 'Missing Fedora 45 Containerfile\n' >&2
	exit 1
}
work=$(mktemp -d "${TMPDIR:-/tmp}/podman-contract.XXXXXX")
trap 'find "$work" -depth -delete' EXIT
mkdir -p "$work/bin" "$work/repository/scripts" "$work/repository/tests/containers/fedora-45"
cp "$repo/scripts/run-tests-podman" "$work/repository/scripts/"
cp "$repo/scripts/run-tests" "$repo/scripts/dwm-packages.sh" "$work/repository/scripts/"
cp "$repo/tests/containers/fedora-45/Containerfile" "$work/repository/tests/containers/fedora-45/"
mkdir -p "$work/repository/tests/containers/fedora-44"
cp "$repo/tests/containers/fedora-44/Containerfile" "$work/repository/tests/containers/fedora-44/"
printf 'ignored/\n' >"$work/repository/.gitignore"
printf 'original\n' >"$work/repository/tracked"
printf 'deleted\n' >"$work/repository/deleted"
mkdir "$work/repository/directory"
printf 'child\n' >"$work/repository/directory/file"
git -C "$work/repository" init -q
git -C "$work/repository" add .
git -C "$work/repository" -c user.name=Test -c user.email=test@example.invalid commit -qm fixture
git -C "$work/repository" worktree add -q --detach "$work/current worktree"
source_tree=$work/current\ worktree
metadata=$(git -C "$source_tree" rev-parse --absolute-git-dir)
ln -s repository "$work/repository-alias"
printf 'gitdir: %s\n' "${metadata/"$work/repository"/"$work/repository-alias"}" >"$source_tree/.git"
git -C "$source_tree" -c user.name=Test -c user.email=test@example.invalid commit --allow-empty -qm 'linked head'
selected_head=$(git -C "$source_tree" rev-parse HEAD)
[[ -z $(git -C "$source_tree" for-each-ref --contains "$selected_head") ]]
printf 'modified\n' >"$source_tree/tracked"
git -C "$source_tree" add tracked
rm "$source_tree/deleted"
printf 'untracked\n' >"$source_tree/new source"
printf 'newline\n' >"$source_tree/"$'new\nline'
printf 'literal\n' >"$source_tree/:(glob)literal"
mkdir "$source_tree/ignored"
printf 'scratch\n' >"$source_tree/ignored/scratch"
printf 'staged ignored\n' >"$source_tree/ignored/staged"
git -C "$source_tree" add -f ignored/staged
ln -s tracked "$source_tree/link"
rm "$source_tree/directory/file"
rmdir "$source_tree/directory"
ln -s tracked "$source_tree/directory"
export CONTRACT_WORK=$work

# Mock container execution while preserving real Git staging and test commands.
cat >"$work/bin/podman" <<'PY'
#!/usr/bin/env python3
import io
import os
from pathlib import Path
import subprocess
import sys
import tarfile

work = Path(os.environ['CONTRACT_WORK'])
args = sys.argv[1:]
release = os.environ.get('DWM_TEST_FEDORA_RELEASE', '45')
containerfile = f'tests/containers/fedora-{release}/Containerfile'
with (work / 'calls').open('a') as log:
    log.write(args[0] + '\n')
if args[0] == 'info':
    assert args == ['info', '--format', '{{.Host.Security.Rootless}}'], args
    print(os.environ.get('CONTRACT_ROOTLESS', 'true'))
    sys.exit(int(os.environ.get('CONTRACT_INFO_STATUS', '0')))
if args[0] == 'build':
    assert args == ['build', '--tag', f'localhost/dwm-titus-tests:fedora-{release}',
                    '--file', containerfile, '-'], args
    archive = tarfile.open(fileobj=io.BytesIO(sys.stdin.buffer.read()))
    assert set(archive.getnames()) == {'scripts/dwm-packages.sh',
                                      containerfile}
    text = archive.extractfile(containerfile).read().decode()
    assert text.splitlines()[0] == f'FROM registry.fedoraproject.org/fedora:{release}'
    assert 'scripts/dwm-packages.sh' in text
    for profile in ['ci-smoke', 'required', 'wifi', 'terminal', 'desktop', 'system-management', 'qml-validation']:
        assert profile in text
    sys.exit(int(os.environ.get('CONTRACT_BUILD_STATUS', '0')))
assert args[0] == 'run', args
assert args[1:8] == ['--rm', '--interactive', '--network=private',
                      '--security-opt=label=disable', '--security-opt=unmask=/proc/*', '--mount',
                      f'type=bind,src={work}/repository/.git,dst=/source/repository,ro=true,bind-nonrecursive'], args
assert args[8:10] == ['--mount',
                    f'type=bind,src={work}/current worktree,dst=/source/worktree,ro=true,bind-nonrecursive'], args
assert args[10:14] == [f'localhost/dwm-titus-tests:fedora-{release}', 'bash', '-c', args[13]], args
assert args[14] == 'container-stage', args
assert len(args[15]) == 40, args
script = args[13]
stage = work / 'container'
stage.mkdir()
script = script.replace('/source/repository', str(work / 'repository/.git'))
# Paths containing spaces must remain quoted by the runner's staging script.
script = script.replace('/source/worktree', str(work / 'current worktree'))
script = script.replace('/workspace', str(stage))
# The mock runs staging directly on its host, not inside a container. Keep
# container account/display setup out of this fixture even when invoked as root;
# the real rootless runner integration covers that namespaced setup.
root_setup = 'if ((EUID == 0)); then'
assert script.count(root_setup) == 1
script = script.replace(root_setup, 'if false; then', 1)
if os.environ.get('CONTRACT_STAGE_FAILURE'):
    args[15] = '0' * 40
result = subprocess.run(['bash', '-c', script, *args[14:]], input=sys.stdin.buffer.read())
import shutil
shutil.rmtree(stage)
sys.exit(result.returncode)
PY
chmod +x "$work/bin/podman"
cat >"$work/bin/findmnt" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $* == '--raw --noheadings --output TARGET' ]]
if [[ -n ${CONTRACT_POST_BUILD_MOUNT:-} && $(tail -n 1 "$CONTRACT_WORK/calls") == build ]]; then
	printf '%s\n' "$CONTRACT_POST_BUILD_MOUNT"
else
	printf '%s\n' "${CONTRACT_MOUNTS-/}"
fi
exit "${CONTRACT_MOUNT_STATUS:-0}"
SH
chmod +x "$work/bin/findmnt"

snapshot() {
	GIT_OPTIONAL_LOCKS=0 git -C "$source_tree" status --porcelain=v1
	git -C "$source_tree" show-ref
	git -C "$source_tree" rev-parse HEAD
	sha256sum "$source_tree/.git"
	find "$work/repository/.git" -type f -print0 | sort -z | xargs -0 sha256sum
}
snapshot >"$work/before"
runner=$source_tree/scripts/run-tests-podman
export PATH="$work/bin:$PATH"

expect_failure() {
	local expected=$1 message=$2 status
	shift 2
	: >"$work/calls"
	if "$@" >"$work/out" 2>"$work/err"; then
		printf 'Expected failure: %s\n' "$message" >&2
		exit 1
	else
		status=$?
	fi
	[[ $status == "$expected" ]] || {
		printf 'Expected status %s for %s, got %s\n' "$expected" "$message" "$status" >&2
		cat "$work/err" >&2
		exit 1
	}
	grep -Fq "$message" "$work/err"
}

expect_failure 2 'Supported test releases are Fedora 44 and 45' env DWM_TEST_FEDORA_RELEASE=46 "$runner"
[[ ! -s $work/calls ]]
expect_failure 2 'Rootless Podman is required' env CONTRACT_ROOTLESS=false "$runner"
[[ $(<"$work/calls") == info ]]
expect_failure 2 'Rootless Podman is required' env CONTRACT_ROOTLESS=unknown "$runner"
[[ $(<"$work/calls") == info ]]
expect_failure 2 'Could not query Podman rootless state' env CONTRACT_INFO_STATUS=19 "$runner"
[[ $(<"$work/calls") == info ]]
expect_failure 2 'Could not inspect host mounts' env CONTRACT_MOUNT_STATUS=19 "$runner"
[[ $(<"$work/calls") == info ]]
expect_failure 2 'Could not inspect host mounts' env CONTRACT_MOUNTS= "$runner"
[[ $(<"$work/calls") == info ]]
expect_failure 2 'Could not inspect host mounts: invalid target' env CONTRACT_MOUNTS=relative "$runner"
[[ $(<"$work/calls") == info ]]
mount_source=${source_tree// /\\x20}
for child in "$mount_source/ignored" "$work/repository/.git/objects"; do
	expect_failure 2 'Nested host mounts are unsupported' env CONTRACT_MOUNTS="$child" "$runner"
	[[ $(<"$work/calls") == info ]]
done
expect_failure 2 'Nested host mounts are unsupported' env CONTRACT_POST_BUILD_MOUNT="$mount_source/ignored" "$runner"
[[ $(<"$work/calls") == $'info\nbuild' ]]
expect_failure 23 'Fedora 45 image build failed' env CONTRACT_BUILD_STATUS=23 "$runner"
[[ $(<"$work/calls") == $'info\nbuild' ]]
expect_failure 128 'Container staging failed (status 128)' env CONTRACT_STAGE_FAILURE=1 "$runner"
mkdir "$work/no-podman"
ln -s "$(command -v bash)" "$work/no-podman/bash"
expect_failure 2 'Required command is unavailable: podman' env PATH="$work/no-podman" "$runner"
[[ ! -s $work/calls ]]
mkdir "$work/no-findmnt"
for dependency in bash git tar; do
	ln -s "$(command -v "$dependency")" "$work/no-findmnt/$dependency"
done
ln -s "$work/bin/podman" "$work/no-findmnt/podman"
expect_failure 2 'Required command is unavailable: findmnt' env PATH="$work/no-findmnt" "$runner"
[[ ! -s $work/calls ]]

# Check actual disposable snapshot contents, history, and managed forwarding.
# shellcheck disable=SC2016
env CONTRACT_MOUNTS=$'/\n'"$mount_source"$'\n'"$mount_source-sibling/child" "$runner" bash -e -c '
[[ $(<tracked) == modified && ! -e deleted && $(<"new source") == untracked ]]
[[ -e $'"'"'new\nline'"'"' && -L link && -L directory && ! -e ignored/scratch ]]
[[ -d .git && -z $(git status --porcelain) ]]
[[ $(git log -1 --format=%s) == "Disposable test snapshot" ]]
[[ $(git rev-list --count HEAD) == 3 && $(git log -1 --format=%s HEAD^) == "linked head" ]]
[[ $(git rev-parse HEAD^) == "$1" && $(git show HEAD:ignored/staged) == "staged ignored" ]]
[[ $(git show "HEAD::(glob)literal") == literal ]]
[[ -n $DWM_TEST_WORKSPACE && $2 == "argument with spaces" && $3 == "--flag=value" ]]
' contract "$selected_head" 'argument with spaces' --flag=value >"$work/success"

expect_failure 17 'Container test command failed (status 17)' "$runner" bash -c 'exit 17'

# A default invocation after a custom one must still use the existing gate.
# shellcheck disable=SC2016 # Make expands this variable inside the container.
printf 'check:\n\t@test -n "$(DWM_TEST_WORKSPACE)"\n' >"$source_tree/Makefile"
"$runner" >"$work/default"
rm "$source_tree/Makefile"
env DWM_TEST_FEDORA_RELEASE=44 "$runner" bash -c 'test -e tracked' >"$work/fedora44"
snapshot >"$work/after"
cmp "$work/before" "$work/after"
[[ ! -e $work/container ]]
printf 'Rootless Fedora 44/45 runner contract: PASS\n'
