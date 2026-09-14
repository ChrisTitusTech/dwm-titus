#!/bin/bash
# Share fresh-account defaults with the supported Fedora installer.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
bash "$repo/scripts/seed-default-apps.sh" --image
