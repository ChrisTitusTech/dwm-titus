/* See LICENSE file for copyright and license details. */

/* appearance */
/* Set this to your monitor's refresh rate (e.g., 60, 120, 144, 165) */
static const unsigned int refresh_rate = 60;    /* matches dwm's mouse event processing to your monitor's refresh rate for smoother window interactions */
static const unsigned int enable_noborder = 1;  /* toggles noborder feature (0=disabled, 1=enabled) */
static const int cursorwarp         = 1;        /* 1 means warp cursor to center of focused window/monitor */
static const unsigned int snap      = 32;       /* snap pixel */
static const int swallowfloating    = 0;        /* 1 means swallow floating windows by default */
/* Window swallowing: when you launch a GUI app from a terminal, the terminal */
/* hides and the GUI app takes its place. Set isterminal=1 in rules[] for your terminal. */
static const int showbar            = 1;        /* 0 means no bar */
static const int topbar             = 1;        /* 0 means bottom bar */
#define ICONSIZE                      17        /* icon size */
#define ICONSPACING                   5         /* space between icon and title */
#define SHOWWINICON                   1         /* 0 means no winicon */
/* Fonts: Install ttf-meslo-nerd and noto-fonts-emoji from pacman */
static const char dmenufont[]       = "MesloLGS Nerd Font Mono:size=12";
/* Fonts for the bar */
static const char *fonts[]          = { "MesloLGS Nerd Font Mono:size=12:antialias=true:autohint=true", "NotoColorEmoji:pixelsize=14:antialias=true:autohint=true" };



/* tagging */
static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };

static const char ptagf[] = "[%s %s]";	/* format of a tag label */
static const char etagf[] = "[%s]";	/* format of an empty tag */
static const int lcaselbl = 0;		/* 1 means make tag label lowercase */	



/* layout(s) */
static const float mfact     = 0.55; /* factor of master area size [0.05..0.95] */
static const int nmaster     = 1;    /* number of clients in master area */
static const int resizehints = 1;    /* 1 means respect size hints in tiled resizals */
static const int lockfullscreen = 1; /* 1 will force focus on the fullscreen window */

static const Layout layouts[] = {
	/* symbol     arrange function */
	{ "[]=",      tile },    /* first entry is default */
	{ "><>",      NULL },    /* no layout function means floating behavior */
	{ "[M]",      monocle },
};

/* key definitions */
/* Mod4Mask = Super/Windows key (recommended), Mod1Mask = Alt key (suckless default) */
#define MODKEY Mod4Mask
#define STATUSBAR "dwmblocks"
