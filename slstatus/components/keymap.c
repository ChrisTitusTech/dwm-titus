/* See LICENSE file for copyright and license details. */
#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <X11/XKBlib.h>
#include <X11/Xlib.h>

#include "../slstatus.h"
#include "../util.h"

static int
valid_layout_or_variant(char *sym)
{
	size_t i;
	/* invalid symbols from xkb rules config */
	static const char *invalid[] = { "evdev", "inet", "pc", "base" };

	for (i = 0; i < LEN(invalid); i++)
		if (!strncmp(sym, invalid[i], strlen(invalid[i])))
			return 0;

	return 1;
}

static char *
get_layout(char *syms, int grp_num)
{
	char *tok, *layout;
	int grp;

	layout = NULL;
	tok = strtok(syms, "+:");
	for (grp = 0; tok && grp <= grp_num; tok = strtok(NULL, "+:")) {
		if (!valid_layout_or_variant(tok)) {
			continue;
		} else if (strlen(tok) == 1 && isdigit(tok[0])) {
			/* ignore :2, :3, :4 (additional layout groups) */
			continue;
		}
		layout = tok;
		grp++;
	}

	return layout;
}

const char *
keymap(const char *unused)
{
	Display *dpy;
	XkbDescRec *desc;
	XkbStateRec state;
	char *symbols;
	const char *layout;

	layout = NULL;

	if (!(dpy = XOpenDisplay(NULL))) {
		warn("XOpenDisplay: Failed to open display");
		return NULL;
	}
	if (!(desc = XkbAllocKeyboard())) {
		warn("XkbAllocKeyboard: Failed to allocate keyboard");
		goto end;
	}
	if (XkbGetNames(dpy, XkbSymbolsNameMask, desc)) {
		warn("XkbGetNames: Failed to retrieve key symbols");
		goto end;
	}
	if (XkbGetState(dpy, XkbUseCoreKbd, &state)) {
		warn("XkbGetState: Failed to retrieve keyboard state");
		goto end;
	}
	if (!(symbols = XGetAtomName(dpy, desc->names->symbols))) {
		warn("XGetAtomName: Failed to get atom name");
		goto end;
	}
	layout = bprintf("%s", get_layout(symbols, state.group));
	XFree(symbols);
end:
	XkbFreeKeyboard(desc, XkbSymbolsNameMask, 1);
	if (XCloseDisplay(dpy))
		warn("XCloseDisplay: Failed to close display");

	return layout;
}
