#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lib/checks.sh"
source "$script_dir/lib/records.sh"

# 1. Settings and checks.
aocc=${1:-}
source_file=${2:-}
output=${3:-}
array_size=${STREAM_ARRAY_SIZE:-280000000}
ntimes=${STREAM_NTIMES:-100}
check_build_request "$@"

aocc=$(realpath -e "$aocc")
source_file=$(realpath -e "$source_file")
output=$(realpath -m "$output")
mkdir "$output"
exec > >(tee "$output/build.log") 2>&1
trap 'echo "ERROR: Build failed at line $LINENO; retain build.log." >&2' ERR

# 2. Use only the selected compiler and its libraries.
export PATH="$aocc/bin:/usr/bin:/bin"
export LIBRARY_PATH="$aocc/lib:$aocc/lib32"
export LD_LIBRARY_PATH="$aocc/lib:$aocc/lib32"
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LD_PRELOAD
"$aocc/bin/clang" --version | tee "$output/compiler-version.txt"
grep -q AOCC "$output/compiler-version.txt" || die "The selected compiler is not AOCC."
cp "$source_file" "$output/stream.c"
record_build_environment

# 3. Compile the original STREAM recipe; also save the exact command.
run_and_record "$output/build-manifest.txt" \
  "$aocc/bin/clang" "$output/stream.c" \
  -fopenmp -mcmodel=large -DSTREAM_TYPE=double \
  "-DSTREAM_ARRAY_SIZE=$array_size" "-DNTIMES=$ntimes" \
  -ffp-contract=fast -fnt-store \
  -O3 -Ofast -ffast-math -ffinite-loops \
  -march=native -zopt -fremap-arrays \
  -mllvm -enable-strided-vectorization -fvector-transform \
  -o "$output/stream"

# 4. Check the executable and record its identity.
[[ -x $output/stream ]] || die "Compiler did not produce an executable."
ldd "$output/stream" | tee "$output/libraries.txt"
if grep -q 'not found' "$output/libraries.txt"; then
  die "Unresolved runtime library."
fi
sha256sum "$output/stream" >> "$output/build-manifest.txt"
echo "Build complete: $output/stream"
