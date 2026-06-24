# dwm version
VERSION = 0.4

# Customize below to fit your system

# paths
PREFIX ?= /usr/local
MANPREFIX ?= ${PREFIX}/share/man
XSESSIONSDIR ?= /usr/share/xsessions
PKG_CONFIG ?= pkg-config

# Xinerama, comment if you don't want it
XINERAMALIBS  = -lXinerama
XINERAMAFLAGS = -DXINERAMA

# Portable X11 and library discovery
PKG_MODULES = x11 xft xinerama xrender imlib2 x11-xcb xcb xcb-res fontconfig freetype2
INCS = $(shell ${PKG_CONFIG} --cflags ${PKG_MODULES})
LIBS = $(shell ${PKG_CONFIG} --libs ${PKG_MODULES}) ${KVMLIB}

# Optional compiler optimisations may create smaller binaries and
# faster code, but increases compile time.
# See https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html
OPTIMISATIONS ?= -march=native -mtune=native -flto=auto -O3

# flags
CPPFLAGS += -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L -DVERSION=\"${VERSION}\" ${XINERAMAFLAGS} ${INCS}
CFLAGS ?= ${OPTIMISATIONS} -std=c99 -pedantic -Wall -Wno-unused-function -Wno-deprecated-declarations
LDLIBS += ${LIBS}

# Solaris
#CFLAGS = -fast ${INCS} -DVERSION=\"${VERSION}\"
#LDFLAGS = ${LIBS}

# compiler and linker
CC ?= cc
