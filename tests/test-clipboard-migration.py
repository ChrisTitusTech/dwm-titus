#!/usr/bin/env python3
"""Exercise clipboard migration without replacing user customizations."""
from pathlib import Path
import runpy
import tempfile
from unittest.mock import patch
from types import SimpleNamespace
import ctypes
import os

root = Path(__file__).resolve().parents[1]
migration = runpy.run_path(str(root / "scripts/dwm-migrate-clipboard-surface"))
# Fake the native API to verify modifier selection and resource cleanup paths.
class NativeCall:
    def __init__(self, value): self.value, self.calls = value, []
    def __call__(self, *args): self.calls.append(args); return self.value
mapping = SimpleNamespace(contents=SimpleNamespace(max_keypermod=1, modifiermap=[0,0,0,0,0,77,0,0]))
api = SimpleNamespace(XOpenDisplay=NativeCall(123), XCloseDisplay=NativeCall(0),
    XGetModifierMapping=NativeCall(mapping), XFreeModifiermap=NativeCall(0), XKeysymToKeycode=NativeCall(77))
with patch.dict(os.environ, {"DISPLAY": ":fixture"}), patch.object(ctypes, "CDLL", return_value=api):
    assert migration["numlock_masks"].__wrapped__() == (32,)
assert len(api.XFreeModifiermap.calls) == len(api.XCloseDisplay.calls) == 1
api.XGetModifierMapping.value = None
with patch.dict(os.environ, {"DISPLAY": ":fixture"}), patch.object(ctypes, "CDLL", return_value=api):
    assert len(migration["numlock_masks"].__wrapped__()) > 1
assert len(api.XFreeModifiermap.calls) == 1 and len(api.XCloseDisplay.calls) == 2
assert all(isinstance(mask, int) and 0 <= mask <= 255 for mask in migration["numlock_masks"]())
# Keep conflict tests independent of the invoking workstation modifier map.
migration["super_bound"].__globals__["numlock_masks"] = lambda: (0, 16, 32, 128, 176)
with patch.dict(migration["super_bound"].__globals__, {"numlock_masks": lambda: (8,)}):
    assert migration["super_bound"]({"mod": "SUPER ALT", "key": "v"})
    assert not migration["super_bound"]({"mod": "SUPER CTRL", "key": "v"})
    assert migration["super_bound"]({"mod": "SUPER UnknownToken", "key": "v"})
    assert migration["super_bound"]({"mod": "SUPER shiftmask", "key": "v"})
    assert not migration["super_bound"]({"mod": "super", "key": "v"})
    assert not migration["super_bound"]({"mod": "UnknownToken", "key": "v"})
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
    keys = path / "hotkeys.toml"
    for modifier in ["SUPER", "MODKEY", "Mod4Mask", "SUPER MODKEY", "SUPER Mod2Mask", "SUPER Mod3Mask", "SUPER Mod5Mask", "SUPER LockMask"]:
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
    keys.write_text('keys = [{mod="SUPER CTRL", key="v", func="quit"}]\n')
    assert migration["migrate_hotkeys"](keys)
    migrated = keys.read_text()
    assert not migration["migrate_hotkeys"](keys)
    assert keys.read_text() == migrated
    assert list(path.glob('hotkeys.toml.before-clipboard.*'))
print("Clipboard migrations preserve custom rules, aliases, and backups: PASS")
