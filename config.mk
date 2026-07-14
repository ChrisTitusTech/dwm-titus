# dwm-titus version
VERSION = 0.5.2

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

# Keep release artifacts portable by default. Developers can opt into
# host-specific tuning with `make native`.
OPTIMISATIONS ?= -O2
NATIVE_OPTIMISATIONS ?= -O3 -march=native -mtune=native -flto=auto

# flags
CPPFLAGS += -D_DEFAULT_SOURCE -D_BSD_SOURCE -D_XOPEN_SOURCE=700L -DVERSION=\"${VERSION}\" ${XINERAMAFLAGS} ${INCS}
CFLAGS ?= ${OPTIMISATIONS} -std=c99 -pedantic -Wall -Wno-deprecated-declarations
LDLIBS += ${LIBS}

# Solaris
#CFLAGS = -fast ${INCS} -DVERSION=\"${VERSION}\"
#LDFLAGS = ${LIBS}

# compiler and linker
CC ?= cc
