#!/usr/bin/env python3
"""Exercise clipboard migration without replacing user customizations."""
from pathlib import Path
import runpy
import tempfile

root = Path(__file__).resolve().parents[1]
migration = runpy.run_path(str(root / "scripts/dwm-migrate-clipboard-surface"))
with tempfile.TemporaryDirectory(prefix="clipboard-migration-") as directory:
    path = Path(directory)
    rules = path / "window-rules.toml"
    original = 'rules = [{title="dwm clipboard", isfloating=0, alwaysontop=0}]\n'
    rules.write_text(original)
    assert not migration["migrate_window_rules"](rules)
    assert rules.read_text() == original
    keys = path / "hotkeys.toml"
    for modifier in ["SUPER", "super", "MODKEY", "Mod4Mask", "SUPER MODKEY"]:
        original = f'keys = [{{mod="{modifier}", key="v", func="quit"}}]\n'
        keys.write_text(original)
        assert not migration["migrate_hotkeys"](keys), modifier
        assert keys.read_text() == original
    for prefix in ["", "[vars]\n"]:
        original = prefix + 'keys = []\ntag_keys = [{key="v", tag=1}]\n'
        keys.write_text(original)
        assert not migration["migrate_hotkeys"](keys)
        assert keys.read_text() == original
    keys.write_text('keys = [{mod="SUPER CTRL", key="v", func="quit"}]\n')
    assert migration["migrate_hotkeys"](keys)
    migrated = keys.read_text()
    assert not migration["migrate_hotkeys"](keys)
    assert keys.read_text() == migrated
    assert list(path.glob('hotkeys.toml.before-clipboard.*'))
print("Clipboard migrations preserve custom rules, aliases, and backups: PASS")
