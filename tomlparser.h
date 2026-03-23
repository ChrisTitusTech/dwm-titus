/* Minimal TOML parser for dwm-titus hot-reload configuration.
 * Supports: string, integer, float, string arrays,
 *           [section], [[array-of-tables]]
 * Comments (#), basic string escapes (\n \t \\ \")
 */
#pragma once
#include <stddef.h>

#define TOML_MAX_ENTRIES 512
#define TOML_MAX_STR     512
#define TOML_MAX_ARR      32

typedef enum {
	TOML_STRING = 0,
	TOML_INT,
	TOML_FLOAT,
	TOML_ARRAY
} TomlType;

typedef struct {
	TomlType type;
	char     s[TOML_MAX_STR];               /* TOML_STRING */
	long     i;                              /* TOML_INT    */
	double   d;                              /* TOML_FLOAT  */
	struct {
		char  items[TOML_MAX_ARR][TOML_MAX_STR];
		int   len;
	} a;                                     /* TOML_ARRAY  */
} TomlValue;

typedef struct {
	char      section[TOML_MAX_STR];
	int       table_idx;   /* -1 for [section], >=0 for [[array-of-tables]] */
	char      key[TOML_MAX_STR];
	TomlValue val;
} TomlEntry;

typedef struct {
	TomlEntry entries[TOML_MAX_ENTRIES];
	int       n;
} TomlDoc;

/* Parse a TOML file at path. Returns 1 on success, 0 on error. */
int toml_parse(const char *path, TomlDoc *doc);

/* Get value from a [section] by key. Returns NULL if not found. */
const TomlValue *toml_get(const TomlDoc *doc, const char *section,
                          const char *key);

/* Count [[section]] array-of-tables entries. */
int toml_table_count(const TomlDoc *doc, const char *section);

/* Get value from the idx-th [[section]] table by key. */
const TomlValue *toml_table_get(const TomlDoc *doc, const char *section,
                                int idx, const char *key);
