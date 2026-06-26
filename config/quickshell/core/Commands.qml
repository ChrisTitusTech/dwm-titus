pragma Singleton

import Quickshell

Singleton {
    function helperCommand(helper, action, args, preferManaged) {
        const argv = args || [];
        const managedScript = "\"$data_dir/scripts/" + helper + "\"";
        const dataDir = "data_dir=${XDG_DATA_HOME:-$HOME/.local/share}/dwm-titus";
        const runManaged = "[ -x " + managedScript + " ] && exec " + managedScript + " \"$@\"";
        const runPath = "command -v " + helper + " >/dev/null 2>&1 && exec " + helper + " \"$@\"";
        const fallback = "exec " + managedScript + " \"$@\"";
        const orderedChecks = preferManaged
            ? [runManaged, runPath, fallback]
            : [runPath, runManaged, fallback];
        const script = [dataDir].concat(orderedChecks).join("; ");

        return ["sh", "-c", script, helper, action].concat(argv);
    }

    function launcherHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-launcher", action, args, true);
    }

    function networkHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-network", action, args, false);
    }

    function controlsHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-controls", action, args, false);
    }
}
