#!/bin/sh
set -eu

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)

model=$repo/config/quickshell/notifications/NotificationModel.qml
pane=$repo/config/quickshell/settings/AppearanceSettingsPane.qml

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
grep -Fq '|| root.policyState === "partial"' "$model"
grep -Fq '|| root.policyState === "unavailable"' "$model"
grep -Fq 'root.applyDoNotDisturb(policy.doNotDisturb);' "$model"
grep -Fq 'if (root.popupSuppressed && item.urgencyName !== "critical") {' "$model"
grep -Fq 'notification.expire();' "$model"
grep -Fq 'root.addHistory(item);' "$model"
grep -Fq 'watchChanges: true' "$model"
grep -Fq 'atomicWrites: true' "$model"
grep -Fq 'policy = JSON.parse(policyFile.text());' "$model"
grep -Fq 'policyFile.setText(JSON.stringify({' "$model"
grep -Fq 'onSaveFailed: error =>' "$model"
grep -Fq 'root.applyDoNotDisturb(root.confirmedDoNotDisturb);' "$model"
grep -Fq 'root.popupTimeoutMs = root.confirmedPopupTimeoutMs;' "$model"
grep -Fq 'root.dismissNonCriticalPopups();' "$model"
grep -Fq 'root.policyReloadPending = true;' "$model"
grep -Fq 'else root.beginPolicyReload(false);' "$model"
grep -Fq 'readonly property bool policyResetReady: !root.policySaving' "$model"
if grep -A1 -F 'readonly property bool policyResetReady:' "$model" |
	grep -Fq 'policyState !== "unavailable"'; then
	printf 'Notification reset cannot recover from a transient save failure\n' >&2
	exit 1
fi
if grep -Fq 'policySelfWriteExpected' "$model"; then
	printf 'Notification policy still guesses FileView save signal ordering\n' >&2
	exit 1
fi
if grep -Fq '} else if (root.policySaving)' "$model"; then
	printf 'Notification policy reload still discards the next change as a self-write\n' >&2
	exit 1
fi
grep -Fq 'error === FileViewError.FileNotFound' "$model"
grep -Fq 'root.policyState = "partial";' "$model"
policy_detail_line=$(grep -nF 'text: root.notificationModel.policyDetail' "$pane" | cut -d: -f1)
sed -n "$((policy_detail_line - 5)),$((policy_detail_line - 1))p" "$pane" |
	grep -Fq 'visible: root.notificationCapability.status === "available"'

printf 'Quickshell notification lifecycle and policy: PASS\n'
