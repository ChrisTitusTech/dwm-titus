#!/bin/bash
# Reads the current DWM layout from state file and outputs it for Polybar
STATE_FILE="/tmp/dwm-layout"

# Initialize state file if missing
[ -f "$STATE_FILE" ] || echo "[T]" > "$STATE_FILE"

cat "$STATE_FILE"
