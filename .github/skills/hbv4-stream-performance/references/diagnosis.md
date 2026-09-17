# Diagnosing a STREAM result

Load this reference for a performance question, not for every routine run.
First recover the user's actual binary/build manifest, launch command,
environment and raw output. Do not replace the slow test with a faster,
differently sized workload and declare it fixed.

## Comparison checklist

| Check | Evidence / interpretation |
|---|---|
| Metric | Which kernel? Decimal MB/s or GB/s (`MB/s / 1000`)? Best iteration, average-time rate or median across trials? |
| Arrays | Elements **per array**, element width, total memory. 280M doubles = 6.72 GB total; 650M = 15.6 GB; 1.3B = 31.2 GB |
| Iterations | Source baseline 100; AMD 2024_10_08 fixed at 10, no documented runtime change. Best-time statistic excludes the first iteration |
| Compiler/build | Source hash, AOCC version, original flags, CPU ISA, binary hash and runtime resolution. Never infer an old build from today's compiler |
| Affinity | Requested versus counted threads and actual binding. Original source: GOMP 0-175. Original prebuilt: OMP core binding. Conflicting OMP/GOMP/KMP variables can override intent |
| Physical CCDs | Full-size HBv4 is physically `8:8:8:8:6:6` per NUMA, not the guest L3 signature. Balanced 144 uses `6:6:6:6:6:6`; not CPUs 0-143 |
| NUMA/resources | Default versus inherited interleave/bind/localalloc policy, first touch, allowed CPUs/memory nodes, ancestor cgroup quotas and memory limits |
| Host state | THP enabled **and** defrag, actual huge-page coverage if needed, load, pressure, other jobs. Cache dropping is not a substitute for idle allocation |
| Correctness | Successful validation, all kernels present, finite timings/rates, full completion, repeated results; exit zero alone is insufficient |

Change one factor at a time after approval. Repeat paired candidates under
matched conditions. Retain failures and outliers. If evidence is insufficient,
say `inconclusive`, not hardware failure. Escalation requires the
[first-line triage procedure](../../hpc-atlas-firstline-triage/SKILL.md).

## Observed baselines, not thresholds

One HBv4 node, AOCC 4.0.0/source or AMD prebuilt 2024_10_08, original flags,
THP allocation/defrag always unless noted. These medians come from **separate
phases**, not one perfectly matched comparison. Rates are decimal **MB/s**.

| Build / launch | Elements | Iterations | Threads | THP | Median Triad |
|---|---:|---:|---|---|---:|
| Source original, cache drop | 280M | 100 | 176 | always | 818020.70 |
| Source balanced | 280M | 100 | 144 | always | 841681.15 |
| Source balanced | 650M | 100 | 144 | always | 778072.55 |
| Source balanced | 1.3B | 100 | 144 | always | 755320.80 |
| Prebuilt original | 650M | 10 | 176 | madvise | 745886.50 |
| Prebuilt original | 650M | 10 | 176 | always | 758270.45 |
| Prebuilt balanced | 650M | 10 | 144 | always | 774710.10 |

Array size materially changes the measured rate: approximately 842 GB/s at
280M versus 755 GB/s at 1.3B. At 1.3B, balanced placement improved Triad
from 649 to 755 GB/s (16.36%) relative to the uneven 144-thread control.

## What tuning established

- Six threads per physical CCD improved the measured source and prebuilt
  workloads. At equal 144 threads, uneven controls were slower; rotating cores
  and using large arrays retained the benefit. Specific cache/link/barrier
  mechanisms remain unmeasured; do not generalize the CPU list to another SKU.
- Source 96 versus 144 was close; 144 is not a universal optimum or necessarily
  best for every kernel. Keep the user's default at 176 unless tuning is requested.
- THP always produced real huge pages in source-process probes. Do not treat
  source snapshots as evidence of prebuilt allocation or assume sysfs proves
  huge-page coverage in every run.
- Cache drops showed no consistent benefit on the quiet test node. They remain
  in the **original source reproduction** only, behind explicit approval.
- More iterations provide more opportunities for a best-time result. Small-array
  best rates improved more than average-time rates in size controls; numerical
  success does not establish cache-independent DRAM bandwidth.

## Choosing array size

The [official rule](https://www.cs.virginia.edu/stream/ref.html#size) requires
each array to be at least four times the sum of last-level caches used, or
one million elements, whichever is larger. The source also requires at least
20 timer ticks in calibration.

This node reports 24 x 96 MiB L3 = 2304 MiB. For doubles, that sizing guidance
corresponds to **1,207,959,552 elements per array**. Use 1.3B for a separately
scoped larger-than-cache comparison. Both 144 and 176 placements use all
24 CCDs, so the cache total is unchanged.

Keep 280M for the original source baseline and 650M for the fixed AMD binary.
These smaller workloads are useful for regression and placement comparisons,
but can be more cache-sensitive. Label the array size in every result rather
than treating different sizes as interchangeable DRAM measurements. STREAM
reports algorithmic bytes divided by time, not measured memory-controller traffic.

## Load detailed evidence only as needed

| Question | Reference |
|---|---|
| Initial builds, original source launch | [results.md](results.md) |
| Array size, THP, cache-drop, thread sweep, 650M follow-up | [tuning.md](tuning.md) |
| Equal-thread physical-CCD balance and large-array replication | [ccd-balance.md](ccd-balance.md) |
| AMD prebuilt, original versus tuned, THP-always baseline | [prebuilt-tuning.md](prebuilt-tuning.md) |

Keep exact provenance and comparison scope in the response; no universal
pass/fail bandwidth threshold follows from these experiments.
