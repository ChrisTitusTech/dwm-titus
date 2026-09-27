import QtQuick
import Quickshell
import Quickshell.Networking
import qs.updatecenter

ShellRoot {
    id: test
    property int step: 0
    property int ticks: 0
    property var retainedProviders: null

    function require(condition, message) {
        if (!condition) throw new Error(message);
    }

    QtObject {
        id: connectivity
        property int connectivity: NetworkConnectivity.None
    }

    QtObject {
        id: initiallyFullConnectivity
        property int connectivity: NetworkConnectivity.Full
    }

    UpdateCenterModel {
        id: model
        connectivitySource: connectivity
    }

    UpdateCenterModel {
        id: initiallyFullModel
        connectivitySource: initiallyFullConnectivity
    }

    Loader {
        id: restarted
        active: false
        sourceComponent: Component {
            UpdateCenterModel { connectivitySource: connectivity }
        }
    }

    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            try {
                test.ticks++;
                test.require(test.ticks < 750, "model test timed out at step " + test.step
                    + " detail=" + (model.providers.length ? model.providers[0].detail : "none")
                    + " pending=" + model.pendingForceRefresh + " message=" + model.message);
                if (test.step === 0 && test.ticks > 10 && model.initialCacheLoaded
                        && initiallyFullModel.initialCacheLoaded && model.savedRefreshSeconds === 600) {
                    test.require(initiallyFullModel.providers[0].detail === "cache" && !initiallyFullModel.scanning
                            && !initiallyFullModel.initialLiveScanComplete,
                        "initially-Full connectivity must not bypass the 30-second startup delay");
                    test.require(model.providers[0].detail === "cache", "cached state must load immediately while offline");
                    const prior = model.providers;
                    const valid = "update-center-protocol\t1\t0\nprovider\tfedora\tFedora\tavailable\t1\t1\tfresh\t10\tyes\t\tReady\nitem\tfedora\tupdate\tPackage\t1\t2\tpkg\tsystem\thttps://example.test/release\ncomplete\tsnapshot\n";
                    const invalid = [
                        valid.replace("protocol\t1\t0", "protocol\t2\t0"),
                        valid.replace("complete\tsnapshot\n", ""),
                        valid.replace("item\tfedora", "unknown\tfedora"),
                        valid.replace("\t1\t1\tfresh", "\t2\t1\tfresh"),
                        valid.replace("https://example.test", "http://example.test"),
                        valid.replace("complete\tsnapshot\n", "provider\tfedora\tFedora\tavailable\t0\t0\tfresh\t10\tno\t\tDuplicate\ncomplete\tsnapshot\n"),
                        "update-center-protocol\t1\t0\n" + Array(16385).fill("unknown\tx").join("\n") + "\ncomplete\tsnapshot\n"
                    ];
                    for (const payload of invalid) test.require(!model.acceptSnapshot(payload), "invalid protocol must fail closed");
                    test.require(model.providers === prior, "invalid protocol must not partially replace prior state");
                    test.require(!model.startupElapsed(), "offline startup deadline must suppress its scheduled scan");
                    model.showSettings();
                    test.require(model.draftRefreshSeconds === 600 && !model.draftAlwaysShow, "settings must open from saved values");
                    model.draftRefreshSeconds = 700;
                    model.draftAlwaysShow = true;
                    test.require(model.savedRefreshSeconds === 600 && !model.savedAlwaysShow, "settings edits must remain drafts");
                    model.discardSettings();
                    test.require(model.draftRefreshSeconds === 600 && !model.draftAlwaysShow, "discard must restore saved settings");
                    model.draftRefreshSeconds = 900;
                    model.draftAlwaysShow = true;
                    test.require(model.saveSettings(), "valid settings must dispatch through the guarded helper");
                    test.step = 1;
                } else if (test.step === 1 && model.savedRefreshSeconds === 900) {
                    test.require(model.refreshIntervalMilliseconds === 900000 && model.savedAlwaysShow,
                        "saved interval must control later scheduling");
                    model.draftRefreshSeconds = 1000;
                    test.require(model.saveSettings(), "concurrent-save fixture must dispatch");
                    test.step = 2;
                } else if (test.step === 2 && model.settingsError.indexOf("changed") >= 0) {
                    test.require(model.savedRefreshSeconds === 900, "concurrent save errors must not mutate saved settings");
                    connectivity.connectivity = NetworkConnectivity.Full;
                    test.step = 21;
                } else if (test.step === 21 && model.scanning) {
                    const started = model.scheduledRefresh();
                    test.require(!started && model.pendingForceRefresh,
                        "a required force refresh must queue behind an in-flight scan: started=" + started
                        + " scanning=" + model.scanning + " pending=" + model.pendingForceRefresh);
                    test.step = 3;
                } else if (test.step === 3 && model.providers[0].detail === "force-2") {
                    test.require(!model.pendingForceRefresh, "required force refresh must coalesce and drain after the active scan");
                    connectivity.connectivity = NetworkConnectivity.None;
                    test.require(!model.scheduledRefresh(), "offline state must suppress scheduled scans");
                    test.require(model.refresh(true), "manual force refresh must bypass the schedule");
                    test.step = 4;
                } else if (test.step === 4 && model.providers[0].detail === "force-3") {
                    connectivity.connectivity = NetworkConnectivity.Full;
                    test.step = 5;
                } else if (test.step === 5 && model.providers[0].detail === "force-4") {
                    test.retainedProviders = model.providers;
                    test.require(model.refresh(true), "failed-refresh fixture must start");
                    test.step = 6;
                } else if (test.step === 6 && model.message.indexOf("fixture scan failure") >= 0) {
                    test.require(model.providers === test.retainedProviders && model.providers[0].detail === "force-4",
                        "failed refresh must preserve prior providers and items");
                    test.require(model.launch("fedora"), "normal provider launch must dispatch");
                    test.step = 7;
                } else if (test.step === 7 && !model.busy && model.providers[0].detail === "force-6") {
                    test.require(model.launch("dwm-titus"), "failed terminal fixture must dispatch");
                    test.step = 8;
                } else if (test.step === 8 && !model.busy && model.providers[0].detail === "force-7") {
                    test.require(model.launch("flatpak"), "ambiguous launch fixture must dispatch");
                    test.step = 9;
                } else if (test.step === 9 && model.busy && model.activeOperation.phase === "interrupted") {
                    test.require(!model.launch("mise"), "all update launches must remain disabled while an operation owns the slot");
                    restarted.active = true;
                    test.step = 10;
                } else if (test.step === 10 && restarted.item && restarted.item.busy) {
                    test.require(restarted.item.activeOperation.operationId === model.activeOperation.operationId,
                        "model recreation must restore the durable operation without duplicate launch");
                    restarted.active = false;
                    test.require(model.recover("flatpak"), "ambiguous operations must expose provider recovery");
                    test.step = 11;
                } else if (test.step === 11 && !model.busy && model.providers[0].detail.indexOf("force-") === 0) {
                    test.require(model.activeOperation === null, "completed recovery terminal close must release Busy");
                    Qt.exit(0);
                }
            } catch (error) {
                console.error("Update Center model test failed: " + error);
                Qt.exit(1);
            }
        }
    }
}
