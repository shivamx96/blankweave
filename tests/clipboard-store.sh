#!/usr/bin/env bash
set -euo pipefail
repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
export test_root
mkdir "$test_root/bin"
cat > "$test_root/bin/wl-paste" <<'STUB'
#!/usr/bin/env bash
if [[ $1 == --list-types ]]; then
    [[ ${query_failure:-0} == 0 ]] || exit 1
    printf '%s\n' "${types:-text/plain}"
else
    [[ ${hint_failure:-0} == 0 ]] || exit 1
    printf '%s' "${hint:-}"
fi
STUB
cat > "$test_root/bin/cliphist" <<'STUB'
#!/usr/bin/env bash
[[ $* == store ]] || exit 1
cat > "$test_root/stored"
STUB
chmod +x "$test_root/bin/"*
export PATH="$test_root/bin:$PATH"
python3 - "$test_root/input" <<'PY'
import sys
open(sys.argv[1], 'wb').write(bytes(range(256))*8)
PY
run() {
    rm -f "$test_root/stored"
    env "$@" bash "$repository/defaults/shell/clipboard-store.sh" < "$test_root/input"
}
run CLIPBOARD_STATE=data
cmp "$test_root/input" "$test_root/stored"
run CLIPBOARD_STATE=sensitive
[[ ! -e $test_root/stored ]]
run CLIPBOARD_STATE= types=x-kde-passwordManagerHint hint=secret
[[ ! -e $test_root/stored ]]
for args in 'query_failure=1' 'hint=public' 'hint_failure=1'; do
    run CLIPBOARD_STATE= types=x-kde-passwordManagerHint "$args"
    cmp "$test_root/input" "$test_root/stored"
done
printf 'Clipboard store tests passed.\n'
