---
name: hbv4-stream-performance
description: Run STREAM optimally on a full-size Azure HBv4/HX VM, and triage when measured bandwidth is lower than expected.
user-invocable: false
---

# STREAM on HBv4 / HX
Azure VM size that should apply this skill for stream run:
- `Standard_HB176rs_v4`
- `Standard_HB176s_v4`
- `Standard_HX176rs_v4`
- `Standard_HX176s_v4`

## When to do what
- **"Run STREAM" / "check memory bandwidth"** → run the optimal config below and report.
- **"Why is my STREAM slow?" / user brings their own numbers** → run the diagnostic workflow; don't just re-benchmark.

## Optimal run
`source-original` recipe: AOCC 4.0.0, 280M doubles/array, 100 iterations, **176 threads**, THP on, `GOMP_CPU_AFFINITY=0-175`. Reuse verified binaries; build only if missing.
Set `SKILL_DIR`, `WORK_ROOT`, `AOCC_ROOT`; output to a **new** directory.

```bash
STREAM_RUN_APPROVED=yes STREAM_THP_APPROVED=yes STREAM_CACHE_DROP_APPROVED=yes \
bash "$SKILL_DIR/scripts/run-stream.sh" "$WORK_ROOT/build/stream" "$WORK_ROOT/run" 3 "$AOCC_ROOT/lib"
```

**Approvals:** THP changes and cache drops modify host state, and a cache drop can't be undone. Default behavior: ask before setting these flags.
**YOLO mode:** if the user has enabled YOLO mode, skip the up-front requests and set the flags directly — then, in the final report, state exactly what was done to the host: whether THP was toggled and restored, and that host caches were dropped (call this out explicitly, since it's irreversible).

THP changes and cache drops need explicit approval — a cache drop can't be undone. Never kill jobs or change persistent host settings implicitly.

## Diagnostic workflow (user's own results look off)
1. Detect and report the **VM size**.
2. Check **NUMA topology + total memory** against the [topology skill](../azure-hbv4-hx176-topology/SKILL.md); flag any mismatch.
3. Check for **other memory consumers / pressure** on the VM, including cgroup limits.
4. Run STREAM with the **optimal config** above and compare to target.
5. If the optimal run hits target but the user's doesn't, the gap is almost certainly their **config** — compiler flags, run parameters (threads/affinity), or huge pages. Compare against the reference data (provided separately).

## Reporting
Report Copy/Scale/Add/Triad **medians + range in MB/s**, plus build, array/iterations, threads, affinity, THP, validation, and log path. Don't cherry-pick a peak. Low bandwidth alone isn't proof of bad hardware.

*Optional:* 144 threads balanced 6 per physical CCD improved results in our HBv4 experiments — offer it as a manual try, but keep the 176-thread default unless asked.
