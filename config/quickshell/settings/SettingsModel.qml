import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool busy: false
    property string searchQuery: ""
    property string selectedSectionId: "displays"
    property string discoveryState: "idle"
    property string message: ""
    property string platformId: "unknown"
    property string platformFamily: "unknown"
    property string platformName: "Unknown Linux"
    property var capabilities: []
    property int selectedIndex: 0

    readonly property var sections: [
        { "id": "displays", "label": "Displays", "description": "Monitors, layouts, and profiles" },
        { "id": "input", "label": "Input", "description": "Keyboard, pointer, and touchpad" },
        { "id": "network", "label": "Network", "description": "Connections and VPN providers" },
        { "id": "bluetooth", "label": "Bluetooth", "description": "Adapters and devices" },
        { "id": "audio", "label": "Audio", "description": "Outputs, inputs, and streams" },
        { "id": "power", "label": "Power", "description": "DPMS, locking, and session policy" },
        { "id": "defaults", "label": "Defaults", "description": "Applications and autostart" },
        { "id": "appearance", "label": "Appearance", "description": "Themes and accessibility" },
        { "id": "system", "label": "System", "description": "Health and administration" }
    ]

    readonly property var filteredSections: {
        const query = root.searchQuery.trim().toLowerCase();
        if (query.length === 0) return root.sections;
        return root.sections.filter(function(section) {
            return section.label.toLowerCase().indexOf(query) >= 0
                || section.description.toLowerCase().indexOf(query) >= 0;
        });
    }

    function sectionById(id) {
        for (const section of root.sections) {
            if (section.id === id) return section;
        }
        return root.sections[0];
    }

    function selectedSection() {
        return root.sectionById(root.selectedSectionId);
    }

    function capabilitiesForSection(id) {
        return root.capabilities.filter(function(capability) {
            return capability.section === id;
        });
    }

    function setSearch(value) {
        root.searchQuery = value;
        root.selectedIndex = 0;
        if (root.filteredSections.length > 0) {
            root.selectedSectionId = root.filteredSections[0].id;
        }
    }

    function selectSection(id) {
        for (let index = 0; index < root.filteredSections.length; index++) {
            if (root.filteredSections[index].id === id) {
                root.selectedIndex = index;
                root.selectedSectionId = id;
                return;
            }
        }
    }

    function selectRelative(delta) {
        const sections = root.filteredSections;
        if (sections.length === 0) return;
        root.selectedIndex = (root.selectedIndex + delta + sections.length) % sections.length;
        root.selectedSectionId = sections[root.selectedIndex].id;
    }

    function parseDiscovery(text) {
        const capabilities = [];
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];
        let validProtocol = false;

        for (const line of lines) {
            const fields = line.split("\t");
            if (fields[0] === "settings-protocol" && fields[1] === "1") {
                validProtocol = true;
            } else if (fields[0] === "platform" && fields.length >= 4) {
                root.platformId = fields[1];
                root.platformFamily = fields[2];
                root.platformName = fields[3];
            } else if (fields[0] === "capability" && fields.length >= 8) {
                capabilities.push({
                    "section": fields[1],
                    "id": fields[2],
                    "label": fields[3],
                    "status": fields[4],
                    "capabilityClass": fields[5],
                    "provider": fields[6],
                    "detail": fields[7]
                });
            }
        }

        root.busy = false;
        if (!validProtocol) {
            root.discoveryState = "failure";
            root.message = "Capability provider returned an unsupported response";
            root.capabilities = [];
            return;
        }

        root.capabilities = capabilities;
        root.discoveryState = "ready";
        root.message = capabilities.length + " capabilities discovered";
    }

    function refresh() {
        if (!root.visible || providerProcess.running) return;
        root.busy = true;
        root.discoveryState = "loading";
        root.message = "Discovering capabilities...";
        providerProcess.running = true;
    }

    function open() {
        root.visible = true;
        root.searchQuery = "";
        root.selectedIndex = 0;
        root.selectedSectionId = root.sections[0].id;
        root.refresh();
    }

    function close() {
        providerProcess.running = false;
        root.visible = false;
        root.busy = false;
        root.searchQuery = "";
        root.selectedIndex = 0;
    }

    function toggle() {
        if (root.visible) root.close(); else root.open();
    }

    Process {
        id: providerProcess

        command: Commands.settingsProviderCommand("discover")
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseDiscovery(this.text)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0) root.message = error;
            }
        }
    }
}
