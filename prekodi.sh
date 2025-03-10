#!/bin/bash

bluetoothctl connect 41:42:87:71:B4:11 && pactl set-sink-volume @DEFAULT_SINK@ 40%
# pactl set-sink-volume @DEFAULT_SINK@ 40%
sleep 5 && wpctl set-volume @DEFAULT_SINK@ 40%

# Check if IPTV server is online (e.g., ping or check a specific port)
until  nc -z -v -w30 127.0.0.1 5001; do
    echo "Waiting for IPTV server to be ready..."
    sleep 5
done
# Once the server is ready, start Kodi
kioclient5 exec  /usr/share/applications/kodi.desktop

