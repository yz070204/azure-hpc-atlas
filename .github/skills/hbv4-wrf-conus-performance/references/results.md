# Historical HBv4 WRF results

Measurements below used WRF 4.4.2 on `Standard_HB176rs_v4`,
176 physical Zen 4 cores, four NUMA nodes,
Ubuntu 24.04, GCC/GFortran 13.3, and Open MPI 5.0.10.

These are observations, not guarantees. Rerun after image, compiler, MPI,
firmware, or WRF changes.

The current runbook targets WRF 4.2.2 with the same v4.2 dataset. Do not
relabel these 4.4.2 timings or use them as a measured baseline for the
4.2.2 default. Record source, dependency and launch differences in comparisons.

Historical build provenance:

```text
WRF v4.4.2 commit: 6233639c599119e76fca17dba9ea211af53a0ba9
NetCDF-C: 4.9.2
NetCDF-Fortran: 4.5.4
Fastest measured wrf.exe SHA-256: fdbe76eb664a59de4cf73a8a8b6aa70d8f3821a7c0d2d4a907e4e6647da3716d
```

The executable hash is specific to that build environment, not an acceptance
hash for a new WRF 4.2.2 build.

## v4.2 dataset with WRF 4.4.2

Dataset:

```text
https://www2.mmm.ucar.edu/wrf/users/benchmark/v422/v42_bench_conus2.5km.tar.gz
SHA-256: dcae9965d1873c1c1e34e21ad653179783302b9a13528ac10fab092b998578f6
```

Domain is 1501×1201×50, timestep 15 seconds, CONUS physics, `radt=3`, one-hour
restart. Results use 176 ranks, ordered CPUs `0-175`, and process grid 16×11.

| WRF 4.4.2 Fortran flags | Last-149 s/step | Wall time |
|---|---:|---:|
| `-O3 -march=znver2` | 2.742287 | 15:30.33 |
| `-O3 -march=znver4` | 2.738733 | 15:29.30 |
| `-O3 -march=znver2 -Ofast` | 2.612883 | 15:07.79 |
| `-O3 -march=znver4 -Ofast` | **2.580346** | **14:52.13** |

`-Ofast` supplied the main gain: 4.72% with `znver2` and 5.78% with
`znver4`. Switching `znver2` to `znver4` was 0.13% at `-O3` and 1.25% at
`-Ofast`.

## v4.4 workload

Dataset:

```text
https://www2.mmm.ucar.edu/wrf/users/benchmark/v44/v4.4_bench_conus2.5km.tar.gz
```

Same grid and timestep, but `radt=10`; therefore it is lighter than v4.2.

| Layout | Last-149 s/step | Wall time |
|---|---:|---:|
| 144 ranks, 12×12, reference HBv4 CPU list | 2.347363 | 14:04.02 |
| 176 ranks, 16×11 | 2.207473 | 13:56.51 |
| 168 ranks, 14×12, local NVMe | 2.185455 | 13:37.00 |

The 168-rank lead was about 1% from one trial. Keep 176 ranks for the
documented single-node baseline and repeat finalists before adopting a change.

## Artifact discovery

Do not assume a workspace path. Prefer explicit `WRF_ROOT`, `WRF_RUN_DIR`, and
`WRF_DATA_DIR` values when provided. Otherwise use `scripts/inventory.sh` to
search the home directory and non-root local filesystems for likely artifacts.

## Storage

RAID0 NVMe is not required for the runbook's `Timing for main` metric;
that metric excludes initialization and WRF output writes. Fast local scratch
can reduce restart staging and end-to-end wall time. Treat RAID0 as temporary,
non-redundant storage and obtain approval before formatting devices.

Observed at 168 ranks on the v4.4 case:

| Storage | Last-149 s/step | Wall time | Final output write |
|---|---:|---:|---:|
| Managed temporary disk | 2.184939 | 13:48.62 | 31.86 s |
| Two local NVMe RAID0 | 2.185455 | 13:37.00 | 29.80 s |

The compute metric was unchanged; RAID0 reduced wall time by about 11.6 seconds
and final-output time by about 2.1 seconds in this run.

### Multi-node storage pattern

Use one of these patterns and benchmark it:

1. **Simple/shared:** Put executable, tables, restart input, and output on NFS.
   This is easiest and provides one common path, but a single NFS server may
   bottleneck concurrent startup, metadata, restart reads, or output.
2. **Preferred staged:** Keep a shared authoritative copy, then stage the
   executable, read-only tables, and required input files to the same local
   path on every node. Use node-local NVMe or RAID0 where available.
3. **Output:** Write to a measured high-throughput shared filesystem when all
   nodes need shared visibility. If the selected WRF I/O mode permits output
   through designated/root ranks, writing to local scratch and copying results
   afterward may be faster, but verify correctness and failure recovery.

Before claiming a storage improvement, keep compute configuration fixed and
report separately:

- last-149 `Timing for main`;
- initialization and restart-read time;
- each `Timing for Writing` record;
- total wall time;
- output size and filesystem;
- NFS/server/network saturation.

For multi-node comparison, every node must see either the same shared path or
an identical staged directory. Do not create RAID0 or an NFS server without
approval; both affect data durability and system configuration.

## Numerical caution

`-Ofast` relaxes IEEE behavior. Compare numerical output with an appropriate
reference and define acceptance tolerances for the scientific workflow before
using it in production. Prefer `-O3` when strict reproducibility is required.
