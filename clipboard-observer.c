/* Optional, unprivileged X11 history source. Never request text from an
 * unapproved owner. This is a retention policy, not an X11 security boundary. */
#include <xcb/xcb.h>
#include <xcb/xcbext.h>
#include <xcb/xfixes.h>
#include <xcb/res.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>

#define MAX_TEXT 65536U
#define MAX_TARGETS 128U
#define WAIT_MS 1000

/* Identifiable native password managers are excluded even without markers.
 * Browser and terminal owners remain eligible: unmarked extension/CLI secrets
 * cannot be distinguished from their ordinary copies. */
static const char *manager_names[] = {
    "bitwarden", "keepass", "1password", "proton-pass", "protonpass", "nordpass",
    "enpass", "dashlane", "lastpass", "keeperpasswordmanager", "keeper-desktop", NULL
};
static xcb_connection_t *connection;
static int fd, fixes_event, broken;
static xcb_window_t root, requestor;
static xcb_atom_t clipboard, targets, utf8, property, secret[5];
static uint64_t generation;
static int pending;
static xcb_xfixes_selection_notify_event_t latest;

static int eligible_path(const char *path)
{
    const char *base = strrchr(path, '/');
    char name[PATH_MAX];
    size_t i;
    base = base ? base + 1 : path;
    if (!*base || strlen(base) >= sizeof(name)) return 0;
    for (i = 0; base[i]; i++) name[i] = (char)tolower((unsigned char)base[i]);
    name[i] = 0;
    for (i = 0; manager_names[i]; i++)
        if (strstr(name, manager_names[i])) return 0;
    return strcmp(name, "bw") && strcmp(name, "bws") && strcmp(name, "rbw") &&
        strcmp(name, "pass") && strcmp(name, "gopass") && strcmp(name, "kpcli");
}

/* Inspect bounded launch metadata for interpreter-hosted apps such as
 * mono KeePass.exe and node /usr/bin/bw. Never print or retain arguments. */
static int eligible_command(uint32_t pid, const char *exe)
{
    char path[64], argument[PATH_MAX];
    FILE *file;
    size_t used = 0, total = 0, argument_index = 0;
    int ch, ok = 1, shell;
    const char *base = strrchr(exe, '/');
    base = base ? base + 1 : exe;
    shell = !strcmp(base, "bash") || !strcmp(base, "sh") ||
        !strcmp(base, "dash") || !strcmp(base, "zsh");
    /* Only interpreter launch arguments identify another application. Browser
     * flags, filenames and arbitrary text arguments are not application IDs. */
    if (strcmp(base, "mono") && strcmp(base, "mono-sgen") && strcmp(base, "node") &&
        strcmp(base, "nodejs") && strncmp(base, "python", 6) && strncmp(base, "perl", 4) && strcmp(base, "java") &&
        strcmp(base, "bash") && strcmp(base, "sh") && strcmp(base, "dash") && strcmp(base, "zsh")) return 1;
    snprintf(path, sizeof(path), "/proc/%u/cmdline", pid);
    file = fopen(path, "r");
    if (!file) return 0;
    while ((ch = fgetc(file)) != EOF) {
        if (++total > 16384 || used == sizeof(argument) - 1) { ok = 0; break; }
        if (!ch) {
            argument[used] = 0;
            /* Only executable-shaped arguments, never arbitrary shell text. */
            if (argument_index && (
                (shell && (!strcmp(argument, "--command") ||
                 (argument[0] == '-' && argument[1] != '-' && strchr(argument, 'c')))) ||
                (!strncmp(base, "python", 6) && !strcmp(argument, "-c")) ||
                ((!strcmp(base, "node") || !strcmp(base, "nodejs")) &&
                 (!strcmp(argument, "-e") || !strcmp(argument, "--eval") ||
                  !strcmp(argument, "-p") || !strcmp(argument, "--print"))) ||
                (!strncmp(base, "perl", 4) && (!strcmp(argument, "-e") || !strcmp(argument, "-E"))))) {
                /* Inline interpreter code has no reliable executable identity.
                 * Do not inspect it as a path or infer secrets from its text. */
                used = 0;
                break;
            }
            if (argument_index && argument[0] == '-') {
                /* Only known operand-free flags may precede the entrypoint.
                 * Otherwise an option operand could be mistaken for the app
                 * (e.g. mono --config file KeePass.exe). Fail closed rather
                 * than guess each interpreter's evolving option grammar. */
                int known = !strcmp(argument, "--") ||
                    (shell && argument[1] && argument[1] != '-' &&
                     strspn(argument + 1, "abefhiklmnprstuvxBCEHPT") == strlen(argument + 1)) ||
                    (!strncmp(base, "python", 6) && (!strcmp(argument, "-u") ||
                     !strcmp(argument, "-B") || !strcmp(argument, "-E") ||
                     !strcmp(argument, "-I") || !strcmp(argument, "-s") ||
                     !strcmp(argument, "-S") || !strcmp(argument, "-m"))) ||
                    (!strcmp(base, "java") && !strcmp(argument, "-jar")) ||
                    ((!strcmp(base, "mono") || !strcmp(base, "mono-sgen")) &&
                     !strcmp(argument, "--debug")) ||
                    (!strncmp(base, "perl", 4) && (!strcmp(argument, "-w") || !strcmp(argument, "-T")));
                if (!known) { ok = 0; used = 0; break; }
            }
            if (argument_index && used && argument[0] != '-') {
                /* Spaces are valid in a script/app pathname (notably Mono). */
                if (strcmp(argument, "/") && argument[used - 1] != '/' && !eligible_path(argument)) ok = 0;
                used = 0;
                break;
            }
            argument_index++;
            used = 0;
        } else argument[used++] = (char)ch;
    }
    if (ferror(file) || !total || used) ok = 0;
    fclose(file);
    { volatile char *wipe = argument; size_t n = sizeof(argument); while (n--) *wipe++ = 0; }
    return ok;
}

static int64_t now_ms(void)
{
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) return 0;
    return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static int wait_fd(int64_t deadline)
{
    int64_t left = deadline - now_ms();
    fd_set readfds;
    struct timeval timeout;
    if (left <= 0 || broken || xcb_connection_has_error(connection)) return 0;
    timeout.tv_sec = left / 1000;
    timeout.tv_usec = (left % 1000) * 1000;
    FD_ZERO(&readfds);
    FD_SET(fd, &readfds);
    return select(fd + 1, &readfds, NULL, NULL, &timeout) > 0;
}

/* Every selection ownership notification invalidates an in-flight read,
 * including a second copy made by the same application/window. */
static void notice(xcb_generic_event_t *event)
{
    if ((event->response_type & 127) == fixes_event && !(event->response_type & 128)) {
        xcb_xfixes_selection_notify_event_t *n = (void *)event;
        if (n->selection == clipboard) {
            latest = *n;
            generation++;
            pending = n->owner != XCB_NONE;
        }
    }
}

static void drain(void)
{
    xcb_generic_event_t *event;
    while ((event = xcb_poll_for_event(connection))) {
        notice(event);
        free(event);
    }
}

/* Unlike *_reply(), polling gives the server a bounded response deadline. */
static void *reply(unsigned sequence)
{
    int64_t deadline = now_ms() + WAIT_MS;
    void *answer = NULL;
    xcb_generic_error_t *error = NULL;
    xcb_flush(connection);
    for (;;) {
        if (xcb_poll_for_reply(connection, sequence, &answer, &error)) {
            if (error) { free(error); free(answer); return NULL; }
            return answer;
        }
        if (!wait_fd(deadline)) {
            xcb_discard_reply(connection, sequence);
            return NULL;
        }
    }
}

static xcb_atom_t atom(const char *name)
{
    xcb_intern_atom_reply_t *r = reply(xcb_intern_atom(connection, 0, strlen(name), name).sequence);
    xcb_atom_t result = r ? r->atom : 0;
    free(r);
    return result;
}

static xcb_window_t owner(void)
{
    xcb_get_selection_owner_reply_t *r = reply(xcb_get_selection_owner(connection, clipboard).sequence);
    xcb_window_t result = r ? r->owner : 0;
    free(r);
    return result;
}

struct identity { uint32_t pid, parent; unsigned long long start; dev_t dev; ino_t ino; char exe[PATH_MAX]; };

static int process_identity(uint32_t pid, struct identity *identity)
{
    char path[64], data[4096], *tail, *token, *save;
    struct stat proc, executable;
    FILE *file;
    ssize_t length;
    int field;
    snprintf(path, sizeof(path), "/proc/%u", pid);
    if (stat(path, &proc) || proc.st_uid != getuid()) return 0;
    snprintf(path, sizeof(path), "/proc/%u/exe", pid);
    length = readlink(path, identity->exe, sizeof(identity->exe) - 1);
    if (length <= 0 || (size_t)length >= sizeof(identity->exe) - 1) return 0;
    identity->exe[length] = 0;
    if (!eligible_path(identity->exe) || stat(path, &executable) || !S_ISREG(executable.st_mode)) return 0;
    if (!eligible_command(pid, identity->exe)) return 0;
    identity->pid = pid;
    identity->dev = executable.st_dev;
    identity->ino = executable.st_ino;
    snprintf(path, sizeof(path), "/proc/%u/stat", pid);
    file = fopen(path, "r");
    if (!file) return 0;
    length = fread(data, 1, sizeof(data) - 1, file);
    fclose(file);
    if (length <= 0 || (size_t)length == sizeof(data) - 1) return 0;
    data[length] = 0;
    tail = strrchr(data, ')');
    if (!tail || tail[1] != ' ') return 0;
    token = strtok_r(tail + 2, " ", &save);
    token = strtok_r(NULL, " ", &save);
    if (!token) return 0;
    identity->parent = (uint32_t)strtoul(token, NULL, 10);
    for (field = 4; token && field < 22; field++) token = strtok_r(NULL, " ", &save);
    if (!token) return 0;
    errno = 0;
    identity->start = strtoull(token, &tail, 10);
    return !errno && *tail == 0 && identity->start != 0;
}

static int eligible_ancestry(struct identity identity)
{
    unsigned depth;
    for (depth = 0; depth < 16 && identity.parent > 1; depth++) {
        char path[64];
        struct stat parent;
        uint32_t pid = identity.parent;
        snprintf(path, sizeof(path), "/proc/%u", pid);
        if (stat(path, &parent)) return 0;
        if (parent.st_uid != getuid()) return 1;
        if (pid == identity.pid || !process_identity(pid, &identity)) return 0;
    }
    return identity.parent <= 1;
}

static int owner_identity(xcb_window_t window, struct identity *identity)
{
    xcb_res_client_id_spec_t spec = {window, XCB_RES_CLIENT_ID_MASK_LOCAL_CLIENT_PID};
    xcb_res_query_client_ids_reply_t *r = reply(xcb_res_query_client_ids(connection, 1, &spec).sequence);
    uint32_t pid = 0;
    if (r && r->num_ids == 1 && r->length == 4) {
        xcb_res_client_id_value_t *value = (void *)(r + 1);
        if (value->spec.mask == XCB_RES_CLIENT_ID_MASK_LOCAL_CLIENT_PID && value->length == 4)
            memcpy(&pid, value + 1, sizeof(pid));
    }
    free(r);
    return pid && process_identity(pid, identity) && eligible_ancestry(*identity);
}

static int unchanged(xcb_window_t window, uint64_t serial, const struct identity *before)
{
    struct identity after;
    int same = owner() == window && owner_identity(window, &after) &&
        before->pid == after.pid && before->start == after.start &&
        before->dev == after.dev && before->ino == after.ino && !strcmp(before->exe, after.exe);
    drain();
    return same && serial == generation;
}

/* Each transaction gets a fresh requestor, so a delayed reply to an earlier
 * request can never be mistaken for a current clipboard value. */
static xcb_get_property_reply_t *selection(xcb_atom_t target, uint32_t timestamp, uint64_t serial)
{
    int64_t deadline = now_ms() + WAIT_MS;
    xcb_generic_event_t *event;
    xcb_convert_selection(connection, requestor, clipboard, target, property, timestamp);
    xcb_flush(connection);
    for (;;) {
        while ((event = xcb_poll_for_event(connection))) {
            int match = 0;
            notice(event);
            if ((event->response_type & 127) == XCB_SELECTION_NOTIFY) {
                xcb_selection_notify_event_t *n = (void *)event;
                match = n->requestor == requestor && n->selection == clipboard &&
                    n->target == target && n->time == timestamp;
                if (match && n->property != property) { free(event); return NULL; }
            }
            free(event);
            if (serial != generation) return NULL;
            if (match) {
                return reply(xcb_get_property(connection, 1, requestor, property,
                    XCB_GET_PROPERTY_TYPE_ANY, 0, target == targets ? MAX_TARGETS : MAX_TEXT / 4).sequence);
            }
        }
        if (!wait_fd(deadline)) return NULL;
    }
}

static int valid_utf8(const unsigned char *s, size_t n)
{
    size_t i = 0;
    while (i < n) {
        uint32_t v, minimum;
        unsigned count, j;
        unsigned char b = s[i++];
        if (b < 0x80) { if (!b) return 0; continue; }
        if (b >= 0xc2 && b <= 0xdf) { count = 1; v = b & 31; minimum = 0x80; }
        else if (b >= 0xe0 && b <= 0xef) { count = 2; v = b & 15; minimum = 0x800; }
        else if (b >= 0xf0 && b <= 0xf4) { count = 3; v = b & 7; minimum = 0x10000; }
        else return 0;
        if (n - i < count) return 0;
        for (j = 0; j < count; j++) {
            b = s[i++];
            if ((b & 0xc0) != 0x80) return 0;
            v = (v << 6) | (b & 63);
        }
        if (v < minimum || v > 0x10ffff || (v >= 0xd800 && v <= 0xdfff)) return 0;
    }
    return 1;
}

static void emit_text(const unsigned char *s, size_t n)
{
    size_t i;
    fputs("{\"event\":\"text\",\"text\":\"", stdout);
    for (i = 0; i < n; i++) {
        if (s[i] == '"' || s[i] == '\\') { putchar('\\'); putchar(s[i]); }
        else if (s[i] < 32) printf("\\u%04x", s[i]);
        else if (s[i] >= 128) {
            /* ASCII-only framing lets bounded frontend chunks be decoded
             * independently, without splitting a UTF-8 sequence. */
            uint32_t value;
            unsigned count, j;
            if (s[i] < 0xe0) { value = s[i] & 31; count = 1; }
            else if (s[i] < 0xf0) { value = s[i] & 15; count = 2; }
            else { value = s[i] & 7; count = 3; }
            for (j = 0; j < count; j++) value = (value << 6) | (s[++i] & 63);
            if (value <= 0xffff) printf("\\u%04x", value);
            else {
                value -= 0x10000;
                printf("\\u%04x\\u%04x", 0xd800 + (value >> 10), 0xdc00 + (value & 1023));
            }
        } else putchar(s[i]);
    }
    fputs("\"}\n", stdout);
    if (fflush(stdout)) broken = 1;
}

static void capture(xcb_xfixes_selection_notify_event_t event, uint64_t serial)
{
    struct identity identity;
    xcb_get_property_reply_t *r = NULL;
    uint32_t *offered;
    size_t i, j;
    int has_text = 0;
    if (!owner_identity(event.owner, &identity) || !unchanged(event.owner, serial, &identity)) return;
    requestor = xcb_generate_id(connection);
    xcb_create_window(connection, XCB_COPY_FROM_PARENT, requestor, root, 0, 0, 1, 1,
        0, XCB_WINDOW_CLASS_INPUT_ONLY, XCB_COPY_FROM_PARENT, 0, NULL);
    r = selection(targets, event.selection_timestamp, serial);
    if (!r || r->type != XCB_ATOM_ATOM || r->format != 32 || r->bytes_after ||
        r->value_len > MAX_TARGETS || !unchanged(event.owner, serial, &identity)) goto done;
    offered = xcb_get_property_value(r);
    for (i = 0; i < r->value_len; i++) {
        for (j = 0; j < sizeof(secret) / sizeof(secret[0]); j++)
            if (offered[i] == secret[j]) goto done;
        if (offered[i] == utf8) has_text = 1;
    }
    free(r); r = NULL;
    if (!has_text) goto done;
    r = selection(utf8, event.selection_timestamp, serial);
    /* INCR, oversized, invalid UTF-8, failed and partial replies are denied. */
    if (r && r->type == utf8 && r->format == 8 && !r->bytes_after && r->value_len <= MAX_TEXT &&
        valid_utf8(xcb_get_property_value(r), r->value_len) && unchanged(event.owner, serial, &identity))
        emit_text(xcb_get_property_value(r), r->value_len);
done:
    if (r) {
        volatile unsigned char *p = (void *)r;
        size_t bytes = 32 + (size_t)r->length * 4;
        while (bytes--) *p++ = 0;
        free(r);
    }
    xcb_destroy_window(connection, requestor);
    xcb_flush(connection);
}

static int initialize(void)
{
    const xcb_setup_t *setup;
    xcb_screen_iterator_t screens;
    xcb_query_extension_reply_t *extension;
    xcb_xfixes_query_version_reply_t *fixes;
    xcb_res_query_version_reply_t *res;
    xcb_window_t window;
    xcb_get_input_focus_reply_t *barrier;
    int screen_number, i, ok;
    const char *display = getenv("DISPLAY");
    const char *markers[] = {"x-kde-passwordManagerHint", "application/x-keepassxc",
        "application/x-nspasteboard-concealed-type", "ExcludeClipboardContentFromMonitorProcessing",
        "application/x-dwm-clipboard-private"};
    if (!display || display[0] != ':') return 0;
    connection = xcb_connect(NULL, &screen_number);
    if (!connection || xcb_connection_has_error(connection)) return 0;
    fd = xcb_get_file_descriptor(connection);
    if (fd < 0 || fd >= FD_SETSIZE) return 0;
    setup = xcb_get_setup(connection);
    screens = xcb_setup_roots_iterator(setup);
    for (i = 0; i < screen_number && screens.rem; i++) xcb_screen_next(&screens);
    if (!screens.rem) return 0;
    root = screens.data->root;
    extension = reply(xcb_query_extension(connection, 6, "XFIXES").sequence);
    if (!extension || !extension->present) { free(extension); return 0; }
    fixes_event = extension->first_event;
    free(extension);
    fixes = reply(xcb_xfixes_query_version(connection, 2, 0).sequence);
    ok = fixes && fixes->major_version >= 2;
    free(fixes);
    if (!ok) return 0;
    res = reply(xcb_res_query_version(connection, 1, 2).sequence);
    ok = res && (res->server_major > 1 || (res->server_major == 1 && res->server_minor >= 2));
    free(res);
    if (!ok) return 0;
    clipboard = atom("CLIPBOARD"); targets = atom("TARGETS"); utf8 = atom("UTF8_STRING");
    property = atom("_DWM_CLIPBOARD_READ");
    for (i = 0; i < 5; i++) if (!(secret[i] = atom(markers[i]))) return 0;
    if (!clipboard || !targets || !utf8 || !property) return 0;
    window = xcb_generate_id(connection);
    xcb_create_window(connection, XCB_COPY_FROM_PARENT, window, root, 0, 0, 1, 1,
        0, XCB_WINDOW_CLASS_INPUT_ONLY, XCB_COPY_FROM_PARENT, 0, NULL);
    xcb_xfixes_select_selection_input(connection, window, clipboard, 7);
    /* Synchronize subscription and discard only startup events. No fixed
     * timestamp cutoff survives initialization (X timestamps wrap). The focus
     * reply is only a server ordering barrier, never source attribution. */
    barrier = reply(xcb_get_input_focus(connection).sequence);
    if (!barrier) return 0;
    free(barrier);
    drain();
    pending = 0;
    return 1;
}

int main(int argc, char **argv)
{
    struct rlimit no_core = {0, 0};
    int result = 1;
    if (argc == 2 && !strcmp(argv[1], "--policy")) {
        puts("Sensitivity markers and identifiable password managers excluded; unmarked browser-extension and terminal secrets may be retained.");
        return 0;
    }
    if (argc != 1) { fputs("usage: dwm-clipboard-observer [--policy]\n", stderr); return 2; }
    if (setrlimit(RLIMIT_CORE, &no_core) || !initialize()) {
        fputs("Clipboard history unavailable: local X11 with XFixes and XRes 1.2 is required.\n", stderr);
        goto done;
    }
    puts("{\"event\":\"ready\",\"protocol\":1}"); fflush(stdout);
    while (!broken && !xcb_connection_has_error(connection)) {
        drain();
        if (pending) {
            xcb_xfixes_selection_notify_event_t event = latest;
            uint64_t serial = generation;
            pending = 0;
            capture(event, serial);
        } else {
            fd_set readfds;
            FD_ZERO(&readfds); FD_SET(fd, &readfds);
            if (select(fd + 1, &readfds, NULL, NULL, NULL) < 0 && errno != EINTR) break;
        }
    }
done:
    if (connection) xcb_disconnect(connection);
    return result;
}
