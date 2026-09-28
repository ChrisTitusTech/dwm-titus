import QtQuick
import Quickshell
import Quickshell.Networking
import qs.updatecenter

ShellRoot {
    id: test
    property int step: 0
    property int ticks: 0
    property var retainedProviders: null
    property bool startupSaveDispatched: false
    property int transitionTick: 0

    function require(condition, message) {
        if (!condition) throw new Error(message);
    }

    QtObject {
        id: connectivityDevice
        property bool connected: false
    }

    QtObject {
        id: initiallyConnectedDevice
        property bool connected: true
    }

    QtObject {
        id: connectivity
        property var devices: QtObject {
            property var values: [connectivityDevice]
        }
    }

    QtObject {
        id: initiallyFullConnectivity
        property var devices: QtObject {
            property var values: [initiallyConnectedDevice]
        }
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
                    + " pending=" + model.pendingForceRefresh + " message=" + model.message
                    + " saved=" + model.savedRefreshSeconds + " baseline=" + model.settingsBaseline
                    + " settingsLoading=" + model.settingsLoading + " dispatched=" + test.startupSaveDispatched
                    + " settingsError=" + model.settingsError);
                if (!test.startupSaveDispatched && model.settingsLoading) {
                    model.draftRefreshSeconds = 900;
                    model.draftAlwaysShow = true;
                    test.require(model.saveSettings(), "save must run while startup status is still active");
                    test.startupSaveDispatched = true;
                }
                if (test.step === 0 && test.ticks > 10 && model.initialCacheLoaded
                        && initiallyFullModel.initialCacheLoaded && model.savedRefreshSeconds === 900) {
                    const cachedProviders = model.providers;
                    const cachedTotalUpdates = model.totalUpdates;
                    model.savedAlwaysShow = false;
                    test.require(model.acceptSnapshot("update-center-protocol\t1\t0\nprovider\tdwm-titus\tDWM-Titus\tavailable\t0\t1\tfresh\t10\tno\t\tReady\ncomplete\tsnapshot\n")
                            && !model.shouldShow(), "healthy current state must honor alwaysShow=false");
                    test.require(model.acceptSnapshot("update-center-protocol\t1\t0\nprovider\tdwm-titus\tDWM-Titus\tavailable\t0\t1\tstale\t10\tno\tnetwork\tCached\ncomplete\tsnapshot\n")
                            && model.shouldShow(), "stale state must force panel visibility");
                    test.require(model.acceptSnapshot("update-center-protocol\t1\t0\nprovider\tdwm-titus\tDWM-Titus\tavailable\t0\t1\tfresh\t10\tno\t\tRestart ready\nguidance\tdwm-titus\trestart\tsession\ncomplete\tsnapshot\n")
                            && model.shouldShow(), "restart guidance must force panel visibility");
                    model.activeOperation = { operationId: "op-00000000000000000000000000000000", providerId: "dwm-titus",
                        action: "update", phase: "running", outcome: "pending" };
                    test.require(model.shouldShow(), "active state must force panel visibility");
                    model.activeOperation.phase = "interrupted";
                    model.activeOperation.outcome = "unknown";
                    test.require(model.shouldShow(), "recovery state must force panel visibility");
                    model.activeOperation = null;
                    model.savedAlwaysShow = true;
                    model.providers = cachedProviders;
                    model.totalUpdates = cachedTotalUpdates;
                    test.require(initiallyFullModel.providers[0].detail === "cache" && !initiallyFullModel.scanning
                            && !initiallyFullModel.initialLiveScanComplete && !initiallyFullModel.periodicRefreshRunning,
                        "initially-Full connectivity must not bypass the 30-second startup delay");
                    test.require(model.providers[0].detail === "cache", "cached state must load immediately while offline");
                    test.require(model.settingsBaseline === "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                        "post-save status reload must replace the delayed pre-save baseline");
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
                    test.require(!model.periodicRefreshRunning, "periodic timer must remain stopped while initially offline");
                    model.showSettings();
                    test.require(model.draftRefreshSeconds === 900 && model.draftAlwaysShow, "settings must open from saved values");
                    model.draftRefreshSeconds = 700;
                    model.draftAlwaysShow = false;
                    test.require(model.savedRefreshSeconds === 900 && model.savedAlwaysShow, "settings edits must remain drafts");
                    model.discardSettings();
                    test.require(model.draftRefreshSeconds === 900 && model.draftAlwaysShow, "discard must restore saved settings");
                    model.draftRefreshSeconds = 1000;
                    model.draftAlwaysShow = false;
                    test.require(model.saveSettings(), "subsequent save must use the refreshed baseline");
                    test.step = 1;
                } else if (test.step === 1 && model.savedRefreshSeconds === 1000) {
                    test.require(model.settingsBaseline === "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                        "successful subsequent save must refresh its baseline");
                    test.require(model.refreshIntervalMilliseconds === 1000000 && !model.savedAlwaysShow,
                        "saved interval must control later scheduling");
                    model.draftRefreshSeconds = 1100;
                    test.require(model.saveSettings(), "concurrent-save fixture must dispatch");
                    test.step = 2;
                } else if (test.step === 2 && model.settingsError.indexOf("changed") >= 0) {
                    test.require(model.savedRefreshSeconds === 1000, "concurrent save errors must not mutate saved settings");
                    connectivityDevice.connected = true;
                    test.transitionTick = test.ticks;
                    test.step = 20;
                } else if (test.step === 20 && test.ticks >= test.transitionTick + 5) {
                    test.require(!model.scanning && model.providers[0].detail === "cache"
                            && !model.periodicRefreshRunning,
                        "connectivity restoration before the startup deadline must not scan or start periodic work");
                    test.require(model.startupElapsed(), "startup deadline must launch the first online force scan");
                    test.step = 21;
                } else if (test.step === 21 && model.scanning) {
                    const started = model.scheduledRefresh();
                    test.require(!started && model.pendingForceRefresh,
                        "a required force refresh must queue behind an in-flight scan: started=" + started
                        + " scanning=" + model.scanning + " pending=" + model.pendingForceRefresh);
                    test.step = 3;
                } else if (test.step === 3 && model.providers[0].detail === "force-2") {
                    test.require(!model.pendingForceRefresh, "required force refresh must coalesce and drain after the active scan");
                    test.require(model.periodicRefreshRunning, "periodic timer must start after connectivity restoration");
                    connectivityDevice.connected = false;
                    test.require(!model.periodicRefreshRunning, "periodic timer must stop when connectivity is lost");
                    test.require(!model.scheduledRefresh(), "offline state must suppress scheduled scans");
                    test.require(model.refresh(true), "manual force refresh must bypass the schedule");
                    test.step = 4;
                } else if (test.step === 4 && model.providers[0].detail === "force-3") {
                    connectivityDevice.connected = true;
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
