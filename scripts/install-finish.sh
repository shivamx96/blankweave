#!/usr/bin/env bash
# Pure output, shared with isolated installer experience tests.
install_welcome() {
    printf '\nBlankweave is installed.\nRestart now: systemctl reboot\n'
    if [[ $1 == yes ]]; then
        printf 'Your disk passphrase is the login.\n'
    else
        printf 'You will sign in with your account password.\n'
    fi
    printf '\nSuper+Space   Launcher\nSuper+Return  Terminal\nSuper+,       Settings\nSuper+/       All shortcuts\nSuper+Escape  Power menu\n'
    printf '\nIf something looks wrong: blankweave doctor\n'
}

install_update_summary() {
    echo "Blankweave configuration applied. Restart your session to use it."
    if [[ $1 == true ]]; then
        echo "A hyprctl reload cannot switch an existing legacy .conf session to Lua."
    fi
}
