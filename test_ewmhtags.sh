#!/bin/bash

# Test script to verify EWMH tags functionality
echo "Testing EWMH tags implementation..."

echo "=== _NET_NUMBER_OF_DESKTOPS ==="
xprop -root _NET_NUMBER_OF_DESKTOPS

echo "=== _NET_CURRENT_DESKTOP ==="
xprop -root _NET_CURRENT_DESKTOP

echo "=== _NET_DESKTOP_NAMES ==="
xprop -root _NET_DESKTOP_NAMES

echo "=== _NET_DESKTOP_VIEWPORT ==="
xprop -root _NET_DESKTOP_VIEWPORT

echo "=== _NET_SUPPORTED (relevant atoms) ==="
xprop -root _NET_SUPPORTED | grep -E "(DESKTOP|CURRENT)"
