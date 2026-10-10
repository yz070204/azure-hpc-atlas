---
name: azure-hbv5-368-topology
description: Guest topology and supplied host NUMA/CCD membership for Standard_HB368rs_v5. Use for topology checks, CCD grouping, and affinity. Pcore ranges are unordered sets. Not for constrained-core sizes.
user-invocable: false
---

# Azure HBv5 368-vCPU topology

**Status: measured guest signature and supplied host/CCD membership available; a [single-VM STREAM reference](../stream-performance/references/stream-reference-hbv5.md) is available, with other calibrated workload coverage pending.** Applies only to `Standard_HB368rs_v5`, not constrained-core sizes such as `Standard_HB368-336rs_v5`. Public specifications are in `azure-hpc-vm-specifications` ([HBv5 reference](../azure-hpc-vm-specifications/references/hbv5.md)).

## Terms

- **vCPU**: VM-visible processor ID. **vNUMA**: VM-visible NUMA node.
- **Pcore**: host processor ID from Hyper-V `Ideal Cpu` data. **Pnuma**: host NUMA node of the Pcore. **PCCD**: physical AMD CCD of the Pcore.
- Guest affinity uses vCPU IDs, never Pcore IDs. Guest L3 IDs are not physical CCD IDs; use the supplied membership table for physical grouping.

## Invariants

- Guest: 368 online vCPUs (`0-367`), 16 vNUMA nodes (`0-15`) of 23 cores, four sockets (`0-3`) of 92 cores, SMT disabled.
- vNUMA = `floor(vCPU / 23)`; socket = `floor(vNUMA / 4)`; guest `CORE` = `CPU`.
- Supplied host reference: 384 Pcores (`0-383`), 16 physical NUMA nodes, four sockets, and 48 CCDs (`0-47`). Each vNUMA node maps to the same-numbered Pnuma; socket = `floor(Pnuma / 4)`. Pnuma `n` contains CCDs `3*n`, `3*n+1`, and `3*n+2`, exposing 7, 8, and 8 cores respectively.
- The supplied sample leaves 16 Pcores unexposed, one per physical NUMA node (`24*n` for `n = 0-15`). Do not assume an ordered vCPU-to-Pcore offset or use HBv4/HX mappings.

## Guest L3 view vs physical CCDs

Each measured guest NUMA node exposes three L3 groups of `8:8:7` cores: 48 groups total (32 eight-core, 16 seven-core). Guest L3 IDs are not contiguous across sockets. Their membership matches the supplied CCD groups, but the IDs differ: in vNUMA `n`, the first eight-vCPU group belongs to PCCD `3*n+1`, the second to `3*n+2`, and the last seven-vCPU group to `3*n`. For example, guest L3 IDs `0, 1, 2` correspond by membership to PCCDs `1, 2, 0`. The guest and host evidence were collected separately; guest L3 IDs alone do not establish physical CCD placement.

## Required guest topology signature

Measured 2026-10-07 on IMDS-confirmed `Standard_HB368rs_v5`, CPU model `EPYC 9V64H CPU`, Ubuntu HPC image `microsoft-dsvm:ubuntu-hpc:2404:24.04.2026092501`, kernel `6.8.0-1067-azure`. This is a single-VM guest reference, not a confirmed signature for every image/kernel or a host mapping.

Collect with `LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE`. All 368 CPUs must be present once and online; `CORE` equals `CPU`. `L1d`, `L1i`, and `L2` each equal the private-cache ID below.

| CPU range | NUMA | Socket | Private-cache ID | Guest L3 groups |
|---:|---:|---:|---|---|
| 0-22 | 0 | 0 | CPU | `0-7→0`, `8-15→1`, `16-22→2` |
| 23-45 | 1 | 0 | CPU + 1 | `23-30→3`, `31-38→4`, `39-45→5` |
| 46-68 | 2 | 0 | CPU + 2 | `46-53→6`, `54-61→7`, `62-68→8` |
| 69-91 | 3 | 0 | CPU + 3 | `69-76→9`, `77-84→10`, `85-91→11` |
| 92-114 | 4 | 1 | CPU + 36 | `92-99→16`, `100-107→17`, `108-114→18` |
| 115-137 | 5 | 1 | CPU + 37 | `115-122→19`, `123-130→20`, `131-137→21` |
| 138-160 | 6 | 1 | CPU + 38 | `138-145→22`, `146-153→23`, `154-160→24` |
| 161-183 | 7 | 1 | CPU + 39 | `161-168→25`, `169-176→26`, `177-183→27` |
| 184-206 | 8 | 2 | CPU + 72 | `184-191→32`, `192-199→33`, `200-206→34` |
| 207-229 | 9 | 2 | CPU + 73 | `207-214→35`, `215-222→36`, `223-229→37` |
| 230-252 | 10 | 2 | CPU + 74 | `230-237→38`, `238-245→39`, `246-252→40` |
| 253-275 | 11 | 2 | CPU + 75 | `253-260→41`, `261-268→42`, `269-275→43` |
| 276-298 | 12 | 3 | CPU + 108 | `276-283→48`, `284-291→49`, `292-298→50` |
| 299-321 | 13 | 3 | CPU + 109 | `299-306→51`, `307-314→52`, `315-321→53` |
| 322-344 | 14 | 3 | CPU + 110 | `322-329→54`, `330-337→55`, `338-344→56` |
| 345-367 | 15 | 3 | CPU + 111 | `345-352→57`, `353-360→58`, `361-367→59` |

Equivalent formulas for CPU `c`: `n = floor(c/23)`, `s = floor(n/4)`, private-cache ID = `c + 36*s + (n mod 4)`, L3 ID = `16*s + 3*(n mod 4) + floor((c mod 23)/8)`.

Run the [shared checker](../../scripts/check-topology.sh) from the repo root after IMDS confirms `Standard_HB368rs_v5`:
```bash
bash .github/scripts/check-topology.sh hbv5
```
The family selects the signature; no exact SKU is passed. The script does not query IMDS or verify SKU eligibility; do not use this profile on constrained-core or other unsupported sizes. It checks all CPU rows, online state, NUMA/socket/core numbering, and cache IDs, and exits nonzero on a mismatch or collection failure. It is read-only and does not validate physical CCD placement.

A pass means only that the guest matches this measured signature, not that the VM is healthy or workloads are calibrated. Report differences with this measured signature and capture SKU, image, kernel, and complete output. Rule out a wrong size, offline CPUs, and guest configuration before treating a difference as a possible platform issue; a numbering difference alone is not proof of a fault.

Read-only evidence to accompany the mapping:

```bash
LC_ALL=C lscpu
LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE
lstopo-no-graphics --no-io --no-legend --of txt
uname -r
```

Record exact VM size, resolved image version, collection date, and host-side mapping provenance. Guest output alone cannot establish Pcore/PCCD placement.

## vCPU -> host mapping

### Mapping validation

Checked: all 368 vCPUs appear once, all 368 Pcores are unique, Pcore values agree with Hyper-V `Ideal Cpu` counters, and membership sizes match. The 16 unexposed host Pcores are `0, 24, 48, 72, 96, 120, 144, 168, 192, 216, 240, 264, 288, 312, 336, 360`.

Physical NUMA/CCD labels come from the supplied host reference; compare live evidence before applying the mapping.

### CCD membership

**Ranges are unordered membership sets.** For example, vCPUs `0-7` map in the raw sample to Pcores `14, 9, 10, 13, 12, 15, 8, 11`, not ordered `8-15`. Use the table for CCD membership; use raw counters for exact per-core mapping.

| vNUMA | Pnuma | PCCD | vCPU members | Pcore members |
|---:|---:|---:|---|---|
| 0 | 0 | 0 | 16-22 | 1-7 |
| 0 | 0 | 1 | 0-7 | 8-15 |
| 0 | 0 | 2 | 8-15 | 16-23 |
| 1 | 1 | 3 | 39-45 | 25-31 |
| 1 | 1 | 4 | 23-30 | 32-39 |
| 1 | 1 | 5 | 31-38 | 40-47 |
| 2 | 2 | 6 | 62-68 | 49-55 |
| 2 | 2 | 7 | 46-53 | 56-63 |
| 2 | 2 | 8 | 54-61 | 64-71 |
| 3 | 3 | 9 | 85-91 | 73-79 |
| 3 | 3 | 10 | 69-76 | 80-87 |
| 3 | 3 | 11 | 77-84 | 88-95 |
| 4 | 4 | 12 | 108-114 | 97-103 |
| 4 | 4 | 13 | 92-99 | 104-111 |
| 4 | 4 | 14 | 100-107 | 112-119 |
| 5 | 5 | 15 | 131-137 | 121-127 |
| 5 | 5 | 16 | 115-122 | 128-135 |
| 5 | 5 | 17 | 123-130 | 136-143 |
| 6 | 6 | 18 | 154-160 | 145-151 |
| 6 | 6 | 19 | 138-145 | 152-159 |
| 6 | 6 | 20 | 146-153 | 160-167 |
| 7 | 7 | 21 | 177-183 | 169-175 |
| 7 | 7 | 22 | 161-168 | 176-183 |
| 7 | 7 | 23 | 169-176 | 184-191 |
| 8 | 8 | 24 | 200-206 | 193-199 |
| 8 | 8 | 25 | 184-191 | 200-207 |
| 8 | 8 | 26 | 192-199 | 208-215 |
| 9 | 9 | 27 | 223-229 | 217-223 |
| 9 | 9 | 28 | 207-214 | 224-231 |
| 9 | 9 | 29 | 215-222 | 232-239 |
| 10 | 10 | 30 | 246-252 | 241-247 |
| 10 | 10 | 31 | 230-237 | 248-255 |
| 10 | 10 | 32 | 238-245 | 256-263 |
| 11 | 11 | 33 | 269-275 | 265-271 |
| 11 | 11 | 34 | 253-260 | 272-279 |
| 11 | 11 | 35 | 261-268 | 280-287 |
| 12 | 12 | 36 | 292-298 | 289-295 |
| 12 | 12 | 37 | 276-283 | 296-303 |
| 12 | 12 | 38 | 284-291 | 304-311 |
| 13 | 13 | 39 | 315-321 | 313-319 |
| 13 | 13 | 40 | 299-306 | 320-327 |
| 13 | 13 | 41 | 307-314 | 328-335 |
| 14 | 14 | 42 | 338-344 | 337-343 |
| 14 | 14 | 43 | 322-329 | 344-351 |
| 14 | 14 | 44 | 330-337 | 352-359 |
| 15 | 15 | 45 | 361-367 | 361-367 |
| 15 | 15 | 46 | 345-352 | 368-375 |
| 15 | 15 | 47 | 353-360 | 376-383 |

For a vCPU, return its row's vNUMA, Pnuma, PCCD, and Pcore **set**, not an exact Pcore. For CCD sharing, return the row's vCPU members. Do not extend the table to constrained-core sizes.

## Affinity recommendations

- Confirm the full-size SKU and live guest topology. Report disagreements with host evidence; do not override them with this reference.
- Use vCPU IDs, never Pcore IDs. Keep latency-sensitive communicating threads within one vNUMA node where possible.
- For eight threads on one CCD, use an eight-vCPU row. Seven-vCPU rows expose only seven cores from that CCD.
- Validate performance and correctness with the workload. This mapping itself provides no benchmark targets; use the separate [HBv5 STREAM reference](../stream-performance/references/stream-reference-hbv5.md) only within its measured scope. HBv4/HX STREAM/WRF targets do not apply.
