/* Native selection owner used only by the observer regression fixture. */
#include <xcb/xcb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sys/wait.h>
#include <signal.h>
#include <sys/prctl.h>

static xcb_atom_t atom(xcb_connection_t *c, const char *name)
{
    xcb_intern_atom_reply_t *r = xcb_intern_atom_reply(c,
        xcb_intern_atom(c, 0, strlen(name), name), NULL);
    if (!r) exit(2);
    xcb_atom_t a = r->atom;
    free(r);
    return a;
}
int main(int argc, char **argv)
{
    if (argc == 6 && !strcmp(argv[1], "-e")) { argc--; argv++; }
    if (argc == 7 && !strcmp(argv[1], "--config")) { argc -= 2; argv += 2; }
    if (argc == 5 && !strcmp(strrchr(argv[1], '/') ? strrchr(argv[1], '/') + 1 : argv[1], "KeePass.exe")) { argc--; argv++; }
    if (argc == 5 && (!strcmp(argv[1], "/usr/bin/kpcli") || !strcmp(argv[1], "/usr/bin/pass"))) { argc--; argv++; }
    if (argc != 4) return 2;
    if (!strcmp(argv[1], "spawn")) {
        const char *child = getenv("CLIPBOARD_FIXTURE_CHILD");
        if (!child) return 2;
        pid_t pid = fork();
        if (pid < 0) return 2;
        if (!pid) {
            if (prctl(PR_SET_PDEATHSIG, SIGTERM)) return 2;
            execl(child, child, "plain", argv[2], argv[3], (char *)NULL);
            return 2;
        }
        /* Parent remains alive so XRes ancestry identifies the manager. */
        int status;
        waitpid(pid, &status, 0);
        return 0;
    }
    xcb_connection_t *c = xcb_connect(NULL, NULL);
    if (xcb_connection_has_error(c)) return 2;
    xcb_screen_t *s = xcb_setup_roots_iterator(xcb_get_setup(c)).data;
    xcb_window_t w = xcb_generate_id(c);
    xcb_create_window(c, XCB_COPY_FROM_PARENT, w, s->root, 0, 0, 1, 1, 0,
        XCB_WINDOW_CLASS_INPUT_OUTPUT, s->root_visual, 0, NULL);
    xcb_atom_t clip = atom(c, "CLIPBOARD"), targets = atom(c, "TARGETS");
    xcb_atom_t utf8 = atom(c, "UTF8_STRING"), hint = atom(c, "x-kde-passwordManagerHint");
    const char forged[] = "gedit\0Gedit\0";
    xcb_change_property(c, XCB_PROP_MODE_REPLACE, w, XCB_ATOM_WM_CLASS,
        XCB_ATOM_STRING, 8, sizeof(forged) - 1, forged);
    const char *claimed_pid = getenv("CLIPBOARD_FIXTURE_PID");
    unsigned int pid = claimed_pid ? (unsigned int)strtoul(claimed_pid, NULL, 10) : (unsigned int)getpid();
    xcb_change_property(c, XCB_PROP_MODE_REPLACE, w, atom(c, "_NET_WM_PID"),
        XCB_ATOM_CARDINAL, 32, 1, &pid);
    xcb_set_selection_owner(c, w, clip, XCB_CURRENT_TIME);
    xcb_flush(c);
    puts("ready"); fflush(stdout);
    int raced = 0;
    xcb_generic_event_t *event;
    while ((event = xcb_wait_for_event(c))) {
        if ((event->response_type & 127) == XCB_SELECTION_REQUEST) {
            xcb_selection_request_event_t *r = (void *)event;
            FILE *log = fopen(argv[3], "a");
            if (!log) return 2;
            fprintf(log, "%s\n", r->target == targets ? "TARGETS" : r->target == utf8 ? "TEXT" : "OTHER");
            fclose(log);
            xcb_atom_t property = r->property ? r->property : r->target;
            xcb_selection_notify_event_t reply = {0};
            reply.response_type = XCB_SELECTION_NOTIFY;
            reply.time = r->time; reply.requestor = r->requestor;
            reply.selection = r->selection; reply.target = r->target;
            reply.property = property;
            if (!strcmp(argv[1], "timeout")) { free(event); continue; }
            if (r->target == targets && !strcmp(argv[1], "many-targets")) {
                xcb_atom_t supported[129];
                for (unsigned int i = 0; i < 129; i++) supported[i] = utf8;
                xcb_change_property(c, XCB_PROP_MODE_REPLACE, r->requestor,
                    property, XCB_ATOM_ATOM, 32, 129, supported);
            } else if (r->target == targets) {
                xcb_atom_t supported[] = {targets, utf8, hint};
                xcb_change_property(c, XCB_PROP_MODE_REPLACE, r->requestor,
                    property, XCB_ATOM_ATOM, 32, (!strcmp(argv[1], "secret") || raced) ? 3 : 2, supported);
            } else if (r->target == utf8 && !strcmp(argv[1], "invalid-utf8")) {
                const unsigned char invalid[] = {0xc0, 0xaf};
                xcb_change_property(c, XCB_PROP_MODE_REPLACE, r->requestor,
                    property, utf8, 8, sizeof(invalid), invalid);
            } else if (r->target == utf8 && !strcmp(argv[1], "incr")) {
                unsigned int size = 1024 * 1024;
                xcb_change_property(c, XCB_PROP_MODE_REPLACE, r->requestor,
                    property, atom(c, "INCR"), 32, 1, &size);
            } else if (r->target == utf8 && !strcmp(argv[1], "oversize")) {
                char *large = malloc(65537);
                if (!large) return 2;
                memset(large, 'S', 65537);
                xcb_change_property(c, XCB_PROP_MODE_REPLACE, r->requestor,
                    property, utf8, 8, 65537, large);
                free(large);
            } else if (r->target == utf8) {
                if (!strcmp(argv[1], "race")) {
                    struct timespec delay = {0, 20000000};
                    nanosleep(&delay, NULL);
                    raced = 1;
                    xcb_set_selection_owner(c, w, clip, XCB_CURRENT_TIME);
                }
                xcb_change_property(c, XCB_PROP_MODE_REPLACE, r->requestor,
                    property, utf8, 8, strlen(argv[2]), argv[2]);
            } else if (r->target == hint && !strcmp(argv[1], "secret")) {
                xcb_change_property(c, XCB_PROP_MODE_REPLACE, r->requestor,
                    property, XCB_ATOM_STRING, 8, 6, "secret");
            } else reply.property = XCB_ATOM_NONE;
            xcb_send_event(c, 0, r->requestor, 0, (char *)&reply);
            xcb_flush(c);
        }
        free(event);
    }
    xcb_disconnect(c);
    return 0;
}
