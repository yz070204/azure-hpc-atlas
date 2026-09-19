#!/usr/bin/env bash
set -euo pipefail

sku=$(
  curl -fsS --max-time 2 -H Metadata:true \
    'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("vmSize","unknown"))' \
    2>/dev/null || printf 'unknown\n'
)
cores=$(lscpu -p=CORE,SOCKET | awk -F, '!/^#/ {x[$1 FS $2]=1} END {print length(x)}')
numa=$(lscpu -J | python3 -c '
import json,sys
d={x["field"].rstrip(":"):x["data"] for x in json.load(sys.stdin)["lscpu"]}
print(d.get("NUMA node(s)","unknown"))
')

printf 'sku=%s\nphysical_cores=%s\nnuma_nodes=%s\n' "$sku" "$cores" "$numa"
printf 'active_wrf=%s\n' "$(pgrep -xc wrf.exe 2>/dev/null || true)"
printf 'load1=%s\n' "$(awk '{print $1}' /proc/loadavg)"
printf 'memory_available_gib=%.1f\n' "$(awk '/MemAvailable/ {print $2/1048576}' /proc/meminfo)"

for tool in gcc gfortran mpicc mpif90 mpirun nc-config nf-config; do
  path=$(command -v "$tool" 2>/dev/null || true)
  if [[ -z "$path" ]]; then
    printf '%s_path=NOT_FOUND\n' "$tool"
    continue
  fi
  printf '%s_path=%s\n' "$tool" "$(realpath "$path" 2>/dev/null || printf '%s' "$path")"
  version=$("$path" --version 2>&1 | head -1 || true)
  printf '%s_version=%s\n' "$tool" "$version"
done

if command -v module >/dev/null 2>&1; then
  modules=$( (module -t list 2>&1 || true) | paste -sd, - )
  printf 'loaded_modules=%s\n' "${modules:-none}"
else
  printf 'loaded_modules=module-command-unavailable\n'
fi

for variable in MPI_ROOT HPCX_DIR HPCX_HOME NETCDF NETCDF_ROOT; do
  printf '%s=%s\n' "$variable" "${!variable:-UNSET}"
done

if [[ -d /opt ]]; then
  find /opt -xdev -maxdepth 7 -type f \
    \( -name mpirun -o -name mpicc -o -name mpif90 -o \
       -name hpcx-init.sh -o -name nf-config -o -name nc-config \) \
    -print 2>/dev/null | \
    awk '!seen[$0]++ && count < 30 {print "opt_stack_candidate=" $0; count++}' || true
fi

declare -a roots=()
[[ -d /opt ]] && roots+=("/opt")
roots+=("$HOME")
for variable in WRF_ROOT WRF_RUN_DIR WRF_DATA_DIR; do
  value=${!variable:-}
  [[ -n "$value" && -e "$value" ]] && roots+=("$value")
done
while read -r target filesystem; do
  [[ "$target" != / && "$filesystem" =~ ^(ext4|xfs)$ ]] && roots+=("$target")
done < <(findmnt -rn -o TARGET,FSTYPE)

printf '%s\n' "${roots[@]}" | awk '!seen[$0]++' |
while read -r root; do
  [[ -d "$root" ]] || continue
  find "$root" -xdev -maxdepth 6 \
    \( -name wrf.exe -o -name launcher.log -o -name benchmark-results.txt \
       -o -name run_conus.sh -o -name 'v*_bench_conus2.5km.tar.gz' \) \
    -print 2>/dev/null || true
done | awk '!seen[$0]++ && count < 40 {print "candidate=" $0; count++}' || true

if [[ "$sku" != Standard_HB176rs_v4 || "$cores" != 176 || "$numa" != 4 ]]; then
  printf 'applicability=FAIL\n'
  exit 2
fi
printf 'applicability=PASS\n'
exit 0
