/* See LICENSE file for copyright and license details. */
#include <dirent.h>
#include <stdio.h>
#include <string.h>

#include "../slstatus.h"
#include "../util.h"

const char *
num_files(const char *path)
{
	struct dirent *dp;
	DIR *dir;
	int num;

	if (!(dir = opendir(path))) {
		warn("opendir '%s':", path);
		return NULL;
	}

	num = 0;
	while ((dp = readdir(dir))) {
		if (!strcmp(dp->d_name, ".") || !strcmp(dp->d_name, ".."))
			continue; /* skip self and parent */

		num++;
	}

	closedir(dir);

	return bprintf("%d", num);
}
