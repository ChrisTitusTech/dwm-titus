#!/bin/bash

MOUNT_POINT="$HOME/gdrive"
REMOTE="gdrive:"

if mountpoint -q "$MOUNT_POINT"; then
    fusermount -u "$MOUNT_POINT"
    notify-send -t 2000 "Rclone" "Google Drive unmounted"  
else
    mkdir -p "$MOUNT_POINT"
    
    rclone mount "$REMOTE" "$MOUNT_POINT" \
        --vfs-cache-mode full \
        --dir-cache-time 24h \
        --poll-interval 5m \
        --vfs-cache-max-age 24h \
        --daemon
        
    notify-send -t 2000 "Rclone" "Google Drive mounted"
fi