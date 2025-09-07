#!/bin/bash

echo "=== EWMH Desktop Properties ==="
echo "Number of desktops:"
xprop -root _NET_NUMBER_OF_DESKTOPS

echo -e "\nCurrent desktop:"
xprop -root _NET_CURRENT_DESKTOP

echo -e "\nDesktop names:"
xprop -root _NET_DESKTOP_NAMES

echo -e "\nDesktop viewport:"
xprop -root _NET_DESKTOP_VIEWPORT

echo -e "\nClient list:"
xprop -root _NET_CLIENT_LIST

echo -e "\nActive window:"
xprop -root _NET_ACTIVE_WINDOW
