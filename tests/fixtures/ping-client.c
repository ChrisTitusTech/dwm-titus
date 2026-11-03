#include <X11/Xlib.h>
#include <stdio.h>

int main(void)
{
    Display *display = XOpenDisplay(NULL);
    if (!display) return 1;
    Window root = DefaultRootWindow(display);
    Window window = XCreateSimpleWindow(display, root, 10, 10, 200, 100, 0, 0, 0);
    Atom protocols = XInternAtom(display, "WM_PROTOCOLS", False);
    Atom ping = XInternAtom(display, "_NET_WM_PING", False);
    Atom supported[] = { ping, XInternAtom(display, "WM_TAKE_FOCUS", False),
                         XInternAtom(display, "WM_DELETE_WINDOW", False) };
    XSetWMProtocols(display, window, supported, 3);
    XStoreName(display, window, "AI assistance ping fixture");
    XMapWindow(display, window);
    XFlush(display);
    printf("0x%lx\n", window);
    fflush(stdout);
    for (;;) {
        XEvent event;
        XNextEvent(display, &event);
        if (event.type == ClientMessage && event.xclient.message_type == protocols
                && (Atom)event.xclient.data.l[0] == ping) {
            event.xclient.window = root;
            XSendEvent(display, root, False, SubstructureRedirectMask | SubstructureNotifyMask, &event);
            XFlush(display);
        }
    }
}
