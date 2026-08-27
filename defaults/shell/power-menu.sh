#!/usr/bin/env bash

choice=$(printf 'Lock\nSuspend\nShutdown\nReboot\nLogout' | fuzzel --dmenu --prompt 'Power  ')

case "$choice" in
    Lock)
        hyprlock
        ;;
    Suspend)
        systemctl suspend
        ;;
    Shutdown)
        systemctl poweroff
        ;;
    Reboot)
        systemctl reboot
        ;;
    Logout)
        uwsm stop
        ;;
esac
