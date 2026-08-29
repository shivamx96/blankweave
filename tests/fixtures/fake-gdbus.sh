#!/usr/bin/env bash
#
# Stand-in for gdbus. Logs every invocation to $FAKE_LOG like fake-log.sh and
# answers NameHasOwner with $FAKE_GDBUS_OWNED (default true) so a test can
# exercise both the "application is running" and "not running" branches.

set -euo pipefail

printf 'gdbus %s\n' "$*" >> "${FAKE_LOG:?FAKE_LOG must be set}"

case " $* " in
    *" org.freedesktop.DBus.NameHasOwner "*)
        printf '(%s,)\n' "${FAKE_GDBUS_OWNED:-true}"
        ;;
    *)
        printf '()\n'
        ;;
esac
