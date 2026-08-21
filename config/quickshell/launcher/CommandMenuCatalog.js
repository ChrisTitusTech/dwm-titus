.pragma library

var menus = {
    "root": [
        { "id": "apps", "label": "Apps", "detail": "Browse installed applications", "kind": "submenu", "target": "apps", "provider": "applications", "keywords": "applications launch programs", "enabled": true, "current": false },
        { "id": "settings", "label": "Settings", "detail": "Open desktop settings", "kind": "action", "actionType": "ipc", "target": "settings", "action": "open", "argument": "", "keywords": "preferences configuration", "enabled": true, "current": false },
        { "id": "display-input", "label": "Display / Input", "detail": "Monitors, keyboard, pointer, and touchpad", "kind": "submenu", "target": "display-input", "keywords": "screen monitor mouse keyboard touchpad", "enabled": true, "current": false },
        { "id": "network", "label": "Network", "detail": "Wi-Fi and wired connections", "kind": "action", "actionType": "ipc", "target": "network", "action": "open", "argument": "", "keywords": "wifi ethernet vpn connections", "enabled": true, "current": false },
        { "id": "bluetooth", "label": "Bluetooth", "detail": "Adapters and paired devices", "kind": "action", "actionType": "ipc", "target": "bluetooth", "action": "open", "argument": "", "keywords": "wireless devices paired", "enabled": true, "current": false },
        { "id": "audio", "label": "Audio", "detail": "Volume, microphone, and media", "kind": "action", "actionType": "ipc", "target": "controls", "action": "open", "argument": "", "keywords": "sound volume microphone media", "enabled": true, "current": false },
        { "id": "health", "label": "System Health", "detail": "Desktop diagnostics and status", "kind": "action", "actionType": "ipc", "target": "systemhealth", "action": "open", "argument": "", "keywords": "diagnostics status services", "enabled": true, "current": false },
        { "id": "keybindings", "label": "Keybindings", "detail": "Search the active keyboard shortcuts", "kind": "action", "actionType": "ipc", "target": "controlcenter", "action": "keybindings", "argument": "", "keywords": "hotkeys shortcuts keys", "enabled": true, "current": false },
        { "id": "screenshots", "label": "Screenshots", "detail": "Capture a monitor, desktop, or region", "kind": "submenu", "target": "screenshots", "keywords": "capture image clipboard", "enabled": true, "current": false },
        { "id": "system", "label": "System", "detail": "Lock, power, and system settings", "kind": "submenu", "target": "system", "keywords": "lock logout reboot shutdown power", "enabled": true, "current": false }
    ],
    "apps": [],
    "display-input": [
        { "id": "displays", "label": "Displays", "detail": "Layouts, modes, rotation, and profiles", "kind": "action", "actionType": "ipc", "target": "settings", "action": "select", "argument": "displays", "keywords": "screen monitor resolution refresh", "enabled": true, "current": false },
        { "id": "input", "label": "Input", "detail": "Keyboard, pointer, and touchpad settings", "kind": "action", "actionType": "ipc", "target": "settings", "action": "select", "argument": "input", "keywords": "mouse keyboard touchpad acceleration", "enabled": true, "current": false }
    ],
    "screenshots": [
        { "id": "screenshot-screen", "label": "Active Monitor", "detail": "Save the monitor containing the pointer", "kind": "action", "actionType": "helper", "target": "screenshot", "action": "screen", "argument": "", "keywords": "capture screen file", "enabled": true, "current": false },
        { "id": "screenshot-full", "label": "All Monitors", "detail": "Save the complete X11 desktop", "kind": "action", "actionType": "helper", "target": "screenshot", "action": "full", "argument": "", "keywords": "capture desktop file", "enabled": true, "current": false },
        { "id": "screenshot-region", "label": "Select Region to File", "detail": "Draw a region and save it", "kind": "action", "actionType": "helper", "target": "screenshot", "action": "gui", "argument": "", "keywords": "capture selection area file", "enabled": true, "current": false },
        { "id": "screenshot-clipboard", "label": "Select Region to Clipboard", "detail": "Draw a region and copy it as PNG", "kind": "action", "actionType": "helper", "target": "screenshot", "action": "clip", "argument": "", "keywords": "capture selection area copy", "enabled": true, "current": false }
    ],
    "system": [
        { "id": "lock", "label": "Lock", "detail": "Secure this session", "kind": "action", "actionType": "helper", "target": "lock", "action": "run", "argument": "", "keywords": "secure session", "enabled": true, "current": false },
        { "id": "power-menu", "label": "Power Menu", "detail": "Lock, log out, reboot, or shut down", "kind": "action", "actionType": "ipc", "target": "power", "action": "open", "argument": "", "keywords": "logout reboot shutdown", "enabled": true, "current": false },
        { "id": "power-settings", "label": "Power Settings", "detail": "DPMS, locking, and session policy", "kind": "action", "actionType": "ipc", "target": "settings", "action": "select", "argument": "power", "keywords": "sleep display dpms", "enabled": true, "current": false },
        { "id": "system-settings", "label": "System Settings", "detail": "Health and administration capabilities", "kind": "action", "actionType": "ipc", "target": "settings", "action": "select", "argument": "system", "keywords": "administration capabilities", "enabled": true, "current": false }
    ]
};

var menuLabels = {
    "root": "Commands",
    "apps": "Apps",
    "display-input": "Display / Input",
    "screenshots": "Screenshots",
    "system": "System"
};

function copyEntry(entry) {
    var copy = {};
    var keys = Object.keys(entry);

    for (var index = 0; index < keys.length; index++) {
        copy[keys[index]] = entry[keys[index]];
    }

    return copy;
}

function entriesFor(menuId) {
    var source = menus[menuId] || [];
    var entries = [];

    for (var index = 0; index < source.length; index++) {
        entries.push(copyEntry(source[index]));
    }

    return entries;
}

function searchableEntries() {
    var entries = [];
    var menuIds = Object.keys(menus);

    for (var menuIndex = 0; menuIndex < menuIds.length; menuIndex++) {
        var menuEntries = menus[menuIds[menuIndex]];
        for (var entryIndex = 0; entryIndex < menuEntries.length; entryIndex++) {
            entries.push(copyEntry(menuEntries[entryIndex]));
        }
    }

    return entries;
}

function textScore(text, query) {
    if (query.length === 0) return 1;
    if (text === query) return 10000;
    if (text.indexOf(query) === 0) return 5000;

    var words = text.split(/[\s._/-]+/);
    for (var wordIndex = 0; wordIndex < words.length; wordIndex++) {
        if (words[wordIndex].indexOf(query) === 0) return 3000;
    }

    if (text.indexOf(query) >= 0) return 1000;

    var offset = 0;
    for (var queryIndex = 0; queryIndex < query.length; queryIndex++) {
        offset = text.indexOf(query.charAt(queryIndex), offset);
        if (offset < 0) return 0;
        offset++;
    }

    return 250;
}

function score(entry, query) {
    var needle = query.trim().toLowerCase();
    var label = String(entry.label || "").toLowerCase();
    var detail = String(entry.detail || "").toLowerCase();
    var keywords = String(entry.keywords || "").toLowerCase();

    return Math.max(
        textScore(label, needle),
        textScore(detail, needle) * 0.65,
        textScore(keywords, needle) * 0.55
    );
}

function filterAndSort(entries, query) {
    var matches = [];
    var needle = query.trim().toLowerCase();

    for (var index = 0; index < entries.length; index++) {
        var entry = copyEntry(entries[index]);
        entry.menuScore = score(entry, needle);
        if (entry.menuScore > 0) matches.push(entry);
    }

    matches.sort(function(left, right) {
        if (right.menuScore !== left.menuScore) return right.menuScore - left.menuScore;
        return String(left.label || "").localeCompare(String(right.label || ""));
    });

    return matches;
}

function isSelectable(entry) {
    return entry && entry.enabled !== false && entry.kind !== "status";
}

function nextSelectable(entries, start, delta) {
    if (entries.length === 0) return 0;

    var direction = delta < 0 ? -1 : 1;
    var index = start;

    for (var count = 0; count < entries.length; count++) {
        index = (index + direction + entries.length) % entries.length;
        if (isSelectable(entries[index])) return index;
    }

    return Math.max(0, Math.min(start, entries.length - 1));
}

function firstSelectable(entries) {
    for (var index = 0; index < entries.length; index++) {
        if (isSelectable(entries[index])) return index;
    }

    return 0;
}

function breadcrumb(menuId) {
    return menuId === "root" ? menuLabels.root : menuLabels.root + " / " + (menuLabels[menuId] || menuId);
}
