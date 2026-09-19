#!/bin/bash
#
# Checks that the guest CPU topology of a full-size 176-vCPU HBv4/HX VM
# matches the reference `lscpu -e` signature in SKILL.md.
#
# Read-only: it does not change affinity, build a physical CCD map, query
# Azure metadata, or run benchmarks. The caller must first confirm that the
# VM is a covered full-size size.
#
# Usage: bash check-topology.sh
# Exit status: 0 if the topology matches, 1 on a mismatch or collection error.

set -euo pipefail

readonly EXPECTED_CPUS=176

#######################################
# Prints an error message to STDERR.
# Arguments:
#   Message to print.
#######################################
err() {
  echo "ERROR: $*" >&2
}

#######################################
# Verifies that the commands this script needs are installed.
# Returns:
#   0 if all tools are present, 1 otherwise.
#######################################
check_tools() {
  local tool
  for tool in lscpu awk; do
    if ! command -v "${tool}" >/dev/null; then
      err "Required tool missing: ${tool}"
      return 1
    fi
  done
}

#######################################
# Validates `lscpu -e` output against the full-size HBv4/HX signature.
# Checks the guest signature only, not physical CCD sharing.
# Inputs:
#   lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE output on STDIN.
# Outputs:
#   PASS line on STDOUT, or the first mismatch on STDERR.
# Returns:
#   0 if every CPU matches, 1 otherwise.
#######################################
validate_topology() {
  awk -v expected_cpus="${EXPECTED_CPUS}" '
    function fail(message) {
      print "ERROR: " message > "/dev/stderr"
      failed = 1
      exit 1
    }

    BEGIN {
      # Per NUMA node: offset from CPU ID to the private-cache (L1/L2) ID.
      private_offset[0] = 0; private_offset[1] = 4
      private_offset[2] = 40; private_offset[3] = 44
      # Per NUMA node: first guest L3 ID (IDs 12-15 are unused).
      l3_base[0] = 0; l3_base[1] = 6
      l3_base[2] = 16; l3_base[3] = 22
    }

    # Header row: require the exact columns the signature needs.
    NR == 1 {
      if (NF != 6 || $1 != "CPU" || $2 != "NODE" || $3 != "SOCKET" ||
          $4 != "CORE" || ($5 != "CACHE" && $5 != "L1d:L1i:L2:L3") ||
          $6 != "ONLINE") {
        fail("Unexpected lscpu header; require CPU NODE SOCKET CORE, " \
             "cache IDs and ONLINE.")
      }
      next
    }

    # One row per CPU: compute the expected values and compare.
    {
      if (NF != 6 || $1 !~ /^[0-9]+$/ || $1 + 0 >= expected_cpus) {
        fail("Unexpected CPU row: " $0)
      }
      cpu = $1 + 0
      if (seen[cpu]++) {
        fail("Duplicated CPU " cpu ".")
      }

      node = int(cpu / 44)            # 44 CPUs per NUMA node
      socket = int(cpu / 88)          # 2 NUMA nodes per socket
      private_cache = cpu + private_offset[node]
      local_l3 = int((cpu % 44) / 8)  # policy 1: 8:8:8:8:8:4
      if (local_l3 > 5) {
        local_l3 = 5
      }
      l3 = l3_base[node] + local_l3
      cache = private_cache ":" private_cache ":" private_cache ":" l3

      if ($2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ ||
          $2 != node || $3 != socket || $4 != cpu || $5 != cache ||
          $6 != "yes") {
        fail("CPU " cpu " topology differs from the full-size HBv4/HX " \
             "reference.")
      }
      count++
    }

    END {
      if (failed) {
        exit 1
      }
      if (count != expected_cpus) {
        fail("Require all " expected_cpus " CPUs; found " count + 0 ".")
      }
      print "PASS: Full-size HBv4/HX guest topology matches the reference."
    }
  '
}

main() {
  if (( $# != 0 )); then
    echo "Usage: bash check-topology.sh" >&2
    exit 1
  fi

  check_tools || exit 1

  # Locale-independent output with every field the signature needs.
  local topology
  if ! topology="$(LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE)"; then
    err "Could not collect the lscpu topology."
    exit 1
  fi

  printf '%s\n' "${topology}" | validate_topology
}

main "$@"
