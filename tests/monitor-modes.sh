#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin"
export XDG_CONFIG_HOME=$test_root/config
export MODE_TEST_STATE=$test_root/monitors.json
export MODE_TEST_LOG=$test_root/commands
export PATH=$test_root/bin:$PATH
cat > "$MODE_TEST_STATE" <<'JSON'
[{"name":"DP-1","description":"Test monitor","width":3840,"height":2160,"refreshRate":60.0,"scale":1.5,"x":1920,"y":0,"availableModes":["3840x2160@60.00Hz","1920x1080@60.00Hz","1280x1024@60.00Hz","1920x1080@60.00Hz","bad"]}]
JSON
cat > "$test_root/bin/hyprctl" <<'PY'
#!/usr/bin/env python3
import json, os, re, sys
from pathlib import Path
state = Path(os.environ['MODE_TEST_STATE'])
if sys.argv[1] == 'monitors':
    print(state.read_text())
else:
    command = sys.argv[2]
    with open(os.environ['MODE_TEST_LOG'], 'a') as log:
        log.write(command + '\n')
    if 'mode = "1920' in command and os.environ.get('MODE_TEST_REJECT'):
        sys.exit(1)
    if 'mode = "1920' in command and os.environ.get('MODE_TEST_IGNORE'):
        sys.exit(0)
    mode = re.search(r'mode = "(\d+)x(\d+)@([\d.]+)"', command)
    if mode:
        rows = json.loads(state.read_text())
        if rows:
            rows[0].update(width=int(mode[1]),height=int(mode[2]),refreshRate=float(mode[3]))
            scale = re.search(r'scale = ([\d.]+)', command)
            if scale:
                rows[0]['scale'] = float(scale[1])
        stage = state.with_suffix('.tmp')
        stage.write_text(json.dumps(rows))
        stage.replace(state)
    print('ok')
PY
chmod +x "$test_root/bin/hyprctl"
script=$repository/defaults/shell/monitor-layout.sh
config=$XDG_CONFIG_HOME/blankweave/monitors.json
pending=$XDG_CONFIG_HOME/blankweave/.monitor-mode-preview.json
rules=$XDG_CONFIG_HOME/blankweave/monitors.lua
token() { jq -r .token "$pending"; }
width() { jq '.[0].width' "$MODE_TEST_STATE"; }

"$script" status | jq -e '.monitors[0].modeOptions == ["3840x2160@60.00","1920x1080@60.00","1280x1024@60.00"]' >/dev/null
if "$script" mode-preview DP-1 '1920x1080@75.00' 2>/dev/null; then exit 1; fi
if "$script" mode-preview DP-9 '1920x1080@60.00' 2>/dev/null; then exit 1; fi
[[ ! -e $config && ! -e $pending && ! -e $MODE_TEST_LOG ]]

# A preview changes the screen, locks other mutations, and never saves until kept.
"$script" mode-preview DP-1 1920x1080@60.00
[[ $(width) == 1920 && ! -e $config ]]
first_token=$(token)
"$script" status | jq -e '.preview.connector == "DP-1" and .preview.mode == "1920x1080@60.00"' >/dev/null
if "$script" set-scale DP-1 1 2>/dev/null; then exit 1; fi
if "$script" set DP-1 left 2>/dev/null; then exit 1; fi
if "$script" mode-preview DP-1 3840x2160@60.00 2>/dev/null; then exit 1; fi
if "$script" mode-confirm wrong-token 2>/dev/null; then exit 1; fi
"$script" mode-revert wrong-token
[[ $(width) == 1920 && -e $pending ]]
"$script" mode-revert "$first_token"
[[ $(width) == 3840 && ! -e $pending && ! -e $config ]]

# Confirmation persists by description; later scale/position edits retain mode.
"$script" mode-preview DP-1 1920x1080@60.00
"$script" mode-confirm "$(token)"
[[ ! -e $pending ]]
jq -e '.monitors[0].mode == "1920x1080@60.00"' "$config" >/dev/null
"$script" set-scale DP-1 1.5
"$script" set DP-1 left
"$script" set DP-1 auto
grep -Fq 'mode = "1920x1080@60.00"' "$rules"
grep -Fq 'mode = "1920x1080@60.00", position = "auto"' "$MODE_TEST_LOG"
saved=$(cat "$config")

# Incompatible scale falls back to 100% for the preview, then restores exactly.
"$script" mode-preview DP-1 1280x1024@60.00
jq -e '.[0].scale == 1' "$MODE_TEST_STATE" >/dev/null
"$script" mode-revert "$(token)"
[[ $(jq '.[0].scale' "$MODE_TEST_STATE") == 1.5 && $(cat "$config") == "$saved" ]]

# A failed revert retains its token and previous geometry for a retry.
"$script" mode-preview DP-1 3840x2160@60.00
if MODE_TEST_REJECT=1 "$script" mode-revert "$(token)" 2>/dev/null; then exit 1; fi
[[ -e $pending && $(cat "$config") == "$saved" ]]
"$script" mode-revert "$(token)"
[[ $(width) == 1920 && ! -e $pending ]]

# A stale watchdog cannot revert a later preview. Expired confirmation reverts.
"$script" mode-preview DP-1 3840x2160@60.00
"$script" mode-revert "$first_token"
[[ $(width) == 3840 && -e $pending ]]
jq '.deadline = 0' "$pending" > "$test_root/expired"
mv "$test_root/expired" "$pending"
if "$script" mode-confirm "$(token)" 2>/dev/null; then exit 1; fi
[[ $(width) == 1920 && ! -e $pending && $(cat "$config") == "$saved" ]]

# Exiting the caller requires no UI timer: the detached watchdog reverts.
"$script" mode-preview DP-1 3840x2160@60.00
for ((attempt=0; attempt<120; attempt++)); do
    [[ -e $pending ]] || break
    sleep 0.2
done
[[ $(width) == 1920 && ! -e $pending && $(cat "$config") == "$saved" ]]

# Rejected and silently ignored compositor requests both recover.
"$script" mode-preview DP-1 3840x2160@60.00
"$script" mode-confirm "$(token)"
saved=$(cat "$config")
if MODE_TEST_REJECT=1 "$script" mode-preview DP-1 1920x1080@60.00 2>/dev/null; then exit 1; fi
if MODE_TEST_IGNORE=1 "$script" mode-preview DP-1 1920x1080@60.00 2>/dev/null; then exit 1; fi
[[ $(width) == 3840 && ! -e $pending && $(cat "$config") == "$saved" ]]
# Hot-unplug during preview still restores the rule for the same description.
"$script" mode-preview DP-1 1920x1080@60.00
printf '[]' > "$MODE_TEST_STATE"
if "$script" mode-confirm "$(token)" 2>/dev/null; then exit 1; fi
"$script" mode-revert "$(token)"
[[ ! -e $pending && $(cat "$config") == "$saved" ]]
printf 'Display mode preview, confirmation, and watchdog tests passed.\n'
