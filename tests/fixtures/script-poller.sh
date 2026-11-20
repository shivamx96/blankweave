#!/usr/bin/env bash
set -eu
if shopt -q login_shell; then
    printf 'login shell used\n'
    exit 9
fi
case ${1:-} in
    good) printf '{"text":"42","tooltip":"Fixture"}\n' ;;
    noisy) printf 'harmless startup noise\n'; printf '{"text":"43","tooltip":"Noisy fixture"}\n'; printf 'stderr noise\n' >&2 ;;
    fail) printf '{"text":"wrong"}\n'; exit 7 ;;
    invalid) printf 'not json\n' ;;
    hang)
        # Both bash and its child ignore TERM. A surviving child would write this.
        trap '' TERM
        python3 -c 'import time,pathlib,os; time.sleep(1.5); pathlib.Path(os.environ["POLLER_TEST_DIR"], "survived").touch()' &
        wait
        ;;
    count)
        count=0
        [[ ! -f $POLLER_TEST_DIR/count ]] || read -r count < "$POLLER_TEST_DIR/count"
        count=$((count + 1))
        printf '%s\n' "$count" > "$POLLER_TEST_DIR/count"
        printf '{"text":"%s"}\n' "$count"
        ;;
esac
