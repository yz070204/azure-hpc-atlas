#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 0 ]]; then
  echo "Usage: bash check-topology.sh" >&2
  exit 1
fi

for tool in lscpu awk; do
  command -v "$tool" >/dev/null || {
    echo "ERROR: Required tool missing: $tool" >&2
    exit 1
  }
done

# This checks the documented guest signature, not physical CCD sharing.
if ! topology=$(LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE); then
  echo "ERROR: Could not collect the lscpu topology." >&2
  exit 1
fi
printf '%s\n' "$topology" | awk '
function fail(message) {
    print "ERROR: " message > "/dev/stderr"
    failed = 1
    exit 1
}
BEGIN {
    private_offset[0] = 0; private_offset[1] = 4
    private_offset[2] = 40; private_offset[3] = 44
    l3_base[0] = 0; l3_base[1] = 6
    l3_base[2] = 16; l3_base[3] = 22
}
NR == 1 {
    if (NF != 6 || $1 != "CPU" || $2 != "NODE" || $3 != "SOCKET" ||
        $4 != "CORE" || ($5 != "CACHE" && $5 != "L1d:L1i:L2:L3") || $6 != "ONLINE")
        fail("Unexpected lscpu header; require CPU NODE SOCKET CORE, cache IDs and ONLINE.")
    next
}
{
    if (NF != 6 || $1 !~ /^[0-9]+$/ || $1 < 0 || $1 > 175)
        fail("Unexpected CPU row: " $0)
    cpu = $1 + 0
    if (seen[cpu]++)
        fail("Duplicated CPU " cpu ".")

    node = int(cpu / 44)
    socket = int(cpu / 88)
    private_cache = cpu + private_offset[node]
    local_l3 = int((cpu % 44) / 8)
    l3 = l3_base[node] + (local_l3 < 5 ? local_l3 : 5)
    cache = private_cache ":" private_cache ":" private_cache ":" l3

    if ($2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ ||
        $2 != node || $3 != socket || $4 != cpu || $5 != cache || $6 != "yes")
        fail("CPU " cpu " topology differs from the full-size HBv4/HX reference.")
    count++
}
END {
    if (failed)
        exit 1
    if (count != 176)
        fail("Require all 176 CPUs; found " count ".")
    print "PASS: Full-size HBv4/HX guest topology matches the reference."
}'
