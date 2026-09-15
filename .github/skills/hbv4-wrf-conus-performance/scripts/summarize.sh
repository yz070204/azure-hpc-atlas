#!/usr/bin/env bash
set -euo pipefail

run=${1:?usage: summarize.sh RUN_DIRECTORY}
log=
for candidate in "$run"/rsl.error.0000 "$run"/rsl.out.0000; do
  [[ -f "$candidate" ]] && log=$candidate && break
done
[[ -n "$log" ]] || { echo "rank-0 WRF log not found in $run" >&2; exit 2; }

grep 'Timing for main' "$log" | tail -149 | awk '
{
  value=$9
  sum+=value
  sumsq+=value*value
  count++
}
END {
  if (count != 149) {
    printf "expected 149 timing records, found %d\n", count > "/dev/stderr"
    exit 3
  }
  mean=sum/count
  sd=sqrt(sumsq/count-mean*mean)
  printf "records=%d\nmean_seconds=%.6f\nstep_sd_seconds=%.6f\n", count, mean, sd
}'

wall=$(
  grep 'Elapsed (wall clock)' "$run/launcher.log" 2>/dev/null |
    tail -1 |
    sed 's/.*): //'
)
[[ -n "$wall" ]] && printf 'wall_time=%s\n' "$wall"
grep -q 'SUCCESS COMPLETE WRF' "$log" &&
  printf 'wrf_status=SUCCESS\n' || printf 'wrf_status=NOT_CONFIRMED\n'
