#!/usr/bin/env bash

run_and_record() {
  local manifest=$1
  shift
  {
    printf 'command='
    printf '%q ' "$@"
    printf '\n'
  } >> "$manifest"
  "$@"
}

record_build_environment() {
  {
    date -u '+timestamp=%FT%TZ'
    printf 'aocc_root=%s\nsource_path=%s\narray_size=%s\nntimes=%s\n' \
      "$aocc" "$source_file" "$array_size" "$ntimes"
    printf 'LIBRARY_PATH=%s\nLD_LIBRARY_PATH=%s\n' "$LIBRARY_PATH" "$LD_LIBRARY_PATH"
    sha256sum "$aocc/bin/clang" "$output/stream.c"
    cat "$output/compiler-version.txt"
    LC_ALL=C lscpu
  } > "$output/build-manifest.txt"
}

record_run_environment() {
  {
    date -u '+timestamp=%FT%TZ'
    printf 'sku=%s\nrepetitions=%s\nprofile=%s\ncpu_list=%s\n' \
      "$sku" "$repetitions" "$profile" "$cpu_list"
    sha256sum "$binary"
    uname -sr
    cat /etc/os-release
    LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE
    grep -E 'Cpus_allowed_list|Mems_allowed_list' /proc/self/status
    cat /proc/self/cgroup
    numactl --show
    printf '\nTHP enabled:\n'
    cat /sys/kernel/mm/transparent_hugepage/enabled
    printf '\nTHP defrag:\n'
    cat /sys/kernel/mm/transparent_hugepage/defrag
  } > "$output/run-manifest.txt" 2>&1
  if [[ -f $(dirname "$binary")/build-manifest.txt ]]; then
    cp "$(dirname "$binary")/build-manifest.txt" "$output/build-manifest.txt"
  fi
  env -i PATH=/usr/bin:/bin "${runtime[@]}" ldd "$binary" > "$output/libraries.txt"
  if grep -q 'not found' "$output/libraries.txt"; then
    die "Unresolved runtime library."
  fi
  record_library_hashes
}

record_library_hashes() {
  local line
  # Preserve spaces in library paths; ignore non-file entries such as linux-vdso.
  local pattern='^[[:space:]]*([^[:space:]]+[[:space:]]+=>[[:space:]]+)?(/.*[^[:space:]])[[:space:]]+\(0x[[:xdigit:]]+\)[[:space:]]*$'
  while IFS= read -r line; do
    if [[ $line =~ $pattern ]]; then
      sha256sum "${BASH_REMATCH[2]}"
    fi
  done < "$output/libraries.txt" > "$output/libraries.sha256"
}
