#!/bin/bash
#
# Runs the STREAM memory-bandwidth benchmark on an Azure HBv4/HX VM with the
# per-SKU thread/affinity recipe, N times, then prints a median/range summary.
# Expects a prebuilt `stream` binary and AOCC's setenv script in <work-dir>,
# and summarize.py next to this script (see build-stream.sh).
#
# Usage: run-stream.sh <work-dir> <sku> [trials]
#   sku:    hbrs_v2 | hbrs_v3 | hbrs_v4 | hx_v4   (HX v4 == HBv4)
#   trials: number of runs to aggregate (default 3)

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

readonly THP_ENABLED="/sys/kernel/mm/transparent_hugepage/enabled"
readonly THP_DEFRAG="/sys/kernel/mm/transparent_hugepage/defrag"

# Current THP mode, captured before we touch it, so the trap can restore it.
readonly SAVED_THP="$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$THP_ENABLED")"

# Per-SKU thread count and CPU affinity (physical-core layout).
configure_sku() {
  case "$1" in
    hbrs_v2)
      export OMP_NUM_THREADS=32
      export GOMP_CPU_AFFINITY="0,1,4,8,12,16,20,24,28,32,36,40,44,48,52,56,60,61,64,68,72,76,80,84,88,92,96,100,104,108,112,116"
      ;;
    hbrs_v3)
      export OMP_NUM_THREADS=16
      export GOMP_CPU_AFFINITY="0,8,16,24,30,38,46,54,60,68,76,84,90,98,106,114"
      ;;
    hbrs_v4|hx_v4)   # HBv4 and HX share the same CPU/topology
      export OMP_NUM_THREADS=176
      export GOMP_CPU_AFFINITY="0-175"
      ;;
    *)
      echo "ERROR: unknown SKU '$1' (expected hbrs_v2|hbrs_v3|hbrs_v4|hx_v4)" >&2
      exit 1
      ;;
  esac
}

# OpenMP runtime settings shared across SKUs. OMP_DISPLAY_AFFINITY makes the
# runtime print each thread's binding; the format is pinned to exactly what
# summarize.py parses, so it doesn't depend on the runtime's default format.
configure_omp() {
  export OMP_SCHEDULE=static
  export OMP_DYNAMIC=false
  export OMP_THREAD_LIMIT=256
  export OMP_STACKSIZE=256M
  export OMP_DISPLAY_AFFINITY=true
  export OMP_AFFINITY_FORMAT="thread %n bound to OS proc set {%A}"
}

# THP is a *global* kernel setting, not per-shell - it stays changed after this
# script exits. Force it on (both knobs) for the run; the EXIT trap restores it.
enable_thp() {
  echo always | sudo tee "$THP_ENABLED" "$THP_DEFRAG" >/dev/null
}
restore_thp() {
  echo "${SAVED_THP:-madvise}" | sudo tee "$THP_ENABLED" "$THP_DEFRAG" >/dev/null
}

main() {
  local wdir=${1:?usage: run-stream.sh <work-dir> <sku> [trials]}
  local sku=${2:?missing SKU (hbrs_v2|hbrs_v3|hbrs_v4|hx_v4)}
  local trials=${3:-3}
  local host rundir i
  host="$(hostname | tr '[:upper:]' '[:lower:]')"

  cd "$wdir"
  rundir="stream-$host"
  mkdir "$rundir"
  cd "$rundir"
  cp ../stream .
  source ../setenv_AOCC.sh

  configure_sku "$sku"
  configure_omp

  trap restore_thp EXIT
  enable_thp

  # One log per trial; drop caches before each so no trial reads warm cache.
  # 2>&1: affinity lines go to stderr, results to stdout - summarize.py needs both.
  for ((i = 1; i <= trials; i++)); do
    echo "Trial $i/$trials..."
    sync; echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
    ./stream > "stream-$host-$i.log" 2>&1
  done

  echo
  echo "=== Summary across $trials trials (median / range) ==="
  python3 "$script_dir/summarize.py" "stream-$host-"*.log

  echo
  echo "Host state: THP set to 'always' for the run and restored to '${SAVED_THP:-madvise}'; page caches dropped before each trial."
  echo "Logs: $(realpath .)"
}

main "$@"
