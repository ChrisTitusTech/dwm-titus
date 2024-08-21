/* See LICENSE file for copyright and license details. */
#include <stdio.h>
#include <string.h>

#include "../slstatus.h"
#include "../util.h"

const char *
cat(const char *path)
{
        char *f;
        FILE *fp;

        if (!(fp = fopen(path, "r"))) {
                warn("fopen '%s':", path);
                return NULL;
        }

        f = fgets(buf, sizeof(buf) - 1, fp);
        if (fclose(fp) < 0) {
                warn("fclose '%s':", path);
                return NULL;
        }
        if (!f)
                return NULL;

        if ((f = strrchr(buf, '\n')))
                f[0] = '\0';

        return buf[0] ? buf : NULL;
}

