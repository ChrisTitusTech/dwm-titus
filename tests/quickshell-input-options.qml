import QtQml
import "../config/quickshell/settings/InputOptions.js" as InputOptions

QtObject {
    function require(condition, message) {
        if (!condition) throw new Error(message);
    }
    Component.onCompleted: {
        try {
            require(InputOptions.current("", InputOptions.switchPrefix) === "", "Empty options have no switch key");
            require(InputOptions.current("caps:escape,grp:alt_shift_toggle", InputOptions.switchPrefix)
                === "grp:alt_shift_toggle", "Switch key is found among other options");
            require(InputOptions.current("grp_led:caps", InputOptions.switchPrefix) === "",
                "The LED option is not a switch key");
            require(InputOptions.current("grp:caps_toggle,grp_led:caps", InputOptions.ledPrefix)
                === "grp_led:caps", "LED option is found");
            require(InputOptions.withChoice("caps:escape,grp:alt_shift_toggle,grp_led:caps",
                InputOptions.switchPrefix, "grp:caps_toggle") === "caps:escape,grp_led:caps,grp:caps_toggle",
                "Switch key is replaced and other options keep their order");
            require(InputOptions.withChoice("grp:alt_shift_toggle,grp:ctrl_shift_toggle",
                InputOptions.switchPrefix, "grp:menu_toggle") === "grp:menu_toggle",
                "Every old switch key is dropped");
            require(InputOptions.withChoice(" grp:caps_toggle , grp_led:caps ", InputOptions.ledPrefix, "")
                === "grp:caps_toggle", "Off removes the LED option and trims spaces");
            require(InputOptions.withChoice("", InputOptions.switchPrefix, "") === "", "None on empty stays empty");
            require(InputOptions.switchChoices.every(choice => choice.value === ""
                || (choice.value.indexOf("grp:") === 0 && choice.value.indexOf("space") < 0
                    && choice.value.indexOf("win") < 0)),
                "No space or Win chords, they clash with dwm bindings");
            require(InputOptions.ledChoices.every(choice => choice.value === "" || choice.value.indexOf("grp_led:") === 0),
                "LED choices only use grp_led");
            require(InputOptions.hint("grp:caps_toggle").indexOf("Shift+Caps Lock") >= 0, "Caps hint");
            console.log("Input options assertions: PASS");
            Qt.quit();
        } catch (error) {
            console.error(error);
            Qt.exit(1);
        }
    }
}
