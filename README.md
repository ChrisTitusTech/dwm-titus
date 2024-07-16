dwm - dynamic window manager
============================
dwm is an extremely fast, small, and dynamic window manager for X.

This is my personal fork with following patches:

+ alwayscenter
+ alwaysfullscreen
+ auto start
+ cfacts
+ chatterino bottom
+ cool autostart
+ fakefullscreen client (with resize fix for chrome-based browsers + noborder fix)
+ multikeycode
+ movestack
+ noborder (floating + border flicker fix)
+ pertag
+ placemouse
+ resizepoint
+ statuscmd
+ swallow
+ switchtag
+ systray
+ true fullscreen
+ hide vacant tags
+ warp v2
+ winicon

Some patches are rewritten or modified to work together.


Requirements
------------
In order to build dwm you need the Xlib header files.

### Build Dependencies

- For Arch-Based Distros

```bash
sudo pacman -S --needed base-devel libx11 libxinerama libxft imlib2
```

- For Debian/Ubuntu-Based Distros

```bash
sudo apt install -y build-essential libx11-dev libxinerama-dev libxft-dev libimblib2-dev
```

Installation
------------
Edit config.mk to match your local setup (dwm is installed into
the /usr/local namespace by default).

Afterwards enter the following command to build and install dwm (if
necessary as root):

    make clean install


Running dwm
-----------
Add the following line to your .xinitrc to start dwm using startx:

    exec dwm

In order to connect dwm to a specific display, make sure that
the DISPLAY environment variable is set correctly, e.g.:

    DISPLAY=foo.bar:1 exec dwm

(This will start dwm on display :1 of the host foo.bar.)

In order to display status info in the bar, you can do something
like this in your .xinitrc:

    while xsetroot -name "`date` `uptime | sed 's/.*,//'`"
    do
    	sleep 1
    done &
    exec dwm


Configuration
-------------
The configuration of dwm is done by creating a custom config.h
and (re)compiling the source code.

>[!TIP]
> Create a convenient alias for recompiling dwm. This alias will clean up your build directory by removing unnecessary files if the build command succeeds
> ```bash
> alias smci="sudo make clean install && rm *.o && rm *.orig"
> ```

