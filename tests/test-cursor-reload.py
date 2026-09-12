#!/usr/bin/python3
"""Check cursor replacement in an existing X11 client, plus XSETTINGS reload."""

import ctypes as c
import importlib.machinery
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

repo = Path(__file__).resolve().parent.parent
os.environ["XCURSOR_PATH"] = str(repo / "assets/cursors")
module = importlib.machinery.SourceFileLoader(
    "cursor_reload", str(repo / "scripts/dwm-cursor-reload")
).load_module()
bind = module.binding
x11, xc, fixes = (
    c.CDLL("libX11.so.6"),
    c.CDLL("libXcursor.so.1"),
    c.CDLL("libXfixes.so.3"),
)
display = bind(x11, "XOpenDisplay", c.c_void_p, c.c_char_p)(None)
assert display
major, minor = c.c_int(2), c.c_int(0)
assert bind(
    fixes,
    "XFixesQueryVersion",
    c.c_int,
    c.c_void_p,
    c.POINTER(c.c_int),
    c.POINTER(c.c_int),
)(display, c.byref(major), c.byref(minor))
root = bind(x11, "XDefaultRootWindow", c.c_ulong, c.c_void_p)(display)
create = bind(
    x11,
    "XCreateSimpleWindow",
    c.c_ulong,
    c.c_void_p,
    c.c_ulong,
    c.c_int,
    c.c_int,
    c.c_uint,
    c.c_uint,
    c.c_uint,
    c.c_ulong,
    c.c_ulong,
)
window = create(display, root, 0, 0, 100, 100, 0, 0, 0)
bind(x11, "XMapWindow", c.c_int, c.c_void_p, c.c_ulong)(display, window)
bind(xc, "XcursorSetTheme", c.c_int, c.c_void_p, c.c_char_p)(
    display, b"Capitaine-Cursors"
)
bind(xc, "XcursorSetDefaultSize", c.c_int, c.c_void_p, c.c_int)(display, 24)
handle = bind(xc, "XcursorLibraryLoadCursor", c.c_ulong, c.c_void_p, c.c_char_p)(
    display, b"left_ptr"
)
assert handle
bind(x11, "XDefineCursor", c.c_int, c.c_void_p, c.c_ulong, c.c_ulong)(
    display, window, handle
)
bind(
    x11,
    "XWarpPointer",
    c.c_int,
    c.c_void_p,
    c.c_ulong,
    c.c_ulong,
    c.c_int,
    c.c_int,
    c.c_uint,
    c.c_uint,
    c.c_int,
    c.c_int,
)(display, 0, window, 0, 0, 0, 0, 25, 25)
sync = bind(x11, "XSync", c.c_int, c.c_void_p, c.c_int)
sync(display, 0)


class CursorImage(c.Structure):
    _fields_ = [
        ("x", c.c_short),
        ("y", c.c_short),
        ("width", c.c_ushort),
        ("height", c.c_ushort),
        ("xhot", c.c_ushort),
        ("yhot", c.c_ushort),
        ("serial", c.c_ulong),
        ("pixels", c.POINTER(c.c_ulong)),
        ("atom", c.c_ulong),
        ("name", c.c_char_p),
    ]


image = bind(fixes, "XFixesGetCursorImage", c.POINTER(CursorImage), c.c_void_p)
free = bind(x11, "XFree", c.c_int, c.c_void_p)


def pixels():
    bind(
        x11,
        "XWarpPointer",
        c.c_int,
        c.c_void_p,
        c.c_ulong,
        c.c_ulong,
        c.c_int,
        c.c_int,
        c.c_uint,
        c.c_uint,
        c.c_int,
        c.c_int,
    )(display, 0, window, 0, 0, 0, 0, 26, 26)
    sync(display, 0)
    pointer = image(display)
    assert pointer
    data = pointer.contents
    result = tuple(data.pixels[i] for i in range(data.width * data.height))
    free(pointer)
    return result


def client_count():
    # Use the same XCB RES runtime already required by the dwm build.
    class Cookie(c.Structure):
        _fields_ = [("sequence", c.c_uint)]

    bridge = c.CDLL("libX11-xcb.so.1")
    res = c.CDLL("libxcb-res.so.0")
    connection = bind(bridge, "XGetXCBConnection", c.c_void_p, c.c_void_p)(display)
    cookie = bind(res, "xcb_res_query_clients", Cookie, c.c_void_p)(connection)
    reply = bind(
        res, "xcb_res_query_clients_reply", c.c_void_p, c.c_void_p, Cookie, c.c_void_p
    )(connection, cookie, None)
    assert reply
    count = bind(res, "xcb_res_query_clients_clients_length", c.c_int, c.c_void_p)(
        reply
    )
    free(reply)
    return count


try:
    before_clients = client_count()
    before = pixels()
    subprocess.run(
        [repo / "scripts/dwm-cursor-reload", "Capitaine-Cursors-White", "24"],
        check=True,
    )
    after = pixels()
    assert before != after, "the existing window retained its old cursor"
    subprocess.run(
        [repo / "scripts/dwm-cursor-reload", "Capitaine-Cursors", "24"], check=True
    )
    assert pixels() == before, "cursor rollback did not restore the existing client"
    assert client_count() == before_clients + 1, (
        "repeated changes leaked retained X11 clients"
    )
finally:
    bind(x11, "XCloseDisplay", c.c_int, c.c_void_p)(display)

test_root = Path(
    os.environ.get("TMPDIR")
    or os.environ.get("DWM_TEST_TMP_ROOT")
    or Path.home() / "tmp"
)
test_root.mkdir(mode=0o700, parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(dir=test_root) as work:
    config = Path(work) / "config/dwm-titus"
    config.mkdir(parents=True)
    runtime = Path(work) / "runtime"
    runtime.mkdir(mode=0o700)
    env = dict(
        os.environ, XDG_CONFIG_HOME=str(config.parent), XDG_RUNTIME_DIR=str(runtime)
    )
    path = config / "xsettingsd.conf"
    try:
        for theme in ("Capitaine-Cursors", "Capitaine-Cursors-White"):
            path.write_text(
                "# Auto-generated by theme-apply.sh - do not edit manually.\n"
                f'Gtk/CursorThemeName "{theme}"\nGtk/CursorThemeSize 24\n'
            )
            subprocess.run(
                [repo / "scripts/dwm-xsettings", "reload"], env=env, check=True
            )
            published = subprocess.check_output(["dump_xsettings"], env=env, text=True)
            assert f'Gtk/CursorThemeName "{theme}"' in published
            assert "Xft/DPI" not in published, "cursor refresh pinned text scaling"
            status = subprocess.check_output(
                [repo / "scripts/dwm-xsettings", "status"], env=env, text=True
            )
            assert "state\tsystem-follow" in status
    finally:
        path.write_text("# Auto-generated by theme-apply.sh - do not edit manually.\n")
        subprocess.run([repo / "scripts/dwm-xsettings", "reload"], env=env, check=True)
print("Live X11 cursor replacement, rollback and XSETTINGS cursor reload: PASS")
