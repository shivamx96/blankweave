#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
    if [[ -n $test_root && -d $test_root ]]; then
        rm -rf -- "$test_root"
    fi
}
trap cleanup EXIT HUP INT TERM

fake_bin=$test_root/bin
fake_home=$test_root/home
fake_data=$test_root/data
fake_config=$test_root/config
log=$test_root/calls.log
mkdir -p "$fake_bin" "$fake_home" "$fake_data" "$fake_config"

cat > "$fake_bin/voxtype" <<'EOF'
#!/usr/bin/env bash
printf 'voxtype\t%s\n' "$*" >> "$VOXTYPE_TEST_LOG"
EOF
cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl\t%s\n' "$*" >> "$VOXTYPE_TEST_LOG"
EOF
chmod +x "$fake_bin/voxtype" "$fake_bin/systemctl"

model_source=$test_root/model.bin
printf 'fixture whisper model\n' > "$model_source"
model_sha=$(sha256sum "$model_source" | cut -d' ' -f1)

run_setup() {
    HOME=$fake_home \
    XDG_DATA_HOME=$fake_data \
    XDG_CONFIG_HOME=$fake_config \
    PATH=$fake_bin:/usr/bin \
    VOXTYPE_TEST_LOG=$log \
    VOXTYPE_MODEL_URL=file://$model_source \
    VOXTYPE_MODEL_SHA256=$model_sha \
        "$repository/defaults/shell/voxtype-setup.sh" "$@"
}

run_setup enable
model=$fake_data/voxtype/models/ggml-small.en.bin
[[ -f $model ]]
[[ $(sha256sum "$model" | cut -d' ' -f1) == "$model_sha" ]]
grep -Fxq $'voxtype\tsetup quickshell --force --skip-bridge' "$log"
grep -Fxq $'systemctl\t--user enable --now voxtype.service' "$log"

# An already verified model makes setup replayable without another download.
rm "$model_source"
run_setup enable

run_setup disable
grep -Fxq $'systemctl\t--user disable --now voxtype.service' "$log"
[[ -f $model ]]

grep -Fq 'mode = "local"' "$repository/defaults/voxtype/config.toml.tmpl"
grep -Fq 'model = "small.en"' "$repository/defaults/voxtype/config.toml.tmpl"
grep -Fq 'enabled = false' "$repository/defaults/voxtype/config.toml.tmpl"
grep -Fq 'frontend = "quickshell"' "$repository/defaults/voxtype/config.toml.tmpl"
grep -Fq 'background = "{{colors.surfaceRaised:rgb}}"' "$repository/defaults/voxtype/config.toml.tmpl"

grep -Fq 'main_mod .. " + T"' "$repository/defaults/hypr/keybindings.lua"
grep -Fq '"SUPER + D"' "$repository/defaults/hypr/voxtype.lua"
grep -Fq 'property Voxtype voxtype: Voxtype' "$repository/defaults/quickshell/shell.qml"
grep -Fq 'VoxtypeWidget' "$repository/defaults/quickshell/Modules/ApplicationIndicatorsWidget.qml"
grep -Fq 'voxtype status --follow' "$repository/defaults/quickshell/Services/Voxtype.qml"
grep -Fq '["voxtype", "record", action]' "$repository/defaults/quickshell/Modules/VoxtypeWidget.qml"
grep -Fq 'installer_profile_enabled voice-dictation' "$repository/install.sh"

printf 'VoxType setup tests passed.\n'
