#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
[[ $# == 3 ]] || die "Usage: bash build-stream.sh AOCC_ROOT STREAM_C NEW_BUILD_DIR"
[[ ${STREAM_LICENSE_ACCEPTED:-no} == yes ]] ||
  die "Review the AOCC license and set STREAM_LICENSE_ACCEPTED=yes when authorized."
[[ ${STREAM_RELAXED_FP_APPROVED:-no} == yes ]] ||
  die "This recipe uses relaxed floating-point optimizations; set STREAM_RELAXED_FP_APPROVED=yes."

aocc=$(realpath -e "$1")
source_file=$(realpath -e "$2")
output=$(realpath -m "$3")
[[ -x $aocc/bin/clang && -f $source_file ]] || die "Missing AOCC clang or STREAM source."
[[ ! -e $output ]] || die "Build directory already exists: $output"
array_size=${STREAM_ARRAY_SIZE:-280000000}
ntimes=${STREAM_NTIMES:-100}
[[ $array_size =~ ^[1-9][0-9]{0,9}$ ]] || die "Invalid STREAM_ARRAY_SIZE."
[[ $ntimes =~ ^[1-9][0-9]{0,3}$ && $ntimes -ge 2 ]] || die "STREAM_NTIMES must be 2-9999."

mkdir "$output"
exec > >(tee "$output/build.log") 2>&1
trap 'echo "ERROR: Build failed at line $LINENO; retain build.log." >&2' ERR
export PATH="$aocc/bin:/usr/bin:/bin"
export LIBRARY_PATH="$aocc/lib:$aocc/lib32"
export LD_LIBRARY_PATH="$aocc/lib:$aocc/lib32"
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LD_PRELOAD
"$aocc/bin/clang" --version | tee "$output/compiler-version.txt"
grep -q AOCC "$output/compiler-version.txt" || die "The selected compiler is not AOCC."
cp "$source_file" "$output/stream.c"
flags=(
  -fopenmp -mcmodel=large -DSTREAM_TYPE=double
  "-DSTREAM_ARRAY_SIZE=$array_size" "-DNTIMES=$ntimes"
  -ffp-contract=fast -fnt-store -O3 -Ofast -ffast-math -ffinite-loops
  -march=native -zopt -fremap-arrays -mllvm -enable-strided-vectorization
  -fvector-transform
)
{
  date -u '+timestamp=%FT%TZ'
  printf 'aocc_root=%s\nsource_path=%s\narray_size=%s\nntimes=%s\n' \
    "$aocc" "$source_file" "$array_size" "$ntimes"
  printf 'command='
  printf '%q ' "$aocc/bin/clang" "$output/stream.c" "${flags[@]}" -o "$output/stream"
  printf '\n'
  printf 'LIBRARY_PATH=%s\nLD_LIBRARY_PATH=%s\n' "$LIBRARY_PATH" "$LD_LIBRARY_PATH"
  sha256sum "$aocc/bin/clang" "$output/stream.c"
  cat "$output/compiler-version.txt"
  LC_ALL=C lscpu
} > "$output/build-manifest.txt"
"$aocc/bin/clang" "$output/stream.c" "${flags[@]}" -o "$output/stream"
[[ -x $output/stream ]] || die "Compiler did not produce an executable."
ldd "$output/stream" | tee "$output/libraries.txt"
if grep -q 'not found' "$output/libraries.txt"; then die "Unresolved runtime library."; fi
sha256sum "$output/stream" >> "$output/build-manifest.txt"
echo "Build complete: $output/stream"
