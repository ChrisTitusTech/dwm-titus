.PHONY: install print-config

LIGHTDM_DIR = $(DESTDIR)/etc/lightdm
LIGHTDM_CONF = $(LIGHTDM_DIR)/lightdm.conf
PIXMAPS_DIR = $(DESTDIR)/usr/share/pixmaps
LIGHTDM_SEAT_SECTION ?= SeatDefaults
LIGHTDM_GREETER_SESSION ?= lightdm-slick-greeter
LIGHTDM_USER_SESSION ?= dwm
LIGHTDM_SESSION_WRAPPER ?= /etc/lightdm/Xsession
LIGHTDM_LOGIND_CHECK ?= false

print-config:
	@if [ "$(LIGHTDM_LOGIND_CHECK)" = true ]; then \
		printf '%s\n' '[LightDM]'; \
		printf '%s\n' 'logind-check-graphical=true'; \
		printf '\n'; \
	fi; \
	printf '[%s]\n' "$(LIGHTDM_SEAT_SECTION)"; \
	printf 'greeter-session=%s\n' "$(LIGHTDM_GREETER_SESSION)"; \
	printf 'user-session=%s\n' "$(LIGHTDM_USER_SESSION)"; \
	if [ -n "$(LIGHTDM_SESSION_WRAPPER)" ]; then \
		printf 'session-wrapper=%s\n' "$(LIGHTDM_SESSION_WRAPPER)"; \
	fi

install:
	tmp=$$(mktemp); \
	trap 'rm -f "$$tmp"' EXIT; \
	$(MAKE) --no-print-directory print-config >"$$tmp"; \
	if [ -f $(LIGHTDM_CONF) ] && ! cmp -s "$$tmp" $(LIGHTDM_CONF); then \
		cp -a $(LIGHTDM_CONF) $(LIGHTDM_CONF).dwm-titus.$$(date +%Y%m%d%H%M%S).bak; \
	fi; \
	install -Dm644 "$$tmp"                           $(LIGHTDM_CONF)
	install -Dm644 slick-greeter.conf                $(LIGHTDM_DIR)/slick-greeter.conf
	install -Dm644 wallpaper.jpg                     $(PIXMAPS_DIR)/dwm-titus.jpg
	install -Dm644 ../dwm-titus.png                  $(PIXMAPS_DIR)/dwm-titus-logo.png
