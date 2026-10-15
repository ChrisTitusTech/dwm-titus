#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
model=$repo/config/quickshell/health/SystemHealthModel.qml
window=$repo/config/quickshell/health/SystemHealthWindow.qml

test -f "$model"
test -f "$window"

# 1. Static contract assertions on SystemHealthModel.qml
grep -Fq 'function categoryWarningCount(' "$model"
grep -Fq 'function categoryErrorCount(' "$model"

# 2. Static contract assertions on SystemHealthWindow.qml
grep -Fq 'categoryWarningCount(' "$window"
grep -Fq 'categoryErrorCount(' "$window"
grep -Fq 'Theme.warning' "$window"
grep -Fq 'Theme.danger' "$window"
grep -Fq 'Theme.readableText(Theme.warning, Theme.dangerSurface)' "$window"
grep -Fq 'Theme.readableText(Theme.danger, Theme.dangerSurface)' "$window"

# 3. Executable assertions via quickshell if available
if ! command -v quickshell >/dev/null 2>&1; then
	printf '%s\n' 'SKIP: Quickshell is unavailable; executable model assertions were not run.'
	exit 0
fi

tmp=$(mktemp -d "${DWM_TEST_WORKSPACE:-${DWM_TEST_TMP_ROOT:-${TMPDIR:-/tmp}}}/health-badges-qml.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/config/core" "$tmp/config/health"

cp "$repo/config/quickshell/core/Theme.qml" "$tmp/config/core/Theme.qml"
cp "$repo/config/quickshell/core/Commands.qml" "$tmp/config/core/Commands.qml"
cp "$repo/config/quickshell/health/SystemHealthModel.qml" "$tmp/config/health/SystemHealthModel.qml"

cat >"$tmp/config/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "health"

ShellRoot {
    id: root

    SystemHealthModel {
        id: healthModel
    }

    Timer {
        interval: 10
        running: true
        repeat: false
        onTriggered: {
            // Seed rows into healthModel
            healthModel.rows = [
                { id: "b1", category: "boot", status: "warn", kind: "check" },
                { id: "b2", category: "boot", status: "warn", kind: "check" },
                { id: "b3", category: "boot", status: "warn", kind: "check" },
                { id: "b4", category: "boot", status: "error", kind: "check" },
                { id: "s1", category: "services", status: "warn", kind: "check" },
                { id: "n1", category: "network", status: "error", kind: "check" },
                { id: "st1", category: "storage", status: "ok", kind: "check" }
            ];

            function assertEq(actual, expected, label) {
                if (actual !== expected) {
                    throw new Error("Assertion failed for " + label + ": expected " + expected + ", got " + actual);
                }
            }

            // Category "boot" has 3 warnings, 1 error
            assertEq(healthModel.categoryWarningCount("boot"), 3, "boot warning count");
            assertEq(healthModel.categoryErrorCount("boot"), 1, "boot error count");

            // Category "services" has 1 warning, 0 errors
            assertEq(healthModel.categoryWarningCount("services"), 1, "services warning count");
            assertEq(healthModel.categoryErrorCount("services"), 0, "services error count");

            // Category "network" has 0 warnings, 1 error
            assertEq(healthModel.categoryWarningCount("network"), 0, "network warning count");
            assertEq(healthModel.categoryErrorCount("network"), 1, "network error count");

            // Category "storage" has 0 warnings, 0 errors
            assertEq(healthModel.categoryWarningCount("storage"), 0, "storage warning count");
            assertEq(healthModel.categoryErrorCount("storage"), 0, "storage error count");

            // Category "overview" aggregates all warnings (4) and errors (2)
            assertEq(healthModel.categoryWarningCount("overview"), 4, "overview warning count");
            assertEq(healthModel.categoryErrorCount("overview"), 2, "overview error count");

            console.log("All health badge model assertions passed.");
            Qt.quit();
        }
    }
}
QML

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
timeout 15 quickshell --no-duplicate --path "$tmp/config/shell.qml" --no-color

printf '%s\n' 'System Health category badges test: PASS'
