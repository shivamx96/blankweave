#!/usr/bin/env bash
# Sourced by the privileged installer. Markers are per account and per default;
# the private user-state parent is shared with the migrations ledger.
installer_choices_init() {
    CHOICES_DIR=$USER_STATE_HOME/blankweave/defaults-seeded
    sudo -H -u "$SUDO_USER" mkdir -p "$USER_STATE_HOME/blankweave"
    local legacy=false
    [[ -d $CHOICES_DIR ]] || legacy=true
    mkdir -p "$CHOICES_DIR"
    chmod 0755 "$CHOICES_DIR"
    installer_choices_own
    if [[ $legacy == true && -s $USER_STATE_HOME/blankweave/installed-revision ]]; then
        # Baseline before packages change. An absent optional package can still
        # be selected for the first time during this apply or a later one.
        touch "$CHOICES_DIR/login-shell" "$CHOICES_DIR/tailscaled" "$CHOICES_DIR/ssh-agent"
        if pacman -Q docker >/dev/null 2>&1; then
            touch "$CHOICES_DIR/docker" "$CHOICES_DIR/docker-group"
        fi
        installer_choices_own
    fi
}

# The markers sit in the user's state tree, so the root apply hands the
# directory and its regular files back, including ones an earlier apply left
# root-owned. Links are never followed.
installer_choices_own() {
    local marker
    (( EUID == 0 )) && [[ -n ${SUDO_USER:-} ]] || return 0
    chown -h "$SUDO_USER:" "$CHOICES_DIR"
    for marker in "$CHOICES_DIR"/*; do
        if [[ -f $marker && ! -L $marker ]]; then
            chown -h "$SUDO_USER:" "$marker"
        fi
    done
}

installer_seed() {
    local item=$1
    shift
    [[ ! -e $CHOICES_DIR/$item ]] || return 0
    "$@" || return $?
    touch "$CHOICES_DIR/$item"
    chmod 0644 "$CHOICES_DIR/$item"
    installer_choices_own
}

installer_seed_service() {
    systemctl enable "$1" || return $?
    systemctl start "$1" || warn "Could not start $1."
}

installer_seed_ssh_agent() {
    [[ -r /usr/lib/systemd/user/gcr-ssh-agent.socket ]] || return 0
    sudo -H -u "$SUDO_USER" env XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RUNTIME_DIR/bus" \
        systemctl --user enable gcr-ssh-agent.socket
}
