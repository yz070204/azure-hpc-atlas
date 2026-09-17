#!/usr/bin/env bash

# These checks read the settings declared in the build/run entry scripts.
die() {
  echo "ERROR: $*" >&2
  exit 1
}

check_build_request() {
  [[ $# == 3 ]] || die "Usage: bash build-stream.sh AOCC_ROOT STREAM_C NEW_BUILD_DIR"
  [[ ${STREAM_LICENSE_ACCEPTED:-no} == yes ]] ||
    die "Review the AOCC license and set STREAM_LICENSE_ACCEPTED=yes when authorized."
  [[ ${STREAM_RELAXED_FP_APPROVED:-no} == yes ]] ||
    die "This recipe uses relaxed floating-point optimizations; set STREAM_RELAXED_FP_APPROVED=yes."
  [[ -x $aocc/bin/clang && -f $source_file ]] || die "Missing AOCC clang or STREAM source."
  [[ ! -e $output ]] || die "Build directory already exists: $output"
  [[ $array_size =~ ^[1-9][0-9]{0,9}$ ]] || die "Invalid STREAM_ARRAY_SIZE."
  [[ $ntimes =~ ^[1-9][0-9]{0,3}$ && $ntimes -ge 2 ]] ||
    die "STREAM_NTIMES must be 2-9999."
}

check_run_request() {
  [[ $# -ge 2 && $# -le 4 ]] ||
    die "Usage: bash run-stream.sh BINARY NEW_RUN_DIR [REPETITIONS=3] [RUNTIME_LIB_DIR]"
  [[ ${STREAM_RUN_APPROVED:-no} == yes ]] ||
    die "Obtain license/run approval and an idle allocation, then set STREAM_RUN_APPROVED=yes."
  [[ -x $binary && ! -e $output ]] || die "Need an executable and a new run directory."
  [[ $repetitions =~ ^([1-9]|10)$ ]] ||
    die "REPETITIONS must be 1-10 within the approved budget."
  case "$profile" in
    source-original|prebuilt-original|tuned-144|prebuilt-144|normalized-176) ;;
    *) die "Unknown STREAM_PROFILE: $profile." ;;
  esac
  if [[ $profile != normalized-176 ]]; then
    [[ ${STREAM_THP_APPROVED:-no} == yes ]] ||
      die "$profile uses global THP always; obtain approval and set STREAM_THP_APPROVED=yes."
  fi
  if [[ $profile == source-original ]]; then
    [[ ${STREAM_CACHE_DROP_APPROVED:-no} == yes ]] ||
      die "source-original drops host caches; obtain approval and set STREAM_CACHE_DROP_APPROVED=yes."
  fi
  if [[ $profile == prebuilt-* ]]; then
    [[ $# -lt 4 ]] || die "$profile must not inject a runtime library directory."
  fi
  if [[ $profile == source-original || $profile == tuned-144 ]]; then
    [[ -n $lib_dir ]] || die "$profile requires the AOCC 4.0.0 runtime library directory."
  fi
  if [[ -n $lib_dir ]]; then
    [[ -d $lib_dir ]] || die "Runtime library path is not a directory."
  fi
  for tool in curl python3 numactl timeout vmstat lscpu sha256sum awk grep sed; do
    command -v "$tool" >/dev/null || die "Required tool missing: $tool"
  done
}

check_sha256() {
  local file=$1 expected=$2 message=$3 actual
  actual=$(sha256sum "$file")
  [[ ${actual%% *} == "$expected" ]] || die "$message"
}

check_run_binary() {
  local build_dir
  case "$profile" in
    prebuilt-original|prebuilt-144)
      check_sha256 "$binary" \
        b6d034f991c560f3f1edfb4da23dd73d11e864878eb60956d2b46e412984f6c0 \
        "Prebuilt executable differs from the validated AMD 2024_10_08 binary."
      ;;
    source-original|tuned-144)
      build_dir=$(dirname "$binary")
      [[ -f $build_dir/build-manifest.txt && -f $build_dir/compiler-version.txt &&
         -f $build_dir/stream.c ]] || die "$profile requires the original source build and manifests."
      grep -Fxq 'array_size=280000000' "$build_dir/build-manifest.txt" ||
        die "$profile requires 280000000 elements per array."
      grep -Fxq 'ntimes=100' "$build_dir/build-manifest.txt" ||
        die "$profile requires 100 iterations."
      grep -q 'AOCC_4.0.0-' "$build_dir/compiler-version.txt" ||
        die "$profile is validated with AOCC 4.0.0 only."
      grep -Fxq "$(sha256sum "$binary")" "$build_dir/build-manifest.txt" ||
        die "Executable does not match its build manifest."
      check_sha256 "$build_dir/stream.c" \
        c388924eb140fda95f534cdb808ae7f1f8ebb18da41d8aec1b512a3c8d303c9b \
        "Source differs from the pinned STREAM comparison."
      [[ -f $lib_dir/libomp.so ]] || die "Missing AOCC libomp.so."
      check_sha256 "$lib_dir/libomp.so" \
        b62fd9fa42dc0d19131cf3368f914d77004cf7200aed710c91a3b97ba92ffef6 \
        "OpenMP runtime differs from the validated AOCC 4.0.0 library."
      ;;
  esac
}

check_run_host() {
  local allowed_cpus available_kib policy
  sku=$(curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 -H Metadata:true \
    'http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text')
  case "$sku" in
    Standard_HB176rs_v4|Standard_HB176s_v4) ;;
    *) die "This full-size HBv4 runner does not support SKU: $sku" ;;
  esac

  allowed_cpus=$(awk '/^Cpus_allowed_list:/ {print $2}' /proc/self/status)
  [[ $allowed_cpus == 0-175 ]] || die "Require an allocation with all CPUs 0-175 available."
  grep -qw avx512f /proc/cpuinfo || die "AVX-512 support is required."
  available_kib=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  [[ $available_kib =~ ^[0-9]+$ ]] || die "Cannot determine available memory."
  ((available_kib >= 24 * 1024 * 1024)) ||
    die "Require at least 24 GiB available; also check cgroup memory limits."

  if [[ $profile != normalized-176 ]]; then
    bash "$script_dir/../../azure-hbv4-hx176-topology/scripts/check-topology.sh"
    policy=$(LC_ALL=C numactl --show)
    grep -Fxq 'policy: default' <<< "$policy" ||
      die "Original and balanced profiles require inherited default NUMA policy."
  fi
}
