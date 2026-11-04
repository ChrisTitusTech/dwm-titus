import QtQuick
import Quickshell

Scope {
    id: root
    property bool visible: false
    property double timestamp: Date.now()
    property int year: new Date(root.timestamp).getFullYear()
    property int month: new Date(root.timestamp).getMonth()
    readonly property string monthTitle: Qt.formatDate(new Date(root.year, root.month, 1), "MMMM yyyy")
    readonly property var days: {
        const first = new Date(root.year, root.month, 1);
        const offset = (first.getDay() + 6) % 7;
        const today = new Date(root.timestamp);
        const rows = [];
        for (let index = 0; index < 42; index++) {
            const date = new Date(root.year, root.month, index - offset + 1);
            rows.push({ day: date.getDate(), current: date.getMonth() === root.month,
                today: date.toDateString() === today.toDateString() });
        }
        return rows;
    }
    function today() {
        const now = new Date(root.timestamp);
        root.year = now.getFullYear(); root.month = now.getMonth();
    }
    function changeMonth(delta) {
        const date = new Date(root.year, root.month + delta, 1);
        root.year = date.getFullYear(); root.month = date.getMonth();
    }
    function toggle() { if (!root.visible) root.today(); root.visible = !root.visible; }
    function close() { root.visible = false; }
}
