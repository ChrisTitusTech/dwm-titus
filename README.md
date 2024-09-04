<div align="center">
  <img src="./dwm-logo-bordered.png" alt="dwm-logo-bordered" width="195" height="90"/>

  # dwm - dynamic window manager
  ### dwm is an extremely ***fast***, ***small***, and ***dynamic*** window manager for X.

</div>

---
This is my **Personal Fork** with following patches:

<details>
  <summary>Click to see the list of patches</summary>

  - alwayscenter
  - alwaysfullscreen
  - auto start
  - cfacts
  - chatterino bottom
  - cool autostart
  - fakefullscreen client (with resize fix for chrome-based browsers + noborder fix)
  - multikeycode
  - movestack
  - noborder (floating + border flicker fix)
  - pertag
  - placemouse
  - resizepoint
  - statuscmd
  - swallow
  - systray
  - true fullscreen
  - hide vacant tags
  - warp v2
  - winicon

  **Note**: Some patches are rewritten or modified to work together.
</details>

## 📋 Prerequisites
This guide assumes your system has the latest updates before going ahead with the installation.

> [!NOTE]
> You may want to keep the source directories of the tools you download in a suitable location for future reference as you may need to recompile them to apply configuration changes.

<details>
  <summary>Arch</summary>

  Install dependencies:

  ```sh
  sudo pacman -S --needed base-devel extra/git extra/libx11 extra/libxcb extra/libxinerama extra/libxft extra/imlib2
  ```

  If you find yourself missing a library then this can usually be found by searching for the file name using pacman:

  ```sh
  $ pacman -F Xlib-xcb.h
  extra/libx11 1.6.12-1 [installed: 1.7.2-1]
  usr/include/X11/Xlib-xcb.h
  ```

</details>

<details>
  <summary>Debian/Ubuntu</summary>

  Install dependencies:

  ```sh
  sudo apt install build-essential git libx11-dev libx11-xcb-dev libxcb-res0-dev libxinerama-dev libxft-dev libimlib2-dev
  ```

  It is worth checking the version of gcc on debian based systems as they may come with older implementations that can result in compilation errors.

  ```sh
  gcc --version
  ```

  You would expect at least v8.x or above here.

  If you find yourself missing a library then this can usually be found by searching for the file name using apt-file, a tool that have to be installed separately:

  ```sh
  $ sudo apt install apt-file
  $ sudo apt-file update
  $ apt-file search xcb/res.h
  libxcb-res0-dev: /usr/include/xcb/res.h
  ```

</details>


<details>
  <summary>Void Linux</summary>

  Install dependencies:

  ```sh
  sudo xbps-install -Su base-devel libX11-devel libXft-devel libXinerama-devel freetype-devel fontconfig-devel libxcb-devel imlib2-devel
  ```

  If you find yourself missing a library then this can usually be found by searching for the file name using xlocate, a tool that have to be installed separately via the xtools package:

  ```sh
  $ xlocate yajl/yajl_gen.h
  yajl-devel-2.1.0._4      /usr/include/yajl/yajl_gen.h
  ```

</details>

## 🛠️ Installation
Clone the repository, then compile and install.

```sh
git clone https://github.com/ChrisTitusTech/dwm-titus.git && \
cd dwm-titus && \
make  && \
sudo make install
```

- A dwm.desktop file will be placed in `/usr/share/xsessions/` so if you are using a login manager you should now be able to select dwm as the window manager when logging in.

- If you do not use a login manager then you already know what you are doing. Add `exec dwm` at the end of your `~/.xinitrc` file.

> [!TIP]
> - By default new terminals are opened by using the keyboard shortcut of <kbd>SUPER</kbd> + <kbd>X</kbd> while rofi is started using <kbd>SUPER</kbd>+<kbd>R</kbd>
> - Check `config.h` for the keybindings, and change them according to your preference.
