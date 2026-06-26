.PHONY: install

LIGHTDM_DIR = /etc/lightdm
LIGHTDM_CONF = $(LIGHTDM_DIR)/lightdm.conf
PIXMAPS_DIR = /usr/share/pixmaps

install:
	if [ -f $(LIGHTDM_CONF) ] && ! cmp -s lightdm.conf $(LIGHTDM_CONF); then \
		cp -a $(LIGHTDM_CONF) $(LIGHTDM_CONF).dwm-titus.$$(date +%Y%m%d%H%M%S).bak; \
	fi
	install -Dm644 lightdm.conf                      $(LIGHTDM_CONF)
	install -Dm644 slick-greeter.conf                $(LIGHTDM_DIR)/slick-greeter.conf
	install -Dm644 wallpaper.jpg                     $(PIXMAPS_DIR)/dwm-titus.jpg
	install -Dm644 ../dwm-logo-bordered.png          $(PIXMAPS_DIR)/dwm-titus-logo.png
