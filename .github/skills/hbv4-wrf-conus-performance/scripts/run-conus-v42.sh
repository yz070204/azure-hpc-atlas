#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
wrf_source=${1:?usage: run-conus-v42.sh WRF_SOURCE ARCHIVE RUN_DIRECTORY}
archive=${2:?usage: run-conus-v42.sh WRF_SOURCE ARCHIVE RUN_DIRECTORY}
run=${3:?usage: run-conus-v42.sh WRF_SOURCE ARCHIVE RUN_DIRECTORY}
archive_sha256=dcae9965d1873c1c1e34e21ad653179783302b9a13528ac10fab092b998578f6
namelist_sha256=9ee91fe71336adb99b7a4da2dcb9af29b416c5fe69b3a4c2f74da7a82c9c50f4
wrf_commit=6233639c599119e76fca17dba9ea211af53a0ba9
wrf_source=$(realpath "$wrf_source")
archive=$(realpath "$archive")
run=$(realpath -m "$run")
exe="$wrf_source/main/wrf.exe"

[[ -x "$exe" ]] || { echo "WRF executable not found: $exe" >&2; exit 2; }
[[ -d "$wrf_source/run" ]] || { echo "WRF runtime directory not found" >&2; exit 2; }
[[ "$(git -C "$wrf_source" rev-parse HEAD 2>/dev/null)" == "$wrf_commit" ]] || {
  echo "WRF source is not the calibrated v4.4.2 commit" >&2
  exit 2
}
grep -Eq '^FCOPTIM[[:space:]]*=[[:space:]]*-O3 -march=znver4 -Ofast -ftree-vectorize -funroll-loops$' \
  "$wrf_source/configure.wrf" || {
  echo "configure.wrf does not contain the calibrated optimization flags" >&2
  exit 2
}
[[ -f "$archive" ]] || { echo "benchmark archive not found: $archive" >&2; exit 2; }
[[ "$(sha256sum "$archive" | awk '{print $1}')" == "$archive_sha256" ]] || {
  echo "archive checksum does not match the official v4.2 CONUS case" >&2
  exit 3
}
[[ ! -e "$run" ]] || {
  echo "refusing to overwrite existing run directory: $run" >&2
  exit 4
}

mkdir -p "$(dirname "$run")"
"$script_dir/inventory.sh" > "${run}.inventory.tmp"
active_wrf=$(awk -F= '$1 == "active_wrf" {print $2}' "${run}.inventory.tmp")
[[ "$active_wrf" == 0 ]] || {
  echo "another WRF process is active" >&2
  rm -f "${run}.inventory.tmp"
  exit 5
}

mkdir -p "$run"
mv "${run}.inventory.tmp" "$run/inventory.txt"
tar -xzf "$archive" -C "$run" --strip-components=1
cd "$run"

for file in namelist.input wrfbdy_d01 wrfrst_d01_2019-11-26_23:00:00 \
  wrfout_d01_2019-11-27_00:00:00; do
  [[ -s "$file" ]] || { echo "required archive member missing: $file" >&2; exit 6; }
done

require_setting() {
  local key=$1 expected=$2
  grep -Eq "^[[:space:]]*$key[[:space:]]*=[[:space:]]*$expected[[:space:]]*," namelist.input ||
    { echo "unexpected namelist setting: $key must be $expected" >&2; exit 7; }
}
require_setting run_hours 1
require_setting time_step 15
require_setting e_we 1501
require_setting e_sn 1201
require_setting e_vert 50
require_setting radt 3
require_setting restart '.true.'

mv wrfout_d01_2019-11-27_00:00:00 wrfout_d01_2019-11-27_00:00:00.orig
sed -i '/num_metgrid_soil_levels[[:space:]]*=/a\
 nproc_x                             = 16,\
 nproc_y                             = 11,' namelist.input
grep -Eq '^[[:space:]]*nproc_x[[:space:]]*=[[:space:]]*16,' namelist.input
grep -Eq '^[[:space:]]*nproc_y[[:space:]]*=[[:space:]]*11,' namelist.input
[[ "$(sha256sum namelist.input | awk '{print $1}')" == "$namelist_sha256" ]] || {
  echo "generated namelist differs from the canonical 16x11 benchmark namelist" >&2
  exit 7
}

cp -as --update=none "$wrf_source/run/." .
rm -f wrf.exe
ln -s "$(realpath "$exe")" wrf.exe
chmod a-w namelist.input wrfbdy_d01 wrfrst_d01_2019-11-26_23:00:00 \
  wrfout_d01_2019-11-27_00:00:00.orig
sha256sum namelist.input wrfbdy_d01 wrfrst_d01_2019-11-26_23:00:00 \
  wrfout_d01_2019-11-27_00:00:00.orig > inputs.sha256

"$script_dir/build-manifest.sh" "$wrf_source" "$exe" > build-manifest.txt
{
  printf 'archive=%s\narchive_sha256=%s\n' "$(realpath "$archive")" "$archive_sha256"
  printf 'namelist_sha256=%s\n' "$namelist_sha256"
  printf 'wrf_commit=%s\n' "$wrf_commit"
  printf 'ranks=176\nnproc_x=16\nnproc_y=11\n'
  printf 'launcher=mpirun -np 176 --map-by core --bind-to core ./wrf.exe\n'
  sha256sum "$script_dir/run-conus-v42.sh" "$script_dir/verify-conus-v42.sh" \
    "$script_dir/compare-netcdf.py"
} > run-manifest.txt

export OMP_NUM_THREADS=1 OMP_PROC_BIND=false
mpirun -np 176 --map-by core --bind-to core sh -c \
  'printf "%s %s\n" "$OMPI_COMM_WORLD_RANK" "$(taskset -pc $$ | awk "{print \$NF}")"' |
  sort -n > affinity-preflight.txt
awk '$1 != $2 {bad++} END {exit bad != 0 || NR != 176}' affinity-preflight.txt || {
  echo "MPI ranks did not map in order to vCPUs 0-175" >&2
  exit 8
}

/usr/bin/time -v -o launcher.log \
  mpirun -np 176 --map-by core --bind-to core ./wrf.exe > mpi.stdout 2>&1
"$script_dir/verify-conus-v42.sh" .
