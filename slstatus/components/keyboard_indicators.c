/* See LICENSE file for copyright and license details. */
#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include <X11/Xlib.h>

#include "../slstatus.h"
#include "../util.h"

/*
 * fmt consists of uppercase or lowercase 'c' for caps lock and/or 'n' for num
 * lock, each optionally followed by '?', in the order of indicators desired.
 * If followed by '?', the letter with case preserved is included in the output
 * if the corresponding indicator is on.  Otherwise, the letter is always
 * included, lowercase when off and uppercase when on.
 */
const char *
keyboard_indicators(const char *fmt)
{
	Display *dpy;
	XKeyboardState state;
	size_t fmtlen, i, n;
	int togglecase, isset;
	char key;

	if (!(dpy = XOpenDisplay(NULL))) {
		warn("XOpenDisplay: Failed to open display");
		return NULL;
	}
	XGetKeyboardControl(dpy, &state);
	XCloseDisplay(dpy);

	fmtlen = strnlen(fmt, 4);
	for (i = n = 0; i < fmtlen; i++) {
		key = tolower(fmt[i]);
		if (key != 'c' && key != 'n')
			continue;

		togglecase = (i + 1 >= fmtlen || fmt[i + 1] != '?');
		isset = (state.led_mask & (1 << (key == 'n')));

		if (togglecase)
			buf[n++] = isset ? toupper(key) : key;
		else if (isset)
			buf[n++] = fmt[i];
	}

	buf[n] = 0;
	return buf;
}
