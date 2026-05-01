#!/usr/bin/env bash

LED="/sys/class/leds/asus::kbd_backlight/brightness"

current=$(cat "$LED")

if [ "$current" -gt 0 ]; then
  echo $((current - 1)) | sudo tee "$LED" >/dev/null
fi
