#!/bin/bash
# Read-only guest topology check; caller confirms a covered full-size VM.
# Usage: bash check-topology.sh <hbv4|hx|hbv5>
# Returns 0 on a match, nonzero on invalid input or a failed check.

set -euo pipefail

err() {
  echo "ERROR: $*" >&2
}

# Compares every lscpu row with the selected guest signature, not a CCD map.
validate_topology() {
  awk -v expected_cpus="$1" -v reference="$2" '
    function fail(message) {
      print "ERROR: " message > "/dev/stderr"
      failed = 1
      exit 1
    }

    BEGIN {
      # HBv4/HX private-cache offsets and guest L3 bases per NUMA node.
      split("0 4 40 44", private_offset)
      split("0 6 16 22", l3_base)
    }

    NR == 1 {
      if (NF != 6 || $1 != "CPU" || $2 != "NODE" || $3 != "SOCKET" ||
          $4 != "CORE" || ($5 != "CACHE" && $5 != "L1d:L1i:L2:L3") ||
          $6 != "ONLINE") {
        fail("Unexpected lscpu header; require CPU NODE SOCKET CORE, " \
             "cache IDs and ONLINE.")
      }
      next
    }

    {
      if (NF != 6 || $1 !~ /^[0-9]+$/ || $1 + 0 >= expected_cpus) {
        fail("Unexpected CPU row: " $0)
      }
      cpu = $1 + 0
      if (seen[cpu]++) {
        fail("Duplicated CPU " cpu ".")
      }

      if (expected_cpus == 176) {
        node = int(cpu / 44)
        socket = int(cpu / 88)
        private_cache = cpu + private_offset[node + 1]
        l3 = l3_base[node + 1] + int((cpu % 44) / 8)
      } else {
        node = int(cpu / 23)
        socket = int(node / 4)
        private_cache = cpu + 36 * socket + (node % 4)
        l3 = 16 * socket + 3 * (node % 4) + int((cpu % 23) / 8)
      }
      cache = private_cache ":" private_cache ":" private_cache ":" l3

      if ($2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ ||
          $2 != node || $3 != socket || $4 != cpu || $5 != cache ||
          $6 != "yes") {
        fail("CPU " cpu " topology differs from the " reference " reference. " \
             "Expected: " cpu " " node " " socket " " cpu " " cache " yes; " \
             "found: " $0)
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
      print "PASS: " reference " guest topology matches the reference."
    }
  '
}

main() {
  if (( $# != 1 )); then
    err "Usage: bash check-topology.sh <hbv4|hx|hbv5>"
    return 1
  fi

  local expected_cpus reference topology
  case "$1" in
    hbv4|hx)
      expected_cpus=176
      reference="Full-size HBv4/HX"
      ;;
    hbv5)
      expected_cpus=368
      reference="Full-size HBv5 measured"
      ;;
    *)
      err "Unknown family '$1'; expected hbv4, hx, or hbv5."
      return 1
      ;;
  esac

  if ! topology="$(LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE)"; then
    err "Could not collect the lscpu topology."
    return 1
  fi

  validate_topology "${expected_cpus}" "${reference}" <<< "${topology}"
}

main "$@"
