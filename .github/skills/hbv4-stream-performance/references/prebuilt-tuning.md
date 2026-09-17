# AMD prebuilt STREAM: HBv4 placement confirmation

## Result

**CCD-balanced placement also benefits the AMD prebuilt binary.** On the
tested HBv4, optionally use **144 threads, six per physical CCD**, for the measured Triad
objective. This is the best of the tested 96/144/176-thread placements, not a
global optimum or a cross-SKU rule.
An ordinary AMD-prebuilt request defaults to its original 176-thread launch
with THP always; this 144-thread profile is explicit opt-in. See
[current workflow defaults](../SKILL.md).

The executable was the user-supplied AMD Zen STREAM `2024_10_08` package,
SHA-256 `b6d034f991c560f3f1edfb4da23dd73d11e864878eb60956d2b46e412984f6c0`.
Every run retained its compiled **650,000,000 doubles per array, 10 iterations**.
No rebuild, source changes, AOCC compiler setup or external OpenMP runtime
injection was used. This is not directly comparable to the source-build
280M/100 numbers.

## Equal-thread placement comparison and initial sweep

Four randomized blocks on 2026-09-17, one `Standard_HB176rs_v4`, same image,
topology and quiet-node conditions as [the source study](tuning.md).
All trials had THP allocation/defrag `always`, no cache drops, inherited
default NUMA policy, and explicit GOMP affinity.

| Prebuilt placement | Median best Triad MB/s | Observed range MB/s | Median average-time Triad MB/s |
|---|---:|---:|---:|
| 96 balanced, four per CCD | 764299.20 | 761429.3-770331.0 | 754980.83 |
| **144 balanced, six per CCD** | **777729.30** | **776584.7-777895.7** | **773598.72** |
| 176, all guest CPUs | 755637.10 | 744771.4-758718.7 | 697808.63 |
| 144 uneven, 8:8:6:6:4:4 | 678644.20 | 678408.5-678880.1 | 675355.84 |
| 144 uneven, 4:4:8:8:6:6 | 692888.00 | 690755.7-692965.0 | 690009.02 |

At identical 144 threads, 36 per NUMA node and all 24 physical CCDs active,
balanced placement improved median best Triad **14.60%** over the first uneven
mask and **12.24%** over the second. It won every paired block against both
controls, with nonoverlapping observed ranges.

Only the affinity list changed between these equal-thread cases. Arrays,
iterations, executable, environment and THP were fixed. The runtime's binding
output verified the exact selected CPUs, so this does not assume the prebuilt
interprets GOMP affinity the same way as a particular source-build runtime.

Use the physical masks in [the CCD-balance study](ccd-balance.md).
Do not group by guest-visible L3 IDs or use the first 144 guest CPUs.

## Independent finalist confirmation

Four additional randomized blocks compared 96, 144 and 176 threads:

| Placement | Median best Triad MB/s | Observed range MB/s | Median average-time Triad MB/s |
|---|---:|---:|---:|
| 96 balanced | 767088.80 | 764364.6-770213.1 | 760809.04 |
| **144 balanced** | **774480.15** | **773079.7-777710.8** | **770162.06** |
| 176 all | 756887.75 | 717045.8-760314.5 | 674806.72 |

144 won all four blocks against both alternatives: **0.96%** higher best-rate
median than 96 and **2.32%** higher than 176. Across the selection and
confirmation phases it won all eight such blocks. This is useful repeatability
on one node, not a population confidence interval.

The slow 176-thread trial is retained, not discarded. Its pre-trial load check
passed, but transient interference or runtime variability remains possible.
The median comparison does not rely on selecting that worst trial.

Individual best Triad rates in confirmation block order:

| Block | 96 balanced | 144 balanced | 176 all |
|---:|---:|---:|---:|
| 1 | 770213.1 | 775076.0 | 759308.6 |
| 2 | 767070.8 | 773079.7 | 760314.5 |
| 3 | 764364.6 | 777710.8 | 754466.9 |
| 4 | 767106.8 | 773884.3 | 717045.8 |

All-kernel best-rate medians in confirmation:

| Placement | Copy MB/s | Scale MB/s | Add MB/s | Triad MB/s |
|---|---:|---:|---:|---:|
| 96 balanced | 704037.85 | 703534.35 | 767944.60 | 767088.80 |
| 144 balanced | 701231.25 | 702536.30 | 774624.80 | 774480.15 |
| 176 all | 690233.95 | 690273.15 | 750901.70 | 756887.75 |

96 has slightly higher Copy/Scale medians; 144 is the recommendation for
Triad/Add, not an unconditional winner for every kernel or CPU-efficiency goal.

## Reusable runner

The `prebuilt-144` profile was then exercised in four further trials:

| Kernel | Median MB/s | Observed range MB/s |
|---|---:|---:|
| Copy | 701400.00 | 700802.7-703503.9 |
| Scale | 702393.90 | 701332.2-703606.1 |
| Add | 774957.15 | 772778.3-775930.8 |
| Triad | **774710.10** | **770294.7-777627.6** |

Median average-time Triad bandwidth was **769876.36 MB/s**. The clean runner
environment reproduces the experimental result without loading AOCC.

When explicitly requested, after license, benchmark-budget and host-wide THP
approval, run from the paths established in [the manual reference](usage.md):

```bash
STREAM_RUN_APPROVED=yes STREAM_THP_APPROVED=yes STREAM_PROFILE=prebuilt-144 \
  bash "$SKILL_DIR/scripts/run-stream.sh" \
  "$WORK_ROOT/amd-zen-stream-2024_10_08/amd_zen_stream" \
  "$WORK_ROOT/run-prebuilt-144" 4
```

No runtime-library argument is accepted. The runner verifies the exact AMD
binary identity, complete HBv4 topology signature and default inherited NUMA
policy, selects 144 physical-CCD-balanced CPUs, and requires the expected
650M/10 output and actual singleton thread binding. It records/restores THP
and never drops caches. The source-only `tuned-144` profile remains distinct.

## Conditions, limits and evidence

### Original prebuilt command baseline

A later user-requested baseline on 2026-09-17 used the supplied command's
settings: `OMP_NUM_THREADS=176 OMP_PROC_BIND=true OMP_PLACES=cores`.
No GOMP affinity, schedule/dynamic/thread-limit/stack overrides or `numactl`
launch wrapper were added. THP allocation/defrag stayed at the existing
`madvise` settings; there were no cache drops. This differs from the controlled
176-thread GOMP/THP-always row above and the initial normalized/localalloc
comparison. Keep the three baselines labeled separately.

The user's `configs.sh` was not supplied; `NUM_THREADS_STREAM=176` is the
known full-size baseline assumption, not a reconstruction of unknown file
contents. Added diagnostics were only environment/affinity display, saved logs
and the 120-second timeout with five-second termination grace.

Four original-command trials, raw best Triad in MB/s:
**743569.5, 748203.5, 749858.4, 740707.6**.

| Kernel | Median MB/s | Observed range MB/s |
|---|---:|---:|
| Copy | 701327.65 | 699959.3-702552.2 |
| Scale | 681074.45 | 654828.7-700949.1 |
| Add | 743057.25 | 695218.1-749746.7 |
| Triad | **745886.50** | **740707.6-749858.4** |

Median average-time Triad was **666809.15 MB/s**. All four runs passed numerical
and 176-thread binding checks, and unchanged THP settings were verified.
The difference from the tuned prebuilt profile changes several factors
(including threads, affinity, OpenMP settings and THP) and is not a pure
thread-count or THP-only comparison.

Local evidence is `run-prebuilt-original/` and `run-prebuilt-original.sh`
under the directory below. These four later trials are additional to the
36 placement/tuning trials described next.

### Original command with THP always

The user then requested the same original prebuilt command with **both THP
allocation and defrag set to `always`**. Four further trials retained 176
threads, `OMP_PROC_BIND=true`, `OMP_PLACES=cores`, 650M/10, no extra OpenMP
tuning, no NUMA override and no cache drops. Relative to the original-command
baseline above, only the two THP controls were intentionally changed.

Best Triad per trial, MB/s:
**757901.4, 758639.5, 758648.3, 754606.1**.

| Kernel | Median MB/s | Observed range MB/s |
|---|---:|---:|
| Copy | 690163.70 | 689743.6-691953.7 |
| Scale | 691120.50 | 658904.0-692129.4 |
| Add | 756439.85 | 751701.9-757655.7 |
| Triad | **758270.45** | **754606.1-758648.3** |

Median average-time Triad was **680619.67 MB/s**. Numerical and thread-binding
checks passed for all four trials. The original `madvise` values were restored
and verified after the batch.

These batches were sequential, not randomized THP-on/off pairs. The higher
Triad median therefore provides an observed comparison, not a precise isolated
THP effect estimate independent of time/run variability. The tuned 144-thread
profile also changes affinity and other OpenMP settings, so comparing with it
is not a thread-count-only test.

Evidence: `run-prebuilt-original-always/`; reproduce with
`bash run-prebuilt-original.sh always` in the retained session workspace after
approval, using a new output directory. This wrapper restores THP on exit.
These four trials are additional to both the original-command four and the
36 placement/tuning trials below.

### Placement/tuning trial scope

All **36 trials** completed with successful numerical validation and correct
thread counts/binding: 20 initial, 12 finalist, four runner confirmations.
The experimental seeds were 20260925 and 20260926. The existing harness's
default 100-iteration check was extended with an explicit per-case `ntimes=10`;
the prebuilt was not modified to satisfy a source-build assumption.

OpenMP settings were `OMP_NUM_THREADS` as selected,
`GOMP_CPU_AFFINITY` as the physical mask, `OMP_SCHEDULE=static`,
`OMP_DYNAMIC=false`, `OMP_THREAD_LIMIT=512`, `OMP_STACKSIZE=256M`,
`OMP_DISPLAY_ENV=VERBOSE` and `OMP_DISPLAY_AFFINITY=true`.
Inherited OMP/GOMP/KMP affinity was cleared, as were unrelated library/preload
overrides. The experiment did not source AOCC. Compared with the user's
initial prebuilt command, explicit physical GOMP binding replaced
`OMP_PROC_BIND=true OMP_PLACES=cores`; all current cases used the same method.

Pre-trial `vmstat` samples required at least 98% CPU idle; runs were bounded
by 120 seconds plus a five-second termination grace. This is still a quiet
shared VM, not proof of no transient contention. Both THP controls were
verified active and restored to their original `madvise` values after each
phase. Actual huge-page coverage was not sampled in these prebuilt trials;
do not reuse source-process memory snapshots as proof for this binary.

The prebuilt implementation/compiler details were not reconstructed. The
data establish a placement effect, not a specific CCD-link/cache/barrier
mechanism. The fixed 650M arrays are below the usual four-times-aggregate-L3
guidance on this VM; results remain tuned STREAM measurements rather than
certified submissions or hardware DRAM-counter readings.

Raw evidence under
`~/.copilot/session-state/3a049321-e64b-451c-a352-3ae254739c74/files/stream/`:
`experiment-prebuilt-placement/`, `experiment-prebuilt-finalists/`,
`run-prebuilt-144-integrated/`, and their `plan-prebuilt-*.json` plans.
Keep this prebuilt evidence separate from source-build experiments and do
not promote these rates or the 144-thread count to another SKU without testing.
