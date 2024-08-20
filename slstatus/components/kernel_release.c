/* See LICENSE file for copyright and license details. */
#include <stdio.h>
#include <sys/utsname.h>

#include "../slstatus.h"
#include "../util.h"

const char *
kernel_release(const char *unused)
{
	struct utsname udata;

	if (uname(&udata) < 0) {
		warn("uname:");
		return NULL;
	}

	return bprintf("%s", udata.release);
}
