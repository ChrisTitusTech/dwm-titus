diff --git a/config.def.h b/config.def.h
index 1c0b587..ed056a4 100644
--- a/config.def.h
+++ b/config.def.h
@@ -18,6 +18,11 @@ static const char *colors[][3]      = {
 	[SchemeSel]  = { col_gray4, col_cyan,  col_cyan  },
 };
 
+static const char *const autostart[] = {
+	"st", NULL,
+	NULL /* terminate */
+};
+
 /* tagging */
 static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };
 
diff --git a/dwm.c b/dwm.c
index 9fd0286..1facd56 100644
--- a/dwm.c
+++ b/dwm.c
@@ -234,6 +234,7 @@ static int xerror(Display *dpy, XErrorEvent *ee);
 static int xerrordummy(Display *dpy, XErrorEvent *ee);
 static int xerrorstart(Display *dpy, XErrorEvent *ee);
 static void zoom(const Arg *arg);
+static void autostart_exec(void);
 
 /* variables */
 static const char broken[] = "broken";
@@ -275,6 +276,34 @@ static Window root, wmcheckwin;
 /* compile-time check if all tags fit into an unsigned int bit array. */
 struct NumTags { char limitexceeded[LENGTH(tags) > 31 ? -1 : 1]; };
 
+/* dwm will keep pid's of processes from autostart array and kill them at quit */
+static pid_t *autostart_pids;
+static size_t autostart_len;
+
+/* execute command from autostart array */
+static void
+autostart_exec() {
+	const char *const *p;
+	size_t i = 0;
+
+	/* count entries */
+	for (p = autostart; *p; autostart_len++, p++)
+		while (*++p);
+
+	autostart_pids = malloc(autostart_len * sizeof(pid_t));
+	for (p = autostart; *p; i++, p++) {
+		if ((autostart_pids[i] = fork()) == 0) {
+			setsid();
+			execvp(*p, (char *const *)p);
+			fprintf(stderr, "dwm: execvp %s\n", *p);
+			perror(" failed");
+			_exit(EXIT_FAILURE);
+		}
+		/* skip arguments */
+		while (*++p);
+	}
+}
+
 /* function implementations */
 void
 applyrules(Client *c)
@@ -1249,6 +1278,16 @@ propertynotify(XEvent *e)
 void
 quit(const Arg *arg)
 {
+	size_t i;
+
+	/* kill child processes */
+	for (i = 0; i < autostart_len; i++) {
+		if (0 < autostart_pids[i]) {
+			kill(autostart_pids[i], SIGTERM);
+			waitpid(autostart_pids[i], NULL, 0);
+		}
+	}
+
 	running = 0;
 }
 
@@ -1632,9 +1671,25 @@ showhide(Client *c)
 void
 sigchld(int unused)
 {
+	pid_t pid;
+
 	if (signal(SIGCHLD, sigchld) == SIG_ERR)
 		die("can't install SIGCHLD handler:");
-	while (0 < waitpid(-1, NULL, WNOHANG));
+	while (0 < (pid = waitpid(-1, NULL, WNOHANG))) {
+		pid_t *p, *lim;
+
+		if (!(p = autostart_pids))
+			continue;
+		lim = &p[autostart_len];
+
+		for (; p < lim; p++) {
+			if (*p == pid) {
+				*p = -1;
+				break;
+			}
+		}
+
+	}
 }
 
 void
@@ -2139,6 +2194,7 @@ main(int argc, char *argv[])
 	if (!(dpy = XOpenDisplay(NULL)))
 		die("dwm: cannot open display");
 	checkotherwm();
+	autostart_exec();
 	setup();
 #ifdef __OpenBSD__
 	if (pledge("stdio rpath proc exec", NULL) == -1)

