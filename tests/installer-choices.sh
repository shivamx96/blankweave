#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
# Never invoke any privileged command: every system mutation is a stub.
source "$repository/scripts/installer-choices.sh"
sudo() { [[ $1 == -H && $2 == -u ]]; shift 3; [[ $1 == mkdir ]]; "$@"; }
pacman() { [[ ${docker_installed:-false} == true ]]; }
systemctl() { printf 'systemctl %s\n' "$*" >> "$test_root/calls"; }
usermod() { printf 'usermod %s\n' "$*" >> "$test_root/calls"; }
chsh() { printf 'chsh %s\n' "$*" >> "$test_root/calls"; }
# Marker ownership is handed back only when the apply runs as root (CI does).
chown() { printf '%s\n' "$*" >> "$test_root/marker-chowns"; }
warn() { printf '%s\n' "$*" >&2; }
SUDO_USER=fixture
apply_choices() {
    installer_choices_init
    installer_seed tailscaled installer_seed_service tailscaled.service
    if [[ ${development:-true} == true ]]; then
        installer_seed docker installer_seed_service docker.service
        installer_seed docker-group usermod -aG docker "$SUDO_USER"
    fi
    installer_seed login-shell chsh -s /usr/bin/zsh "$SUDO_USER"
}
USER_STATE_HOME=$test_root/fresh
apply_choices
[[ $(wc -l < "$test_root/calls") == 6 ]]
for item in tailscaled docker docker-group login-shell; do
    [[ -f $CHOICES_DIR/$item && $(stat -c %a "$CHOICES_DIR/$item") == 644 ]]
done
cp "$test_root/calls" "$test_root/first"
# A disabled unit/removed membership/changed shell must not be reset.
apply_choices
cmp "$test_root/first" "$test_root/calls"
USER_STATE_HOME=$test_root/upgrade
mkdir -p "$USER_STATE_HOME/blankweave"
printf 'old-revision\n' > "$USER_STATE_HOME/blankweave/installed-revision"
docker_installed=true
apply_choices
cmp "$test_root/first" "$test_root/calls"
# Existing installs without Docker can select development later.
USER_STATE_HOME=$test_root/new-profile
mkdir -p "$USER_STATE_HOME/blankweave"
printf 'old-revision\n' > "$USER_STATE_HOME/blankweave/installed-revision"
docker_installed=false development=false apply_choices
cmp "$test_root/first" "$test_root/calls"
development=true apply_choices
[[ $(tail -n 3 "$test_root/calls") == $'systemctl enable docker.service\nsystemctl start docker.service\nusermod -aG docker fixture' ]]
[[ $(wc -l < "$test_root/calls") == 9 ]]
# Failed choices must remain retryable even when the caller checks status.
if installer_seed failed-choice false; then exit 1; fi
[[ ! -e $CHOICES_DIR/failed-choice ]]
# Future defaults have independent markers, even on existing installs.
installer_seed future-default systemctl enable future.service
[[ -e $CHOICES_DIR/future-default ]]

if (( EUID == 0 )); then
    grep -Fxq -e "-h fixture: $CHOICES_DIR" "$test_root/marker-chowns"
    grep -Fxq -e "-h fixture: $CHOICES_DIR/future-default" "$test_root/marker-chowns"
    if grep -v -e '^-h fixture: ' "$test_root/marker-chowns"; then exit 1; fi
else
    [[ ! -e $test_root/marker-chowns ]]
fi
unset -f chown

# Exercise the installer's exact ownership block against a disposable tree.
mkdir -p "$test_root/bin"
export OWNERSHIP_LOG=$test_root/ownership
cat > "$test_root/bin/chown" <<'STUB'
#!/usr/bin/env bash
[[ $1 == -h && $2 == fixture:fixture ]] || exit 90
shift 2
printf '%s\n' "$@" >> "$OWNERSHIP_LOG"
STUB
chmod +x "$test_root/bin/chown"
export PATH="$test_root/bin:$PATH"
DOTS_DIR=$test_root/home/.local/share/blankweave
mkdir -p "$DOTS_DIR" "$test_root/unmanaged"
printf 'untouched\n' > "$test_root/unmanaged/file"
managed_trees=(hypr quickshell voxtype dunst thunar ghostty xdg-desktop-portal fontconfig spotify-launcher mangohud shell webapps plymouth themes)
for tree in "${managed_trees[@]}"; do
    mkdir -p "$DOTS_DIR/$tree"
    touch "$DOTS_DIR/$tree/file"
    printf '%s\n' "$DOTS_DIR/$tree" "$DOTS_DIR/$tree/file" >> "$test_root/expected"
done
ln -s "$test_root/unmanaged" "$DOTS_DIR/shell/foreign"
printf '%s\n' "$DOTS_DIR/shell/foreign" >> "$test_root/expected"
for name in VERSION MIN_ROLLBACK_VERSION hardware-overrides.json hardware-capabilities.json; do
    touch "$DOTS_DIR/$name"
    printf '%s\n' "$DOTS_DIR/$name" >> "$test_root/expected"
done
section() { :; }
# shellcheck disable=SC1090
source <(sed -n '/^section "FIXING OWNERSHIP"/,/^section "GENERATING USER CONFIGS"/p' "$repository/install.sh")
sort "$test_root/expected" > "$test_root/expected-sorted"
sort "$OWNERSHIP_LOG" > "$test_root/actual-sorted"
cmp "$test_root/expected-sorted" "$test_root/actual-sorted"
[[ $(cat "$test_root/unmanaged/file") == untouched ]]
if grep -q 'chown -R' "$repository/install.sh"; then exit 1; fi
printf 'Installer first-run choices and managed ownership tests passed.\n'
