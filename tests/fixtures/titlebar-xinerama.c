/* A vertically arranged Xinerama topology inside one tall private Xvfb root. */
#include <X11/Xlib.h>
#include <X11/extensions/Xinerama.h>
#include <stdlib.h>

Bool XineramaIsActive(Display *display) {
    (void)display;
    return True;
}

XineramaScreenInfo *XineramaQueryScreens(Display *display, int *count) {
    (void)display;
    XineramaScreenInfo *screens = calloc(2, sizeof *screens);
    if (!screens) { *count = 0; return NULL; }
    *count = 2;
    for (int index = 0; index < 2; index++) {
        screens[index].screen_number = index;
        screens[index].y_org = index * 800;
        screens[index].width = 1280;
        screens[index].height = 800;
    }
    return screens;
}
