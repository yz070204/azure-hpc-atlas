# HBv4 STREAM build and launch comparisons

These measurements compare the source and AMD prebuilt workflows on one
`Standard_HB176rs_v4`. The default is the original source recipe at 176 threads
with THP always; AMD prebuilt is used when requested. See the
[runbook](../SKILL.md) for commands and [tuning study](tuning.md) for optional
144-thread placement.

## Test environment

Measurements were collected on 2026-09-17 using AMD EPYC 9V33X, 176 exposed
CPUs, four 44-CPU NUMA nodes, Ubuntu 24.04.4 LTS and kernel
`6.8.0-1064-azure`. CPU and memory-node access covered the full VM, with no
finite cgroup CPU or memory caps. Sampled CPU idle time was approximately 99%.
Results describe a quiet shared VM; they are observations, not performance
guarantees.

Source builds used AOCC 4.0.0 and the [documented source and flags](usage.md).
All trials passed numerical validation and actual 176-thread binding checks.
Each trial had a 120-second timeout plus five-second termination grace.
Rates below are medians or individual best-iteration rates as labeled,
excluding STREAM's first iteration.

## Matched source versus prebuilt: 650M elements, 10 iterations

Both binaries used 650M doubles per array, 176 threads, OMP core binding,
static schedule, dynamic disabled, thread limit 512, stack 256M and
`numactl --localalloc`. THP allocation/defrag remained `madvise`; no cache
drops were performed. This is the explicit `normalized-176` comparison
profile, not either original default launch.

Values are decimal **GB/s** (`MB/s / 1000`).

| Candidate / trial | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| Prebuilt 1 | 708.3017 | 711.5948 | 759.6436 | 753.4765 |
| Prebuilt 2 | 703.0731 | 701.7158 | 722.9881 | 744.0938 |
| Prebuilt 3 | 708.1982 | 708.5894 | 756.9194 | 756.1759 |
| **Prebuilt median** | **708.1982** | **708.5894** | **756.9194** | **753.4765** |
| Source 1 | 709.3153 | 709.9502 | 760.7122 | 728.5994 |
| Source 2 | 706.2833 | 706.6151 | 754.1365 | 752.3502 |
| Source 3 | 708.7275 | 708.1637 | 751.2273 | 750.8652 |
| **Source median** | **708.7275** | **708.1637** | **754.1365** | **750.8652** |

The 0.35% difference in median Triad was smaller than run-to-run variation:
prebuilt spanned 744.0938-756.1759 GB/s and source 728.5994-752.3502 GB/s.
This comparison does not establish a build-method performance advantage.
Matching dimensions also does not imply identical generated code or runtime
implementations.

Trial order was prebuilt 1, source 1, prebuilt 2, source 2, prebuilt 3, source 3.
The first prebuilt trial used the same benchmark settings but retained `HOME`
in the clean environment. NUMA page distribution was not sampled.

## Original source dimensions with normalized launch: 280M/100

Three trials changed the source build to 280M doubles per array and 100
iterations while retaining the normalized launch above. This compares
workloads; array size and iteration count both changed.

| Trial | Copy GB/s | Scale GB/s | Add GB/s | Triad GB/s |
|---|---:|---:|---:|---:|
| 1 | 695.8665 | 698.7907 | 826.8518 | 806.5277 |
| 2 | 695.2228 | 698.5829 | 828.3827 | 809.3531 |
| 3 | 693.2734 | 696.8471 | 814.2397 | 795.7348 |
| **Median** | **695.2228** | **698.5829** | **826.8518** | **806.5277** |

Triad spanned 795.7348-809.3531 GB/s. To repeat this configuration, explicitly
select `STREAM_PROFILE=normalized-176` with the original source binary.

## Original source build and launch: 280M/100

Three trials used the same original source binary with:

- 176 threads, `GOMP_CPU_AFFINITY=0-175`, static schedule, dynamic disabled,
  thread limit 512 and stack 256M.
- No OMP/KMP affinity overrides or NUMA wrapper; inherited NUMA policy was default.
- `sync` and `drop_caches=3` before each trial, with both THP controls `always`.
- The vendor AOCC environment, with library resolution confirming AOCC 4.0.0
  `libomp.so`.

Values are **MB/s**.

| Trial | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 1 | 691894.9 | 693810.9 | 824939.9 | 817427.7 |
| 2 | 694477.7 | 697183.2 | 829724.0 | 824650.3 |
| 3 | 693299.0 | 696847.1 | 823133.1 | 818020.7 |
| **Median** | **693299.0** | **696847.1** | **824939.9** | **818020.7** |

Triad spanned 817427.7-824650.3 MB/s. Multiple launch factors changed together,
so this is not an isolated THP, affinity or cache-drop test. THP settings were
restored after the batch; cache drops cannot be undone.

The current `source-original` helper reproduces these explicit benchmark
settings using a clean process-local AOCC environment instead of sourcing an
inherited shell. THP changes and cache drops require separate approval.

## Reproducing and interpreting results

Use the [preparation and launch reference](usage.md), including its
[matched-comparison commands](usage.md#explicit-matched-comparison).
Keep new output directories and retain the generated build/run manifests,
raw logs, library identities, load samples and restoration records.
Original raw run archives are not distributed with this repository.

Compare like-sized workloads under matching launch conditions. For larger-
than-cache characterization and the meaning of STREAM's bandwidth metric,
see [array sizing and interpretation](diagnosis.md#choosing-array-size).
