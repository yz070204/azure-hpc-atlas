#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
[[ $# -ge 2 && $# -le 4 ]] ||
  die "Usage: bash run-stream.sh BINARY NEW_RUN_DIR [REPETITIONS=3] [RUNTIME_LIB_DIR]"
[[ ${STREAM_RUN_APPROVED:-no} == yes ]] ||
  die "Obtain license/run approval and an idle allocation, then set STREAM_RUN_APPROVED=yes."
binary=$(realpath -e "$1")
output=$(realpath -m "$2")
repetitions=${3:-3}
[[ -x $binary && ! -e $output ]] || die "Need an executable and a new run directory."
[[ $repetitions =~ ^([1-9]|10)$ ]] || die "REPETITIONS must be 1-10 within the approved budget."
profile=${STREAM_PROFILE:-source-original}
case "$profile" in
  normalized-176) threads=176; cpu_list=0-175 ;;
  source-original|prebuilt-original|tuned-144|prebuilt-144)
    threads=176
    cpu_list=0-175
    if [[ $profile == *-144 ]]; then
      threads=144
      cpu_list=
      for node in 0 1 2 3; do
        for offset in 0 8 16 24 32 38; do
          first=$((node * 44 + offset))
          cpu_list+="${cpu_list:+,}$first-$((first + 5))"
        done
      done
    fi
    [[ ${STREAM_THP_APPROVED:-no} == yes ]] ||
      die "$profile uses global THP always; obtain approval and set STREAM_THP_APPROVED=yes."
    if [[ $profile == prebuilt-* ]]; then
      [[ $# -lt 4 ]] || die "$profile must not inject a runtime library directory."
      [[ $(sha256sum "$binary" | cut -d ' ' -f 1) == \
         b6d034f991c560f3f1edfb4da23dd73d11e864878eb60956d2b46e412984f6c0 ]] ||
        die "Prebuilt executable differs from the validated AMD 2024_10_08 binary."
      expected_elements=650000000
      expected_ntimes=10
    else
      if [[ $profile == source-original ]]; then
        [[ ${STREAM_CACHE_DROP_APPROVED:-no} == yes ]] ||
          die "source-original drops host caches; obtain approval and set STREAM_CACHE_DROP_APPROVED=yes."
      fi
      [[ -n ${4:-} ]] || die "$profile requires the AOCC 4.0.0 runtime library directory."
      build_dir=$(dirname "$binary")
      [[ -f $build_dir/build-manifest.txt && -f $build_dir/compiler-version.txt &&
         -f $build_dir/stream.c ]] || die "$profile requires the original source build and manifests."
      grep -Fxq 'array_size=280000000' "$build_dir/build-manifest.txt" ||
        die "$profile requires 280000000 elements per array."
      grep -Fxq 'ntimes=100' "$build_dir/build-manifest.txt" ||
        die "$profile requires 100 iterations."
      grep -q 'AOCC_4.0.0-' "$build_dir/compiler-version.txt" ||
        die "$profile is validated with AOCC 4.0.0 only."
      grep -Fxq "$(sha256sum "$binary")" "$build_dir/build-manifest.txt" ||
        die "Executable does not match its build manifest."
      [[ $(sha256sum "$build_dir/stream.c" | cut -d ' ' -f 1) == \
         c388924eb140fda95f534cdb808ae7f1f8ebb18da41d8aec1b512a3c8d303c9b ]] ||
        die "Source differs from the pinned STREAM comparison."
      expected_elements=280000000
      expected_ntimes=100
    fi
    ;;
  *) die "Unknown STREAM_PROFILE: $profile (use source-original, prebuilt-original, tuned-144, prebuilt-144 or normalized-176)." ;;
esac
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
runtime=()
if [[ -n ${4:-} ]]; then
  lib_dir=$(realpath -e "$4")
  [[ -d $lib_dir ]] || die "Runtime library path is not a directory."
  runtime=("LD_LIBRARY_PATH=$lib_dir")
  if [[ $profile == source-original || $profile == tuned-144 ]]; then
    [[ -f $lib_dir/libomp.so ]] || die "Missing AOCC libomp.so."
    [[ $(sha256sum "$lib_dir/libomp.so" | cut -d ' ' -f 1) == \
       b62fd9fa42dc0d19131cf3368f914d77004cf7200aed710c91a3b97ba92ffef6 ]] ||
      die "OpenMP runtime differs from the validated AOCC 4.0.0 library."
  fi
fi
for tool in curl python3 numactl timeout vmstat lscpu sha256sum; do
  command -v "$tool" >/dev/null || die "Required tool missing: $tool"
done
sku=$(curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 -H Metadata:true \
  'http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text')
case "$sku" in
  Standard_HB176rs_v4|Standard_HB176s_v4) ;;
  *) die "This full-size HBv4 runner does not support SKU: $sku" ;;
esac
python3 - <<'PY'
import os
from pathlib import Path
import subprocess

if os.sched_getaffinity(0) != set(range(176)):
    raise SystemExit("ERROR: Require an allocation with all CPUs 0-175 available.")
if "avx512f" not in Path("/proc/cpuinfo").read_text():
    raise SystemExit("ERROR: AVX-512 support is required.")
available = int(next(line.split()[1] for line in Path("/proc/meminfo").read_text().splitlines()
                     if line.startswith("MemAvailable:")))
if available < 24 * 1024 * 1024:
    raise SystemExit("ERROR: Require at least 24 GiB available; also check cgroup memory limits.")
if os.environ.get("STREAM_PROFILE", "source-original") != "normalized-176":
    topology = subprocess.check_output(
        ["lscpu", "-e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE"], text=True,
        env={**os.environ, "LC_ALL": "C"}).splitlines()[1:]
    if len(topology) != 176:
        raise SystemExit("ERROR: Full-size topology signature mismatch.")
    seen = set()
    for row in topology:
        cpu, node, socket, core, cache, online = row.split()
        cpu, node, socket, core = map(int, (cpu, node, socket, core))
        expected_node = cpu // 44
        if cpu not in range(176) or expected_node not in range(4):
            raise SystemExit("ERROR: Unexpected CPU in topology.")
        private = cpu + (0, 4, 40, 44)[expected_node]
        l3 = (0, 6, 16, 22)[expected_node] + min((cpu % 44) // 8, 5)
        expected_cache = f"{private}:{private}:{private}:{l3}"
        if (node, socket, core, cache, online) != (
                expected_node, cpu // 88, cpu, expected_cache, "yes"):
            raise SystemExit(f"ERROR: CPU {cpu} topology differs from validated HBv4 mapping.")
        seen.add(cpu)
    if seen != set(range(176)):
        raise SystemExit("ERROR: Missing or duplicated topology CPUs.")
    policy = subprocess.check_output(["numactl", "--show"], text=True)
    if "policy: default" not in policy.splitlines():
        raise SystemExit("ERROR: Original and balanced profiles require inherited default NUMA policy.")
PY
mkdir "$output"
trap 'echo "ERROR: Run failed at line $LINENO; retain logs in $output." >&2' ERR
affinity=(OMP_PROC_BIND=true OMP_PLACES=cores)
omp_options=(OMP_SCHEDULE=static OMP_DYNAMIC=false OMP_THREAD_LIMIT=512 OMP_STACKSIZE=256M)
placement=(numactl --localalloc)
parse_options=(--expected-cpus "$cpu_list")
if [[ $profile != normalized-176 ]]; then
  affinity=("GOMP_CPU_AFFINITY=${cpu_list//,/ }")
  placement=()
  parse_options+=(--expected-array-elements "$expected_elements" --expected-ntimes "$expected_ntimes")
fi
if [[ $profile == prebuilt-original ]]; then
  affinity=(OMP_PROC_BIND=true OMP_PLACES=cores)
  omp_options=()
fi
launch=(
  env -i PATH=/usr/bin:/bin LANG=C "${runtime[@]}"
  "OMP_NUM_THREADS=$threads" "${affinity[@]}"
  "${omp_options[@]}"
  OMP_DISPLAY_ENV=VERBOSE OMP_DISPLAY_AFFINITY=true
  timeout --kill-after=5s 120s "${placement[@]}" "$binary"
)
{
  date -u '+timestamp=%FT%TZ'
  printf 'sku=%s\nrepetitions=%s\nprofile=%s\ncpu_list=%s\n' "$sku" "$repetitions" "$profile" "$cpu_list"
  printf 'command='; printf '%q ' "${launch[@]}"; printf '\n'
  sha256sum "$binary"
  uname -sr
  cat /etc/os-release
  LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE
  grep -E 'Cpus_allowed_list|Mems_allowed_list' /proc/self/status
  cat /proc/self/cgroup
  numactl --show
  printf '\nTHP enabled:\n'
  cat /sys/kernel/mm/transparent_hugepage/enabled
  printf '\nTHP defrag:\n'
  cat /sys/kernel/mm/transparent_hugepage/defrag
} > "$output/run-manifest.txt" 2>&1
if [[ -f $(dirname "$binary")/build-manifest.txt ]]; then
  cp "$(dirname "$binary")/build-manifest.txt" "$output/build-manifest.txt"
fi
env -i PATH=/usr/bin:/bin "${runtime[@]}" ldd "$binary" > "$output/libraries.txt"
if grep -q 'not found' "$output/libraries.txt"; then die "Unresolved runtime library."; fi
python3 - "$output/libraries.txt" > "$output/libraries.sha256" <<'PY'
import hashlib
from pathlib import Path
import re
import sys

for line in Path(sys.argv[1]).read_text().splitlines():
    match = re.fullmatch(r"\s*(?:\S+\s+=>\s+)?(/.*?)\s+\(0x[0-9a-fA-F]+\)\s*", line)
    if match:
        library = Path(match[1])
        print(hashlib.sha256(library.read_bytes()).hexdigest(), library)
PY
thp_dir=/sys/kernel/mm/transparent_hugepage
active_thp() { sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$1"; }
restore_thp() {
  status=$?
  trap - EXIT
  set +e
  failed=0
  printf '%s\n' "$old_enabled" | sudo -n tee "$thp_dir/enabled" > /dev/null || failed=1
  printf '%s\n' "$old_defrag" | sudo -n tee "$thp_dir/defrag" > /dev/null || failed=1
  [[ $(active_thp "$thp_dir/enabled") == "$old_enabled" &&
     $(active_thp "$thp_dir/defrag") == "$old_defrag" ]] || failed=1
  cat "$thp_dir/enabled" "$thp_dir/defrag" > "$output/thp-restored.txt" || failed=1
  if ((failed)); then
    echo "ERROR: THP restoration failed; restore values in $output/thp-original.txt." >&2
    exit 1
  fi
  exit "$status"
}
if [[ $profile != normalized-176 ]]; then
  command -v sudo >/dev/null || die "sudo is required for the approved THP profile."
  sudo -n true || die "Non-interactive privilege is required; no THP setting changed."
  old_enabled=$(active_thp "$thp_dir/enabled")
  old_defrag=$(active_thp "$thp_dir/defrag")
  [[ -n $old_enabled && -n $old_defrag ]] || die "Cannot determine THP values to restore."
  printf 'enabled=%s\ndefrag=%s\n' "$old_enabled" "$old_defrag" > "$output/thp-original.txt"
  trap restore_thp EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  printf 'always\n' | sudo -n tee "$thp_dir/enabled" > /dev/null
  printf 'always\n' | sudo -n tee "$thp_dir/defrag" > /dev/null
  [[ $(active_thp "$thp_dir/enabled") == always && $(active_thp "$thp_dir/defrag") == always ]] ||
    die "THP always did not take effect."
  cat "$thp_dir/enabled" "$thp_dir/defrag" > "$output/thp-active.txt"
fi
cd "$output"
for ((run=1; run<=repetitions; run++)); do
  vmstat 1 3 > "load-before-$run.txt"
  if [[ $profile == source-original ]]; then
    sync
    printf '3\n' | sudo -n tee /proc/sys/vm/drop_caches > "cache-drop-$run.txt"
  fi
  printf 'Running trial %s/%s (120-second limit)\n' "$run" "$repetitions"
  "${launch[@]}" > "stream-$run.log" 2>&1
  python3 "$script_dir/summarize.py" "${parse_options[@]}" "stream-$run.log" > "result-$run.json"
  vmstat 1 2 > "load-after-$run.txt"
done
python3 "$script_dir/summarize.py" "${parse_options[@]}" stream-*.log > summary.json
cat summary.json
