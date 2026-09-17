#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lib/checks.sh"
source "$script_dir/lib/records.sh"
source "$script_dir/lib/thp.sh"

# 1. Settings and read-only checks.
binary=${1:-}
output=${2:-}
repetitions=${3:-3}
lib_dir=${4:-}
profile=${STREAM_PROFILE:-source-original}
check_run_request "$@"

binary=$(realpath -e "$binary")
output=$(realpath -m "$output")
runtime=()
if [[ -n $lib_dir ]]; then
  lib_dir=$(realpath -e "$lib_dir")
  runtime=("LD_LIBRARY_PATH=$lib_dir")
fi
check_run_binary
check_run_host

# 2. Keep 176 threads unless a balanced profile was explicitly selected.
threads=176
cpu_list=0-175
if [[ $profile == tuned-144 || $profile == prebuilt-144 ]]; then
  threads=144
  cpu_list=
  for node in 0 1 2 3; do
    for offset in 0 8 16 24 32 38; do
      first=$((node * 44 + offset))
      cpu_list+="${cpu_list:+,}$first-$((first + 5))"
    done
  done
fi
parse_options=(--expected-cpus "$cpu_list")
case "$profile" in
  source-original|tuned-144)
    parse_options+=(--expected-array-elements 280000000 --expected-ntimes 100) ;;
  prebuilt-original|prebuilt-144)
    parse_options+=(--expected-array-elements 650000000 --expected-ntimes 10) ;;
esac

# 3. Explicit launch recipes. Arrays above only handle optional paths and CPU lists.
run_stream() {
  case "$profile" in
    source-original|tuned-144|prebuilt-144)
      run_and_record "$output/run-manifest.txt" \
        env -i PATH=/usr/bin:/bin LANG=C "${runtime[@]}" \
        OMP_NUM_THREADS="$threads" GOMP_CPU_AFFINITY="${cpu_list//,/ }" \
        OMP_SCHEDULE=static OMP_DYNAMIC=false OMP_THREAD_LIMIT=512 OMP_STACKSIZE=256M \
        OMP_DISPLAY_ENV=VERBOSE OMP_DISPLAY_AFFINITY=true \
        timeout --kill-after=5s 120s "$binary"
      ;;
    prebuilt-original)
      run_and_record "$output/run-manifest.txt" \
        env -i PATH=/usr/bin:/bin LANG=C \
        OMP_NUM_THREADS=176 OMP_PROC_BIND=true OMP_PLACES=cores \
        OMP_DISPLAY_ENV=VERBOSE OMP_DISPLAY_AFFINITY=true \
        timeout --kill-after=5s 120s "$binary"
      ;;
    normalized-176)
      run_and_record "$output/run-manifest.txt" \
        env -i PATH=/usr/bin:/bin LANG=C "${runtime[@]}" \
        OMP_NUM_THREADS=176 OMP_PROC_BIND=true OMP_PLACES=cores \
        OMP_SCHEDULE=static OMP_DYNAMIC=false OMP_THREAD_LIMIT=512 OMP_STACKSIZE=256M \
        OMP_DISPLAY_ENV=VERBOSE OMP_DISPLAY_AFFINITY=true \
        timeout --kill-after=5s 120s numactl --localalloc "$binary"
      ;;
  esac
}

# 4. Save provenance and apply approved THP settings with automatic restoration.
mkdir "$output"
trap 'echo "ERROR: Run failed at line $LINENO; retain logs in $output." >&2' ERR
record_run_environment
if [[ $profile != normalized-176 ]]; then
  enable_thp
fi

# 5. Run the approved trials and validate each result before continuing.
cd "$output"
for ((run=1; run<=repetitions; run++)); do
  vmstat 1 3 > "load-before-$run.txt"
  if [[ $profile == source-original ]]; then
    sync
    printf '3\n' | sudo -n tee /proc/sys/vm/drop_caches > "cache-drop-$run.txt"
  fi
  printf 'Running trial %s/%s (120-second limit)\n' "$run" "$repetitions"
  run_stream > "stream-$run.log" 2>&1
  python3 "$script_dir/summarize.py" "${parse_options[@]}" "stream-$run.log" > "result-$run.json"
  vmstat 1 2 > "load-after-$run.txt"
done
python3 "$script_dir/summarize.py" "${parse_options[@]}" stream-*.log > summary.json
cat summary.json
