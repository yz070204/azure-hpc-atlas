#!/usr/bin/env bash
set -euo pipefail

src=${1:?usage: build-manifest.sh WRF_SOURCE_DIRECTORY [WRF_EXECUTABLE]}
exe=${2:-"$src/main/wrf.exe"}
config="$src/configure.wrf"

[[ -d "$src" ]] || { echo "source directory not found: $src" >&2; exit 2; }
[[ -f "$config" ]] || { echo "configure.wrf not found: $config" >&2; exit 2; }
[[ -x "$exe" ]] || { echo "WRF executable not found: $exe" >&2; exit 2; }

printf 'source=%s\n' "$(realpath "$src")"
if git -C "$src" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'git_commit=%s\n' "$(git -C "$src" rev-parse HEAD)"
  printf 'git_describe=%s\n' "$(git -C "$src" describe --tags --always --dirty)"
  printf 'git_remote=%s\n' "$(git -C "$src" remote get-url origin 2>/dev/null || true)"
fi

grep -E '^(DESCRIPTION|DM_FC|DM_CC|FCOPTIM|CFLAGS_LOCAL|NETCDFPATH)' "$config"
printf 'wrf_executable=%s\n' "$(realpath "$exe")"
printf 'wrf_sha256=%s\n' "$(sha256sum "$exe" | awk '{print $1}')"

for tool in gcc gfortran mpicc mpif90 mpirun nc-config nf-config; do
  path=$(command -v "$tool" 2>/dev/null || true)
  [[ -z "$path" ]] && continue
  printf '%s_path=%s\n' "$tool" "$path"
  version=$("$path" --version 2>&1 | head -1 || true)
  printf '%s_version=%s\n' "$tool" "$version"
done

printf 'linked_libraries_begin\n'
ldd "$exe"
printf 'linked_libraries_end\n'
if ldd "$exe" | grep -q 'not found'; then
  printf 'link_status=FAIL\n'
  exit 3
fi
printf 'link_status=PASS\n'
