#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
run=${1:?usage: verify-conus-v42.sh RUN_DIRECTORY}
cd "$run"

[[ -f inputs.sha256 ]] || {
  echo "inputs.sha256 is missing; this run was not prepared by the reproducible harness" >&2
  exit 2
}
sha256sum --quiet --check inputs.sha256 || {
  echo "a benchmark input changed during the run" >&2
  exit 3
}

output=wrfout_d01_2019-11-27_00:00:00
reference="$output.orig"
[[ -s "$output" && -s "$reference" ]] || {
  echo "candidate or reference output is missing" >&2
  exit 4
}

success_ranks=$(
  { grep -l 'SUCCESS COMPLETE WRF' rsl.out.* 2>/dev/null || true; } | wc -l
)
[[ "$success_ranks" -eq 176 ]] || {
  echo "expected 176 successful rank logs, found $success_ranks" >&2
  exit 5
}
if grep -Eqi 'fatal|segmentation fault|mpi_abort' rsl.error.* 2>/dev/null; then
  echo "fatal text found in rank error logs" >&2
  exit 6
fi

"$script_dir/summarize.sh" . | tee benchmark-results.txt
python3 "$script_dir/compare-netcdf.py" "$reference" "$output" |
  tee numerical-differences.csv
printf 'comparison_status=REVIEW_REQUIRED\n' | tee -a benchmark-results.txt
printf 'candidate_output_sha256=%s\n' "$(sha256sum "$output" | awk '{print $1}')" |
  tee -a benchmark-results.txt
