#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${1:-} == --help || $# != 1 ]]; then
  echo "Usage: bash build-wrf.sh WRF_SOURCE"
  echo "Uses the selected GNU/Open MPI/NetCDF stack; does not install or download anything."
  echo "Settings: NPROCS=8 BUILD_TIMEOUT=3600 WRF_FCFLAGS=-O3"
  echo "Expected versions: WRF_NETCDF_C_VERSION=4.7.4 WRF_NETCDF_FORTRAN_VERSION=4.5.3"
  [[ ${1:-} == --help ]] && exit 0
  exit 2
fi

stage=preflight
logs="not created"
fail() { echo "BUILD FAILED [$stage]: $*. Logs: $logs" >&2; exit 1; }
trap 'fail "line $LINENO, exit $?"' ERR
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_dir=$(realpath "$1")
NPROCS=${NPROCS:-8}
BUILD_TIMEOUT=${BUILD_TIMEOUT:-3600}
WRF_FCFLAGS=${WRF_FCFLAGS:--O3}
WRF_NETCDF_C_VERSION=${WRF_NETCDF_C_VERSION:-4.7.4}
WRF_NETCDF_FORTRAN_VERSION=${WRF_NETCDF_FORTRAN_VERSION:-4.5.3}

check_libraries() {
  ldd "$1" > "$2"
  if grep -q 'not found' "$2"; then fail "Unresolved runtime libraries; inspect $2"; fi
}

env_prep() {
  [[ $NPROCS =~ ^[1-9][0-9]*$ && $BUILD_TIMEOUT =~ ^[1-9][0-9]*$ ]] ||
    fail "NPROCS and BUILD_TIMEOUT must be positive integers"
  [[ $WRF_FCFLAGS =~ ^[-a-zA-Z0-9_.,/+%:=@\ ]+$ ]] ||
    fail "Use simple compiler flags without shell/make expressions"
  [[ $(uname -sm) == "Linux x86_64" ]] || fail "This recipe requires Linux x86_64"
  [[ $source_dir != *[[:space:]]* ]] || fail "WRF source paths must not contain whitespace"
  cd "$source_dir"
  for tool in gcc gfortran mpicc mpif90 mpirun nc-config nf-config csh make m4 perl ldd git timeout flock; do
    command -v "$tool" >/dev/null || fail "Missing tool: $tool; select the build stack first"
  done
  [[ -x configure && -x compile && -f arch/Config.pl && -f arch/configure.defaults ]] ||
    fail "Not a supported WRF source directory"
  exec 9> .wrf-build.lock
  flock -n 9 || fail "Another build is using this source directory"
  [[ ! -e configure.wrf && ! -L configure.wrf &&
     ! -e main/wrf.exe && ! -L main/wrf.exe && ! -e main/real.exe && ! -L main/real.exe ]] ||
    fail "Source already configured/built; inspect existing results or use a fresh checkout"
  [[ -z $(find . -name '*.o' -print -quit) ]] || fail "Existing objects; use a fresh checkout"
  [[ $(mpif90 --showme:command) == gfortran && $(mpicc --showme:command) == gcc ]] ||
    fail "MPI wrappers must select gfortran/gcc without a wrapper chain"
  mpi_bin=$(dirname "$(realpath "$(command -v mpicc)")")
  for tool in mpif90 mpirun; do
    [[ $(dirname "$(realpath "$(command -v "$tool")")") == "$mpi_bin" ]] ||
      fail "MPI wrappers and launcher belong to different installations"
  done
  [[ $(mpirun --version) == *"Open MPI"* ]] || fail "Select Open MPI or HPC-X"
  nc_version=$(nc-config --version)
  nf_version=$(nf-config --version)
  [[ $nc_version == "netCDF $WRF_NETCDF_C_VERSION" ]] ||
    fail "Expected NetCDF-C $WRF_NETCDF_C_VERSION, found $nc_version; select it or document an approved exception"
  [[ $nf_version == "netCDF-Fortran $WRF_NETCDF_FORTRAN_VERSION" ]] ||
    fail "Expected NetCDF-Fortran $WRF_NETCDF_FORTRAN_VERSION, found $nf_version; select it or document an approved exception"
  prefix=$(nc-config --prefix)
  [[ -z ${NETCDF:-} || $NETCDF == "$prefix" ]] || fail "NETCDF disagrees with nc-config"
  [[ $(nf-config --prefix) == "$prefix" && -f "$prefix/include/netcdf.inc" ]] ||
    fail "Select NetCDF-C/Fortran under one prefix with include/netcdf.inc"
  [[ $prefix != *[[:space:]]* ]] || fail "NetCDF paths must not contain whitespace"
  [[ -z ${PNETCDF:-}${NETCDFPAR:-} ]] || fail "This recipe uses classic NetCDF, not parallel NetCDF"
  grep -q NETCDF_LDFLAGS arch/Config.pl || fail "WRF lacks the NETCDF_LDFLAGS interface"
  export NETCDF="$prefix" NETCDF_classic=1 WRFIO_NCD_LARGE_FILE_SUPPORT=1
  NETCDF_LDFLAGS=$(nf-config --flibs)
  export NETCDF_LDFLAGS
  logs=$(mktemp -d "$source_dir/build-logs.XXXXXX")
  echo "PREFLIGHT: logs in $logs"
  {
    gcc --version; gfortran --version; mpirun --version; nc-config --all; nf-config --all
    printf 'NPROCS=%s\nBUILD_TIMEOUT=%s\nWRF_FCFLAGS=%s\n' "$NPROCS" "$BUILD_TIMEOUT" "$WRF_FCFLAGS"
  } > "$logs/toolchain.txt" 2>&1
  read -r -a flags <<< "$WRF_FCFLAGS"
  read -r -a includes <<< "$(nf-config --fflags)"
  read -r -a libraries <<< "$NETCDF_LDFLAGS"
  cat > "$logs/probe.f90" <<'EOF'
program probe
  use mpi
  use netcdf
  logical initialized
  integer ierr
  call MPI_Initialized(initialized, ierr)
  print *, nf90_inq_libvers()
end program
EOF
  timeout --kill-after=10s 120s mpif90 "${flags[@]}" "${includes[@]}" \
    "$logs/probe.f90" "${libraries[@]}" -o "$logs/probe.exe" > "$logs/probe.log" 2>&1
  check_libraries "$logs/probe.exe" "$logs/probe-libraries.txt"
}

configure_wrf() {
  stage=configure
  printf '%s\n' -1 | timeout --kill-after=10s 30s perl arch/Config.pl \
    -os=Linux -mach=x86_64 > "$logs/menu.log" 2>&1
  choice=$(awk '/GNU \(gfortran\/gcc\)[[:space:]]*$/ {
    for (i=2; i<=NF; i++) if ($i=="(dmpar)") {n=$(i-1); sub(/\.$/, "", n); print n}
  }' "$logs/menu.log")
  [[ $choice =~ ^[0-9]+$ ]] || fail "Expected one GNU dmpar menu entry; inspect menu.log"
  echo "CONFIGURE: GNU dmpar option $choice, basic nesting 1"
  printf '%s\n1\n' "$choice" | timeout --kill-after=10s 120s \
    ./configure -os Linux -mach x86_64 > "$logs/configure.log" 2>&1
  cp configure.wrf "$logs/configure.original.wrf"
  awk -v flags="$WRF_FCFLAGS" '
    /^DM_FC[[:space:]]*=/ {print "DM_FC = mpif90"; fc++; next}
    /^DM_CC[[:space:]]*=/ {print "DM_CC = mpicc"; cc++; next}
    /^FCOPTIM[[:space:]]*=/ {print "FCOPTIM = " flags; opt++; next}
    {print}
    END {if (fc!=1 || cc!=1 || opt!=1) exit 1}
  ' configure.wrf > "$logs/configure.wrf"
  grep -Eq -- '-lnetcdff([[:space:]]|$)' "$logs/configure.wrf" ||
    fail "Generated configuration is missing NetCDF-Fortran linkage"
  grep -Eq -- '-lnetcdf([[:space:]]|$)' "$logs/configure.wrf" ||
    fail "Generated configuration is missing NetCDF-C linkage"
  cp "$logs/configure.wrf" configure.wrf
}

build_wrf() {
  stage=compile
  echo "BUILD: $NPROCS jobs; see $logs/compile.log"
  timeout --kill-after=10s "$BUILD_TIMEOUT" ./compile -j "$NPROCS" em_real \
    > "$logs/compile.log" 2>&1
  stage=validate
  for exe in wrf real; do
    [[ -x main/$exe.exe ]] || fail "Build did not produce main/$exe.exe; inspect compile.log"
    check_libraries "main/$exe.exe" "$logs/$exe-libraries.txt"
  done
  bash "$script_dir/build-manifest.sh" "$source_dir" > "$logs/build-manifest.txt"
  sha256sum main/wrf.exe main/real.exe > "$logs/outputs.sha256"
  echo "BUILD PASS: $source_dir/main/wrf.exe"
  echo "Evidence: $logs. No benchmark or scientific validation was run."
}

env_prep
configure_wrf
build_wrf
