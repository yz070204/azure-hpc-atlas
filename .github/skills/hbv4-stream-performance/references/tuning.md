# Controlled HBv4 STREAM tuning, 2026-09-17

## Optional tuning recommendation and confidence

For the **280,000,000-double-per-array, 100-iteration** source workload,
optional tuning uses **144 threads, six per physical CCD, THP allocation/defrag `always`,
no cache drops**, keeping AOCC 4.0.0 and the original flags.
Routine runs retain the original source recipe at 176 threads with THP always;
see [current workflow defaults](../SKILL.md). Do not apply tuning automatically.

Four randomized confirmation blocks measured median Triad **841515.55 MB/s**
versus **825036.75 MB/s** for the original 176-thread/cache-drop recipe:
**2.00% higher best-iteration bandwidth**. All four candidate trials exceeded
all four original-recipe trials. Median bandwidth derived from the printed
average iteration time improved **17.71%** (826419.62 versus 702061.81 MB/s).
This is a more useful sustained-kernel signal than comparing only the maxima.

The 96-thread option was only **0.29%** behind 144 in best-rate median, with
overlapping ranges; it is a credible lower-thread alternative. 144 had the
highest Triad median in both the initial sweep and confirmation, but is not a
statistically established winner over 96. Nor is it best for every kernel:
96 had higher Copy/Scale medians in confirmation.

Confidence is good for the repeated improvement over the original 176-thread
configuration **on this node and workload**. It is limited for choosing 144
over 96, extrapolating to other images/nodes, and explaining the microarchitecture.
No formal confidence interval, universal optimum, or hardware-health threshold
is claimed. Three or four repetitions do not characterize rare outliers.

## Fixed environment and design

One `Standard_HB176rs_v4`, AMD EPYC 9V33X, 176 guest CPUs, four NUMA nodes,
Ubuntu 24.04.4 LTS, kernel `6.8.0-1064-azure`. The complete guest topology
matched the [topology reference](../../azure-hbv4-hx176-topology/SKILL.md).
AOCC 4.0.0, pinned source and original flags are specified in
[the build reference](usage.md). All source profiles use **100 iterations** here.

Every case used the same OpenMP schedule/dynamic/thread-limit/stack settings,
explicit GOMP singleton affinity, default inherited NUMA policy, and
parallel first touch. OMP/KMP affinity controls were cleared before setting
the selected GOMP list; runtime display verified every actual thread binding.
The experiment harness sourced the vendor AOCC environment in a subshell.
It capped every trial at 120 seconds plus a five-second termination grace.

Three randomized blocks selected candidates; four separate randomized blocks
confirmed finalists. Randomization seeds were fixed before measurements.
All variants were interleaved within each phase to reduce
drift; build work did not overlap performance runs. Pre-trial `vmstat` samples
had to show at least 98% CPU idle; observed samples were around 99%.
This is a quiet shared VM, not scheduler-enforced exclusivity or proof of
zero transient contention. Effective CPU/memory allocation and cgroup limits
were checked before benchmarking.

There were **54 timing trials** (15 controls, 15 placement, 20 confirmation,
four integrated-runner trials) and **four separate diagnostic trials** with
memory snapshots. Snapshot trials were excluded from the timing comparisons.
All 58 trials completed with successful numerical validation and expected
thread binding. No system compiler replacement or source/compiler-flag
substitution occurred. THP settings were restored to `madvise` after each phase;
all restorations were verified. Approved cache drops cannot be undone.

## 1. Array size, THP and cache-drop controls

At 176 threads and 100 iterations, three runs per case. Rates are medians
in decimal **MB/s**. "Average-time rate" is
`array_elements * 24 / printed_Triad_average_seconds / 1e6`; output times are
rounded, and this is not the average of individual iteration bandwidths.

| Array elements | THP enabled / defrag | Cache drop | Best Triad median | Average-time Triad median |
|---:|---|---|---:|---:|
| 280,000,000 | always / always | Yes | 809748.40 | 688877.50 |
| 650,000,000 | always / always | Yes | 760270.30 | 685895.18 |
| 1,300,000,000 | always / always | Yes | 736559.30 | 692195.06 |
| 280,000,000 | madvise / madvise | Yes | 807799.00 | 665873.96 |
| 280,000,000 | always / always | No | 819614.50 | 681403.37 |

**What this establishes:** the smaller array's higher reported best rate
persists with iteration count fixed. The previous 100-versus-10 confound is
not enough to explain it. However, the average-time rates across array sizes
are similar, so the best-rate increase is not a general sustained-DRAM gain.
At 176 threads, the THP best-rate difference was small relative to variability;
the lower-thread finalists provide clearer THP evidence below.

Cache dropping gave no repeatable advantage in this quiet, low-pressure
environment, so it is omitted from the optional tuned profile. No-drop trials
were interleaved with drop trials; this does not prove equivalence under
heavy page-cache pressure. The integrated finalist also completed repeated
runs with no cache-drop calls.

Each 280M array occupies 2.24 GB, each 650M array 5.2 GB, and each 1.3B array
10.4 GB. Choose the workload according to the
[array-sizing guidance](diagnosis.md#choosing-array-size).

**Interpretation, not proof:** array size can change cache reuse, translation
behavior and timing variability. STREAM counts algorithmic bytes, not DRAM
transactions; cache-served reads can raise the score. All three arrays do not
simply fit in L3, and the cache is physically distributed. No cache-miss or
memory-controller counters were collected, so no specific cache mechanism
is established. Keep 280M for reproducing/tuning this benchmark; use a separate
large-array workload when the objective is sustained DRAM characterization.

## 2. Physical-CCD-balanced thread sweep

280M elements, 100 iterations, THP allocation/defrag `always`, no cache drop,
three randomized repetitions per count. The 24/48/96/144-thread cases use
1/2/4/6 threads per physical CCD, respectively; 176 uses every guest CPU.
Every NUMA node has an equal number of selected threads.

| Threads | Median best Triad MB/s | Median average-time Triad MB/s |
|---:|---:|---:|
| 24 | 786322.30 | 770995.87 |
| 48 | 832714.60 | 802867.38 |
| 96 | 837987.90 | 817021.28 |
| 144 | 841892.60 | 824843.50 |
| 176 | 821023.10 | 705215.66 |

This justifies taking 96 and 144 into confirmation rather than selecting
solely from the 176-thread result. Fewer, balanced threads can supply enough
concurrent memory traffic while reducing synchronization and resource
contention. With 176 threads, some physical CCDs contribute six exposed cores
and others eight; six per CCD also equalizes their work share.
In this initial sweep, these were explanations consistent with the data, not
isolated causal findings: thread count and physical distribution changed
together, and no barrier, frequency, or cache-traffic profiling was performed.
The subsequent [fixed-thread CCD-balance study](ccd-balance.md) held total
threads and threads per NUMA constant, found a repeatable placement benefit,
and replicated it with rotated cores and a large-array workload. It isolates
placement from thread count, but still does not identify the limiting hardware
resource.

## 3. Independent confirmation

All arrays 280M, all iteration counts 100. "Always" and "madvise" apply to
both THP controls. Only the original recipe drops caches.

| Candidate | Triad best median MB/s | Observed min-max MB/s | Range / median | Average-time median MB/s |
|---|---:|---:|---:|---:|
| Original 176, always, drop | 825036.75 | 817119.6-826488.1 | 1.14% | 702061.81 |
| 96, always, no drop | 839049.15 | 837589.5-840411.6 | 0.34% | 823327.67 |
| **144, always, no drop** | **841515.55** | **838935.7-843580.8** | **0.55%** | **826419.62** |
| 96, madvise, no drop | 807788.25 | 800867.3-816930.1 | 1.99% | 774163.70 |
| 144, madvise, no drop | 817013.00 | 816409.5-822628.6 | 0.76% | 794140.68 |

Individual best Triad rates in block order:

| Candidate | Block 1 | Block 2 | Block 3 | Block 4 |
|---|---:|---:|---:|---:|
| Original 176 | 824626.2 | 825447.3 | 817119.6 | 826488.1 |
| 96 always | 837589.5 | 839985.8 | 840411.6 | 838112.5 |
| 144 always | 843580.8 | 838935.7 | 841465.3 | 841565.8 |
| 96 madvise | 813957.6 | 816930.1 | 801618.9 | 800867.3 |
| 144 madvise | 822628.6 | 816811.7 | 816409.5 | 817214.3 |

Confirmation medians for all four kernels:

| Candidate | Copy MB/s | Scale MB/s | Add MB/s | Triad MB/s |
|---|---:|---:|---:|---:|
| Original 176 | 693939.10 | 695005.30 | 827899.30 | 825036.75 |
| 96 always | 710831.85 | 718072.85 | 846126.00 | 839049.15 |
| 144 always | 707513.00 | 713652.95 | 849338.50 | 841515.55 |

At fixed 144-thread placement, THP always raised the best-rate median **3.00%**
over madvise, with nonoverlapping observed ranges. The experiment changes
allocation and defrag settings together; it does not show that aggressive
defrag itself is necessary. This is the measured pair of settings, not
permission to change a shared host without approval.

## 4. Actual huge-page and NUMA evidence

Separate diagnostic runs sampled only the benchmark child's `smaps_rollup`
and `numa_maps` one second after launch. They were excluded from timing results
because reading mappings can perturb the process.

| Threads / THP | Anonymous kB | AnonHugePages kB |
|---|---:|---:|
| 144 / always | 6567748 | 6559744 |
| 144 / madvise | 6567744 | 0 |
| 176 / always | 6568860 | 6559744 |
| 176 / madvise | 6568864 | 0 |

Approximately **99.9% of anonymous memory** was huge-page backed under always
in these snapshots; none was under madvise. Anonymous page counts were
approximately balanced across all four NUMA nodes in every diagnostic case.
That supports huge pages as a real mechanism rather than a nominal sysfs
change, and argues against gross node-level allocation imbalance in these
snapshots. Lower translation overhead is plausible, but TLB misses were not
measured. Balanced node totals do not prove every thread accesses only local
pages, nor do four snapshots prove page placement for every performance run.

## 5. Reusable-runner confirmation

The final `STREAM_PROFILE=tuned-144` implementation was then run four times
with a clean launch environment, explicit AOCC 4.0.0 runtime directory,
no NUMA override, no cache drops, the same 144 CPU IDs, and approved THP always.
All four runs passed and restoration was verified.

| Kernel | Median MB/s | Observed min-max MB/s |
|---|---:|---:|
| Copy | 707792.85 | 706302.9-708192.9 |
| Scale | 713274.30 | 712570.4-714304.0 |
| Add | 848213.90 | 846875.9-849121.0 |
| Triad | **841681.15** | **840211.1-843479.9** |

Median average-time Triad bandwidth was **827331.56 MB/s**. This demonstrates
the executable skill path, not just a one-off command. The source binary
remained the original 280M/100 artifact with SHA-256
`f82215d247be14237bd05359c3ec6e6fe959834677ab4ba0e7be23ff8398c5e6`.

## Follow-up: 650M/100 source build at balanced 144 threads

Four additional trials measured **650,000,000 elements per array,
100 iterations, balanced 144 threads** using AOCC 4.0.0 and the original
compiler flags, with the same six-per-physical-CCD
GOMP mask, default inherited memory policy, THP allocation/defrag `always`,
and no cache drops.

| Trial | Best Triad MB/s |
|---:|---:|
| 1 | 778979.3 |
| 2 | 776778.3 |
| 3 | 777165.8 |
| 4 | 780475.2 |

Median best Triad was **778072.55 MB/s**, range **776778.3-780475.2 MB/s**
(0.48% of median); median average-time Triad bandwidth was **769041.39 MB/s**.
Best-rate medians for Copy, Scale and Add were **703770.70**, **703481.25** and
**779044.25 MB/s**, respectively.

This larger workload measured approximately 778 GB/s, compared with
approximately 842 GB/s for 280M/100. It was not interleaved with a
different candidate in this follow-up. The AMD prebuilt still has 10 iterations,
so these results do not establish a source-versus-prebuilt winner even though
array size and thread placement now match. The earlier 650M/10 build-method
comparison used 176 threads.

All four trials passed numerical and affinity validation. Pre-trial activity
was low; the harness checked the same quiet-node gate and 120-second timeout.
Both THP controls were restored to `madvise` and verified.
These four trials are additional to the
58-run tuning study counted above.

## Reproduce and retain scope

Use the explicit tuned command in [the manual reference](usage.md#optional-144-thread-runs); no benchmark
runs merely because the skill is loaded. Keep approval for benchmarks and
host-wide THP changes separate. The explicit `normalized-176` comparison
profile remains available and does not change global settings; it is not the
default. A request to reproduce the
original recipe must retain its original threads and disclosed differences.

The tuned CPU list is generated as follows:

```text
for NUMA base in [0, 44, 88, 132]:
    for physical-group offset in [0, 8, 16, 24, 32, 38]:
        select base + offset through base + offset + 5 inclusive
```

Do not use this mapping on a different topology. The runner validates the
complete expected HBv4 guest signature, source/build dimensions, binary
manifest identity, compiler version, and runtime library before launch.
Numerical output and actual singleton thread bindings must match the selected
profile. Missing evidence or unsupported output is a failure, not a fallback.

For new comparisons, retain the trial order, build/run manifests, raw output,
load samples and THP restoration records. Original raw run archives are not
distributed with this repository.

These observations apply to the stated STREAM configurations, not other
applications. The two THP controls were paired, and compiler flags were held
fixed. Use matched, repeated tests before adopting a change in another workload.
