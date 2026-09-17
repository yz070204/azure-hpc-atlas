# HBv4 STREAM comparisons

This file retains the initial build comparison and original-recipe
reproduction. The later [controlled tuning study](tuning.md) supports optional
144-thread balancing for the original 280M/100 workload. Current workflow
defaults remain original source at 176 threads and THP always, or original
prebuilt at 176/THP always when requested; see [the skill](../SKILL.md).

## Decision

**This initial comparison did not establish a build-method winner.** At matched 650M/10
dimensions, the prebuilt's median Triad rate was only 0.35% higher, smaller
than the observed run-to-run variation. The original 280M/100 source profile
subsequently reached a higher reported Add/Triad rate, but changes in workload
dimensions prevent attributing that difference to the build method.
Preserve the user's baseline before choosing a replacement. Prebuilt remains
an operationally simpler option, not a proven faster one. This is not an
optimal-thread search, cache-independent DRAM measurement, or hardware-health
threshold. A later run with the supplied original launch settings reached
824650.3 MB/s peak Triad (818020.7 MB/s median); see the original-settings
follow-up below.

## Scope and conditions

Measured on 2026-09-17 on one `Standard_HB176rs_v4`, AMD EPYC 9V33X,
176 exposed CPUs, four 44-CPU NUMA nodes, Ubuntu 24.04.4 LTS, kernel
`6.8.0-1064-azure`. The full guest topology matched the topology skill.
All CPUs 0-175 and memory nodes 0-3 were available; inspected cgroup ancestors
had no finite CPU quota or memory cap. The machine had roughly 741 GiB available
before staging. Sampled CPU idle time was approximately 99% around the runs.
This was a quiet shared VM, not a scheduler-enforced exclusive allocation;
no claim of zero transient contention is made.

Both candidates used 650,000,000 doubles per array (15.6 GB total),
10 iterations, 176 threads, `OMP_PROC_BIND=true`, `OMP_PLACES=cores`,
`OMP_SCHEDULE=static`, `OMP_DYNAMIC=false`, `OMP_THREAD_LIMIT=512`,
`OMP_STACKSIZE=256M`, and `numactl --localalloc`.
`OMP_DISPLAY_ENV=VERBOSE` and `OMP_DISPLAY_AFFINITY=true` recorded the runtime
settings and all 176 singleton CPU bindings. All six runs reported successful
STREAM numerical validation and the requested/counted 176 threads.

During the initial comparison, THP allocation and defragmentation remained
`madvise`. No cache drop, THP
change, boost setting, system install, or image-compiler replacement occurred.
The source build used a separately extracted AOCC 4.0.0; the image's AOCC 5.2.0
was not used. Resident NUMA page distribution was not sampled, so matching
requested policy and observed CPU binding does not prove identical page layout.

The first prebuilt trial was a bounded manual pilot, before the reusable
runner existed. It used the same benchmark settings with `HOME` also present
in its otherwise clean environment. Its raw output and tool-call launch are
retained, but it has no runner-generated per-trial manifest or post-run load
file. The remaining order was source 1, prebuilt 2, source 2, prebuilt 3,
source 3. All trials had a 120-second timeout plus five-second kill grace.
The original 280M/100-iteration source profile was compiled successfully but
**not benchmarked** in this six-run budget.

## Measurements

Values below are decimal **GB/s** (`MB/s / 1000`). Each is the benchmark's
best-iteration rate, excluding its first iteration. Summary values are medians
across the three independent trials; ranges are not confidence intervals.

| Candidate / trial | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| Prebuilt 1 (pilot) | 708.3017 | 711.5948 | 759.6436 | 753.4765 |
| Prebuilt 2 | 703.0731 | 701.7158 | 722.9881 | 744.0938 |
| Prebuilt 3 | 708.1982 | 708.5894 | 756.9194 | 756.1759 |
| **Prebuilt median** | **708.1982** | **708.5894** | **756.9194** | **753.4765** |
| Source 1 (matched) | 709.3153 | 709.9502 | 760.7122 | 728.5994 |
| Source 2 (matched) | 706.2833 | 706.6151 | 754.1365 | 752.3502 |
| Source 3 (matched) | 708.7275 | 708.1637 | 751.2273 | 750.8652 |
| **Source median** | **708.7275** | **708.1637** | **754.1365** | **750.8652** |

Triad ranges: prebuilt **744.0938-756.1759 GB/s** (1.60% of median);
source **728.5994-752.3502 GB/s** (3.16% of median).
Median relative difference:
`100 * (753.4765 - 750.8652) / 750.8652 = 0.35%`.
Other kernels likewise do not justify a universal performance advantage.

These are **tuned STREAM variants**. With approximately 2.3 GiB aggregate
guest-visible L3, neither original nor matched array dimensions satisfy the
source's four-times-available-cache guidance per array. See the pinned
[`stream.c`, lines 50-75](https://github.com/jeffhammond/STREAM/blob/6703f7504a38a8da96b353cadafa64d3c2d7a2d3/stream.c#L50-L75).
Do not publish these as certified STREAM results or compare them directly
with a differently sized benchmark.

## Reproduction and evidence

### Follow-up: original 280M/100 source profile

Later on 2026-09-17, the user requested the original array size. Three runs used
the already-built **280,000,000 doubles per array, 100-iteration** executable,
AOCC 4.0.0 and the original compiler flags. The previous normalized launch
settings were retained: 176 threads, OMP core binding, explicit local
allocation, THP allocation/defrag at `madvise`, and no cache drops.
Thus this restores the original build dimensions, **not the entire historical
launch recipe**. It changes both array size and iteration count relative to
the matched comparison and does not isolate an array-size-only effect.

| Original source / trial | Copy GB/s | Scale GB/s | Add GB/s | Triad GB/s |
|---|---:|---:|---:|---:|
| 1 | 695.8665 | 698.7907 | 826.8518 | 806.5277 |
| 2 | 695.2228 | 698.5829 | 828.3827 | 809.3531 |
| 3 | 693.2734 | 696.8471 | 814.2397 | 795.7348 |
| **Median** | **695.2228** | **698.5829** | **826.8518** | **806.5277** |

All three runs passed numerical validation and the 176-thread binding checks.
CPU samples before/after each run were approximately 99% idle. Triad spanned
795.7348-809.3531 GB/s (1.69% of median). This normalized launch did not reproduce
the reported historical 820 GB/s Triad result; Add exceeded 820 GB/s in two runs. The historical
kernel, source revision and full launch conditions remain comparison gaps.

Run with the helper and explicit `STREAM_PROFILE=normalized-176`,
substituting `build-original/stream` and a new
output directory. Raw evidence is in `run-original-280m/` under the local
evidence directory below, including `summary.json`, all trial logs, the build
manifest, runtime library hashes, and load samples. Original executable SHA-256:
`f82215d247be14237bd05359c3ec6e6fe959834677ab4ba0e7be23ff8398c5e6`.

### Follow-up: original build and supplied launch settings

On 2026-09-17 the user explicitly requested the supplied launch settings,
including the previously disclosed host-wide THP/cache changes. Three trials
reused the same 280M/100 AOCC 4.0.0 executable and:

- Sourced the vendor-generated `setenv_AOCC.sh` in the inherited shell rather
  than using `env -i`. Library resolution confirmed AOCC 4.0.0 `libomp.so`.
- Set `GOMP_CPU_AFFINITY=0-175`, `OMP_NUM_THREADS=176`,
  `OMP_SCHEDULE=static`, `OMP_DYNAMIC=false`, `OMP_THREAD_LIMIT=512`,
  and `OMP_STACKSIZE=256M`.
- Left `OMP_PROC_BIND`, `OMP_PLACES`, and `KMP_AFFINITY` unset. Launched the
  executable without a `numactl` wrapper; observed inherited policy was `default`.
- Ran `sync` and wrote `3` to `drop_caches` before each trial, then set both
  THP allocation and defrag to `always`, verifying their active values.

Diagnostic-only additions were `OMP_DISPLAY_ENV=VERBOSE`,
`OMP_DISPLAY_AFFINITY=true`, saved logs and a 120-second timeout with five-second
termination grace. Unrelated cloud/KVP collection was omitted. The wrapper
restored and verified both original THP values (`madvise`) on exit; dropping
caches cannot be undone. Global changes remain approval-gated, never a routine
readiness action. The reusable `source-original` runner now includes these
explicit benchmark settings with separate THP/cache-drop approval; it uses a
clean process-local AOCC environment instead of sourcing the inherited shell.

Raw benchmark rates, in **MB/s**:

| Trial | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 1 | 691894.9 | 693810.9 | 824939.9 | 817427.7 |
| 2 | 694477.7 | 697183.2 | 829724.0 | 824650.3 |
| 3 | 693299.0 | 696847.1 | 823133.1 | 818020.7 |
| **Median** | **693299.0** | **696847.1** | **824939.9** | **818020.7** |

Triad spanned **817427.7-824650.3 MB/s** (0.88% of median), consistent with the
user's approximate 820 GB/s report. All trials passed numerical and 176-thread
binding checks; CPU samples around the runs were approximately 99% idle.
This matches the supplied benchmark-affecting settings, not a proven
byte-for-byte reproduction of the historical source/image/shell environment.
Several launch factors changed together, so these results cannot isolate a
THP-only, affinity-only, NUMA-policy-only or cache-drop effect.

The local evidence directory contains the retained
`run-original-settings.sh` wrapper and `run-original-settings/`, including
`summary.json`, trial logs, exact environment/library provenance,
`thp-original.txt`, `thp-active-*.txt`, `thp-restored.txt`, and load samples.
The original build source and executable hashes are unchanged.

### Initial matched comparison evidence

Use the [matched-comparison commands](usage.md#explicit-matched-comparison).
Keep the prebuilt version, source revision, compiler, flags and array settings
fixed. The source and prebuilt implementations and OpenMP runtime versions are
not identical; matching dimensions does not establish identical generated code.

| Identity | SHA-256 |
|---|---|
| Prebuilt executable | `b6d034f991c560f3f1edfb4da23dd73d11e864878eb60956d2b46e412984f6c0` |
| Matched source executable from this build | `9ebf732930f99a8db0f73f6e9536b12ca6e27000d89d805f5d0c34d3624dcff6` |
| AOCC 4.0.0 `libomp.so` | `b62fd9fa42dc0d19131cf3368f914d77004cf7200aed710c91a3b97ba92ffef6` |

Package/source hashes and pinned URLs are in [the preparation reference](usage.md). Executable hashes
identify these artifacts, not a requirement that builds in different paths
produce byte-identical binaries.

Local raw evidence is retained outside the repository in
`~/.copilot/session-state/3a049321-e64b-451c-a352-3ae254739c74/files/stream/`:
`prebuilt-pilot.log`, `run-prebuilt-{1,2}/`, `run-source-{1,2,3}/`,
`summary-prebuilt.json`, `summary-source.json`, and both build directories.
The follow-up runner directories contain exact commands, binary checksums,
library resolution, CPU topology, load samples, validation and binding output.
Vendor archives and extracted packages stay local with their license files.
No cloud resource identifiers or unrelated infrastructure constants are needed
to reproduce this comparison.
