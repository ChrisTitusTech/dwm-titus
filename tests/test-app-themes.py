#!/usr/bin/env python3
"""Exercise installed GTK palettes on X11; run via scripts/run-tests xvfb-run."""
import importlib.util
import json
import shutil
import os
import sys
sys.dont_write_bytecode = True
from pathlib import Path
import subprocess
import tempfile
import tomllib

import gi

gi.require_version('Gtk', '3.0')
gi.require_version('Gdk', '3.0')
from gi.repository import Gdk, Gtk  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('palettes', ROOT / 'scripts/generate-app-themes.py')
palettes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(palettes)
themes = tomllib.loads((ROOT / 'config/themes.toml').read_text())['theme']
subprocess.run(['python3', str(ROOT / 'scripts/generate-app-themes.py'), '--check'], check=True)


def pump():
    while Gtk.events_pending():
        Gtk.main_iteration()


def ratio(a, b):
    lo, hi = sorted((palettes.luminance(a), palettes.luminance(b)))
    return (hi + .05) / (lo + .05)


def hex_color(rgba):
    return '#' + ''.join(f'{round(c * 255):02x}' for c in (rgba.red, rgba.green, rgba.blue))


with tempfile.TemporaryDirectory(dir=os.environ['DWM_TEST_WORKSPACE']) as work:
    stage = Path(work)
    subprocess.run(['make', 'install-app-themes', f'DESTDIR={stage}', 'PREFIX=/usr'],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    stale = stage / 'usr/share/themes/Dwm-dracula/obsolete.css'
    stale.write_text('obsolete')
    unrelated = stage / 'usr/share/themes/Personal/gtk-3.0/gtk.css'
    unrelated.parent.mkdir(parents=True)
    unrelated.write_text('personal')
    subprocess.run(['make', 'install-app-themes', f'DESTDIR={stage}', 'PREFIX=/usr'],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    assert not stale.exists(), 'Theme updates must remove obsolete managed assets'
    assert unrelated.read_text() == 'personal', 'Unrelated themes must be preserved'
    Gtk.Settings.get_default().set_property('gtk-enable-animations', False)
    # Parse the GTK 4 sheets in a separate process (GTK major versions cannot mix).
    subprocess.run([sys.executable, '-c', """
import gi, sys
from pathlib import Path
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk
Gtk.init()
errors = []
for path in Path(sys.argv[1]).glob('Dwm-*/gtk-4.0/gtk.css'):
    provider = Gtk.CssProvider()
    provider.connect('parsing-error', lambda p, s, e: errors.append(str(e)))
    provider.load_from_path(str(path))
assert not errors, errors
""", str(stage / 'usr/share/themes')], check=True)
    home = stage / 'home'
    config = home / '.config'
    (config / 'dwm-titus').mkdir(parents=True)
    (config / 'alacritty').mkdir()
    (config / 'kitty').mkdir()
    runtime = stage / 'runtime'
    runtime.mkdir(mode=0o700)
    theme_file = config / 'dwm-titus/themes.toml'
    # qt6ct is optional. Its executable is only discovered, never invoked,
    # while generating configuration; use a fixture to keep this deterministic.
    binary_dir = stage / 'bin'
    binary_dir.mkdir()
    (binary_dir / 'qt6ct').write_text('#!/bin/sh\nexit 0\n')
    (binary_dir / 'qt6ct').chmod(0o755)
    env = dict(os.environ, PATH=str(binary_dir) + ':' + os.environ['PATH'],
               HOME=str(home), XDG_CONFIG_HOME=str(config),
               XDG_DATA_HOME=str(home / '.local/share'), XDG_DATA_DIRS=str(stage / 'usr/share'),
               XDG_STATE_HOME=str(home / '.local/state'), XDG_RUNTIME_DIR=str(runtime),
               DWM_APPEARANCE_THEMES_FILE=str(theme_file), DISPLAY='', DBUS_SESSION_BUS_ADDRESS='',
               DWM_APPEARANCE_TRANSACTIONAL='1', DWM_APPEARANCE_RUNTIME_ONLY='0')
    for name in themes:
        theme_file.write_text((ROOT / 'config/themes.toml').read_text().replace('theme = "nord"', f'theme = "{name}"'))
        subprocess.run([str(ROOT / 'scripts/theme-apply.sh')], env=env, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        gtk_settings = (config / 'gtk-3.0/settings.ini').read_text()
        assert f'gtk-theme-name=Dwm-{name}' in gtk_settings, (name, gtk_settings)
        for terminal, filename in [('alacritty', 'active-theme.toml'), ('kitty', 'active-theme.conf')]:
            assert themes[name]['term_bg'] in (config / terminal / filename).read_text()
        qt_files = list(config.glob('qt*ct/qt*ct.conf'))
        assert qt_files, 'The detected Qt backend must receive its palette configuration'
        for qt_file in qt_files:
            qt_settings = qt_file.read_text()
            assert f'{qt_file.parent.name}/colors/Dwm-{name}.conf' in qt_settings
            assert 'custom_palette=true' in qt_settings

    # Run the actual shared QML Theme singleton against every preset and a
    # dark-to-light switch, so the original terminal-color hover bug regresses.
    qml_config = stage / 'qml-config/quickshell'
    shutil.copytree(ROOT / 'config/quickshell/core', qml_config / 'core')
    mappings = {
        'background': 'term_bg', 'bar-background': 'normbgcolor', 'surface': 'normbgcolor',
        'surface-hover': 'term_color8', 'surface-active': 'selbgcolor',
        'border': 'normbordercolor', 'border-strong': 'selbordercolor',
        'text': 'normfgcolor', 'text-strong': 'selfgcolor', 'text-muted': 'term_fg',
        'placeholder': 'term_color8', 'accent': 'selbordercolor',
        'accent-secondary': 'term_color4', 'accent-text': 'term_bg',
        'success': 'term_color2', 'warning': 'term_color3',
        'danger': 'term_color1', 'danger-surface': 'term_color0',
    }
    snapshots = [{'name': name, 'dark': themes[name]['dark_mode'],
                  'colors': {role: themes[name][key] for role, key in mappings.items()}}
                 for name in [*themes, 'dracula', 'catppuccin-latte']]
    qml = """import QtQuick
import Quickshell
import qs.core
ShellRoot {
 Timer { interval: 1; running: true; onTriggered: {
  const snapshots = SNAPSHOTS;
  for (const snapshot of snapshots) {
   Theme.applyAppearanceColors(snapshot.colors, snapshot.dark);
   for (const pair of [[Theme.controlNormalText, Theme.controlNormalFill],
                       [Theme.controlHoverText, Theme.controlHoverFill],
                       [Theme.controlSelectedText, Theme.controlSelectedFill],
                       [Theme.controlFocusText, Theme.controlFocusFill],
                       [Theme.menuHoverText, Theme.menuHoverBackground],
                       [Theme.menuSelectedText, Theme.menuSelectedBackground],
                       [Theme.accentText, Theme.accent],
                       [Theme.accentHoverText, Theme.accentSecondary]]) {
    const a = Theme.luminance(pair[0]);
    const b = Theme.luminance(pair[1]);
    if ((Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05) < 4.5)
     throw new Error(snapshot.name + " unreadable role " + pair);
   }
   if (!snapshot.dark && Theme.luminance(Theme.surfaceHover) < 0.5)
    throw new Error(snapshot.name + " dark hover surface");
   console.warn("CONTRAST PASS " + snapshot.name);
  }
  Qt.quit();
 }}
}
""".replace('SNAPSHOTS', json.dumps(snapshots))
    (qml_config / 'shell.qml').write_text(qml)
    qml_env = dict(os.environ, XDG_CONFIG_HOME=str(qml_config.parent),
                   XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(stage / 'qml-cache'),
                   QT_QPA_PLATFORM='xcb')
    try:
        result = subprocess.run(['quickshell', '--no-duplicate'], env=qml_env, timeout=20,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
    except subprocess.TimeoutExpired as error:
        raise AssertionError(error.stdout) from error
    assert result.stdout.count('CONTRAST PASS ') == len(snapshots), result.stdout

    window = Gtk.Window(title='Application palette states')
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=20)
    window.add(box)
    buttons = []
    for label, state in [('Normal', Gtk.StateFlags.NORMAL), ('Hovered', Gtk.StateFlags.PRELIGHT),
                         ('Selected', Gtk.StateFlags.CHECKED), ('Focused', Gtk.StateFlags.FOCUSED),
                         ('Disabled', Gtk.StateFlags.INSENSITIVE)]:
        button = Gtk.Button(label=label)
        box.pack_start(button, False, False, 0)
        buttons.append((button, state))
    window.show_all()
    pump()
    previous = None
    # Repeat a light preset after Dracula to catch stale provider colors.
    for name in [*themes, 'dracula', 'catppuccin-latte']:
        provider = Gtk.CssProvider()
        errors = []
        provider.connect('parsing-error', lambda _p, _s, error: errors.append(str(error)))
        provider.load_from_path(str(stage / f'usr/share/themes/Dwm-{name}/gtk-3.0/gtk.css'))
        assert not errors, (name, errors)
        if previous:
            Gtk.StyleContext.remove_provider_for_screen(Gdk.Screen.get_default(), previous)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider, 600)
        previous = provider
        for button, state in buttons:
            button.set_state_flags(state, True)
        pump()
        for button, state in buttons:
            context = button.get_style_context()
            fg = hex_color(context.get_color(state))
            bg = hex_color(context.get_background_color(state))
            if state != Gtk.StateFlags.INSENSITIVE:
                assert ratio(fg, bg) >= 4.5, (name, button.get_label(), fg, bg, ratio(fg, bg))
        evidence = os.environ.get('DWM_THEME_EVIDENCE_DIR')
        if evidence:
            path = Path(evidence)
            path.mkdir(parents=True, exist_ok=True)
            width, height = window.get_size()
            Gdk.pixbuf_get_from_window(window.get_window(), 0, 0, width, height).savev(
                str(path / f'gtk-{name}.png'), 'png', [], [])
    window.destroy()
print('PASS: all 15 installed GTK palettes parse, retain readable widget states, and apply matching GTK/Qt/terminal colors')
