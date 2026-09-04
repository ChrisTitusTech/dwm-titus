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

        const command = ["sh", "-c", script, helper];
        if (action !== undefined && action !== null) {
            command.push(action);
        }

        return command.concat(argv);
    }

    function checkedCommand(command) {
        // Hold helper stdout until it exits successfully, so a result record
        // followed by a nonzero exit can never be accepted by a QML parser.
        const script = 'output=$("$@"); status=$?; [ "$status" -eq 0 ] || exit "$status"; printf "%s\\n" "$output"';
        return ["sh", "-c", script, "dwm-checked-command"].concat(command);
    }

    function terminatingCheckedCommand(command) {
        // Preserve checkedCommand's success gate while forwarding surface-close
        // signals to a long-running helper instead of orphaning it.
        const script = [
            'runtime_dir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}',
            'output_file=$(mktemp "$runtime_dir/dwm-checked-command.XXXXXX") || exit 1',
            'child=',
            'cleanup() { status=$?; trap - EXIT; rm -f -- "$output_file"; exit "$status"; }',
            'terminate() { trap - HUP INT TERM; if [ -n "$child" ]; then kill -TERM "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; fi; exit 143; }',
            'trap cleanup EXIT',
            'trap terminate HUP INT TERM',
            '"$@" >"$output_file" &',
            'child=$!',
            'wait "$child"',
            'status=$?',
            'child=',
            '[ "$status" -eq 0 ] || exit "$status"',
            'cat "$output_file"'
        ].join("\n");
        return ["sh", "-c", script, "dwm-terminating-checked-command"].concat(command);
    }

    function booleanStatusCommand(command) {
        const script = 'if "$@" >/dev/null 2>&1; then printf "available\\n"; else printf "restricted\\n"; fi';
        return ["sh", "-c", script, "dwm-boolean-status"].concat(command);
    }

    function launcherHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-launcher", action, args, true);
    }

    function networkHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-network", action, args, false);
    }

    function pointerHelperCommand(action) {
        return helperCommand("dwm-quickshell-pointer", action, [], true);
    }

    function controlsHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-controls", action, args, true);
    }

    function controlCenterHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-controlcenter", action, args, true);
    }

    function powerHelperCommand(action, args) {
        return helperCommand("dwm-quickshell-controlcenter", action, args, true);
    }

    function sessionActionCommand(action) {
        return powerHelperCommand("session-action", [action]);
    }

    function defaultsHelperCommand(action, args) {
        return helperCommand("dwm-default-apps", action, args, true);
    }

    function autostartHelperCommand(action, args) {
        return helperCommand("dwm-xdg-autostart", action, args, true);
    }

    function lockHelperCommand() {
        return helperCommand("dwm-lock", undefined, [], true);
    }

    function screenshotHelperCommand(action) {
        return helperCommand("dwm-screenshot", action, [], true);
    }

    function systemHealthHelperCommand(action, args) {
        return helperCommand("dwm-system-health", action, args, true);
    }

    function systemManagementCommand(action, args) {
        return helperCommand("dwm-system-management", action, args, true);
    }

    function settingsProviderCommand(action, args) {
        return helperCommand("dwm-settings-provider", action, args, true);
    }

    function settingsDisplayCommand(action, args) {
        return helperCommand("dwm-settings-display", action, args, true);
    }

    function settingsInputCommand(action, args) {
        return helperCommand("dwm-settings-input", action, args, true);
    }

    function settingsAppearanceCommand(action, args) {
        return helperCommand("dwm-settings-appearance", action, args, true);
    }

    function settingsWallpaperCommand(action, args) {
        return helperCommand("dwm-settings-wallpaper", action, args, true);
    }

    function settingsFontCommand(action, args) {
        return helperCommand("dwm-settings-font", action, args, true);
    }

    function settingsPersonalizationCommand(action, args) {
        return helperCommand("dwm-settings-personalization", action, args, true);
    }

    function settingsXsettingsCommand(action, args) {
        return helperCommand("dwm-xsettings", action, args, true);
    }

    function settingsThemeCommand(action, args) {
        return helperCommand("dwm-settings-theme", action, args, true);
    }

    function panelSettingsCommand(action, args) {
        return helperCommand("dwm-panel-settings", action, args, true);
    }

    function accessibilitySettingsCommand(action, args) {
        return helperCommand("dwm-accessibility-settings", action, args, true);
    }
}
