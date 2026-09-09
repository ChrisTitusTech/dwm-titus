// Pure layout geometry shared by Settings and its regression tests.
function size(output) {
    const match = /^(\d+)x(\d+)/.exec(output.mode || "");
    const pixelWidth = Number(output.pixelWidth) || (match ? Number(match[1]) : 0);
    const pixelHeight = Number(output.pixelHeight) || (match ? Number(match[2]) : 0);
    const rotated = output.rotation === "left" || output.rotation === "right";
    const width = rotated ? pixelHeight : pixelWidth;
    const height = rotated ? pixelWidth : pixelHeight;
    return Number.isInteger(width) && Number.isInteger(height) && width > 0 && height > 0
        ? { width: width, height: height } : null;
}

function targets(outputs, index) {
    return outputs.map(function(output, other) {
        return { index: other, name: output.name, label: "Monitor " + (other + 1) + " - " + output.name };
    }).filter(function(target) {
        return target.index !== index && outputs[target.index].enabled && size(outputs[target.index]);
    });
}

function relation(outputs, index, anchorIndex) {
    const output = outputs[index];
    const anchor = outputs[anchorIndex];
    if (!output || !anchor || !output.enabled || !anchor.enabled || index === anchorIndex) return "";
    const own = size(output), reference = size(anchor);
    if (!own || !reference) return "";
    if (output.y === anchor.y && output.x + own.width === anchor.x) return "left";
    if (output.y === anchor.y && output.x === anchor.x + reference.width) return "right";
    if (output.x === anchor.x && output.y + own.height === anchor.y) return "above";
    if (output.x === anchor.x && output.y === anchor.y + reference.height) return "below";
    return "";
}

function place(outputs, index, anchorIndex, direction) {
    const output = outputs[index], anchor = outputs[anchorIndex];
    if (!output || !anchor || !output.enabled || !anchor.enabled || index === anchorIndex) return null;
    const own = size(output), reference = size(anchor);
    if (!own || !reference || ["left", "right", "above", "below"].indexOf(direction) < 0) return null;
    const result = outputs.map(function(item) { return Object.assign({}, item); });
    result[index].x = anchor.x + (direction === "left" ? -own.width : direction === "right" ? reference.width : 0);
    result[index].y = anchor.y + (direction === "above" ? -own.height : direction === "below" ? reference.height : 0);
    // RandR uses a non-negative framebuffer origin. Translate the whole active
    // layout together so positioning to the left or above preserves its shape.
    const active = result.filter(function(item) { return item.enabled; });
    const minX = Math.min.apply(null, active.map(function(item) { return item.x; }));
    const minY = Math.min.apply(null, active.map(function(item) { return item.y; }));
    for (const item of active) { item.x -= minX; item.y -= minY; }
    return result;
}

function preview(outputs) {
    const tiles = [];
    outputs.forEach(function(output, index) {
        const dimensions = size(output);
        if (output.enabled && dimensions) tiles.push({
            number: index + 1, name: output.name, primary: output.primary,
            x: output.x, y: output.y, width: dimensions.width, height: dimensions.height
        });
    });
    if (!tiles.length) return { tiles: [], x: 0, y: 0, width: 1, height: 1 };
    const x = Math.min.apply(null, tiles.map(function(tile) { return tile.x; }));
    const y = Math.min.apply(null, tiles.map(function(tile) { return tile.y; }));
    const right = Math.max.apply(null, tiles.map(function(tile) { return tile.x + tile.width; }));
    const bottom = Math.max.apply(null, tiles.map(function(tile) { return tile.y + tile.height; }));
    return { tiles: tiles, x: x, y: y, width: right - x, height: bottom - y };
}
