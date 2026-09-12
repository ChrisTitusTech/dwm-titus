#!/bin/bash
# Required image tools, downloaded and verified only in the disposable factory.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[[ $(id -u) == 0 && -f /etc/dwm-titus-factory-target && $(uname -m) == x86_64 ]]
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
starship_version=1.26.0
starship_sha=b7c232b0e8249d8e55a40beb79c5c43a7d370f3f9408bd215deb0170daeaadf3
printf 'Downloading required Starship %s (SHA-256 verified)\n' "$starship_version"
curl --fail --location --silent --show-error --retry 3 --connect-timeout 10 --max-time 120 \
	"https://github.com/starship/starship/releases/download/v$starship_version/starship-x86_64-unknown-linux-musl.tar.gz" \
	-o "$work/starship.tar.gz"
printf '%s  %s\n' "$starship_sha" "$work/starship.tar.gz" | sha256sum --check --status
tar -xzf "$work/starship.tar.gz" -C "$work" starship
install -o root -g root -m 0755 "$work/starship" /usr/local/bin/starship
# Use the same reviewed release as install-herdr, without executing a mutable
# upstream installer (which now follows latest.json instead of this version).
herdr_version=0.7.5
herdr_sha=3dc83288073e4c2d3c679a30e7be97bcca9141c6fd17dbbb9219142e95c59253
printf 'Downloading required Herdr %s (SHA-256 verified)\n' "$herdr_version"
curl --fail --location --silent --show-error --retry 3 --connect-timeout 10 --max-time 120 \
	"https://github.com/herdrdev/herdr/releases/download/v$herdr_version/herdr-linux-x86_64" \
	-o "$work/herdr"
printf '%s  %s\n' "$herdr_sha" "$work/herdr" | sha256sum --check --status
install -o root -g root -m 0755 "$work/herdr" /usr/local/bin/herdr
install -d /usr/local/share/doc/starship /usr/local/share/doc/herdr
install -m 0644 /usr/share/dwm-titus-image/docs/licenses/starship-LICENSE /usr/local/share/doc/starship/LICENSE
install -m 0644 /usr/share/dwm-titus-image/docs/licenses/herdr-LICENSE /usr/local/share/doc/herdr/LICENSE
# Keep the corresponding pinned source with the redistributed Herdr binary.
curl --fail --location --silent --show-error --retry 3 --connect-timeout 10 --max-time 120 \
	"https://github.com/herdrdev/herdr/archive/refs/tags/v$herdr_version.tar.gz" \
	-o "$work/herdr-source.tar.gz"
printf '%s  %s\n' 5ea0f1003af1801a6a85d201b6fa7e1de46686fccb7df1d3fa3a03c4ec2be68c "$work/herdr-source.tar.gz" | sha256sum --check --status
install -m 0644 "$work/herdr-source.tar.gz" /usr/local/share/doc/herdr/source.tar.gz
starship --version
herdr --version
sha256sum /usr/local/bin/starship /usr/local/bin/herdr \
	>/usr/share/dwm-titus-image/tool-sha256.txt
