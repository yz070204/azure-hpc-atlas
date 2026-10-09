#!/bin/bash
# Shared, read-only guest signature validator. Wrappers select the profile;
# the caller confirms VM identity. No host/CCD mapping or metadata queries.
# Usage: bash check-topology.sh <hbv4-hx|hbv5> [--sku <confirmed-vm-size>]
# Exit status: 0 on a match, 1 on invalid input, mismatch, or collection error.

set -euo pipefail

err() {
  echo "ERROR: $*" >&2
}

check_sku() {
  local profile=$1 sku=$2
  case "$profile" in
    hbv4-hx)
      if [[ "$sku" =~ ^Standard_HB176[[:alnum:]]*_v4$ ||
            "$sku" =~ ^Standard_HX176[[:alnum:]]*$ ]]; then
        return 0
      fi
      ;;
    hbv5)
      if [[ "$sku" == Standard_HB368rs_v5 ]]; then
        return 0
      fi
      ;;
  esac
  err "SKU '$sku' is not covered by the '$profile' profile (full-size VMs only)."
  return 1
}

validate_topology() {
  awk -v profile="$1" -v expected_cpus="$2" -v reference="$3" '
    function fail(message) {
      print "ERROR: " message > "/dev/stderr"
      failed = 1
      exit 1
    }

    BEGIN {
      # HBv4/HX private-cache offsets and guest L3 bases per NUMA node.
      private_offset[0] = 0; private_offset[1] = 4
      private_offset[2] = 40; private_offset[3] = 44
      l3_base[0] = 0; l3_base[1] = 6
      l3_base[2] = 16; l3_base[3] = 22
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

      if (profile == "hbv4-hx") {
        node = int(cpu / 44)
        socket = int(cpu / 88)
        private_cache = cpu + private_offset[node]
        l3 = l3_base[node] + int((cpu % 44) / 8)
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
  if (( $# != 1 && $# != 3 )); then
    err "Usage: bash check-topology.sh <hbv4-hx|hbv5> [--sku <confirmed-vm-size>]"
    return 1
  fi

  local profile=$1 expected_cpus reference tool topology
  case "$profile" in
    hbv4-hx) expected_cpus=176; reference="Full-size HBv4/HX" ;;
    hbv5) expected_cpus=368; reference="Full-size HBv5 measured" ;;
    *) err "Unknown topology profile '$profile' (expected hbv4-hx or hbv5)."; return 1 ;;
  esac

  if (( $# == 3 )); then
    if [[ "$2" != --sku ]]; then
      err "Expected --sku <confirmed-vm-size>."
      return 1
    fi
    check_sku "$profile" "$3" || return 1
  fi

  for tool in lscpu awk; do
    if ! command -v "$tool" >/dev/null; then
      err "Required tool missing: $tool"
      return 1
    fi
  done

  if ! topology="$(LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE)"; then
    err "Could not collect the lscpu topology."
    return 1
  fi

  printf '%s\n' "$topology" | validate_topology "$profile" "$expected_cpus" "$reference"
}

main "$@"
