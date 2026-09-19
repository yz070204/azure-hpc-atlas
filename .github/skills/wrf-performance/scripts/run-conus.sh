#!/bin/bash
#
# Runs the WRF v4.2 CONUS 2.5 km benchmark on one full-size HBv4/HX VM:
# 176 ranks pinned in order to CPUs 0-175, process grid 16x11. Checks the
# build and dataset first, prepares a new run directory, runs WRF, and calls
# summarize.sh. Never overwrites an existing run directory.
#
# Usage: run-conus.sh <wrf-source-dir> <dataset-archive> <new-run-dir>

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Pinned recipe (see references/wrf-reference-hbv4-hx.md).
readonly WRF_COMMIT="fb60d61cc44e2a2e8b8311f0b79185724010d510"
readonly FCFLAGS="-O3 -march=znver4 -Ofast -ftree-vectorize -funroll-loops"
readonly ARCHIVE_SHA256="dcae9965d1873c1c1e34e21ad653179783302b9a13528ac10fab092b998578f6"
readonly NAMELIST_SHA256="9ee91fe71336adb99b7a4da2dcb9af29b416c5fe69b3a4c2f74da7a82c9c50f4"
readonly RANKS=176
readonly MPI_ARGS=(-np "${RANKS}" --map-by core --bind-to core)

# The dataset ships the expected output; it is kept as the comparison reference.
readonly RESTART="wrfrst_d01_2019-11-26_23:00:00"
readonly OUTPUT="wrfout_d01_2019-11-27_00:00:00"

#######################################
# Prints an error to STDERR and exits.
# Arguments:
#   Message.
#######################################
die() {
  echo "RUN FAILED: $*" >&2
  exit 1
}

#######################################
# Confirms the build, dataset, and run directory match the recipe.
# Arguments:
#   WRF source dir, archive path, run dir.
#######################################
check_inputs() {
  local src="$1" archive="$2" run="$3"
  [[ -x "${src}/main/wrf.exe" ]] || die "no ${src}/main/wrf.exe; build first"
  [[ "$(git -C "${src}" rev-parse HEAD 2>/dev/null)" == "${WRF_COMMIT}" ]] \
    || die "WRF source is not the v4.2.2 recipe commit"
  grep -qx "FCOPTIM = ${FCFLAGS}" "${src}/configure.wrf" \
    || die "configure.wrf does not use the recipe flags"
  [[ -f "${archive}" ]] || die "dataset archive not found: ${archive}"
  [[ "$(sha256sum "${archive}" | awk '{print $1}')" == "${ARCHIVE_SHA256}" ]] \
    || die "archive checksum does not match the official v4.2 CONUS case"
  [[ ! -e "${run}" ]] || die "run directory already exists: ${run}"
  ! pgrep -x wrf.exe >/dev/null || die "another wrf.exe is already running"
}

#######################################
# Stops early if the run directory's filesystem can't hold the extracted
# case plus WRF's new output (about one more wrfout) with a 10% margin.
# Reads the archive listing once, which takes a minute or two.
# Arguments:
#   Archive path, run dir.
#######################################
check_space() {
  local archive="$1" run="$2" need avail
  echo "Checking free space for ${run}..."
  need="$(tar -tzvf "${archive}" | awk '
    {total += $3}
    $NF ~ /wrfout_/ {out += $3}
    END {printf "%.0f", (total + out) * 1.1}')"
  mkdir -p "$(dirname "${run}")"
  avail="$(df -B1 --output=avail "$(dirname "${run}")" | tail -1)"
  (( avail >= need )) || die "need $((need >> 30)) GiB free at $(dirname "${run}"), have $((avail >> 30)) GiB; choose a larger disk"
}

#######################################
# Extracts the case, adds the 16x11 grid, links the WRF runtime files, and
# records input hashes and provenance. Runs inside the new run directory.
# Arguments:
#   WRF source dir, archive path.
#######################################
prepare_run() {
  local src="$1" archive="$2" file
  tar -xzf "${archive}" --strip-components=1
  for file in namelist.input wrfbdy_d01 "${RESTART}" "${OUTPUT}"; do
    [[ -s "${file}" ]] || die "dataset is missing ${file}"
  done
  mv "${OUTPUT}" "${OUTPUT}.orig"

  sed -i '/num_metgrid_soil_levels[[:space:]]*=/a\
 nproc_x                             = 16,\
 nproc_y                             = 11,' namelist.input
  [[ "$(sha256sum namelist.input | awk '{print $1}')" == "${NAMELIST_SHA256}" ]] \
    || die "generated namelist differs from the recipe namelist"

  # Link WRF's runtime tables without overwriting dataset files.
  for file in "${src}"/run/*; do
    [[ -e "$(basename "${file}")" ]] || ln -s "${file}" .
  done
  ln -sf "${src}/main/wrf.exe" wrf.exe

  sha256sum namelist.input wrfbdy_d01 "${RESTART}" "${OUTPUT}.orig" > inputs.sha256
  cp "${src}/build-manifest.txt" . 2>/dev/null \
    || echo "NOTE: no build-manifest.txt in ${src}; provenance incomplete"
  {
    echo "archive=${archive}"
    echo "wrf_commit=${WRF_COMMIT}"
    echo "wrf_sha256=$(sha256sum "${src}/main/wrf.exe" | awk '{print $1}')"
    echo "launch=mpirun ${MPI_ARGS[*]} ./wrf.exe"
    echo "grid=16x11"
  } > run-manifest.txt
}

#######################################
# Verifies that MPI rank N is bound to CPU N for every rank.
#######################################
check_affinity() {
  OMP_NUM_THREADS=1 mpirun "${MPI_ARGS[@]}" sh -c \
    'echo "${OMPI_COMM_WORLD_RANK} $(taskset -pc $$ | awk "{print \$NF}")"' \
    | sort -n > affinity-preflight.txt
  awk -v n="${RANKS}" '$1 != $2 {bad++} END {exit (bad || NR != n)}' \
    affinity-preflight.txt \
    || die "ranks are not bound in order to CPUs 0-$((RANKS - 1)); see affinity-preflight.txt"
}

main() {
  local src archive run
  src="$(realpath "${1:?usage: run-conus.sh <wrf-source-dir> <archive> <new-run-dir>}")"
  archive="$(realpath "${2:?missing dataset archive}")"
  run="$(realpath -m "${3:?missing new run directory}")"

  check_inputs "${src}" "${archive}" "${run}"
  check_space "${archive}" "${run}"
  mkdir -p "${run}"
  cd "${run}"
  prepare_run "${src}" "${archive}"
  check_affinity

  echo "Running WRF on ${RANKS} ranks; log: ${run}/mpi.stdout"
  OMP_NUM_THREADS=1 /usr/bin/time -v -o launcher.log \
    mpirun "${MPI_ARGS[@]}" ./wrf.exe > mpi.stdout 2>&1 \
    || die "WRF exited with an error; see mpi.stdout and rsl.error.*"

  bash "${SCRIPT_DIR}/summarize.sh" "${run}"
}

main "$@"
