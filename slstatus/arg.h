/* See LICENSE file for copyright and license details. */
#ifndef ARG_H
#define ARG_H

extern char *argv0;

/* int main(int argc, char *argv[]) */
#define ARGBEGIN for (argv0 = *argv, *argv ? (argc--, argv++) : ((void *)0);      \
                      *argv && (*argv)[0] == '-' && (*argv)[1]; argc--, argv++) { \
                 	int i_, argused_;                                         \
                 	if ((*argv)[1] == '-' && !(*argv)[2]) {                   \
                 		argc--, argv++;                                   \
                 		break;                                            \
                 	}                                                         \
                 	for (i_ = 1, argused_ = 0; (*argv)[i_]; i_++) {           \
				switch ((*argv)[i_])
#define ARGEND   		if (argused_) {                                   \
                 			if ((*argv)[i_ + 1]) {                    \
                 				break;                            \
                 			} else {                                  \
                 				argc--, argv++;                   \
                 				break;                            \
                 			}                                         \
                 		}                                                 \
                 	}                                                         \
                 }
#define ARGC()    ((*argv)[i_])
#define ARGF_(x) (((*argv)[i_ + 1]) ? (argused_ = 1, &((*argv)[i_ + 1])) :        \
                  (*(argv + 1))     ? (argused_ = 1, *(argv + 1))        : (x))
#define EARGF(x) ARGF_(((x), exit(1), (char *)0))
#define ARGF()   ARGF_((char *)0)

#endif
