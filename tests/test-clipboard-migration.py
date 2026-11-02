#!/usr/bin/env python3
"""Exercise clipboard migration without replacing user customizations."""
from pathlib import Path
import runpy
import tempfile
import tomllib
root = Path(__file__).resolve().parents[1]
migration = runpy.run_path(str(root / "scripts/dwm-migrate-clipboard-surface"))
# Modifier aliases may be remapped by the user's compiled MODKEY. Any existing
# V action must survive, including an ALT binding under a custom Mod1Mask build.
for modifier in ["SUPER", "MODKEY", "ALT", "Mod1Mask", "CTRL", "SUPER CTRL", "", ["ALT"]]:
    assert migration["v_bound"]({"mod": modifier, "key": "v"})
for key in ["v", "U0076", "U000076", "0x76", "0x000076"]:
    assert migration["v_bound"]({"mod": "ALT", "key": key}), key
for key in ["x", "V", "U0056", "0x56", "not-a-keysym", 118]:
    assert not migration["v_bound"]({"mod": "ALT", "key": key}), key
with tempfile.TemporaryDirectory(prefix="clipboard-migration-") as directory:
    path = Path(directory)
    rules = path / "window-rules.toml"
    original = 'rules = [{title="dwm clipboard", isfloating=0, alwaysontop=0}]\n'
    rules.write_text(original)
    assert not migration["migrate_window_rules"](rules)
    assert rules.read_text() == original
    rules.write_text('rules = [{title="clipboard", isfloating=0}]\n')
    assert not migration["migrate_window_rules"](rules)
    assert rules.read_text() == 'rules = [{title="clipboard", isfloating=0}]\n'
    for selector in ["class", "instance"]:
        rules.write_text('rules = [{title="clipboard", ' + selector + '="Firefox", isfloating=0}]\n')
        assert migration["migrate_window_rules"](rules), selector
        assert 'title="dwm clipboard"' in rules.read_text()
        assert not migration["migrate_window_rules"](rules)
        rules.write_text('rules = [{title="clipboard", ' + selector + '="broken", isfloating=0}]\n')
        assert not migration["migrate_window_rules"](rules), selector
    keys = path / "hotkeys.toml"
    for modifier in ["SUPER", "MODKEY", "Mod4Mask", "SUPER MODKEY", "SUPER Mod2Mask", "SUPER Mod3Mask", "SUPER Mod5Mask", "SUPER LockMask", "ALT", "Mod1Mask", "SUPER CTRL", "CTRL"]:
        original = f'keys = [{{mod="{modifier}", key="v", func="quit"}}]\n'
        keys.write_text(original)
        assert not migration["migrate_hotkeys"](keys), modifier
        assert keys.read_text() == original
    for prefix in ["", "[vars]\n"]:
        original = prefix + 'keys = []\ntag_keys = [{key="v", tag=1}]\n'
        keys.write_text(original)
        assert not migration["migrate_hotkeys"](keys)
        assert keys.read_text() == original
    for header in ["keys", "vars.keys"]:
        keys.write_text(f'[[{header}]]\nmod="SUPER"\nkey="x"\nfunc="quit"\n')
        assert migration["migrate_hotkeys"](keys)
        assert f'[[{header}]]' in keys.read_text()
        assert not migration["migrate_hotkeys"](keys)
    for prefix in ["", "[vars]\n"]:
        for spelling in ["U0076", "0x76"]:
            for kind in ["keys", "tag_keys"]:
                original = prefix + f'{kind} = [{{key="{spelling}", mod="ALT", tag=1}}]\n'
                keys.write_text(original)
                assert not migration["migrate_hotkeys"](keys)
                assert keys.read_text() == original
        for tag_text in ['tag_keys = [{key="1", tag=1}]\n', '[[tag_keys]]\nkey="1"\ntag=1\n']:
            original = prefix + tag_text
            keys.write_text(original)
            assert migration["migrate_hotkeys"](keys)
            document = tomllib.loads(keys.read_text())
            assert document["keys"][0]["key"] == "v"
            assert not migration["migrate_hotkeys"](keys)
    keys.write_text('keys = [{key="U0076", mod="ALT"}]\n[vars]\nkeys=[]\n')
    assert not migration["migrate_hotkeys"](keys)
    keys.write_text('keys = [{mod="SUPER CTRL", key="x", func="quit"}]\n')
    assert migration["migrate_hotkeys"](keys)
    migrated = keys.read_text()
    assert not migration["migrate_hotkeys"](keys)
    assert keys.read_text() == migrated
    assert list(path.glob('hotkeys.toml.before-clipboard.*'))
print("Clipboard migrations preserve custom rules, aliases, and backups: PASS")
