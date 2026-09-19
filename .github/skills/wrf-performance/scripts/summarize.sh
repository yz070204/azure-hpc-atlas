#!/bin/bash
#
# Checks and summarizes a completed WRF CONUS run: all ranks finished,
# inputs unchanged, timing metric (mean of the last 149 rank-0
# "Timing for main" records), wall time, and a numerical comparison of the
# output against the dataset's reference. Writes benchmark-results.txt.
# Safe to rerun; it never reruns WRF.
#
# Usage: summarize.sh <run-dir>

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly RANKS=176
readonly TIMING_RECORDS=149
readonly OUTPUT="wrfout_d01_2019-11-27_00:00:00"

#######################################
# Prints an error to STDERR and exits.
# Arguments:
#   Message.
#######################################
die() {
  echo "SUMMARY FAILED: $*" >&2
  exit 1
}

#######################################
# Confirms every rank completed, nothing fatal was logged, and inputs are
# unchanged.
#######################################
check_completion() {
  local done_ranks
  done_ranks="$( { grep -l 'SUCCESS COMPLETE WRF' rsl.out.* 2>/dev/null || true; } | wc -l)"
  [[ "${done_ranks}" -eq "${RANKS}" ]] \
    || die "${done_ranks}/${RANKS} ranks reported SUCCESS COMPLETE WRF"
  ! grep -Eqi 'fatal|segmentation fault|mpi_abort' rsl.error.* \
    || die "fatal errors in rsl.error.*"
  sha256sum --quiet --check inputs.sha256 || die "benchmark inputs changed during the run"
}

#######################################
# Prints the timing metric from the rank-0 log and the wall time.
#######################################
timing() {
  grep 'Timing for main' rsl.error.0000 | tail -n "${TIMING_RECORDS}" \
    | awk -v want="${TIMING_RECORDS}" '
      $9 ~ /^[0-9.]+$/ {sum += $9; sumsq += $9 * $9; n++}
      END {
        if (n != want) {
          printf "expected %d numeric timing records, found %d\n", want, n > "/dev/stderr"
          exit 1
        }
        mean = sum / n
        printf "timing_records=%d\nmean_seconds=%.6f\nstep_sd_seconds=%.6f\n",
          n, mean, sqrt(sumsq / n - mean * mean)
      }' || die "timing records incomplete in rsl.error.0000"
  echo "wall_time=$(sed -n 's/.*Elapsed (wall clock).*: //p' launcher.log 2>/dev/null)"
}

#######################################
# Compares output with the dataset's reference; skipped if the Python
# NetCDF packages are missing.
#######################################
compare_output() {
  if ! python3 -c 'import numpy, netCDF4' 2>/dev/null; then
    echo "comparison_status=SKIPPED (python3 numpy/netCDF4 not installed)"
    return
  fi
  python3 "${SCRIPT_DIR}/compare-netcdf.py" "${OUTPUT}.orig" "${OUTPUT}" \
    > numerical-differences.csv || die "numerical comparison failed"
  # No acceptance tolerance is defined, so a human must review the differences.
  echo "comparison_status=REVIEW_REQUIRED (see numerical-differences.csv)"
}

main() {
  cd "${1:?usage: summarize.sh <run-dir>}"
  check_completion
  {
    echo "wrf_status=SUCCESS"
    timing
    compare_output
  } | tee benchmark-results.txt
}

main "$@"
