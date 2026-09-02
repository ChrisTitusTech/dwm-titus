#!/bin/sh
set -eu

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)

model=$repo/config/quickshell/notifications/NotificationModel.qml

grep -Fq 'notification.closed.connect(() => root.remove(item.key));' "$model"
grep -Fq 'const overflow = candidates.slice(root.maxVisible);' "$model"
grep -Fq 'root.closeItem(overflowItem, false);' "$model"
grep -Fq 'root.notifications = [];' "$model"
grep -Fq 'root.remove(item.key);' "$model"
grep -Fq 'root.closeItem(root.notifications.find(n => n.key === key), false);' "$model"
grep -Fq 'root.closeItem(root.notifications.find(n => n.key === key), true);' "$model"
grep -Fq 'property bool doNotDisturb: false' "$model"
grep -Fq 'readonly property var popupTimeoutOptions: [4000, 6000, 10000]' "$model"
grep -Fq 'readonly property bool popupSuppressed: root.policyState === "loading"' "$model"
grep -Fq 'root.applyDoNotDisturb(policyFile.doNotDisturb);' "$model"
grep -Fq 'if (root.popupSuppressed && item.urgencyName !== "critical") {' "$model"
grep -Fq 'notification.expire();' "$model"
grep -Fq 'root.addHistory(item);' "$model"
grep -Fq 'watchChanges: true' "$model"
grep -Fq 'atomicWrites: true' "$model"
grep -Fq 'onSaveFailed: error =>' "$model"
grep -Fq 'root.applyDoNotDisturb(root.confirmedDoNotDisturb);' "$model"
grep -Fq 'root.policyReloadPending = true;' "$model"

printf 'Quickshell notification lifecycle and policy: PASS\n'
