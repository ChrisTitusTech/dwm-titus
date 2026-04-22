/* See LICENSE file for copyright and license details.
 * Minimal TOML parser for dwm-dohc hot-reload configuration.
 */
#include "tomlparser.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

static char *
strtrim(char *s)
{
	while (isspace((unsigned char)*s)) s++;
	if (*s) {
		char *e = s + strlen(s) - 1;
		while (e > s && isspace((unsigned char)*e)) *e-- = '\0';
	}
	return s;
}

int
toml_table_count(const TomlDoc *doc, const char *section)
{
	int max = -1, i;
	for (i = 0; i < doc->n; i++)
		if (doc->entries[i].table_idx >= 0
		    && strcmp(doc->entries[i].section, section) == 0
		    && doc->entries[i].table_idx > max)
			max = doc->entries[i].table_idx;
	return max + 1;
}

/* ── Inline string un-escaping ───────────────────────────────────────────── */
/* Copies unescaped content from src (pointing just after opening '"') into
 * dst, stopping before the closing '"'.  Returns pointer to the closing '"'
 * (or end-of-string if unterminated). */
static const char *
unescape_into(const char *src, char *dst, int maxlen)
{
	int si = 0;
	while (*src && *src != '"' && si < maxlen - 1) {
		if (*src == '\\' && *(src + 1)) {
			src++;
			switch (*src) {
			case 'n':  dst[si++] = '\n'; break;
			case 't':  dst[si++] = '\t'; break;
			case '\\': dst[si++] = '\\'; break;
			case '"':  dst[si++] = '"';  break;
			default:   dst[si++] = *src; break;
			}
		} else {
			dst[si++] = *src;
		}
		src++;
	}
	dst[si] = '\0';
	return src; /* points to closing '"' or '\0' */
}

/* ── Inline table parser ─────────────────────────────────────────────────── */
/* Parses key=value pairs from content between { and }.
 * p points to first character *after* the opening '{'.
 * Returns pointer to first character *after* the closing '}'.
 * Each pair is stored as a TomlEntry with the given section and tidx. */
static const char *
parse_inline_table(const char *p, TomlDoc *doc, const char *section, int tidx)
{
	while (*p) {
		/* skip whitespace and commas between pairs */
		while (isspace((unsigned char)*p) || *p == ',') p++;
		if (*p == '}' || *p == '\0') break;
		if (doc->n >= TOML_MAX_ENTRIES) break;

		/* key (unquoted identifier) */
		const char *kstart = p;
		while (*p && *p != '=' && !isspace((unsigned char)*p) && *p != '}') p++;
		int klen = (int)(p - kstart);
		if (klen <= 0 || klen >= TOML_MAX_STR) break;
		while (isspace((unsigned char)*p)) p++;
		if (*p != '=') break;
		p++; /* skip '=' */
		while (isspace((unsigned char)*p)) p++;

		TomlEntry *ent = &doc->entries[doc->n];
		strncpy(ent->section, section, TOML_MAX_STR - 1);
		ent->section[TOML_MAX_STR - 1] = '\0';
		ent->table_idx = tidx;
		strncpy(ent->key, kstart, (size_t)klen);
		ent->key[klen] = '\0';

		if (*p == '"') {
			ent->val.type = TOML_STRING;
			p = unescape_into(p + 1, ent->val.s, TOML_MAX_STR);
			if (*p == '"') p++; /* skip closing quote */

		} else if (*p == '[') {
			ent->val.type = TOML_ARRAY;
			ent->val.a.len = 0;
			p++; /* skip '[' */
			while (*p && *p != ']' && ent->val.a.len < TOML_MAX_ARR) {
				while (isspace((unsigned char)*p) || *p == ',') p++;
				if (*p == ']' || *p == '\0') break;
				if (*p == '"') {
					char *dst = ent->val.a.items[ent->val.a.len];
					p = unescape_into(p + 1, dst, TOML_MAX_STR);
					if (*p == '"') p++;
					ent->val.a.len++;
				} else {
					p++;
				}
			}
			if (*p == ']') p++;

		} else {
			/* integer or float */
			char nbuf[64];
			int ni = 0;
			while (*p && *p != ',' && *p != '}' && !isspace((unsigned char)*p) && ni < 63)
				nbuf[ni++] = *p++;
			nbuf[ni] = '\0';
			char *ep;
			long iv = strtol(nbuf, &ep, 10);
			if (ep != nbuf && *ep == '\0') {
				ent->val.type = TOML_INT;
				ent->val.i = iv;
			} else {
				double dv = strtod(nbuf, &ep);
				ent->val.type = TOML_FLOAT;
				ent->val.d = dv;
			}
		}
		doc->n++;

		/* advance past any trailing chars before next comma/brace */
		while (*p && *p != ',' && *p != '}') p++;
	}
	if (*p == '}') p++;
	return p;
}

int
toml_parse(const char *path, TomlDoc *doc)
{
	FILE *f = fopen(path, "r");
	if (!f) return 0;
	doc->n = 0;
	char line[4096];
	char cur_section[TOML_MAX_STR] = "";
	int  cur_tidx = -1;

	/* multi-line array-of-inline-tables state (compact format: key = [...]) */
	int  ml_active = 0;
	char ml_section[TOML_MAX_STR] = "";
	int  ml_tidx   = 0;

	while (fgets(line, sizeof(line), f)) {
		char *p = strtrim(line);

		/* ── multi-line array mode ── */
		if (ml_active) {
			if (!*p || *p == '#') continue;           /* blank / comment */
			if (p[0] == ']') { ml_active = 0; continue; }  /* end of array */
			/* parse every { ... } block on this line */
			const char *sp = p;
			while (*sp) {
				while (*sp && *sp != '{') sp++;
				if (!*sp) break;
				sp++; /* skip '{' */
				sp = parse_inline_table(sp, doc, ml_section, ml_tidx);
				ml_tidx++;
			}
			continue;
		}

		if (!*p || *p == '#') continue;

		/* [[array-of-tables]] */
		if (p[0] == '[' && p[1] == '[') {
			char *end = strstr(p + 2, "]]");
			if (!end) continue;
			int len = (int)(end - (p + 2));
			if (len >= TOML_MAX_STR) len = TOML_MAX_STR - 1;
			strncpy(cur_section, p + 2, len);
			cur_section[len] = '\0';
			cur_tidx = toml_table_count(doc, cur_section);
			continue;
		}

		/* [section] */
		if (p[0] == '[') {
			char *end = strchr(p + 1, ']');
			if (!end) continue;
			int len = (int)(end - (p + 1));
			if (len >= TOML_MAX_STR) len = TOML_MAX_STR - 1;
			strncpy(cur_section, p + 1, len);
			cur_section[len] = '\0';
			cur_tidx = -1;
			continue;
		}

		/* key = value */
		char *eq = strchr(p, '=');
		if (!eq) continue;

		/* extract key name into local buf first */
		int klen = (int)(eq - p);
		while (klen > 0 && isspace((unsigned char)p[klen - 1])) klen--;
		if (klen <= 0 || klen >= TOML_MAX_STR) continue;
		char key[TOML_MAX_STR];
		strncpy(key, p, (size_t)klen);
		key[klen] = '\0';

		char *v = strtrim(eq + 1);
		/* strip inline comment (outside strings) */
		{
			int in_str = 0;
			for (char *cp = v; *cp; cp++) {
				if (*cp == '"') in_str = !in_str;
				if (!in_str && *cp == '#') { *cp = '\0'; break; }
			}
			v = strtrim(v);
		}

		/* ── compact array-of-tables: key = [ or key = [{...},...] ── */
		if (*v == '[') {
			const char *after = v + 1;
			while (isspace((unsigned char)*after)) after++;

			if (*after == '\0') {
				/* multi-line array: opening '[' on its own */
				strncpy(ml_section, key, TOML_MAX_STR - 1);
				ml_section[TOML_MAX_STR - 1] = '\0';
				ml_tidx   = 0;
				ml_active = 1;
				continue;
			}

			if (*after == '{') {
				/* single-line array of inline tables: key = [{...}, ...] */
				const char *sp = v + 1;
				int tidx_local = 0;
				while (*sp && *sp != ']') {
					while (*sp && *sp != '{' && *sp != ']') sp++;
					if (*sp == '{') {
						sp++;
						sp = parse_inline_table(sp, doc, key, tidx_local++);
					}
				}
				continue;
			}
		}

		/* ── standard scalar / array value ── */
		if (doc->n >= TOML_MAX_ENTRIES) continue;
		TomlEntry *ent = &doc->entries[doc->n];
		strncpy(ent->section, cur_section, TOML_MAX_STR - 1);
		ent->section[TOML_MAX_STR - 1] = '\0';
		ent->table_idx = cur_tidx;
		strncpy(ent->key, key, TOML_MAX_STR - 1);
		ent->key[TOML_MAX_STR - 1] = '\0';

		if (*v == '"') {
			ent->val.type = TOML_STRING;
			const char *sp = unescape_into(v + 1, ent->val.s, TOML_MAX_STR);
			(void)sp;

		} else if (*v == '[') {
			ent->val.type = TOML_ARRAY;
			ent->val.a.len = 0;
			const char *vp = v + 1;
			while (*vp && *vp != ']' && ent->val.a.len < TOML_MAX_ARR) {
				while (isspace((unsigned char)*vp) || *vp == ',') vp++;
				if (*vp == ']' || *vp == '\0') break;
				if (*vp == '"') {
					char *dst = ent->val.a.items[ent->val.a.len];
					vp = unescape_into(vp + 1, dst, TOML_MAX_STR);
					if (*vp == '"') vp++;
					ent->val.a.len++;
				} else {
					vp++;
				}
			}

		} else {
			char *ep;
			long iv = strtol(v, &ep, 10);
			if (ep != v && (*ep == '\0' || *ep == '#' || isspace((unsigned char)*ep))) {
				ent->val.type = TOML_INT;
				ent->val.i = iv;
			} else {
				double dv = strtod(v, &ep);
				if (ep != v) {
					ent->val.type = TOML_FLOAT;
					ent->val.d = dv;
				} else {
					ent->val.type = TOML_STRING;
					strncpy(ent->val.s, v, TOML_MAX_STR - 1);
					ent->val.s[TOML_MAX_STR - 1] = '\0';
				}
			}
		}
		doc->n++;
	}
	fclose(f);
	return 1;
}

const TomlValue *
toml_get(const TomlDoc *doc, const char *section, const char *key)
{
	int i;
	for (i = 0; i < doc->n; i++) {
		const TomlEntry *e = &doc->entries[i];
		if (e->table_idx < 0
		    && strcmp(e->section, section) == 0
		    && strcmp(e->key, key) == 0)
			return &e->val;
	}
	return NULL;
}

const TomlValue *
toml_table_get(const TomlDoc *doc, const char *section, int idx, const char *key)
{
	int i;
	for (i = 0; i < doc->n; i++) {
		const TomlEntry *e = &doc->entries[i];
		if (e->table_idx == idx
		    && strcmp(e->section, section) == 0
		    && strcmp(e->key, key) == 0)
			return &e->val;
	}
	return NULL;
}
