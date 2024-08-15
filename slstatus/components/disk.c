/* See LICENSE file for copyright and license details. */
#include <stdio.h>
#include <sys/statvfs.h>

#include "../slstatus.h"
#include "../util.h"

const char *
disk_free(const char *path)
{
	struct statvfs fs;

	if (statvfs(path, &fs) < 0) {
		warn("statvfs '%s':", path);
		return NULL;
	}

	return fmt_human(fs.f_frsize * fs.f_bavail, 1024);
}

const char *
disk_perc(const char *path)
{
	struct statvfs fs;

	if (statvfs(path, &fs) < 0) {
		warn("statvfs '%s':", path);
		return NULL;
	}

	return bprintf("%d", (int)(100 *
	               (1 - ((double)fs.f_bavail / (double)fs.f_blocks))));
}

const char *
disk_total(const char *path)
{
	struct statvfs fs;

	if (statvfs(path, &fs) < 0) {
		warn("statvfs '%s':", path);
		return NULL;
	}

	return fmt_human(fs.f_frsize * fs.f_blocks, 1024);
}

const char *
disk_used(const char *path)
{
	struct statvfs fs;

	if (statvfs(path, &fs) < 0) {
		warn("statvfs '%s':", path);
		return NULL;
	}

	return fmt_human(fs.f_frsize * (fs.f_blocks - fs.f_bfree), 1024);
}
