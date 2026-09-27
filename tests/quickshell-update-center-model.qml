import QtQuick
import "../config/quickshell/updatecenter/UpdateCenterProtocol.js" as Protocol

Item {
    function require(condition, message) {
        if (!condition) throw new Error(message);
    }

    function snapshot(providerId, url) {
        return "update-center-protocol\t1\t0\n"
            + "provider\t" + providerId + "\tFedora\tavailable\t1\t1\tfresh\t10\tyes\t\tReady\n"
            + "item\t" + providerId + "\tupdate\tPackage\t1\t2\tpkg\tsystem\t" + (url || "https://example.test/release") + "\n"
            + "complete\tsnapshot\n";
    }

    Component.onCompleted: {
        try {
            const parsed = Protocol.parseSnapshot(snapshot("fedora"));
            require(parsed !== null && parsed.providers.length === 1, "valid snapshot must parse atomically");
            require(parsed.providers[0].items.length === 1, "items must attach to their provider");
            require(Object.isFrozen(parsed) && Object.isFrozen(parsed.providers), "parsed snapshot must be immutable");

            const invalid = [
                snapshot("fedora").replace("complete\tsnapshot\n", "provider\tfedora\tFedora\tavailable\t0\t0\tfresh\t10\tno\t\tDuplicate\ncomplete\tsnapshot\n"),
                snapshot("fedora").replace("item\tfedora", "unknown\tfedora"),
                snapshot("fedora").replace("\t1\t1\tfresh", "\t2\t1\tfresh"),
                snapshot("fedora", "http://example.test/release"),
                snapshot("fedora").replace("update-center-protocol\t1\t0", "update-center-protocol\t2\t0"),
                snapshot("fedora").replace("complete\tsnapshot\n", ""),
                "update-center-protocol\t1\t0\n" + Array(16385).fill("item\tfedora\tupdate\tP\t1\t2\tp\tsystem\t").join("\n") + "\ncomplete\tsnapshot\n"
            ];
            for (const payload of invalid)
                require(Protocol.parseSnapshot(payload) === null, "malformed snapshot must fail closed");

            const operation = Protocol.parseAction("update-center-action-protocol\t1\t0\noperation\top-0123456789abcdef0123456789abcdef\tfedora\tupdate\trunning\tpending\ncomplete\taction\n");
            require(operation && operation.providerId === "fedora" && operation.phase === "running", "operation state must parse");
            require(Protocol.parseAction("update-center-action-protocol\t1\t0\nactive\tnone\ncomplete\taction\n").operationId === "", "empty active state must parse");

            const settings = Protocol.parseSettings("update-center-settings-protocol\t1\t0\nstate\tavailable\tReady\npreference\trefreshSeconds\t3600\npreference\talwaysShow\tenabled\nbaseline\tabsent\ncomplete\tstatus\n");
            require(settings && settings.refreshSeconds === 3600 && settings.alwaysShow, "settings status must parse");
            require(Protocol.parseSettings("update-center-settings-protocol\t1\t0\npreference\trefreshSeconds\t299\ncomplete\tstatus\n") === null, "invalid settings must fail closed");

        } catch (error) {
            console.error("Update Center protocol test failed: " + error);
            Qt.exit(1);
            return;
        }
        Qt.exit(0);
    }
}
