#define _POSIX_C_SOURCE 200809L
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static Display *display;
static Window root;
static const char *theme_path;

static int xerror(Display *connection, XErrorEvent *event) {
	/* Root children can disappear between XQueryTree and property reads. */
	if (event->error_code == BadWindow) return 0;
	char message[128];
	XGetErrorText(connection, event->error_code, message, sizeof message);
	fprintf(stderr, "Unexpected X11 error: %s\n", message);
	abort();
}

static void pause_tick(void) {
	struct timespec delay = {0, 50000000};
	nanosleep(&delay, NULL);
}

static Atom atom(const char *name) { return XInternAtom(display, name, False); }

static Window title_for(Window client, int visible) {
	Window parent, returned_root, *children = NULL, result = None;
	unsigned int count;
	assert(XQueryTree(display, root, &returned_root, &parent, &children, &count));
	for (unsigned int index = 0; index < count; index++) {
		Atom type;
		int format;
		unsigned long length, after;
		unsigned char *data = NULL;
		XWindowAttributes attributes;
		if (XGetWindowProperty(display, children[index], atom("_DWM_TITLEBAR_FOR"), 0, 1,
		    False, XA_WINDOW, &type, &format, &length, &after, &data) == Success
		&& type == XA_WINDOW && format == 32 && length == 1 && !after
		&& ((Window *)data)[0] == client && XGetWindowAttributes(display, children[index], &attributes)
		&& (!visible || attributes.map_state == IsViewable)) result = children[index];
		if (data) XFree(data);
	}
	if (children) XFree(children);
	return result;
}

static Window wait_title(Window client, int visible) {
	for (int attempt = 0; attempt < 200; attempt++) {
		Window window = title_for(client, 1);
		if (!!window == !!visible) return window;
		pause_tick();
	}
	fprintf(stderr, "Titlebar visibility did not become %d for 0x%lx\n", visible, client);
	abort();
}

static void configure_titlebars(int enabled, unsigned int tags) {
	FILE *file = fopen(theme_path, "w");
	assert(file);
	fprintf(file, "[appearance]\nborderpx = 1\ntitlebars = %d\ntitlebar_tags = %u\n", enabled, tags);
	assert(fclose(file) == 0);
}

static void message(Window window, const char *name, long first, long second) {
	XEvent event = {0};
	event.xclient.type = ClientMessage;
	event.xclient.window = window;
	event.xclient.message_type = atom(name);
	event.xclient.format = 32;
	event.xclient.data.l[0] = first;
	event.xclient.data.l[1] = second;
	assert(XSendEvent(display, root, False, SubstructureRedirectMask | SubstructureNotifyMask, &event));
	XSync(display, False);
}

static Window make_client(const char *name, int floating) {
	Window window = XCreateSimpleWindow(display, root, 100, 150, 360, 220, 1, 0, 0x557799);
	Atom delete = atom("WM_DELETE_WINDOW"), dialog = atom("_NET_WM_WINDOW_TYPE_DIALOG");
	XSetWMProtocols(display, window, &delete, 1);
	XStoreName(display, window, name);
	if (floating) XChangeProperty(display, window, atom("_NET_WM_WINDOW_TYPE"), XA_ATOM,
		32, PropModeReplace, (unsigned char *)&dialog, 1);
	XSelectInput(display, window, StructureNotifyMask);
	XMapWindow(display, window);
	XSync(display, False);
	return window;
}

static XWindowAttributes geometry(Window window) {
	XWindowAttributes attributes;
	assert(XGetWindowAttributes(display, window, &attributes));
	return attributes;
}

static void xdotool(char **arguments) {
	pid_t child = fork();
	assert(child >= 0);
	if (!child) { execvp("xdotool", arguments); _exit(127); }
	int status;
	assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

int main(int argc, char **argv) {
	assert(argc == 2);
	theme_path = argv[1];
	display = XOpenDisplay(NULL);
	assert(display);
	XSetErrorHandler(xerror);
	root = DefaultRootWindow(display);
	Window normal = make_client("Tiled client stays undecorated", 0);
	Window floating = make_client("Floating client - drag title or close with x", 1);
	for (int attempt = 0; attempt < 100; attempt++) {
		if (geometry(floating).map_state == IsViewable) break;
		pause_tick();
	}
	pause_tick();
	assert(!title_for(normal, 0) && !title_for(floating, 0));
	configure_titlebars(1, 1);
	Window title = wait_title(floating, 1);
	assert(!title_for(normal, 1));
	XWindowAttributes body = geometry(floating), bar = geometry(title);
	assert(bar.x == body.x && bar.y + bar.height == body.y);
	assert(bar.width == body.width + 2 * body.border_width);
	puts("SCREENSHOT_READY"); fflush(stdout);
	assert(getchar() != EOF);
	XMoveWindow(display, floating, 0, 0);
	XSync(display, False);
	for (int attempt = 0; attempt < 100; attempt++) {
		body = geometry(floating); bar = geometry(title);
		if (body.x == 0 && body.y == bar.height && bar.x == body.x
		&& bar.y + bar.height == body.y) break;
		pause_tick();
	}
	assert(body.x == 0 && body.y == bar.height && bar.x == body.x && bar.y + bar.height == body.y);
	char title_id[32]; snprintf(title_id, sizeof title_id, "%lu", title);
	char *drag[] = {"xdotool", "mousemove", "--window", title_id, "12", "12", "mousedown", "1",
		"sleep", "0.3", "mousemove_relative", "--sync", "50", "40", "sleep", "0.2",
		"mousemove_relative", "--sync", "50", "40", "sleep", "0.2", "mouseup", "1", NULL};
	xdotool(drag);
	for (int attempt = 0; attempt < 100 && geometry(floating).x < body.x + 90; attempt++) pause_tick();
	fprintf(stdout, "Native drag: (%d,%d) -> (%d,%d)\n", body.x, body.y,
		geometry(floating).x, geometry(floating).y);
	assert(geometry(floating).x >= body.x + 90);
	body = geometry(floating); bar = geometry(title);
	assert(bar.x == body.x && bar.y + bar.height == body.y);
	configure_titlebars(1, 2);
	wait_title(floating, 0);
	message(floating, "_NET_WM_DESKTOP", 1, 0);
	message(root, "_NET_CURRENT_DESKTOP", 1, 0);
	wait_title(floating, 1);
	message(floating, "_NET_WM_STATE", 1, atom("_NET_WM_STATE_FULLSCREEN"));
	wait_title(floating, 0);
	message(floating, "_NET_WM_STATE", 0, atom("_NET_WM_STATE_FULLSCREEN"));
	title = wait_title(floating, 1);
	configure_titlebars(0, 511);
	wait_title(floating, 0);
	configure_titlebars(1, 511);
	title = wait_title(floating, 1);
	/* The two-screen fixture also moves the client to the other actual
	 * monitor, without giving the decoration its own client-list entry. */
	Atom actual;
	int format;
	unsigned long count, after;
	unsigned char *data = NULL;
	assert(XGetWindowProperty(display, root, atom("_NET_CLIENT_LIST"), 0, 32,
		False, XA_WINDOW, &actual, &format, &count, &after, &data) == Success);
	assert(count == 2);
	if (data) XFree(data);
	data = NULL;
	assert(XGetWindowProperty(display, root, atom("_DWM_MONITOR_DESKTOPS"), 0, 64,
		False, AnyPropertyType, &actual, &format, &count, &after, &data) == Success);
	if (data) XFree(data);
	if (count >= 10) {
		message(floating, "_NET_WM_DESKTOP", 5, 0);
		message(root, "_NET_CURRENT_DESKTOP", 5, 0);
		title = wait_title(floating, 1);
		body = geometry(floating); bar = geometry(title);
		assert(bar.x == body.x && bar.y + bar.height == body.y);
		message(floating, "_NET_WM_DESKTOP", 1, 0);
		message(root, "_NET_CURRENT_DESKTOP", 1, 0);
		title = wait_title(floating, 1);
	}
	message(normal, "_NET_WM_DESKTOP", 1, 0);
	char *layout_float[] = {"xdotool", "key", "super+f", NULL};
	xdotool(layout_float);
	wait_title(normal, 1);
	char *layout_tile[] = {"xdotool", "key", "super+t", NULL};
	xdotool(layout_tile);
	wait_title(normal, 0);
	XStoreName(display, floating, "Title changed while open");
	XSync(display, False);
	bar = geometry(title);
	char close_x[32]; snprintf(close_x, sizeof close_x, "%d", bar.width - bar.height / 2);
	char *close[] = {"xdotool", "mousemove", "--window", title_id, close_x, "10", "click", "1", NULL};
	xdotool(close);
	int deleted = 0;
	for (int attempt = 0; attempt < 100 && !deleted; attempt++) {
		while (XPending(display)) {
			XEvent event; XNextEvent(display, &event);
			if (event.type == ClientMessage && event.xclient.window == floating
			&& event.xclient.message_type == atom("WM_PROTOCOLS")
			&& (Atom)event.xclient.data.l[0] == atom("WM_DELETE_WINDOW")) deleted = 1;
		}
		if (!deleted) pause_tick();
	}
	assert(deleted);
	XDestroyWindow(display, floating);
	XSync(display, False);
	for (int attempt = 0; attempt < 100 && title_for(floating, 0); attempt++) pause_tick();
	assert(!title_for(floating, 0));
	XDestroyWindow(display, normal);
	XSync(display, False);
	XCloseDisplay(display);
	puts("Titlebar defaults, geometry, application resize, drag, per-tag policy, fullscreen, layouts, WM_DELETE and cleanup: PASS");
	return 0;
}
