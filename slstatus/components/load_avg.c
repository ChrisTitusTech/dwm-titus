/* See LICENSE file for copyright and license details. */
#include <stdio.h>
#include <stdlib.h>

#include "../slstatus.h"
#include "../util.h"

const char *
load_avg(const char *unused)
{
	double avgs[3];

	if (getloadavg(avgs, 3) < 0) {
		warn("getloadavg: Failed to obtain load average");
		return NULL;
	}

	return bprintf("%.2f %.2f %.2f", avgs[0], avgs[1], avgs[2]);
}
