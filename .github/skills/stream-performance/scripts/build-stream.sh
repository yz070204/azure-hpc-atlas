#!/bin/bash
#
# Builds the STREAM memory-bandwidth benchmark with AMD's AOCC compiler
# using the pinned recipe for Azure HBv4 / HX VMs. AOCC and stream.c are
# downloaded fresh; run from a scratch dir — artifacts land in the CWD.

set -euo pipefail

# AOCC version expected on the base image. Bump this (and re-verify the
# compile flags below still apply) whenever the base image's AOCC changes.
readonly AOCC_VERSION="4.0.0"

# STREAM array size. 560M doubles/array (4.48 GB each) is the default: larger than
# aggregate L3, so its bandwidth aligns with Azure's published sustained figures.
# (280M reads higher because it is cache-sensitive; 1.3B is the strict
# larger-than-cache size — see reference.md.)
readonly ARRAY_SIZE="560000000"
readonly NTIMES="100"

# Install AOCC into ./aocc-compiler-<version> and load its environment.
install_aocc() {
  local tarball="aocc-compiler-${AOCC_VERSION}.tar"
  wget "https://download.amd.com/developer/eula/aocc-compiler/${tarball}"
  tar -xf "${tarball}"
  ( cd "aocc-compiler-${AOCC_VERSION}" && ./install.sh )
  source "aocc-compiler-${AOCC_VERSION}/setenv_AOCC.sh"
}

# Fetch a clean copy of the upstream STREAM source.
download_stream() {
  rm -f stream.c
  wget "https://raw.githubusercontent.com/jeffhammond/STREAM/master/stream.c"
}

# Compile STREAM with the pinned AOCC recipe. Do not change these flags.
build_stream() {
  clang stream.c \
    -fopenmp -mcmodel=large \
    -DSTREAM_TYPE=double -DSTREAM_ARRAY_SIZE="${ARRAY_SIZE}" -DNTIMES="${NTIMES}" \
    -ffp-contract=fast -fnt-store \
    -O3 -Ofast -ffast-math -ffinite-loops \
    -march=native -zopt -fremap-arrays \
    -mllvm -enable-strided-vectorization -fvector-transform \
    -o stream
}

main() {
  install_aocc
  download_stream
  build_stream
  echo "Build complete: $(realpath stream)"
}

main "$@"
