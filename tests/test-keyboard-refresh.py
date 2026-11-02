#!/usr/bin/env python3
"""Exercise XKB refresh failures without depending on a failing X server."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "dwm.c").read_text()

def function(name):
    start = source.index("void\n" + name + "(")
    end = source.index("\n}\n", start) + 3
    return source[start:end]

fixture = r'''
#include <assert.h>
#include <X11/XKBlib.h>
#define XkbAllocKeyboard fixture_alloc
#define XkbGetControls fixture_controls
#define XkbGetNames fixture_names
#define XkbGetState fixture_state
#define XkbFreeKeyboard fixture_free
static Display *dpy;
static int xkbeventbase = 90, kbretry, kbgroups;
static unsigned char kbwrap;
static int failure, reads, publications;
static XkbDescRec keyboard;
static XkbControlsRec controls;
static XkbNamesRec names;
static XkbDescPtr fixture_alloc(void) {
    reads++;
    keyboard.ctrls = &controls;
    keyboard.names = &names;
    return failure == 5 ? NULL : &keyboard;
}
static int fixture_controls(Display *d, unsigned long mask, XkbDescPtr k) {
    (void)d; (void)mask;
    k->ctrls->num_groups = failure == 4 ? 0 : 2;
    k->ctrls->groups_wrap = XkbWrapIntoRange;
    return failure == 1 ? BadAccess : Success;
}
static int fixture_names(Display *d, unsigned int mask, XkbDescPtr k) {
    (void)d; (void)mask; (void)k;
    return failure == 2 ? BadAccess : Success;
}
static int fixture_state(Display *d, unsigned int id, XkbStatePtr state) {
    (void)d; (void)id;
    state->group = 1;
    return failure == 3 ? BadAccess : Success;
}
static void fixture_free(XkbDescPtr k, unsigned int mask, Bool all) {
    (void)k; (void)mask; (void)all;
}
static void kbpublishgroup(int group) {
    assert(group == 1); publications++;
}
static int kbpublishnames(XkbDescPtr k) {
    (void)k; publications++; return failure != 6;
}
'''
fixture += function("updatekeyboard") + function("xkbevent")
fixture += r'''
int main(void) {
    XkbEvent event = {0};
    event.any.xkb_type = XkbStateNotify;
    event.state.group = 1;
    for (failure = 1; failure <= 5; failure++) {
        kbgroups = 3; kbwrap = XkbClampIntoRange;
        kbretry = publications = 0;
        updatekeyboard();
        assert(kbretry && kbgroups == 3 && kbwrap == XkbClampIntoRange);
        assert(publications == 0);
    }
    failure = 6;
    updatekeyboard();
    assert(kbretry);
    publications = 0;
    failure = 0;
    xkbevent((XEvent *)&event);
    assert(!kbretry && kbgroups == 2 && kbwrap == XkbWrapIntoRange);
    assert(publications == 2);
    int previous_reads = reads;
    xkbevent((XEvent *)&event);
    assert(reads == previous_reads && publications == 3);
    return 0;
}
'''
with tempfile.TemporaryDirectory(prefix="keyboard-refresh-") as directory:
    path = Path(directory)
    (path / "fixture.c").write_text(fixture)
    subprocess.run(shlex.split(os.environ.get("CC", "cc")) + [
        "-std=c99", "-Wall", "-Wextra", "-Werror", str(path / "fixture.c"),
        "-o", str(path / "fixture")], check=True)
    subprocess.run([str(path / "fixture")], check=True)
print("XKB refresh preserves state after read failures and retries on events: PASS")

# Exercise the production parser without starting an X server.
helper = (root / "scripts/dwm-quickshell-state").read_text()
parser = helper[helper.index("keyboard_codes() {"):helper.index("# One xprop read for all keyboard fields.")]
for symbols, groups, expected in [
    ("pc+us+inet(evdev)+group(alts_toggle):1", "1", "us"),
    ("pc+us+level3(ralt_switch):1", "1", "us"),
    ("pc+us+inet(evdev)+gr:2", "2", "us|gr"),
    ("pc+us+capslock(escape):1+ctrl(nocaps):1+compose(ralt):1", "1", "us"),
    ("pc+inet(evdev)+gr:2+us:1+level3(ralt_switch):1", "2", "us|gr"),
    ("pc+unlisted_custom+inet(evdev)+gr:2", "2", "|gr"),
    ("us:1+inet(evdev)+gr:2", "2", "us|gr"),
    ("pc+us:1+inet(evdev)+de:3", "3", "us||de"),
]:
    result = subprocess.run(["sh", "-c", parser + '\nkeyboard_codes "$1" "" "$2" "us|gr|de"',
                             "sh", symbols, groups], capture_output=True, text=True, check=True)
    assert result.stdout == expected, (symbols, result.stdout)
print("Keyboard symbols preserve layout codes around option components: PASS")
