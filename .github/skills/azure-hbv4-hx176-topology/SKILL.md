---
name: azure-hbv4-hx176-topology
description: Understand and answer questions about vCPU, vNUMA, host physical-core, physical-NUMA, and CCD placement for full-size 176-vCPU Azure HBv4 and HX VMs. Use for CPU affinity, NUMA locality, CCD grouping, core-placement analysis, and interpreting Hyper-V Ideal Cpu data on these VM sizes, and also for performance optimizing, troubleshooting and tuning. Do not apply this mapping to constrained-core or smaller sizes. If in-VM data and topology information disagrees with this reference, report the discrepancy rather than silently substituting this reference, as there may be a VM platform issue.
user-invocable: false
---

# Azure HBv4 and HX 176-vCPU topology

Use this skill only for the full-size 176-vCPU Azure HBv4 and HX series. Do not
apply this mapping to constrained-core or smaller sizes.

For Azure VM, this should apply to size below only:
 - Standard_HB176rs_v4
 - Standard_HX176rs_v4
 - Standard_HB176s_v4
 - Standard_HX176s_v4

## Terminology

- **vCPU** or **Vcore**: VM-visible logical processor ID, numbered `0-175`.
- **vNUMA**: VM-visible NUMA node, numbered `0-3`.
- **Pcore**: host processor ID reported by the Hyper-V `Ideal Cpu` counter.
- **Pnuma**: physical host NUMA node containing the Pcore.
- **PCCD**: physical AMD CCD containing the Pcore.
- A range such as `0-7 -> 16-23` maps in order: vCPU 0 maps to Pcore 16,
  vCPU 1 maps to Pcore 17, and so on.

Here, `Pcore` denotes the measured host processor ID. A guest cannot directly
pin a thread to a Pcore; guest affinity controls vCPU IDs.

## Topology invariants

- The VM exposes 176 vCPUs: `0-175`.
- There are four vNUMA nodes with 44 vCPUs each:

  | vNUMA | vCPU range | Physical NUMA |
  |---:|---:|---:|
  | 0 | 0-43 | 0 |
  | 1 | 44-87 | 1 |
  | 2 | 88-131 | 2 |
  | 3 | 132-175 | 3 |

- Therefore, for a valid vCPU `v`, `vNUMA = floor(v / 44)`.
- Every vCPU stays local to the physical NUMA node matching its vNUMA node.
- The reference host topology has 192 Pcores (`0-191`),
  four physical NUMA nodes, and 24 physical CCDs (`0-23`).
- A full-size VM receives 176 of those 192 Pcores. Sixteen Pcores are not in
  the VM mapping.
- CCDs normally contribute eight cores. CCDs `0`, `1`, `6`, `7`, `12`, `13`,
  `18`, and `19` contribute six mapped cores each, accounting for the 16-core
  difference.
- Do not infer Pcore or PCCD from the vCPU number alone. Use the exact table.

## L3 processor distribution policy

The OS `L3ProcessorDistributionPolicy` supports four distribution patterns for
the six guest-visible L3 groups within each 44-vCPU NUMA node:

| Policy | Guest-visible cores per L3 group |
|---:|---|
| 0 | `4:8:8:8:8:8` |
| 1 | `8:8:8:8:8:4` |
| 2 | `7:7:7:7:8:8` |
| 3 | `8:8:7:7:7:7` |

The physical allocation would be represented more naturally as
`8:8:8:8:6:6`, but that pattern is not supported by the current policy
options. Policy 1 is used as the closest supported guest representation.

Treat the pattern shown by `lscpu -e` as a signature of which guest L3
distribution policy is active, not as an authoritative physical-CCD map.
Guest cache IDs do not necessarily identify the vCPUs that share a physical
L3 cache.

For example, the policy-1 guest view groups vCPUs `32-39` under one L3 ID and
`40-43` under the next. The measured physical map instead places:

- vCPUs `32-37` on PCCD 0, Pcores `2-7`
- vCPUs `38-39` on PCCD 6, Pcores `54-55`
- vCPUs `40-43` on the same PCCD 6, Pcores `50-53`

Thus, vCPUs `38-43` physically share PCCD 6 even though `lscpu -e` splits them
across two guest L3 IDs. Conversely, the guest L3 group for vCPUs `32-39`
spans physical PCCD 0 and PCCD 6.

## Required full-size guest topology signature

On the full-size HBv4/HX SKUs listed in this skill, `lscpu -e` is expected to
show all 176 CPUs online with the following exact structure:

| CPU range | NUMA node | Socket | Core | Private-cache ID (`L1d:L1i:L2`) | L3 groups |
|---:|---:|---:|---:|---:|---|
| 0-43 | 0 | 0 | Same as CPU | Same as CPU | `0-7 -> 0`, `8-15 -> 1`, `16-23 -> 2`, `24-31 -> 3`, `32-39 -> 4`, `40-43 -> 5` |
| 44-87 | 1 | 0 | Same as CPU | CPU + 4 | `44-51 -> 6`, `52-59 -> 7`, `60-67 -> 8`, `68-75 -> 9`, `76-83 -> 10`, `84-87 -> 11` |
| 88-131 | 2 | 1 | Same as CPU | CPU + 40 | `88-95 -> 16`, `96-103 -> 17`, `104-111 -> 18`, `112-119 -> 19`, `120-127 -> 20`, `128-131 -> 21` |
| 132-175 | 3 | 1 | Same as CPU | CPU + 44 | `132-139 -> 22`, `140-147 -> 23`, `148-155 -> 24`, `156-163 -> 25`, `164-171 -> 26`, `172-175 -> 27` |

For each row:

- `CORE` equals `CPU`.
- `L1d`, `L1i`, and `L2` all equal the private-cache ID in the table.
- `ONLINE` is `yes`.
- Each NUMA node has the policy-1 guest L3 distribution `8:8:8:8:8:4`.

Use `LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE` when collecting the
signature so parsing is locale-independent and all required fields are
present.

For a read-only check from the repository root:

```bash
bash .github/skills/azure-hbv4-hx176-topology/scripts/check-topology.sh
```

The reusable Bash/awk checker validates every row, including duplicates,
missing/offline CPUs and all cache IDs. It exits nonzero on a mismatch or
collection failure. It does not change affinity, generate a physical CCD map,
query Azure metadata or run a benchmark. The caller must first establish that
the VM is a covered full-size SKU. STREAM calls this checker; other benchmark
workflows can reuse it without embedding their own topology parser.

For one CPU `c`, the expected L3 ID can be calculated as:

```text
node = floor(c / 44)
offset = c modulo 44
local_l3_group = min(floor(offset / 8), 5)
l3_base_by_node = [0, 6, 16, 22]
expected_l3 = l3_base_by_node[node] + local_l3_group
```

Any difference in CPU count, online state, NUMA range, socket, core numbering,
private-cache IDs, or the `8:8:8:8:8:4` L3 signature is a reportable topology
discrepancy for these full-size SKUs. Capture the complete `lscpu -e` output,
detected Azure SKU, OS image, and kernel. Do not dismiss the discrepancy
because the workload still runs, and do not reinterpret the unexpected output
as a valid physical CCD map.

First check whether the wrong SKU, offline CPUs, boot configuration, or a
known OS/kernel configuration explains the difference. If not, classify it as
`possible-platform-or-node-health` and prepare the HPC Atlas escalation
bundle.

## Exact vCPU-to-host mapping

| vNUMA / Pnuma | Physical CCD | vCPU range | Pcore range | Mapping notes |
|---:|---:|---:|---:|---|
| 0 | 2 | 0-7 | 16-23 | Ordered |
| 0 | 4 | 8-15 | 32-39 | Ordered |
| 0 | 8 | 16-23 | 64-71 | Ordered |
| 0 | 10 | 24-31 | 80-87 | Ordered |
| 0 | 0 | 32-37 | 2-7 | Ordered |
| 0 | 6 | 38-39 | 54-55 | Ordered |
| 0 | 6 | 40-43 | 50-53 | Ordered |
| 1 | 3 | 44-47 | 24-27 | Ordered |
| 1 | 3 | 48-51 | 28-31 | Ordered |
| 1 | 5 | 52-55 | 40-43 | Ordered |
| 1 | 5 | 56-59 | 44-47 | Ordered |
| 1 | 9 | 60-63 | 72-75 | Ordered |
| 1 | 9 | 64-67 | 76-79 | Ordered |
| 1 | 11 | 68-71 | 88-91 | Ordered |
| 1 | 11 | 72-75 | 92-95 | Ordered |
| 1 | 1 | 76-79 | 10-13 | Ordered |
| 1 | 1 | 80-81 | 14-15 | Ordered |
| 1 | 7 | 82-83 | 62-63 | Ordered |
| 1 | 7 | 84-87 | 58-61 | Ordered |
| 2 | 14 | 88-95 | 112-119 | Ordered |
| 2 | 16 | 96-103 | 128-135 | Ordered |
| 2 | 20 | 104-111 | 160-167 | Ordered |
| 2 | 22 | 112-119 | 176-183 | Ordered |
| 2 | 12 | 120-125 | 98-103 | Ordered |
| 2 | 18 | 126-127 | 150-151 | Ordered |
| 2 | 18 | 128-131 | 146-149 | Ordered |
| 3 | 15 | 132-135 | 120-123 | Ordered |
| 3 | 15 | 136-139 | 124-127 | Ordered |
| 3 | 17 | 140-143 | 136-139 | Ordered |
| 3 | 17 | 144-147 | 140-143 | Ordered |
| 3 | 21 | 148-151 | 168-171 | Ordered |
| 3 | 21 | 152-155 | 172-175 | Ordered |
| 3 | 23 | 156-159 | 184-187 | Ordered |
| 3 | 23 | 160-163 | 188-191 | Ordered |
| 3 | 13 | 164-167 | 106-109 | Ordered |
| 3 | 13 | 168-169 | 110-111 | Ordered |
| 3 | 19 | 170-171 | 158-159 | Ordered |
| 3 | 19 | 172-175 | 154-157 | Ordered |

The table is ordered by vCPU. Physical CCD numbers are not contiguous within
each NUMA node:

- Pnuma 0 uses even CCDs `0, 2, 4, 6, 8, 10`.
- Pnuma 1 uses odd CCDs `1, 3, 5, 7, 9, 11`.
- Pnuma 2 uses even CCDs `12, 14, 16, 18, 20, 22`.
- Pnuma 3 uses odd CCDs `13, 15, 17, 19, 21, 23`.

## Lookup procedure

When asked about one vCPU:

1. Reject IDs outside `0-175` as invalid for this VM size.
2. Compute its vNUMA as `floor(vCPU / 44)`.
3. Find the row whose vCPU range contains the ID.
4. Apply the same offset within the paired Pcore range.
5. Report vCPU, vNUMA, Pcore, Pnuma, and physical CCD.

Example: vCPU 42 is in `40-43 -> 50-53`. Its offset is 2, so it maps to
Pcore 52, Pnuma 0, physical CCD 6.

When asked for CPUs sharing a CCD, return every table row with that PCCD. Some
six-core CCD mappings are split into two non-monotonic vCPU/Pcore ranges; do
not fill the gaps or reorder the mapping.

When recommending guest CPU affinity:

- Express affinity using vCPU IDs, not Pcore IDs.
- Keep latency-sensitive communicating threads within one vNUMA node when
  possible.
- For an eight-thread group intended to share one complete physical CCD, use
  one of the eight-vCPU rows.
- For CCDs `0`, `1`, `6`, `7`, `12`, `13`, `18`, or `19`, state that this VM
  has only six mapped cores from that CCD.
- Verify the guest's CPU enumeration and NUMA topology with OS tools such as
  `lscpu -e=CPU,NODE,CACHE` on Linux before applying affinity. Use the output
  to identify CPU numbering, NUMA placement, and the active L3 distribution
  pattern. Do not use its L3 IDs to decide which vCPUs physically share a CCD.
  Exact Pcore and PCCD placement comes from the Hyper-V measurement and the
  mapping table above.

## Source and interpretation guardrails

Treat this as a mapping for the measured Azure HBv4/HX full-size topology.
The policy patterns describe this reference topology; check the live VM
before applying the mapping.

If a live VM's Hyper-V Ideal Cpu data or measured performance disagrees,
report the discrepancy rather than silently substituting this reference.
