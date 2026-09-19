---
name: azure-hbv4-hx176-topology
description: vCPU, vNUMA, host physical-core, physical-NUMA, and CCD placement for full-size 176-vCPU Azure HBv4 and HX VMs. Use for CPU affinity, NUMA locality, CCD grouping, core-placement analysis, interpreting Hyper-V Ideal Cpu data, and performance tuning or troubleshooting on these sizes. Not for constrained-core or smaller sizes. If live VM data disagrees with this reference, report the discrepancy instead of substituting the reference; it may be a platform issue.
user-invocable: false
---

# Azure HBv4 and HX 176-vCPU topology

Applies only to full-size 176-vCPU HBv4 and HX sizes: names matching `Standard_HB176*_v4` or `Standard_HX176*` with no hyphen after `176` (e.g. `Standard_HB176rs_v4`, `Standard_HX176rs`). Never apply it to constrained-core sizes (e.g. `Standard_HB176-144rs_v4`). When naming sizes to users, use only the public examples above.

## Terms
- **vCPU**: VM-visible processor ID `0-175`. **vNUMA**: VM-visible NUMA node `0-3`.
- **Pcore**: host processor ID from the Hyper-V `Ideal Cpu` counter. **Pnuma**: host NUMA node of the Pcore. **PCCD**: physical AMD CCD of the Pcore.
- A guest can't pin to a Pcore; guest affinity always uses vCPU IDs.
- A range mapping like `0-7 -> 16-23` is ordered: vCPU 0 → Pcore 16, vCPU 1 → Pcore 17, and so on.

## Invariants
- 176 vCPUs in four vNUMA nodes of 44: vNUMA = `floor(vCPU / 44)` (0-43, 44-87, 88-131, 132-175). Each vNUMA node maps to the physical NUMA node with the same number, and every vCPU stays local to it.
- Host: 192 Pcores (`0-191`), four physical NUMA nodes, 24 CCDs (`0-23`). The VM gets 176; 16 Pcores are unmapped.
- CCDs normally contribute 8 cores; CCDs `0, 1, 6, 7, 12, 13, 18, 19` contribute 6 each (the 16-core difference).
- Pnuma 0 uses CCDs `0, 2, 4, 6, 8, 10`; Pnuma 1 `1, 3, 5, 7, 9, 11`; Pnuma 2 `12, 14, 16, 18, 20, 22`; Pnuma 3 `13, 15, 17, 19, 21, 23`.
- Never infer Pcore or PCCD from the vCPU number; use the mapping table.

## Guest L3 view vs physical CCDs
The OS `L3ProcessorDistributionPolicy` splits each 44-vCPU node into six guest L3 groups:

| Policy | Cores per guest L3 group |
|---:|---|
| 0 | `4:8:8:8:8:8` |
| 1 | `8:8:8:8:8:4` |
| 2 | `7:7:7:7:8:8` |
| 3 | `8:8:7:7:7:7` |

The physical allocation (`8:8:8:8:6:6`) isn't a supported option, so policy 1 is used as the closest match. Guest L3 IDs from `lscpu -e` show which policy is active; they are **not** a physical CCD map.

Example (policy 1): the guest groups vCPUs `32-39` under one L3 ID and `40-43` under the next. Physically, `32-37` are on PCCD 0 (Pcores `2-7`), while `38-39` (Pcores `54-55`) and `40-43` (Pcores `50-53`) share PCCD 6. So `38-43` share a CCD even though the guest splits them, and guest group `32-39` spans two CCDs.

## Required guest topology signature
Collect with `LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE`. Expected: all 176 CPUs online, `CORE` = `CPU`, and `L1d`, `L1i`, `L2` all equal the private-cache ID below.

| CPU range | NUMA | Socket | Private-cache ID | L3 groups (policy 1, `8:8:8:8:8:4`) |
|---:|---:|---:|---:|---|
| 0-43 | 0 | 0 | CPU | `0-7→0`, `8-15→1`, `16-23→2`, `24-31→3`, `32-39→4`, `40-43→5` |
| 44-87 | 1 | 0 | CPU + 4 | `44-51→6`, `52-59→7`, `60-67→8`, `68-75→9`, `76-83→10`, `84-87→11` |
| 88-131 | 2 | 1 | CPU + 40 | `88-95→16`, `96-103→17`, `104-111→18`, `112-119→19`, `120-127→20`, `128-131→21` |
| 132-175 | 3 | 1 | CPU + 44 | `132-139→22`, `140-147→23`, `148-155→24`, `156-163→25`, `164-171→26`, `172-175→27` |

Expected L3 ID for CPU `c`: `[0, 6, 16, 22][floor(c/44)] + min(floor((c mod 44)/8), 5)`.

Read-only checker (run from the repo root; confirm the VM is a covered size first):
```bash
bash .github/skills/azure-hbv4-hx176-topology/scripts/check-topology.sh
```
It validates every row (duplicates, missing/offline CPUs, all cache IDs) and exits nonzero on a mismatch or collection failure. It doesn't change affinity, build a CCD map, query Azure metadata, or run benchmarks. STREAM uses it; other workflows should reuse it rather than writing their own parser.

**Any difference** in CPU count, online state, NUMA ranges, socket, core numbering, private-cache IDs, or the L3 signature is a reportable discrepancy, even if the workload runs. Capture the full `lscpu -e` output, SKU, image, and kernel; don't reinterpret the output as a physical map. First rule out a wrong SKU, offline CPUs, boot configuration, or a known OS/kernel setting; otherwise classify `possible-platform-or-node-health` and prepare the escalation bundle.

## vCPU → host mapping
All ranges are ordered. Rows are split where the Pcore order is non-monotonic; don't merge or reorder them.

| vNUMA/Pnuma | PCCD | vCPU | Pcore |
|---:|---:|---:|---:|
| 0 | 2 | 0-7 | 16-23 |
| 0 | 4 | 8-15 | 32-39 |
| 0 | 8 | 16-23 | 64-71 |
| 0 | 10 | 24-31 | 80-87 |
| 0 | 0 | 32-37 | 2-7 |
| 0 | 6 | 38-39 | 54-55 |
| 0 | 6 | 40-43 | 50-53 |
| 1 | 3 | 44-51 | 24-31 |
| 1 | 5 | 52-59 | 40-47 |
| 1 | 9 | 60-67 | 72-79 |
| 1 | 11 | 68-75 | 88-95 |
| 1 | 1 | 76-81 | 10-15 |
| 1 | 7 | 82-83 | 62-63 |
| 1 | 7 | 84-87 | 58-61 |
| 2 | 14 | 88-95 | 112-119 |
| 2 | 16 | 96-103 | 128-135 |
| 2 | 20 | 104-111 | 160-167 |
| 2 | 22 | 112-119 | 176-183 |
| 2 | 12 | 120-125 | 98-103 |
| 2 | 18 | 126-127 | 150-151 |
| 2 | 18 | 128-131 | 146-149 |
| 3 | 15 | 132-139 | 120-127 |
| 3 | 17 | 140-147 | 136-143 |
| 3 | 21 | 148-155 | 168-175 |
| 3 | 23 | 156-163 | 184-191 |
| 3 | 13 | 164-169 | 106-111 |
| 3 | 19 | 170-171 | 158-159 |
| 3 | 19 | 172-175 | 154-157 |

**One vCPU:** reject IDs outside `0-175`; find its row, apply the same offset in the Pcore range, and report vCPU, vNUMA, Pcore, Pnuma, and PCCD. Example: vCPU 42 is in `40-43 -> 50-53`, offset 2 → Pcore 52, Pnuma 0, PCCD 6.

**CPUs sharing a CCD:** return every row with that PCCD; six-core CCDs may span two non-adjacent rows. Don't fill gaps.

**Affinity recommendations:**
- Use vCPU IDs, never Pcore IDs.
- Keep latency-sensitive communicating threads within one vNUMA node when possible.
- For an 8-thread group on one full CCD, use an 8-vCPU row. For the six-core CCDs, say the VM has only six cores from that CCD.
- Check the live `lscpu -e` first for numbering, NUMA placement, and the active L3 policy, but take CCD sharing from this table, not from guest L3 IDs.

This is a measured reference. Check the live VM before applying it, and report (don't override) any disagreement with live Hyper-V Ideal Cpu data or measured performance.
