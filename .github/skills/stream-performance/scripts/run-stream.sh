#!/bin/bash
# Usage: run-stream.sh <work-dir> <platform> [trials] [all-core|ccd-balanced|ccd-balanced-7]
# HBv5 is restricted to Standard_HB368rs_v5; balanced options select six or seven cores/CCD.

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly THP_ENABLED="/sys/kernel/mm/transparent_hugepage/enabled"
readonly THP_DEFRAG="/sys/kernel/mm/transparent_hugepage/defrag"
SAVED_THP_ENABLED=""
SAVED_THP_DEFRAG=""

configure_sku() {
  local platform=$1 placement=${2:-all-core} n offset c
  if [[ "$placement" != "all-core" && "$placement" != "ccd-balanced" && "$placement" != "ccd-balanced-7" ]]; then
    echo "ERROR: unknown placement '$placement' (expected all-core|ccd-balanced|ccd-balanced-7)" >&2
    return 1
  fi
  if [[ "$placement" != "all-core" && "$platform" != "hbv5" ]]; then
    echo "ERROR: $placement is currently defined only for full-size HBv5" >&2
    return 1
  fi
  case "$platform" in
    hbv2)
      export OMP_NUM_THREADS=32
      export GOMP_CPU_AFFINITY="0,1,4,8,12,16,20,24,28,32,36,40,44,48,52,56,60,61,64,68,72,76,80,84,88,92,96,100,104,108,112,116"
      ;;
    hbv3)
      export OMP_NUM_THREADS=16
      export GOMP_CPU_AFFINITY="0,8,16,24,30,38,46,54,60,68,76,84,90,98,106,114"
      ;;
    hbv4|hx)
      export OMP_NUM_THREADS=176
      export GOMP_CPU_AFFINITY="0-175"
      ;;
    hbv5)
      export OMP_NUM_THREADS=368
      export GOMP_CPU_AFFINITY="0-367"
      if [[ "$placement" != "all-core" ]]; then
        local cpus=() cores_per_ccd=6 first
        if [[ "$placement" == "ccd-balanced-7" ]]; then
          cores_per_ccd=7
        fi
        for ((n = 0; n < 16; n++)); do
          for offset in 0 8 16; do
            first=0
            # Match the supplied seven/CCD mask: omit the first core of each eight-core group.
            if [[ "$placement" == "ccd-balanced-7" && "$offset" != "16" ]]; then
              first=1
            fi
            for ((c = first; c < first + cores_per_ccd; c++)); do
              cpus+=("$((23 * n + offset + c))")
            done
          done
        done
        export OMP_NUM_THREADS=$((48 * cores_per_ccd))
        GOMP_CPU_AFFINITY=$(IFS=,; echo "${cpus[*]}")
      fi
      ;;
    *)
      echo "ERROR: unknown platform '$platform' (expected hbv2|hbv3|hbv4|hx|hbv5)" >&2
      return 1
      ;;
  esac
}

configure_omp() {
  unset OMP_PLACES OMP_PROC_BIND KMP_AFFINITY KMP_HW_SUBSET KMP_PLACE_THREADS KMP_STACKSIZE GOMP_STACKSIZE
  export OMP_SCHEDULE=static OMP_DYNAMIC=false
  export OMP_THREAD_LIMIT=$((OMP_NUM_THREADS > 256 ? OMP_NUM_THREADS : 256))
  export OMP_STACKSIZE=256M OMP_DISPLAY_AFFINITY=true
  export OMP_AFFINITY_FORMAT="thread %n bound to OS proc set {%A}"
}

verify_hbv5() {
  local sku
  sku=$(curl -fsS --max-time 10 --noproxy '*' -H Metadata:true \
    'http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text')
  if [[ "$sku" != "Standard_HB368rs_v5" ]]; then
    echo "ERROR: hbv5 requires Standard_HB368rs_v5, detected '$sku'" >&2
    return 1
  fi
  bash "$script_dir/../../../scripts/check-topology.sh" hbv5
}

restore_thp() {
  local status=$?
  if ! printf '%s\n' "$SAVED_THP_ENABLED" | sudo -n tee "$THP_ENABLED" >/dev/null; then
    echo "ERROR: failed to restore THP enabled='$SAVED_THP_ENABLED'" >&2
    status=1
  fi
  if ! printf '%s\n' "$SAVED_THP_DEFRAG" | sudo -n tee "$THP_DEFRAG" >/dev/null; then
    echo "ERROR: failed to restore THP defrag='$SAVED_THP_DEFRAG'" >&2
    status=1
  fi
  return "$status"
}

main() {
  local wdir=${1:?usage: run-stream.sh <work-dir> <platform> [trials] [placement]}
  local platform=${2:?missing platform (hbv2|hbv3|hbv4|hx|hbv5)}
  local trials=${3:-3} placement=${4:-all-core}
  local host rundir i artifact
  if (( $# > 4 )) || [[ ! "$trials" =~ ^[1-9][0-9]*$ ]] || (( ${#trials} > 4 )); then
    echo "ERROR: trials must be a positive integer of at most 4 digits; expected at most four arguments" >&2
    return 1
  fi
  configure_sku "$platform" "$placement"
  configure_omp
  if [[ "$platform" == "hbv5" ]]; then
    verify_hbv5
  fi
  wdir=$(realpath "$wdir")
  if [[ ! -x "$wdir/stream" || ! -f "$wdir/setenv_AOCC.sh" ]]; then
    echo "ERROR: missing STREAM binary or AOCC environment in '$wdir'; run build-stream.sh first" >&2
    return 1
  fi
  sudo -n true
  host=$(hostname | tr '[:upper:]' '[:lower:]')
  rundir=$(mktemp -d "$wdir/stream-$host-$platform-$placement-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
  cd "$rundir"
  echo "Run directory: $rundir"
  cp ../stream .
  for artifact in stream.c build.json build-command.txt compiler-version.txt; do
    if [[ -f "../$artifact" ]]; then
      cp "../$artifact" .
    else
      echo "WARNING: legacy build is missing provenance artifact '$artifact'" >&2
    fi
  done
  : "${LIBRARY_PATH:=}" "${LD_LIBRARY_PATH:=}" "${C_INCLUDE_PATH:=}" "${CPLUS_INCLUDE_PATH:=}"
  source ../setenv_AOCC.sh
  ldd ./stream > linkage.txt
  SAVED_THP_ENABLED=$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$THP_ENABLED")
  SAVED_THP_DEFRAG=$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$THP_DEFRAG")
  if [[ -z "$SAVED_THP_ENABLED" || -z "$SAVED_THP_DEFRAG" ]]; then
    echo "ERROR: could not read original THP modes" >&2
    return 1
  fi
  LC_ALL=C lscpu > lscpu.txt
  LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE > topology.txt
  grep -E 'MemTotal|MemAvailable|SwapTotal' /proc/meminfo > memory.txt
  python3 - "$platform" "$placement" "$trials" "$SAVED_THP_ENABLED" "$SAVED_THP_DEFRAG" <<'PYMETA'
import datetime, json, os, pathlib, platform, sys

metadata = {
    "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "platform": sys.argv[1], "placement": sys.argv[2], "trials": int(sys.argv[3]),
    "kernel": platform.release(),
    "numa_balancing": int(pathlib.Path("/proc/sys/kernel/numa_balancing").read_text()),
    "zone_reclaim_mode": int(pathlib.Path("/proc/sys/vm/zone_reclaim_mode").read_text()),
    "environment": {k: v for k, v in os.environ.items() if k.startswith(("OMP_", "GOMP_", "KMP_"))},
    "thp_during_run": {"enabled": "always", "defrag": "always"},
    "thp_original": {"enabled": sys.argv[4], "defrag": sys.argv[5]},
    "cache_handling": "sync and drop_caches=3 before each trial",
}
pathlib.Path("run.json").write_text(json.dumps(metadata, indent=2) + "\n")
PYMETA

  trap restore_thp EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  printf 'always\n' | sudo -n tee "$THP_ENABLED" "$THP_DEFRAG" >/dev/null
  for ((i = 1; i <= trials; i++)); do
    echo "Trial $i/$trials: platform=$platform placement=$placement threads=$OMP_NUM_THREADS stacksize=$OMP_STACKSIZE"
    vmstat 1 4 > "vmstat-before-$i.txt"
    if ! awk 'NR > 3 && (100 - $15) >= 5 {busy=1} END {exit busy}' "vmstat-before-$i.txt"; then
      echo "ERROR: CPU utilization is not below 5% in all three samples; defer STREAM. Evidence: $rundir/vmstat-before-$i.txt" >&2
      return 1
    fi
    sync
    printf '3\n' | sudo -n tee /proc/sys/vm/drop_caches >/dev/null
    if ./stream > "stream-$host-$i.log" 2>&1; then
      :
    else
      local status=$?
      echo "ERROR: STREAM trial $i exited $status; inspect $rundir/stream-$host-$i.log" >&2
      return "$status"
    fi
    python3 "$script_dir/summarize.py" --expected-threads "$OMP_NUM_THREADS" \
      --expected-cpus "$GOMP_CPU_AFFINITY" "stream-$host-$i.log" > "trial-$i.json"
  done

  python3 "$script_dir/summarize.py" --expected-threads "$OMP_NUM_THREADS" \
    --expected-cpus "$GOMP_CPU_AFFINITY" "stream-$host-"*.log > summary.json
  echo
  echo "=== Summary across $trials trials (median / range) ==="
  cat summary.json
  echo
  echo "Host state: THP set to 'always' for the run; restoring enabled='$SAVED_THP_ENABLED', defrag='$SAVED_THP_DEFRAG'; page caches dropped before each trial."
  echo "Logs: $rundir"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
