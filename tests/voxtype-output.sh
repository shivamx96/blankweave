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
runtime=$test_root/runtime
state_home=$test_root/state
log=$test_root/voxtype.log
mkdir -p "$fake_bin" "$runtime/voxtype" "$state_home"

cat > "$fake_bin/voxtype" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$VOXTYPE_TEST_LOG"
EOF
chmod +x "$fake_bin/voxtype"

run_record() {
    PATH=$fake_bin:/usr/bin \
    XDG_RUNTIME_DIR=$runtime \
    VOXTYPE_TEST_LOG=$log \
    BLANKWEAVE_VOXTYPE_FOCUS=$1 \
        "$repository/defaults/shell/voxtype-record.sh" "$2"
}

printf 'idle\n' > "$runtime/voxtype/state"
run_record none start
grep -Fxq 'record start --clipboard' "$log"
[[ $(< "$runtime/blankweave/voxtype-output-mode") == clipboard ]]

transcript=$'Unicode stays intact: café, हिन्दी, 日本語.\nSecond line.'
processed=$(
    printf '%s' "$transcript" \
        | XDG_RUNTIME_DIR=$runtime XDG_STATE_HOME=$state_home \
            "$repository/defaults/shell/voxtype-post-process.sh"
    printf '\034'
)
processed=${processed%$'\034'}
[[ $processed == "$transcript" ]]
transcript_state=$state_home/blankweave/voxtype-last-transcript.json
[[ $(jq -r '.text' "$transcript_state") == "$transcript" ]]
[[ $(jq -r '.delivery' "$transcript_state") == clipboard ]]
[[ ! -e $runtime/blankweave/voxtype-output-mode ]]

run_record editable start
tail -n 1 "$log" | grep -Fxq 'record start'
printf 'typed normally' \
    | XDG_RUNTIME_DIR=$runtime XDG_STATE_HOME=$state_home \
        "$repository/defaults/shell/voxtype-post-process.sh" \
    | grep -Fxq 'typed normally'
[[ $(jq -r '.delivery' "$transcript_state") == type ]]

# Unknown accessibility is not proof that a target is absent. Preserve the
# user's clipboard and let normal typing proceed, while retaining the text.
run_record unknown start
tail -n 1 "$log" | grep -Fxq 'record start'
[[ $(< "$runtime/blankweave/voxtype-output-mode") == unverified ]]
printf 'recoverable unknown target' \
    | XDG_RUNTIME_DIR=$runtime XDG_STATE_HOME=$state_home \
        "$repository/defaults/shell/voxtype-post-process.sh" \
    | grep -Fxq 'recoverable unknown target'
[[ $(jq -r '.delivery' "$transcript_state") == unverified ]]

# Toggling an active recording stops it without re-evaluating its output mode.
printf 'recording\n' > "$runtime/voxtype/state"
run_record none toggle
tail -n 1 "$log" | grep -Fxq 'record toggle'

# A truly empty Hyprland focus result is a definite clipboard route and a
# terminal remains a valid typing target even when AT-SPI is unavailable.
if printf '{"address":"0x0","pid":0,"class":""}\n' \
    | "$repository/defaults/shell/voxtype-focus.py"; then
    printf 'No active window was reported as editable.\n' >&2
    exit 1
else
    [[ $? -eq 1 ]]
fi
printf '{"address":"0x123","pid":42,"class":"com.mitchellh.ghostty"}\n' \
    | "$repository/defaults/shell/voxtype-focus.py"

printf 'VoxType output routing tests passed.\n'
