---
name: hbv4-stream-performance
description: Run or diagnose STREAM on full-size Azure HBv4. Default to the original AOCC source build with 176 threads and THP always; use AMD prebuilt only when requested. Explain optional 144-thread physical-CCD balancing without silently changing the baseline.
user-invocable: false
---

# HBv4 STREAM: Check -> Build -> Run -> Review

Scope: one `Standard_HB176rs_v4` or `Standard_HB176s_v4`. Other SKUs need their
own topology and placement. STREAM does not test InfiniBand.

## 1. Choose exactly one workflow

| User asks | Action |
|---|---|
| "Run STREAM" / "test memory bandwidth" | **`source-original`**: AOCC 4.0.0, 280M doubles per array, 100 iterations, **176 threads**, THP allocation/defrag **always** |
| "Run AMD prebuilt STREAM" | **`prebuilt-original`**: AMD 2024_10_08, fixed 650M/10, **176 threads**, both THP settings **always** |
| "Why is STREAM slow?" | Diagnose existing build/run evidence first; do not automatically benchmark or tune |
| Explicitly requests 144-core balancing | Source: `tuned-144`; prebuilt: `prebuilt-144`. Follow [manual commands](references/usage.md#optional-144-thread-runs) |

**Do not substitute 144 threads, another array size/compiler, or prebuilt for
the default source recipe.** Honor explicit user parameters; label departures
from the measured profiles.

## 2. Check and prepare

- Detect SKU; compare full CPU/NUMA signature with the
  [topology skill](../azure-hbv4-hx176-topology/SKILL.md). Require the intended
  allocation, default NUMA policy, low competing activity and adequate memory.
  Check cgroup limits: the runner's 24 GiB available-memory check is not enough.
- Discover software under `/opt` first, then modules/PATH and scoped work
  directories. Record actual versions; never replace AOCC 4.0.0 silently.
- Obtain AMD license authorization, download/build permission where needed,
  and a bounded run budget. **THP changes need explicit approval.**
  The original source recipe also drops host caches before each trial:
  **separate approval is required; a cache drop cannot be undone.**
- Use [preparation and build instructions](references/usage.md) only when
  artifacts are missing. Reuse verified binaries. Never source cluster-validation
  constants/utilities: they perform unrelated cloud/identity operations.

Stop on wrong SKU/topology, busy allocation, missing approval, incompatible
build or failed validation. Do not kill jobs, install tools or change persistent
host settings implicitly.

## 3. Run the selected default

Set `SKILL_DIR` to this skill's absolute directory, `WORK_ROOT` to the chosen
existing work directory, and `AOCC_ROOT` to the verified compiler directory.
Output directories must be new. Set approval variables **only after approval**.
Default budget: three trials, at most 120 seconds each plus five-second kill grace.

**Source default:**

```bash
STREAM_PROFILE=source-original STREAM_RUN_APPROVED=yes \
STREAM_THP_APPROVED=yes STREAM_CACHE_DROP_APPROVED=yes \
bash "$SKILL_DIR/scripts/run-stream.sh" \
  "$WORK_ROOT/build-original/stream" "$WORK_ROOT/run-source-original" 3 "$AOCC_ROOT/lib"
```

**AMD prebuilt, only when requested:**

```bash
STREAM_PROFILE=prebuilt-original STREAM_RUN_APPROVED=yes STREAM_THP_APPROVED=yes \
bash "$SKILL_DIR/scripts/run-stream.sh" \
  "$WORK_ROOT/amd-zen-stream-2024_10_08/amd_zen_stream" \
  "$WORK_ROOT/run-prebuilt-original" 3
```

Source uses `GOMP_CPU_AFFINITY=0-175` and the original OpenMP settings.
Prebuilt uses `OMP_PROC_BIND=true OMP_PLACES=cores`, without source-specific
OpenMP overrides or cache drops. Neither default adds a NUMA-policy override.
The helper records settings, checks numerical output and actual binding, and
restores THP on exit. Verify `thp-restored.txt`; interruption/privilege failures
can prevent restoration. Never rerun a failed batch without inspecting its logs.

## 4. If performance is bad

Check in this order; explain the mismatch before changing it:

1. **Metric/workload:** kernel, MB/s versus GB/s, array size, iterations,
   best versus average time, repetitions. Do not compare 280M/100 with 650M/10.
2. **Build:** source revision or prebuilt hash, compiler/version/flags,
   target ISA, executable checksum and linked runtime.
3. **Run:** actual threads/binding, conflicting OMP/GOMP/KMP variables,
   NUMA policy, THP, cache-drop behavior, memory pressure and competing work.
4. Compare only matching conditions using
   [experiment baselines and caveats](references/diagnosis.md). If unresolved,
   use [first-line triage](../hpc-atlas-firstline-triage/SKILL.md); low bandwidth
   alone is not evidence of faulty hardware.

## 5. Report and mention optional tuning

Report Copy/Scale/Add/Triad medians and range in **MB/s**, plus build,
array/iterations, threads, affinity, THP, validation and log path.
Read `summary.json` and `run-manifest.txt`; do not cherry-pick a peak.

Tell the user: **"144 threads balanced six per physical CCD improved results
in our HBv4 experiments. You can try the optional manual command; this run
kept your 176-thread default."** Say *observed improvement*, not a guarantee.
Do not run that comparison unless requested. Use physical topology, not guest
L3 IDs or CPUs `0-143`; preserve the [CCD-balance evidence](references/ccd-balance.md).

Label these **tuned STREAM workloads**, not certified DRAM measurements.
280M and prebuilt 650M are below STREAM's four-times-total-L3 size requirement
on this node; 1.3B meets that size criterion but is a **separate** workload,
not a silent replacement for the historical default.
