.PHONY: install

LIGHTDM_DIR = /etc/lightdm
PIXMAPS_DIR = /usr/share/pixmaps

install:
	install -Dm644 lightdm.conf                      $(LIGHTDM_DIR)/lightdm.conf
	install -Dm644 slick-greeter.conf                $(LIGHTDM_DIR)/slick-greeter.conf
	install -Dm644 wallpaper.jpg                     $(PIXMAPS_DIR)/dwm-dohc.jpg
	install -Dm644 ../dwm-logo-bordered.png          $(PIXMAPS_DIR)/dwm-dohc-logo.png
