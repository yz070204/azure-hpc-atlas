# Isolating physical-CCD balance on HBv4

## Finding

**At the same 144 threads and 36 threads per NUMA node, balanced placement
across physical CCDs materially outperformed uneven placement.** This is
evidence of a placement effect independent of lowering total thread count.

On 2026-09-17, eight randomized comparison blocks at 280M elements per array
gave:

| Threads per physical CCD within each NUMA | Total threads | Median best Triad MB/s | Observed range MB/s | Median average-time Triad MB/s |
|---|---:|---:|---:|---:|
| **6:6:6:6:6:6** | **144** | **839422.90** | **836669.5-841993.2** | **822118.96** |
| 8:8:6:6:4:4 | 144 | 737247.90 | 734022.3-739123.2 | 729839.98 |
| 4:4:8:8:6:6 | 144 | 747245.40 | 746582.3-749341.3 | 741681.30 |

The balanced layout won **all eight blocks against both uneven controls**.
Its best-rate median was **13.86%** above `8:8:6:6:4:4` and **12.34%** above
`4:4:8:8:6:6`. The observed ranges did not overlap. These percentages compare
ratios of medians; individual paired improvements ranged **13.20-14.38%** and
**11.72-12.78%**, respectively. Average-time bandwidth improved too.

Two further controls strengthen the conclusion:

- Selecting different cores while preserving six per CCD retained the benefit.
- At **1.3B elements per array**, balanced placement remained **16.36% faster**
  than `8:8:6:6:4:4`, so the placement advantage is not confined to the
  smaller, more cache-sensitive array.

This establishes a robust **placement effect for the tested node, binary and
workloads**. It does not directly measure CCD-link saturation, cache misses,
per-thread barrier waiting, or explain the entire earlier 176-to-144 change.
CPU selection and thread-to-data assignment necessarily change with affinity;
the rotated-core control reduces, but cannot eliminate, all CPU-identity
alternatives. Validate other SKUs separately.

These source-build results were later replicated as a placement effect in
[AMD's prebuilt STREAM](prebuilt-tuning.md), using that binary's fixed
650M/10 workload. That is separate evidence, not an assumption that the source
and prebuilt implementations are identical.

## What was held fixed

All comparisons used the same `Standard_HB176rs_v4` node and image as
[the tuning study](tuning.md), AOCC 4.0.0, the pinned source and original
flags, **100 iterations**, **144 threads**, and **36 threads in each NUMA node**.
All **24 physical CCDs** remained active. Within each array-size comparison,
the executable and its checksum were identical.

THP allocation and defrag stayed `always` during trials; cache drops were
disabled. OpenMP used `GOMP_CPU_AFFINITY` with the selected CPU list,
`OMP_SCHEDULE=static`, dynamic disabled, thread limit 512, stack 256M,
and runtime affinity logging. The inherited NUMA policy was `default`, with
parallel first touch. Runtime output confirmed the requested/counted 144
threads and the exact expected singleton CPU set in every trial.

Only the explicit affinity list changed in the primary comparison. The two
uneven lists put the eight-thread groups on different physical CCDs, reducing
dependence on one particular overloaded pair.

The harness randomized case order within each block using a retained seed,
checked quiet-node conditions, and capped each trial at 120 seconds with
five-second termination grace. No build work overlapped benchmarking.
This was a quiet shared VM, not a scheduler-enforced exclusive allocation.
The eight blocks are repeated measurements on one node, not eight independent
machines; no population confidence interval or universal performance threshold
is inferred from them.

There were **44 timing trials** (24 primary, 12 rotated-core, eight large-array)
and **three separate memory-diagnostic trials**. All 47 completed with
successful numerical validation and exact expected thread binding.
Diagnostic trials were excluded from the timing tables. THP values were
restored to the original `madvise` settings after every phase and verified.

## Physical mapping and repeatable masks

Use the exact [HBv4 topology mapping](../../azure-hbv4-hx176-topology/SKILL.md),
not guest L3 IDs. Per NUMA node, the six physical groups correspond to these
guest CPU offsets:

```text
0-7, 8-15, 16-23, 24-31, 32-37, 38-43
```

For each NUMA base `0,44,88,132`, select the following offsets:

| Case | CPU offsets relative to each NUMA base |
|---|---|
| Balanced, low cores | `0-5,8-13,16-21,24-29,32-37,38-43` |
| Uneven 8:8:6:6:4:4 | `0-7,8-15,16-21,24-29,32-35,38-41` |
| Uneven 4:4:8:8:6:6 | `0-3,8-11,16-23,24-31,32-37,38-43` |
| Balanced, high cores | `2-7,10-15,18-23,26-31,32-37,38-43` |

Every row selects exactly 36 unique CPUs per NUMA and keeps all six physical
CCDs active. Balanced low/high select different six-core subsets of the
eight-core groups while keeping the two six-core groups fully used.
The last physical group spans guest-reported L3 groups on this VM; grouping
by guest cache ID would not reproduce the intended experiment.

The runner exposes the balanced profile, not an unrestricted CPU-list tuning
interface. To repeat the controls in a separate approved experiment, use the
masks and fixed conditions above, randomize trial order and record the seed.
Keep array size, iterations, environment and THP fixed when testing placement.

## Primary trial results

Best Triad in **MB/s**, paired by randomized block:

| Block | Balanced 6:6:6:6:6:6 | Uneven 8:8:6:6:4:4 | Uneven 4:4:8:8:6:6 |
|---:|---:|---:|---:|
| 1 | 841993.2 | 736111.9 | 746582.3 |
| 2 | 839585.4 | 737093.6 | 748088.3 |
| 3 | 839260.4 | 737575.8 | 746582.3 |
| 4 | 837166.5 | 734022.3 | 749341.3 |
| 5 | 837987.9 | 737402.2 | 747077.0 |
| 6 | 836669.5 | 739123.2 | 747413.8 |
| 7 | 840111.0 | 737498.6 | 749241.7 |
| 8 | 840010.8 | 735305.3 | 746740.6 |

All-kernel best-rate medians:

| Placement | Copy MB/s | Scale MB/s | Add MB/s | Triad MB/s |
|---|---:|---:|---:|---:|
| Balanced | 706515.35 | 712583.95 | 846240.20 | 839422.90 |
| Uneven 8:8:6:6:4:4 | 635468.45 | 636178.35 | 743235.60 | 737247.90 |
| Uneven 4:4:8:8:6:6 | 644834.65 | 646009.85 | 754082.65 | 747245.40 |

## Rotated-core control

Four randomized blocks, still 280M elements, 100 iterations and 144 threads:

| Placement | Median best Triad MB/s | Observed range MB/s | Median average-time Triad MB/s |
|---|---:|---:|---:|
| Balanced low cores | 840837.90 | 839160.5-841792.0 | 821014.25 |
| Balanced high cores | 842584.75 | 840411.6-846570.6 | 824186.63 |
| Uneven 8:8:6:6:4:4 | 738833.90 | 737093.6-741553.9 | 732586.01 |

Both balanced variants beat the uneven case in every block. Their own ranges
overlap; the small difference between the balanced masks does not justify
changing the production mask or claiming a superior set of individual cores.

## Large-array control

Four randomized blocks at **1,300,000,000 doubles per array** (10.4 GB per
array, 31.2 GB total), 100 iterations and the same 144-thread masks:

| Placement | Median best Triad MB/s | Observed range MB/s | Median average-time Triad MB/s |
|---|---:|---:|---:|
| Balanced 6:6:6:6:6:6 | **755320.80** | 753298.6-757191.0 | **748318.17** |
| Uneven 8:8:6:6:4:4 | 649100.80 | 647948.6-651085.3 | 645341.45 |

Best Triad per block:

| Block | Balanced | Uneven |
|---:|---:|---:|
| 1 | 755870.1 | 647948.6 |
| 2 | 757191.0 | 649134.6 |
| 3 | 753298.6 | 649067.0 |
| 4 | 754771.5 | 651085.3 |

The balanced advantage remains in both best and average-time rates with
the larger working set. It is therefore not confined to the smaller 280M
workload. See [array sizing and interpretation](diagnosis.md#choosing-array-size);
STREAM reports algorithmic bandwidth, not memory-controller traffic.

## Memory-allocation checks

Separate 280M diagnostic runs sampled the benchmark child's memory one second
after launch:

| Placement | Anonymous kB | AnonHugePages kB |
|---|---:|---:|
| Balanced | 6567744 | 6559744 |
| Uneven 8:8:6:6:4:4 | 6567748 | 6559744 |
| Uneven 4:4:8:8:6:6 | 6567748 | 6559744 |

All had approximately 99.9% anonymous huge-page coverage and roughly equal
anonymous page totals across the four NUMA nodes. Gross THP-coverage or
node-level allocation differences therefore do not explain the diagnostic
cases. Snapshots are not continuous proof for every trial, and equal node
totals do not establish per-thread locality.

## Mechanism: supported explanation versus unmeasured detail

With approximately equal per-thread STREAM partitions, CCD work is proportional
to its active thread count. In `8:8:6:6:4:4`, the eight-thread CCDs receive twice
the work of the four-thread CCDs. Uniform `6:6:6:6:6:6` distributes work evenly
across CCD-local shared resources and paths to the I/O die. If those paths or
shared resources are limiting, an overloaded group can determine whole-kernel
completion while other groups finish earlier.

The source loops have no explicit schedule clause. The unchanged compiler/
runtime determines their default partitioning; `OMP_SCHEDULE=static` alone
does not prove it, because that variable controls `schedule(runtime)` loops.
Per-thread iteration counts were not instrumented. Equal work per thread is
a mechanism assumption here, not another directly measured result.

The fixed-thread placement tests, rotated-core control and large-array
replication are consistent with that mechanism. They establish that the
CCD-aware distribution is useful independently of total thread count.
They do **not** isolate whether the limiting resource is a CCD data link,
cache bandwidth/capacity, translation, thread scheduling, or another shared
resource. Barrier waiting, frequency and per-CCD traffic were not measured.
The original 176-thread pattern `8:8:8:8:6:6` is less skewed than these
deliberate 144-thread controls; do not apply their 12-16% gaps to the original
176-to-144 comparison, which measured a much smaller best-rate improvement.

## Transfer to another SKU

The reusable hypothesis is **balance work across physical sharing/bandwidth
domains while maintaining enough concurrent memory requests**, not "use 144"
or "six is always optimal". A different SKU may have different CCD counts,
exposed cores, cache size, memory channels and saturation points.

For another SKU, verify its actual physical mapping, hold total threads,
threads per NUMA, active CCD count, executable, memory policy and workload
fixed, then randomize balanced/uneven placements and repeat. Include a rotated-
core control and a large-array comparison.
Do not copy this HBv4 CPU list or promote it to a cross-SKU invariant.

For new measurements, retain masks, trial order, raw logs, build/runtime
identities, load samples and THP restoration records in a new output directory.
Original raw run archives are not distributed with this repository.
