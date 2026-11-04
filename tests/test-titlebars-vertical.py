"""Verify a real titlebar drag from a lower virtual monitor to an upper one."""
import ctypes as C
import ctypes.util
import os
import shlex
from pathlib import Path
import shutil, subprocess as S, sys, tempfile, time
sys.dont_write_bytecode = True
repo = Path(__file__).resolve().parents[1]

class Connection:

    def __init__(self):
        self.x = C.CDLL(ctypes.util.find_library('X11') or 'libX11.so.6')
        signatures = {'XOpenDisplay': ([C.c_char_p], C.c_void_p), 'XDefaultRootWindow': ([C.c_void_p], C.c_ulong), 'XInternAtom': ([C.c_void_p, C.c_char_p, C.c_int], C.c_ulong), 'XGetWindowProperty': ([C.c_void_p, C.c_ulong, C.c_ulong, C.c_long, C.c_long, C.c_int, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_int), C.POINTER(C.c_ulong), C.POINTER(C.c_ulong), C.POINTER(C.c_void_p)], C.c_int), 'XFlush': ([C.c_void_p], C.c_int), 'XFree': ([C.c_void_p], C.c_int), 'XCloseDisplay': ([C.c_void_p], C.c_int)}
        for name, (args, result) in signatures.items():
            function = getattr(self.x, name)
            function.argtypes = args
            function.restype = result
        self.display = self.x.XOpenDisplay(None)
        assert self.display, 'Cannot open private X11 display'
        self.root = self.x.XDefaultRootWindow(self.display)

    def atom(self, name):
        return self.x.XInternAtom(self.display, name.encode(), False)

    def property(self, window, name):
        actual, count, after = (C.c_ulong(), C.c_ulong(), C.c_ulong())
        form = C.c_int()
        data = C.c_void_p()
        self.x.XGetWindowProperty(self.display, window, self.atom(name), 0, 4, False, 0, C.byref(actual), C.byref(form), C.byref(count), C.byref(after), C.byref(data))
        try:
            return list(C.cast(data, C.POINTER(C.c_ulong))[:count.value]) if data and form.value == 32 and (not after.value) else []
        finally:
            if data:
                self.x.XFree(data)

    def close(self):
        self.x.XCloseDisplay(self.display)

def run(*a):
    return S.run(a, check=True, text=True, capture_output=True, timeout=15)

def wait(f):
    end = time.monotonic() + 10
    while time.monotonic() < end:
        v = f()
        if v:
            return v
        time.sleep(0.05)
    raise AssertionError('Probe condition timed out')
with tempfile.TemporaryDirectory(dir=os.environ['TMPDIR']) as t:
    cfg = Path(t) / 'config/dwm-titus'
    cfg.mkdir(parents=True)
    for name in ('hotkeys.toml', 'window-rules.toml'):
        shutil.copy(repo / 'config' / name, cfg / name)
    (cfg / 'themes.toml').write_text('[appearance]\ntitlebars=1\ntitlebar_tags=511\n')
    flags = shlex.split(S.check_output(['pkg-config', '--cflags', 'xinerama'], text=True))
    S.run(shlex.split(os.environ.get('CC', 'cc')) + ['-std=c99', '-shared', '-fPIC', '-Wall', '-Wextra', '-Werror', str(repo / 'tests/fixtures/titlebar-xinerama.c'), '-o', str(Path(t) / 'xinerama.so')] + flags, check=True)
    env = {**os.environ, 'HOME': t, 'XDG_CONFIG_HOME': str(cfg.parent), 'XDG_DATA_HOME': t + '/data', 'LD_PRELOAD': str(Path(t) / 'xinerama.so')}
    with (Path(t) / 'dwm.log').open('w') as log:
        wm = S.Popen([str(repo / 'dwm')], env=env, stdout=log, stderr=log)
        c = None
        try:
            c = Connection()
            x, d, r = (c.x, c.display, c.root)
            wait(lambda: c.property(r, '_NET_SUPPORTING_WM_CHECK'))
            run('xdotool', 'set_desktop', '5')
            wait(lambda: c.property(r, '_NET_CURRENT_DESKTOP') == [5])
            x.XCreateSimpleWindow.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_uint, C.c_ulong, C.c_ulong]
            x.XCreateSimpleWindow.restype = C.c_ulong
            x.XChangeProperty.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_ulong, C.c_int, C.c_int, C.c_void_p, C.c_int]
            x.XMapWindow.argtypes = [C.c_void_p, C.c_ulong]
            w = x.XCreateSimpleWindow(d, r, 200, 1000, 360, 220, 1, 0, 1)
            dialog = C.c_ulong(c.atom('_NET_WM_WINDOW_TYPE_DIALOG'))
            x.XChangeProperty(d, w, c.atom('_NET_WM_WINDOW_TYPE'), 4, 32, 0, C.byref(dialog), 1)
            x.XMapWindow(d, w)
            x.XFlush(d)

            def title():
                q = S.run(['xdotool', 'search', '--class', 'DwmTitlebar'], text=True, capture_output=True)
                return q.stdout.splitlines()[0] if q.returncode == 0 and q.stdout.strip() else None
            titleid = wait(title)

            def geometry(win):
                return dict((line.split('=', 1) for line in run('xdotool', 'getwindowgeometry', '--shell', str(win)).stdout.splitlines()))
            bar = geometry(titleid)
            body = geometry(w)
            print('Before', bar, body, flush=True)
            assert int(bar['Y']) >= 800
            run('xdotool', 'mousemove', str(int(bar['X']) + 12), str(int(bar['Y']) + 12), 'mousedown', '1', 'sleep', '0.3', 'mousemove', '600', '500', 'sleep', '0.2', 'mousemove', '600', '200', 'sleep', '0.2', 'mouseup', '1')
            wait(lambda: int(geometry(w)['Y']) < 800)
            body = geometry(w)
            bar = geometry(titleid)
            print('After', bar, body, flush=True)
            assert int(bar['Y']) >= 0 and int(bar['Y']) + int(bar['HEIGHT']) == int(body['Y'])
            assert int(geometry(w)['Y']) < 800
            print('Real lower-to-upper monitor titlebar drag: PASS', flush=True)
        finally:
            wm.terminate()
            wm.wait(timeout=5)
            if c:
                c.close()
