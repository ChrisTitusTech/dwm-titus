import QtQml
import "../config/quickshell/settings/DisplayLayout.js" as Layout

QtObject {
    function require(condition, message) {
        if (!condition) throw new Error(message);
    }
    Component.onCompleted: {
        try {
            const outputs = [
                { name: "eDP-1", enabled: false, mode: "2560x1600_90.00", x: 0, y: 0, rotation: "normal" },
                { name: "DVI-I-2-2", enabled: true, primary: true, mode: "2560x1440", x: 2560, y: 0, rotation: "normal" },
                { name: "DVI-I-1-1", enabled: true, mode: "2560x1440", x: 0, y: 0, rotation: "normal" }
            ];
            const original = JSON.stringify(outputs);
            require(Layout.targets(outputs, 1).length === 1, "Only other enabled monitors can be anchors");
            for (const direction of ["left", "right", "above", "below"]) {
                const placed = Layout.place(outputs, 1, 2, direction);
                require(Layout.relation(placed, 1, 2) === direction, "Placement must match " + direction);
                require(placed.filter(item => item.enabled).every(item => item.x >= 0 && item.y >= 0), "Origin must be non-negative");
                require(placed[1].primary, "Primary must be preserved");
                const bounds = Layout.preview(placed);
                require(bounds.tiles.length === 2 && bounds.tiles[0].number === 2, "Preview numbers must match cards including disabled gaps");
                require(bounds.width === (direction === "left" || direction === "right" ? 5120 : 2560), "Preview width");
                require(bounds.height === (direction === "above" || direction === "below" ? 2880 : 1440), "Preview height");
            }
            require(JSON.stringify(outputs) === original, "Placement cannot mutate discovered state");
            const three = outputs.map(item => Object.assign({}, item));
            three[0].enabled = true;
            three[0].x = -2560;
            three[0].y = -1600;
            const arranged = Layout.place(three, 1, 2, "above");
            require(arranged[0].x - arranged[2].x === three[0].x - three[2].x
                && arranged[0].y - arranged[2].y === three[0].y - three[2].y,
                "Normalization preserves the other monitors' relative placement");
            require(Layout.preview(arranged).tiles.length === 3, "All enabled monitors appear");
            outputs[1].rotation = "left";
            outputs[2].mode = "1920x1080";
            const left = Layout.place(outputs, 1, 2, "left");
            require(left[2].x === 1440 && left[1].x === 0, "Rotated own width sets left distance");
            const below = Layout.place(outputs, 2, 1, "below");
            require(below[2].y === 2560, "Rotated anchor height sets below distance");
            require(Layout.place(outputs, 1, 1, "left") === null, "No self reference");
            require(Layout.place(outputs, 1, 0, "right") === null, "No disabled anchor");
            require(Layout.place(outputs, 1, 2, "unknown") === null, "Reject invalid direction");
            outputs[1].mode = "h:";
            require(Layout.place(outputs, 1, 2, "left") === null, "Reject invalid geometry");
            require(Layout.preview([]).width === 1, "Empty preview stays finite");
            outputs[1].mode = "native";
            outputs[1].pixelWidth = 2560;
            outputs[1].pixelHeight = 1440;
            require(Layout.size(outputs[1]).width === 1440, "Custom mode uses actual rotated pixel dimensions");
            require(Layout.targets(outputs, 2).length === 1, "Custom modes remain usable as anchors");
            require(Layout.place(outputs, 2, 1, "below")[2].y === 2560, "Custom mode placement uses actual height");
            require(Layout.preview(outputs).tiles.length === 2, "Custom modes appear in the preview");
            console.log("Display relative layout: PASS");
            Qt.quit();
        } catch (error) {
            console.error(error);
            Qt.exit(1);
        }
    }
}
