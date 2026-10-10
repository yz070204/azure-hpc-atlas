#!/bin/bash
#
# Builds the STREAM memory-bandwidth benchmark with AMD's AOCC compiler
# using the pinned recipe for full-size Azure HBv4 / HX / HBv5 VMs. AOCC and stream.c are
# downloaded fresh (unless already cached) into <work-dir>; all artifacts
# land there, never in the caller's cwd.
#
# Usage: build-stream.sh <work-dir> [array-elements]

set -euo pipefail

# Pin the measured recipe independently of the system compiler.
readonly AOCC_VERSION="4.0.0"
readonly STREAM_REVISION="4dbce1d0fdb7410e8f21b48f3381bc0a1341967f"

# Default array size; optional sizes are explicit experiments, not comparable metrics.
ARRAY_SIZE="560000000"
readonly NTIMES="100"

# Install AOCC into ./aocc-compiler-<version> and load its environment. Skips
# the download/install if a matching, working compiler is already cached in
# the work dir from a prior run.
install_aocc() {
  local install_dir="aocc-compiler-${AOCC_VERSION}"
  local setenv="${install_dir}/setenv_AOCC.sh"

  if [[ ! -x "${install_dir}/bin/clang" ]]; then
    local tarball="aocc-compiler-${AOCC_VERSION}.tar"
    if [[ -e "${install_dir}" ]]; then
      echo "ERROR: incomplete AOCC install at $(realpath "$install_dir"); inspect it before retrying" >&2
      return 1
    fi
    wget -q "https://download.amd.com/developer/eula/aocc-compiler/${tarball}" -O "${tarball}.part"
    mv "${tarball}.part" "${tarball}"
    tar -xf "${tarball}"
    # install.sh writes setenv_AOCC.sh into the cwd (not the extracted dir),
    # so run it from inside install_dir and move the result alongside clang.
    ( cd "${install_dir}" && ./install.sh )
    mv setenv_AOCC.sh "${setenv}"
    # run-stream.sh expects setenv_AOCC.sh directly in the work dir; keep a
    # copy there too so its lookup (../setenv_AOCC.sh) keeps working.
  fi
  cp "${setenv}" setenv_AOCC.sh

  # setenv_AOCC.sh appends to vars like $LIBRARY_PATH without defining them
  # first, which trips `set -u`; seed them empty before sourcing.
  : "${LIBRARY_PATH:=}" "${LD_LIBRARY_PATH:=}" "${C_INCLUDE_PATH:=}" "${CPLUS_INCLUDE_PATH:=}"
  source "${setenv}"
}

# Fetch the pinned source without replacing the cache on a failed download.
download_stream() {
  wget -q "https://raw.githubusercontent.com/jeffhammond/STREAM/${STREAM_REVISION}/stream.c" -O stream.c.part
  mv stream.c.part stream.c
}

# Compile STREAM with the pinned AOCC recipe. Do not change these flags.
build_stream() {
  local flags=(
    -fopenmp -mcmodel=large
    -DSTREAM_TYPE=double -DSTREAM_ARRAY_SIZE="${ARRAY_SIZE}" -DNTIMES="${NTIMES}"
    -ffp-contract=fast -fnt-store
    -O3 -Ofast -ffast-math -ffinite-loops
    -march=native -zopt -fremap-arrays
    -mllvm -enable-strided-vectorization -fvector-transform
  )
  clang stream.c "${flags[@]}" -o stream
  clang --version > compiler-version.txt
  printf '%q ' "$(command -v clang)" stream.c "${flags[@]}" -o stream > build-command.txt
  printf '\n' >> build-command.txt
  python3 - "$ARRAY_SIZE" "$NTIMES" "$(command -v clang)" "$STREAM_REVISION" "${flags[@]}" <<'PYMETA'
import json, pathlib, platform, sys

metadata = {
    "array_elements": int(sys.argv[1]), "element_bytes": 8,
    "ntimes": int(sys.argv[2]), "compiler": sys.argv[3],
    "compiler_version": pathlib.Path("compiler-version.txt").read_text(),
    "source_revision": sys.argv[4],
    "flags": sys.argv[5:], "build_kernel": platform.release(),
}
pathlib.Path("build.json").write_text(json.dumps(metadata, indent=2) + "\n")
PYMETA
}

main() {
  local wdir=${1:?usage: build-stream.sh <work-dir> [array-elements]}
  if (( $# > 2 )); then
    echo "ERROR: usage: build-stream.sh <work-dir> [array-elements]" >&2
    return 1
  fi
  ARRAY_SIZE=${2:-560000000}
  if [[ ! "$ARRAY_SIZE" =~ ^[1-9][0-9]*$ ]] || (( ${#ARRAY_SIZE} > 10 )); then
    echo "ERROR: array size must be a positive integer of at most 10 digits" >&2
    return 1
  fi
  mkdir -p "$wdir"
  cd "$wdir"
  install_aocc
  download_stream
  build_stream
  echo "Build complete: $(realpath stream)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
