#!/bin/bash

MOUNT_POINT="$HOME/gdrive"
REMOTE="gdrive:"

if mountpoint -q "$MOUNT_POINT"; then
    # Si c'est monté, on démonte
    fusermount -u "$MOUNT_POINT"
    notify-send -t 2000 "Rclone" "Drive déconnecté"  
else
    # Si c'est pas monté, on s'assure que le dossier existe
    mkdir -p "$MOUNT_POINT"
    
    # On monte avec les réglages basse conso
    rclone mount "$REMOTE" "$MOUNT_POINT" \
        --vfs-cache-mode full \
        --dir-cache-time 24h \
        --poll-interval 5m \
        --vfs-cache-max-age 24h \
        --daemon
        
    notify-send -t 2000 "Rclone" "Drive connecté"
fi