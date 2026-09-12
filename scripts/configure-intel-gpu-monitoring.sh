#!/usr/bin/env bash

set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
system_root=${BLANKWEAVE_SYSTEM_ROOT:-}
intel_gpu_top=${BLANKWEAVE_INTEL_GPU_TOP:-$system_root/usr/bin/intel_gpu_top}
setcap_command=${BLANKWEAVE_SETCAP:-setcap}
getcap_command=${BLANKWEAVE_GETCAP:-getcap}
hook_source=$repository/defaults/system/90-blankweave-intel-gpu-top.hook
hook_target=$system_root/etc/pacman.d/hooks/90-blankweave-intel-gpu-top.hook

if [[ ! -x $intel_gpu_top ]]; then
    printf 'Intel GPU monitoring: %s is not executable.\n' "$intel_gpu_top" >&2
    exit 1
fi

if ! command -v "$setcap_command" > /dev/null 2>&1 \
    || ! command -v "$getcap_command" > /dev/null 2>&1; then
    printf 'Intel GPU monitoring: setcap and getcap are required.\n' >&2
    exit 1
fi

"$setcap_command" cap_perfmon=ep "$intel_gpu_top"
capabilities=$("$getcap_command" "$intel_gpu_top" 2>/dev/null || true)
if [[ ! $capabilities =~ cap_perfmon[=+][a-z]*e[a-z]* ]]; then
    printf 'Intel GPU monitoring: CAP_PERFMON was not applied to %s.\n' "$intel_gpu_top" >&2
    exit 1
fi

# Package upgrades replace the executable and its extended attributes. The
# hook restores the narrowly scoped capability after intel-gpu-tools changes.
install -D -m 0644 "$hook_source" "$hook_target"

printf 'Intel GPU monitoring: live engine telemetry enabled.\n'
