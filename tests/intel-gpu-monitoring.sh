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
fake_sys=$test_root/sys
device=$fake_sys/devices/pci0000:00/0000:00:02.0
card=$fake_sys/class/drm/card1
mkdir -p "$fake_bin" "$device" "$fake_sys/bus/pci/drivers/i915" "$card/gt/gt0"
ln -s "$device" "$card/device"
ln -s "$fake_sys/bus/pci/drivers/i915" "$device/driver"
printf '0x8086\n' > "$device/vendor"
printf '0\n' > "$card/gt/gt0/rps_act_freq_mhz"
printf '1700\n' > "$card/gt/gt0/rps_cur_freq_mhz"
printf '2350\n' > "$card/gt/gt0/rps_max_freq_mhz"

cat > "$fake_bin/lspci" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '0000:00:02.0 VGA compatible controller: Intel Corporation Meteor Lake-P [Intel Arc Graphics] (rev 08)'
EOF

cat > "$fake_bin/intel_gpu_top" <<'EOF'
#!/usr/bin/env bash
if [[ ${BLANKWEAVE_TEST_GPU_SAMPLE:-live} == empty ]]; then
    exit 1
fi
cat <<'JSON'
[
  {"engines":{"Render/3D/0":{"busy":1}}},
  {
    "frequency":{"actual":600},
    "power":{"GPU":4.25},
    "rc6":{"value":91.5},
    "engines":{
      "Render/3D/0":{"busy":42.5},
      "Video/0":{"busy":12.5},
      "Video/1":{"busy":20.0}
    },
    "clients":{
      "1":{"pid":"101","name":"one","memory":{"system":{"resident":"100"},"local":{"resident":"10"}},"engine-classes":{"Render/3D":{"busy":10}}},
      "2":{"pid":"102","name":"two","memory":{"system":{"resident":"200"},"local":{"resident":"20"}},"engine-classes":{"Render/3D":{"busy":20}}},
      "3":{"pid":"103","name":"three","memory":{"system":{"resident":"300"},"local":{"resident":"30"}},"engine-classes":{"Render/3D":{"busy":30}}},
      "4":{"pid":"104","name":"four","memory":{"system":{"resident":"400"},"local":{"resident":"40"}},"engine-classes":{"Render/3D":{"busy":40}}},
      "5":{"pid":"105","name":"five","memory":{"system":{"resident":"500"},"local":{"resident":"50"}},"engine-classes":{"Render/3D":{"busy":50}}},
      "6":{"pid":"106","name":"six","memory":{"system":{"resident":"600"},"local":{"resident":"60"}},"engine-classes":{"Render/3D":{"busy":60}}}
    }
  }
]
JSON
EOF
chmod +x "$fake_bin/lspci" "$fake_bin/intel_gpu_top"

run_gpu_usage() {
    PATH="$fake_bin:/usr/bin" \
        BLANKWEAVE_GPU_SYSFS_ROOT="$fake_sys" \
        BLANKWEAVE_TEST_GPU_SAMPLE="${BLANKWEAVE_TEST_GPU_SAMPLE:-live}" \
        "$repository/defaults/shell/gpu-usage.sh" "$1"
}

summary=$(run_gpu_usage summary)
jq -e '
    .available == true
    and .detailed == false
    and .backend == "intel"
    and .driver == "i915"
    and .accuracy == "live"
    and .usage == 42.5
    and .clockMHz == 600
    and .powerDrawWatts == 4.25
    and .idlePercent == 91.5
    and (.engines | length) == 2
' <<< "$summary" > /dev/null

detail=$(run_gpu_usage detail)
jq -e '
    .available == true
    and .detailed == true
    and .memoryUsedBytes == 2310
    and (.processes | length) == 5
    and .processes[0].pid == 106
    and .processes[0].usage == 60
' <<< "$detail" > /dev/null

fallback=$(BLANKWEAVE_TEST_GPU_SAMPLE=empty run_gpu_usage detail)
jq -e '
    .available == true
    and .detailed == true
    and .backend == "intel"
    and .accuracy == "unavailable"
    and .usage == null
    and .text == "—"
    and .clockMHz == 0
    and .memoryUsedBytes == 0
    and .processes == []
' <<< "$fallback" > /dev/null

cat > "$fake_bin/setcap" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$BLANKWEAVE_TEST_SETCAP_LOG"
EOF
cat > "$fake_bin/getcap" <<'EOF'
#!/usr/bin/env bash
printf '%s cap_perfmon=ep\n' "$1"
EOF
chmod +x "$fake_bin/setcap" "$fake_bin/getcap"

system_root=$test_root/root
BLANKWEAVE_SYSTEM_ROOT="$system_root" \
    BLANKWEAVE_INTEL_GPU_TOP="$fake_bin/intel_gpu_top" \
    BLANKWEAVE_SETCAP="$fake_bin/setcap" \
    BLANKWEAVE_GETCAP="$fake_bin/getcap" \
    BLANKWEAVE_TEST_SETCAP_LOG="$test_root/setcap.log" \
    "$repository/scripts/configure-intel-gpu-monitoring.sh" > /dev/null

grep -Fxq "cap_perfmon=ep $fake_bin/intel_gpu_top" "$test_root/setcap.log"
cmp "$repository/defaults/system/90-blankweave-intel-gpu-top.hook" \
    "$system_root/etc/pacman.d/hooks/90-blankweave-intel-gpu-top.hook"

printf 'Intel GPU monitoring tests passed.\n'
