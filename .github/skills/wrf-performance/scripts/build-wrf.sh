#!/bin/bash
#
# Builds WRF (em_real, GNU dmpar) with the pinned CONUS benchmark flags for
# Azure HBv4/HX VMs. Uses the already-selected GNU + Open MPI/HPC-X + NetCDF
# stack; never installs or downloads anything. Logs and build-manifest.txt
# land in the WRF source directory.
#
# Usage: build-wrf.sh <wrf-source-dir>
#   NPROCS: parallel compile jobs (default 8)

set -euo pipefail

# Pinned benchmark flags. Do not change them here; a different build is a
# different experiment and run-conus.sh will refuse it.
readonly FCFLAGS="-O3 -march=znver4 -Ofast -ftree-vectorize -funroll-loops"

# NetCDF versions of the original comparison stack. Other versions are
# allowed but recorded as a difference.
readonly BASELINE_NETCDF_C="4.7.4"
readonly BASELINE_NETCDF_F="4.5.3"

readonly NPROCS="${NPROCS:-8}"

#######################################
# Prints an error to STDERR and exits.
# Arguments:
#   Message.
#######################################
die() {
  echo "BUILD FAILED: $*" >&2
  exit 1
}

#######################################
# Checks the toolchain and source tree, then exports the NetCDF settings
# that WRF's configure reads.
#######################################
check_env() {
  local tool
  for tool in gcc gfortran mpicc mpif90 mpirun nc-config nf-config csh perl \
      make m4; do
    command -v "${tool}" >/dev/null || die "missing ${tool}; select the build stack first"
  done
  [[ "$(mpif90 --showme:command 2>/dev/null)" == gfortran ]] \
    || die "mpif90 must be Open MPI/HPC-X wrapping gfortran"
  [[ -x configure && -x compile ]] || die "not a WRF source directory: ${PWD}"
  [[ ! -e configure.wrf ]] \
    || die "source already configured; use a fresh checkout to rebuild"

  export NETCDF NETCDF_LDFLAGS
  NETCDF="$(nf-config --prefix)"
  NETCDF_LDFLAGS="$(nf-config --flibs)"   # handles multiarch lib dirs
  export NETCDF_classic=1 WRFIO_NCD_LARGE_FILE_SUPPORT=1
  [[ -f "${NETCDF}/include/netcdf.inc" ]] \
    || die "NetCDF-C and NetCDF-Fortran must share one prefix (${NETCDF})"

  local nc_version nf_version
  nc_version="$(nc-config --version | awk '{print $2}')"
  nf_version="$(nf-config --version | awk '{print $2}')"
  if [[ "${nc_version}" != "${BASELINE_NETCDF_C}" \
      || "${nf_version}" != "${BASELINE_NETCDF_F}" ]]; then
    echo "NOTE: NetCDF-C ${nc_version} / NetCDF-Fortran ${nf_version} differ" \
      "from baseline ${BASELINE_NETCDF_C} / ${BASELINE_NETCDF_F}; recorded in manifest."
  fi
}

#######################################
# Runs WRF configure with the GNU dmpar option and patches in the MPI
# wrappers and benchmark flags.
#######################################
configure_wrf() {
  # The menu numbering changes between WRF versions, so find the GNU dmpar
  # entry instead of hardcoding it.
  local choice
  choice="$(printf '%s\n' -1 | perl arch/Config.pl -os=Linux -mach=x86_64 2>&1 \
    | awk '/GNU \(gfortran\/gcc\)[[:space:]]*$/ {
        for (i = 2; i <= NF; i++) if ($i == "(dmpar)") {
          n = $(i - 1); sub(/\.$/, "", n); print n
        }
      }')"
  [[ "${choice}" =~ ^[0-9]+$ ]] || die "could not find the GNU dmpar configure option"

  echo "Configuring: GNU dmpar option ${choice}, basic nesting"
  printf '%s\n1\n' "${choice}" | ./configure > configure.log 2>&1 \
    || die "configure failed; see ${PWD}/configure.log"

  sed -i \
    -e 's|^DM_FC[[:space:]]*=.*|DM_FC = mpif90|' \
    -e 's|^DM_CC[[:space:]]*=.*|DM_CC = mpicc|' \
    -e "s|^FCOPTIM[[:space:]]*=.*|FCOPTIM = ${FCFLAGS}|" \
    configure.wrf
  grep -qx "FCOPTIM = ${FCFLAGS}" configure.wrf \
    || die "could not set FCOPTIM in configure.wrf"
}

#######################################
# Compiles em_real and confirms both executables exist.
#######################################
compile_wrf() {
  echo "Compiling with ${NPROCS} jobs; log: ${PWD}/compile.log"
  ./compile -j "${NPROCS}" em_real > compile.log 2>&1 || true   # WRF's exit code is unreliable
  local exe
  for exe in wrf real; do
    [[ -x "main/${exe}.exe" ]] || die "main/${exe}.exe not built; see ${PWD}/compile.log"
  done
}

#######################################
# Writes build-manifest.txt: source, flags, toolchain, and linkage.
# Fails if any runtime library is unresolved.
#######################################
write_manifest() {
  local tool
  {
    echo "source=${PWD}"
    echo "git_commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    grep -E '^(DM_FC|DM_CC|FCOPTIM)[[:space:]]*=' configure.wrf
    for tool in gcc gfortran mpirun nc-config nf-config; do
      echo "${tool}_version=$("${tool}" --version 2>&1 | head -1)"
    done
    echo "wrf_sha256=$(sha256sum main/wrf.exe | awk '{print $1}')"
    echo "linked_libraries_begin"
    ldd main/wrf.exe
    echo "linked_libraries_end"
  } > build-manifest.txt
  if grep -q 'not found' build-manifest.txt; then
    die "unresolved libraries in main/wrf.exe; see build-manifest.txt"
  fi
}

main() {
  local src="${1:?usage: build-wrf.sh <wrf-source-dir>}"
  cd "${src}"
  check_env
  configure_wrf
  compile_wrf
  write_manifest
  echo "BUILD PASS: ${PWD}/main/wrf.exe (manifest: ${PWD}/build-manifest.txt)"
}

main "$@"
