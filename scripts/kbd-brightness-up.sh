#!/usr/bin/env bash

LED="/sys/class/leds/asus::kbd_backlight/brightness"
MAX="/sys/class/leds/asus::kbd_backlight/max_brightness"

current=$(cat "$LED")
max=$(cat "$MAX")

if [ "$current" -lt "$max" ]; then
  echo $((current + 1)) | sudo tee "$LED" >/dev/null
fi
