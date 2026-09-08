import QtQuick
import Quickshell
import qs.systemmanagement

ShellRoot {
    id: root
    property int assertions: 0

    function check(condition, detail) {
        root.assertions++;
        if (!condition) {
            console.error("Native snapshot FAILED: " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }

    function base() {
        return ["system-management-protocol\t1\t0", "snapshot-generation\t" + "a".repeat(64),
            "provider\tupdates\tavailable\tdelegated\tPackageKit\tFixture updates",
            "provider\trecovery\tavailable\tuser-session\tJournal\tValidated journal",
            "state\tupdate-summary\tavailable\t1\tOne update",
            "state\tupdate-last-refresh\tavailable\t10\tRecent",
            "state\tupdate-restart\tavailable\tnone\tNo restart",
            "action\tupdates-refresh\tavailable\tdelegated\tupdates\tRefresh\tConfirm first",
            "action\tupdates-install-all\tavailable\tdelegated\tupdates\tInstall\tConfirm first",
            "action\tupdates-cancel\tunavailable\tdelegated\tupdates\tCancel\tNo owner",
            "update\talpha;1;x86_64;updates\tsecurity\tinstallable\talpha\t1\tUpdate",
            "package-change\talpha;1;x86_64;updates\tupdate\talpha\t1\tUpdate"];
    }

    function nativeRows() {
        return ["provider\tregional\tavailable\tdelegated\tsystemd\tRegional state",
            "provider\taccounts\tavailable\tdelegated\tAccountsService\tAccount state",
            "provider\tprinters\tavailable\tdelegated\tCUPS\tPrinter state",
            "provider\tsources\tavailable\tdelegated\tPackageKit\tSources",
            "state\ttimezone\tavailable\tAmerica/Chicago\tSystem timezone",
            "state\tntp-enabled\tavailable\tyes\tEnabled",
            "state\tntp-synchronized\tavailable\tno\tNot yet synchronized",
            "state\tlocale\tavailable\ten_US.UTF-8\tLC_TIME=C",
            "state\taccounts-count\tavailable\t1\tOne account",
            "state\tcups-service\tavailable\tsocket-ready\tReady socket",
            "action\ttimezone-set\tavailable\tdelegated\tregional\tTimezone\tConfirm first",
            "action\tntp-set\tavailable\tdelegated\tregional\tNetwork time\tConfirm first",
            "action\tlocale-set\tavailable\tdelegated\tregional\tLanguage\tConfirm first",
            "action\taccounts-open\tavailable\tdelegated\taccounts\tAccounts\tConfirm launch",
            "action\tpassword-open\tavailable\tdelegated\taccounts\tPassword\tConfirm launch",
            "action\tprinters-open\tavailable\tdelegated\tprinters\tPrinters\tConfirm launch",
            "action\tsources-open\tavailable\tdelegated\tsources\tSources\tConfirm launch",
            "account\t/opaque/current\tcurrent\tCurrent user\tfixture",
            "repository\tfedora\tenabled\tFedora"];
    }

    function snapshot() {
        const lines = root.base();
        lines[0] = "system-management-protocol\t1\t1";
        return lines.concat(root.nativeRows());
    }

    function parse(lines) {
        return model.parseSnapshot(lines.concat(["complete\tsnapshot"]).join("\n") + "\n", model.requestGeneration);
    }

    function replaceRow(lines, prefix, replacement) {
        return lines.map(line => line.startsWith(prefix) ? replacement : line);
    }

    function malformedOwner(lines, owner, detail) {
        root.parse(lines);
        root.check(model.snapshotState === "partial", detail + " must be partial");
        root.check(model.nativeProviders[owner].status === "partial", detail + " must invalidate its owner");
        root.check(!model.actions.some(action => action.owner === owner), detail + " must remove originating offers");
        root.check(model.updates.length === 1 && model.packageChanges.length === 1, detail + " must preserve updates");
        const unaffected = owner === "regional" ? "printers" : "regional";
        root.check(model.nativeProviders[unaffected].status === "available", detail + " must preserve unrelated native state");
    }

    function informationRows() {
        const lines = [];
        for (const owner of ["information", "storage", "security", "diagnostics"])
            lines.push("provider\t" + owner + "\tavailable\t" + (owner === "diagnostics" ? "user-session" : "read-only") + "\tFixture\tRead only");
        for (const identifier of ["os-name", "os-version", "kernel-release", "architecture", "hardware-vendor", "hardware-model", "cpu-model"])
            lines.push("state\t" + identifier + "\tavailable\tFixture\tDisplay text");
        for (const identifier of ["logical-cpus", "memory-total-bytes", "memory-available-bytes", "swap-total-bytes", "swap-free-bytes", "uptime-seconds"])
            lines.push("state\t" + identifier + "\tavailable\t18446744073709551615\tExact counter");
        for (const identifier of ["selinux", "secure-boot", "firewalld", "root-encryption", "screen-lock"])
            lines.push("state\t" + identifier + "\tavailable\t" + (identifier === "selinux" ? "enforcing" : identifier === "root-encryption" ? "encrypted" : "enabled") + "\tSecurity");
        return lines.concat(["state\tfilesystem-summary\tavailable\t1\tMounts",
            "filesystem\t42\tavailable\t/dev/test\t/\text4\t18446744073709551615\t2\t3\tBytes",
            "action\thealth-open\tavailable\tuser-session\tdiagnostics\tHealth\tNavigation only"]);
    }

    function informationSnapshot() {
        const lines = root.snapshot().concat(root.informationRows());
        lines[0] = "system-management-protocol\t1\t2";
        return lines;
    }

    function informationTests() {
        root.check(root.parse(root.informationSnapshot()), "Minor two retains journal evidence");
        root.check(model.snapshotState === "ready" && model.actions.length === 11, "All cumulative providers and actions accepted");
        root.check(model.filesystems.length === 1 && model.filesystems[0].sizeBytes === "18446744073709551615", "Filesystem integers remain exact strings");
        root.check(model.nativeStates["memory-total-bytes"].value === "18446744073709551615", "Memory integer stays exact");
        for (const row of root.informationRows()) {
            const fields = row.split("\t");
            root.parse(root.informationSnapshot().concat([row]));
            root.check(model.snapshotState === "failure", "Duplicate information identity is fatal: " + fields[1]);
            root.parse(root.snapshot().concat([row]));
            root.check(model.snapshotState === "failure", "Minor one rejects inactive information owner: " + fields[1]);
            if (fields[0] !== "filesystem") {
                root.parse(root.informationSnapshot().filter(line => line !== row));
                root.check(model.snapshotState === "partial", "Missing required information record is partial: " + fields[1]);
                root.check(model.updates.length === 1 && model.nativeProviders.regional.status === "available", "Missing information cannot hide other providers");
            }
        }
        for (const value of ["18446744073709551616", "99999999999999999999", "01", "-1", "1.5", "1e3", "unknown"])
            root.malformedOwner(root.replaceRow(root.informationSnapshot(), "state\tmemory-total-bytes\t",
                "state\tmemory-total-bytes\tavailable\t" + value + "\tBad integer"), "information", "Invalid uint64 " + value);
        for (const status of ["partial", "restricted", "unavailable", "unsupported"]) {
            root.parse(root.replaceRow(root.informationSnapshot(), "state\tselinux\t", "state\tselinux\t" + status + "\tunknown\tNot known"));
            root.check(model.nativeStates.selinux.status === status, "Unknown security status stays distinct");
            root.malformedOwner(root.replaceRow(root.informationSnapshot(), "state\tselinux\t", "state\tselinux\t" + status + "\tdisabled\tUnproven"), "security", "Unavailable cannot mean disabled");
        }
        root.malformedOwner(root.replaceRow(root.informationSnapshot(), "provider\tsecurity\t",
            "provider\tsecurity\tavailable\tprivileged\tFixture\tWrong class"), "security", "Security class is fixed");
        for (const row of ["filesystem\t42\tavailable\t/dev/test\t/\text4\tunknown\t2\t3\tMissing bytes",
                "filesystem\t42\tavailable\t/dev/test\t/\text4\t18446744073709551616\t2\t3\tOverflow",
                "filesystem\t42\tunsupported\t/dev/test\t/\text4\tunknown\tunknown\tunknown\tWrong status"])
            root.malformedOwner(root.replaceRow(root.informationSnapshot(), "filesystem\t", row), "storage", "Malformed filesystem");
        let lines = root.replaceRow(root.informationSnapshot(), "filesystem\t", "filesystem\t42\tpartial\t/dev/test\t/\text4\tunknown\t2\t3\tPartial bytes");
        lines = root.replaceRow(lines, "state\tfilesystem-summary\t", "state\tfilesystem-summary\tpartial\tunknown\tSubset");
        root.parse(lines);
        root.check(model.filesystems.length === 1 && model.filesystems[0].sizeBytes === "unknown", "Usable partial mount subset retained");
        lines = root.replaceRow(root.informationSnapshot(), "provider\trecovery\t", "provider\trecovery\tpartial\tuser-session\tJournal\tBlocked");
        lines = lines.map(line => line.startsWith("action\t") && !line.startsWith("action\thealth-open\t")
            ? line.replace("\tavailable\t", "\tunavailable\t") : line);
        root.check(!root.parse(lines), "Health navigation cannot admit journal recovery");
        root.check(model.actions.some(action => action.id === "health-open" && action.availability === "available"), "Health stays accessible with blocked recovery");
        root.check(model.operationActionKind("health-open") === "", "Health is never a journaled operation");
        root.check(!model.openHealth(), "Closed pane cannot navigate to health");
        model.settingsVisible = true;
        root.check(model.openHealth(), "Blocked recovery does not block health navigation");
        root.check(health.opens === 1 && health.screen === model.targetScreen, "Health uses the fixed model and current screen");
        root.check(!model.operation.streamOwned, "Health never originates an operation");
        model.settingsVisible = false;
        root.parse(root.snapshot());
        root.check(model.filesystems.length === 0 && !model.nativeStates.selinux, "Older minor clears information projections");
    }

    function run() {
        root.check(root.parse(root.snapshot()), "Complete recovery remains known");
        root.check(model.snapshotState === "ready" && model.actions.length === 10, "Complete cumulative snapshot accepted");
        root.check(model.nativeStates.locale.detail === "LC_TIME=C", "Full override detail retained");
        root.check(model.accounts.length === 1 && model.repositories.length === 1, "Both native lists retained");
        root.check(model.accounts[0].id === "/opaque/current", "Account object remains opaque display data");
        root.check(!model.prepareUpdate("timezone-set"), "Native snapshot does not enable a new origin through update controls");
        root.parse(root.replaceRow(root.snapshot(), "state\tlocale\t", "state\tlocale\tavailable\t\tnone"));
        root.check(model.snapshotState === "ready" && model.nativeStates.locale.value === "", "Explicit empty LANG remains readable");
        root.check(model.nativeStates.timezone.status === "available" && model.actions.some(action => action.id === "locale-set"),
            "Empty LANG cannot hide timezone state or an independently offered replacement");

        root.parse(root.base());
        root.check(model.snapshotState === "ready" && model.actions.length === 3, "Minor zero remains compatible");
        root.check(Object.keys(model.nativeProviders).length === 0 && Object.keys(model.nativeStates).length === 0
            && model.accounts.length === 0 && model.repositories.length === 0, "Older snapshot clears stale cumulative projections");

        for (const row of root.nativeRows()) {
            const fields = row.split("\t");
            if (fields[0] === "account" || fields[0] === "repository") continue;
            const owner = fields[0] === "provider" ? fields[1]
                : fields[0] === "state" ? model.nativeStateOwner(fields[1]) : model.nativeActionOwner(fields[1]);
            root.malformedOwner(root.snapshot().filter(line => line !== row), owner, "Missing " + fields[1]);
            root.parse(root.snapshot().concat([row]));
            root.check(model.snapshotState === "failure", "Duplicate " + fields[1] + " is framing failure");
        }
        for (const type of ["account", "repository"]) {
            const row = root.nativeRows().find(line => line.startsWith(type + "\t"));
            root.parse(root.snapshot().concat([row]));
            root.check(model.snapshotState === "failure" && model.actions.length === 0, "Duplicate list identity clears every action");
            root.parse(root.base().concat([row]));
            root.check(model.snapshotState === "failure", "Minor zero cannot advertise an inactive list");
        }
        for (const row of ["provider\tfuture\tavailable\tdelegated\tOther\tUnknown",
                "state\tfuture\tavailable\tyes\tUnknown", "action\tfuture\tavailable\tdelegated\tregional\tUnknown\tUnknown",
                "error\tfuture\tinternal\tUnknown"]) {
            root.parse(root.snapshot().concat([row]));
            root.check(model.snapshotState === "failure", "Unknown known-record owner is fatal");
        }
        for (const mutation of [
                ["provider\tregional\t", "provider\tregional\tavailable\tprivileged\tsystemd\tWrong class", "regional"],
                ["state\tntp-enabled\t", "state\tntp-enabled\tavailable\ttrue\tWrong enum", "regional"],
                ["state\tntp-synchronized\t", "state\tntp-synchronized\tpartial\tyes\tWrong status", "regional"],
                ["state\tcups-service\t", "state\tcups-service\tpartial\trunning\tWrong status", "printers"],
                ["state\taccounts-count\t", "state\taccounts-count\tavailable\t2\tWrong count", "accounts"],
                ["action\taccounts-open\t", "action\taccounts-open\tavailable\tdelegated\tprinters\tWrong owner\tMismatch", "accounts"],
                ["account\t", "account\t/opaque/current\tcurrent\tName", "accounts"],
                ["repository\t", "repository\tfedora\tunknown\tWrong enum", "sources"]]) {
            root.malformedOwner(root.replaceRow(root.snapshot(), mutation[0], mutation[1]), mutation[2], mutation[0]);
        }
        let lines = root.replaceRow(root.snapshot(), "state\taccounts-count\t", "state\taccounts-count\tpartial\tunknown\tIncomplete inventory");
        lines = root.replaceRow(lines, "provider\taccounts\t", "provider\taccounts\tpartial\tdelegated\tAccountsService\tIncomplete inventory");
        root.parse(lines.concat(["error\taccounts\ttimeout\tPartial inventory"]));
        root.check(model.accounts.length === 1 && model.nativeStates["accounts-count"].value === "unknown", "Validated partial account subset retained");
        lines = root.replaceRow(root.snapshot(), "action\tsources-open\t", "action\tsources-open\tunavailable\tdelegated\tsources\tSources\tTool missing");
        lines = root.replaceRow(lines, "provider\tsources\t", "provider\tsources\tpartial\tdelegated\tPackageKit\tTool missing");
        root.parse(lines);
        root.check(model.repositories.length === 1, "Missing source tool cannot hide repository records");
        lines = root.replaceRow(root.snapshot(), "state\tupdate-summary\t", "state\tupdate-summary\tavailable\tbad\tMalformed updates");
        root.parse(lines);
        root.check(model.updates.length === 0 && model.nativeStates.timezone.status === "available"
            && model.actions.some(action => action.id === "timezone-set"), "Malformed updates do not suppress valid native state");
        lines = root.replaceRow(root.snapshot(), "provider\trecovery\t", "provider\trecovery\tpartial\tuser-session\tJournal\tNo session timestamp");
        root.check(root.parse(lines), "Validated native offers prove independent journal admission");
        root.check(model.nativeStates.timezone.status === "available", "Partial recovery preserves readable native state");
        const nativeIds = ["timezone-set", "ntp-set", "locale-set", "accounts-open", "password-open", "printers-open", "sources-open"];
        for (const offered of nativeIds) {
            const selected = lines.map(line => {
                const fields = line.split("\t");
                if (fields[0] === "action" && nativeIds.indexOf(fields[1]) >= 0 && fields[1] !== offered)
                    fields[2] = "unavailable";
                return fields.join("\t");
            });
            root.check(root.parse(selected), offered + " independently proves admission");
            const owner = model.nativeActionOwner(offered);
            const unrelated = owner === "regional" ? "printers" : "regional";
            root.check(root.parse(root.replaceRow(selected, "provider\t" + unrelated + "\t",
                "provider\t" + unrelated + "\tavailable\tprivileged\tWrong\tInvalid")), "Unrelated invalid owner does not block independent admission");
            root.check(!root.parse(root.replaceRow(selected, "provider\t" + owner + "\t",
                "provider\t" + owner + "\tavailable\tprivileged\tWrong\tInvalid")), "Invalid owner cannot prove admission");
            root.check(!root.parse(selected.filter(line => !line.startsWith("provider\trecovery\t"))), "Missing recovery fails closed");
            root.check(!model.actions.some(action => nativeIds.indexOf(action.id) >= 0), "Missing recovery removes native offers");
            root.check(model.nativeStates.timezone.status === "available", "Missing recovery retains readable native state");
            root.check(!root.parse(root.replaceRow(selected, "provider\trecovery\t",
                "provider\trecovery\tpartial\tprivileged\tWrong\tInvalid")), "Malformed recovery fails closed");
            root.check(!model.actions.some(action => nativeIds.indexOf(action.id) >= 0), "Malformed recovery removes native offers");
            root.check(model.nativeStates.timezone.status === "available", "Malformed recovery retains readable native state");
            const kind = model.operationActionKind(offered);
            root.check(!root.parse(selected.concat([["active-operation", "op-" + "e".repeat(32), offered, kind,
                "cancel-requested", "unknown", "no", "Invalid native cancellation"].join("\t")])), "Native cancellation request cannot enter through a snapshot");
            root.check(model.snapshotState === "failure" && model.actions.length === 0, "Invalid native active record clears all offers");
        }
        root.check(!root.parse(lines.map(line => line.startsWith("action\t") ? line.replace("\tavailable\t", "\tunavailable\t") : line)),
            "No native offer cannot establish empty journal");
        root.parse(lines);
        model.settingsVisible = true;
        model.snapshotOwned = false;
        model.snapshotPending = false;
        model.requiredPending = false;
        model.discovery.visible = true;
        model.discovery.ready = true;
        root.check(model.updateActionReason("updates-refresh").indexOf("Complete recovery") >= 0,
            "Independent native admission does not bypass update recovery");
        model.snapshotOwned = true;
        model.settingsVisible = false;
        model.discovery.visible = false;
        model.discovery.ready = false;
        model.operation.blocked = true;
        root.check(root.parse(lines) && model.operation.blocked, "Parsing an offer never clears uncertain owner state");
        model.operation.blocked = false;

        for (const family of ["account", "repository"]) {
            const count = family === "account" ? 256 : 512;
            lines = root.snapshot().filter(line => !line.startsWith(family + "\t"));
            if (family === "account") lines = root.replaceRow(lines, "state\taccounts-count\t",
                "state\taccounts-count\tavailable\t256\tComplete bounded inventory");
            const records = [];
            for (let index = 0; index < count; index++) records.push(family === "account"
                ? "account\t/opaque/" + index + "\tother\tName\tuser" + index
                : "repository\tid" + index + "\tdisabled\tDescription");
            root.parse(lines.concat(records));
            root.check(model.snapshotState === "ready" && (family === "account" ? model.accounts.length : model.repositories.length) === count,
                "Exact " + family + " count boundary accepted");
            root.malformedOwner(lines.concat(records, [records[0].replace(family === "account" ? "/opaque/0" : "id0", "extra")]),
                family === "account" ? "accounts" : "sources", family + " count overflow");
            const overflowRow = records[0].replace(family === "account" ? "/opaque/0" : "id0", "extra");
            root.parse(lines.concat(records, [overflowRow, overflowRow]));
            root.check(model.snapshotState === "failure", family + " duplicate after count overflow remains fatal");
            const oversized = [];
            for (let index = 0; index < count; index++) oversized.push(family === "account"
                ? "account\t/" + String(index).padStart(511, "x") + "\tother\t" + "n".repeat(512) + "\t" + "u".repeat(512)
                : "repository\t" + String(index).padStart(512, "x") + "\tenabled\t" + "d".repeat(512));
            root.malformedOwner(lines.concat(oversized), family === "account" ? "accounts" : "sources", family + " encoded-byte overflow");
            root.parse(lines.concat(oversized, [oversized[oversized.length - 1]]));
            root.check(model.snapshotState === "failure", family + " duplicate after byte overflow remains fatal");
        }
        for (const family of ["update", "package-change"]) {
            lines = root.snapshot().filter(line => !line.startsWith(family + "\t"));
            const records = [];
            for (let index = 0; index < 4097; index++) records.push(family === "update"
                ? "update\tid" + index + "\tnormal\tblocked\tname\t1\tSummary"
                : "package-change\tid" + index + "\tinstall\tname\t1\tSummary");
            root.parse(lines.concat(records, [records[records.length - 1]]));
            root.check(model.snapshotState === "failure", family + " duplicate after overflow remains fatal");
        }
        lines = root.snapshot().filter(line => !line.startsWith("account\t"));
        for (let index = 0; index < 9217; index++) lines.push("account\t/" + index + "\tother\tName\tuser");
        root.parse(lines);
        root.check(model.snapshotState === "failure", "Overall list reservation bounds duplicate tracking");
        root.malformedOwner(root.snapshot().concat(["error\tregional\tbogus\tBad code"]), "regional", "Owned illegal enum");
        root.parse(root.snapshot().concat(["future-record\tignored", "error\tregional\tunsupported\tReadable state\textra ignored"]));
        root.check(model.snapshotState === "ready", "Unknown records and trailing fields remain append-compatible");
        root.parse(root.snapshot().concat(["future-record\t" + "x".repeat(1024 * 1024)]));
        root.check(model.snapshotState === "failure", "Non-list reservation enforced independently of total size");
        root.parse(root.snapshot().concat(["complete\tsnapshot"]));
        root.check(model.snapshotState === "failure", "Duplicate completion is fatal");
        root.parse(root.snapshot());
        const old = model.nativeStates;
        model.parseSnapshot("malformed", model.requestGeneration - 1);
        root.check(model.nativeStates === old, "Stale snapshot cannot replace current projections");
        root.check(!model.operation.streamOwned, "Parsing never originates an operation");
        for (const entry of [["timezone-set", 1], ["ntp-set", 1], ["locale-set", 2],
                ["accounts-open", 3], ["password-open", 3], ["printers-open", 4],
                ["sources-open", 0], ["updates-refresh", 0], ["updates-install-all", 0], ["unknown", -1]]) {
            const monitors = model.discoveryModels();
            for (const monitor of monitors) {
                monitor.cycle.enabled = true;
                monitor.cycle.phase = "idle";
                monitor.publish();
            }
            model.invalidateActionDiscovery(entry[0]);
            for (let index = 0; index < monitors.length; index++)
                root.check(monitors[index].phase === (index === entry[1] ? "initial-pending" : "idle"),
                    entry[0] + " invalidates only its fixed provider");
        }
        root.informationTests();
        console.info("Native snapshot tests: PASS (" + root.assertions + " assertions)");
        Qt.quit();
    }

    QtObject {
        id: health
        property int opens: 0
        property var screen: null
        function openOnScreen(value) { opens++; screen = value; }
    }
    SystemManagementModel {
        id: model
        healthModel: health
        targetScreen: "fixed-test-screen"
        // This fixture exercises only parsing. Reserve the finite-read slot
        // so automatic startup recovery queues instead of launching a helper
        // that Qt.quit would kill before its capture-file cleanup can finish.
        snapshotOwned: true
    }
    Component.onCompleted: Qt.callLater(root.run)
}
