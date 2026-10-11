// XKB modifier option presets for the keyboard layout switch key and LED.
// Space chords (Win/Alt/Ctrl+Space) and Left Win are left out on purpose: XKB
// switches the layout and dwm still runs its own binding on the same chord
// (Super+Space toggles floating), and Super is the dwm modifier.
.pragma library

const switchPrefix = "grp:";
const ledPrefix = "grp_led:";

const switchChoices = [
    { value: "grp:alt_shift_toggle", label: "Alt+Shift" },
    { value: "grp:ctrl_shift_toggle", label: "Ctrl+Shift" },
    { value: "grp:caps_toggle", label: "Caps Lock" },
    { value: "grp:shift_caps_toggle", label: "Shift+Caps Lock" },
    { value: "grp:shifts_toggle", label: "Both Shifts" },
    { value: "grp:toggle", label: "Right Alt" },
    { value: "grp:rctrl_toggle", label: "Right Ctrl" },
    { value: "grp:menu_toggle", label: "Menu" },
    { value: "", label: "None" }
];

const ledChoices = [
    { value: "", label: "Off" },
    { value: "grp_led:caps", label: "Caps Lock" },
    { value: "grp_led:scroll", label: "Scroll Lock" },
    { value: "grp_led:num", label: "Num Lock" }
];

function tokens(options) {
    return String(options || "").split(",").map(item => item.trim()).filter(item => item.length > 0);
}

// The option with this prefix, "" when there is none.
function current(options, prefix) {
    const found = tokens(options).filter(item => item.indexOf(prefix) === 0);
    return found.length > 0 ? found[0] : "";
}

// Replaces every option with this prefix by value and keeps the rest in order.
function withChoice(options, prefix, value) {
    const kept = tokens(options).filter(item => item.indexOf(prefix) !== 0);
    if (value) kept.push(value);
    return kept.join(",");
}

function hint(options) {
    const key = current(options, switchPrefix);
    if (key === "grp:caps_toggle") return "Caps Lock switches layouts; Shift+Caps Lock is Caps Lock.";
    if (key === "grp:shift_caps_toggle") return "Shift+Caps Lock switches layouts; Caps Lock stays Caps Lock.";
    if (key === "grp:toggle") return "Right Alt switches layouts and no longer works as Alt or AltGr.";
    if (key === "grp:rctrl_toggle") return "Right Ctrl switches layouts and no longer works as Ctrl.";
    if (key === "grp:menu_toggle") return "Menu switches layouts; Shift+Menu is Menu.";
    if (key === "") return "No switch key; use the panel pill or a cyclelayout hotkey.";
    return "";
}
