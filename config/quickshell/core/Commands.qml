pragma Singleton

import Quickshell

Singleton {
    function launcherHelperCommand(action, args) {
        const argv = args || [];
        const script = "if command -v dwm-quickshell-launcher >/dev/null 2>&1; then exec dwm-quickshell-launcher \"$@\"; fi; data_dir=${XDG_DATA_HOME:-$HOME/.local/share}/dwm-titus; exec \"$data_dir/scripts/dwm-quickshell-launcher\" \"$@\"";

        return ["sh", "-c", script, "dwm-quickshell-launcher", action].concat(argv);
    }

    function networkHelperCommand(action, args) {
        const argv = args || [];
        const script = "if command -v dwm-quickshell-network >/dev/null 2>&1; then exec dwm-quickshell-network \"$@\"; fi; data_dir=${XDG_DATA_HOME:-$HOME/.local/share}/dwm-titus; exec \"$data_dir/scripts/dwm-quickshell-network\" \"$@\"";

        return ["sh", "-c", script, "dwm-quickshell-network", action].concat(argv);
    }
}
