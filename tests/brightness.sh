#!/usr/bin/env bash
# All hardware commands are fixtures; no host backlights or I2C devices are used.
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/backlight/fake" "$test_root/runtime"
printf '60\n' > "$test_root/backlight/fake/brightness"
printf '60\n' > "$test_root/internal"
printf '40\n' > "$test_root/external"
export BRIGHTNESS_TEST_ROOT="$test_root"
export XDG_RUNTIME_DIR="$test_root/runtime"
export BLANKWEAVE_BACKLIGHT_ROOT="$test_root/backlight"
export PATH="$test_root/bin:$PATH"
cat > "$test_root/bin/brightnessctl" <<'EOF'
#!/bin/bash
case "$1" in
 get) cat "$BRIGHTNESS_TEST_ROOT/internal" ;;
 max) echo 100 ;;
 set) printf '%s\n' "${2%%%}" > "$BRIGHTNESS_TEST_ROOT/internal" ;;
 *) exit 1 ;;
esac
EOF
cat > "$test_root/bin/ddcutil" <<'EOF'
#!/bin/bash
case "$*" in
 'detect --brief') printf 'I2C bus: /dev/i2c-9999\nDRM connector: card0-DP-3\n' ;;
 *'getvcp 10 --brief') printf 'VCP 10 C %s 100\n' "$(cat "$BRIGHTNESS_TEST_ROOT/external")" ;;
 *'--noverify setvcp 10 '*) printf '%s\n' "${@: -1}" > "$BRIGHTNESS_TEST_ROOT/external" ;;
 *) exit 1 ;;
esac
EOF
cat > "$test_root/bin/notify-send" <<'EOF'
#!/bin/bash
echo 'unexpected notification' >> "$BRIGHTNESS_TEST_ROOT/notifications"
exit 1
EOF
chmod +x "$test_root/bin/"*
helper="$repository/defaults/shell/brightness.sh"
[[ $(bash "$helper" up 5 DP-3) == '' ]]
[[ $(cat "$test_root/external") == 45 && $(cat "$test_root/internal") == 60 ]]
[[ $(bash "$helper" down 5 eDP-1) == '' ]]
[[ $(cat "$test_root/internal") == 55 && $(cat "$test_root/external") == 45 ]]
bash "$helper" up 100 eDP-1
[[ $(cat "$test_root/internal") == 100 ]]
bash "$helper" down 100 DP-3
[[ $(cat "$test_root/external") == 5 ]]
[[ ! -e $test_root/notifications ]]
if grep -q 'notify-send' "$helper"; then exit 1; fi
printf 'Brightness silent connector fixtures passed.\n'
