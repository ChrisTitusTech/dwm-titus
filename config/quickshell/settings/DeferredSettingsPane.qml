import QtQuick

Loader {
    id: root

    required property bool selected
    required property bool windowVisible
    property bool visited: false

    // Keep visited items alive: switching sections must preserve local drafts,
    // scroll positions and bindings to the independently owned operation models.
    active: visited
    asynchronous: true
    visible: selected && status === Loader.Ready
    focus: true

    function loadIfSelected() {
        if (windowVisible && selected) visited = true;
    }
    onSelectedChanged: loadIfSelected()
    onWindowVisibleChanged: loadIfSelected()
    Component.onCompleted: loadIfSelected()
}
