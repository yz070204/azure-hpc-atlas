# HBv4/HX STREAM reference

Load this when diagnosing a result or explaining the optional tuning — not for
a routine run. Applies to HBv4 and HX — same CPU and topology (EPYC 9V33X, 176
cores, 4×44 NUMA, 24 CCDs); they differ only in total memory, which doesn't affect
STREAM bandwidth as long as the working set fits (it does). All numbers are observed
medians on one quiet `Standard_HB176rs_v4` node
(AOCC 4.0.0, original flags, 280M doubles/array, 100 iterations, THP always).
They are reference points, **not guarantees or pass/fail thresholds**; run-to-run
spread is ~1%. Always label the array size — different sizes are not comparable.

## Target numbers (HBv4/HX, 280M/100)

Decimal GB/s (×1000 for MB/s):

| Config | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 176 threads, THP always (default) | 693 | 697 | 825 | 818 |
| 144 threads, CCD-balanced (optional) | 708 | 714 | 849 | 842 |

These cover HBv4 and HX. HBv2/v3 need their own baselines before they mean anything.

## Target numbers (HBv4/HX, 560M/100)

| Config | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 176 threads, THP always (default) | 693 | 694 | 764 | 764 |
| 144 threads, CCD-balanced | 704 | 705 | 783 | 786 |

144-balanced beats 176 by ~2.9% on Triad here (786 vs 764 GB/s) and ~2.5% on Add, in
line with the ~2% at 280M. An earlier test showed only ~0.3% here, but that was a
test-condition artifact, not a real size effect: THP *defrag* was left at `madvise`
while only `enabled` was `always`, and cache drops were applied to the 176 trials but
not the 144 trials. With defrag `always` on both knobs, consistent cache handling and
interleaved trials, the gain reproduces cleanly with tight ranges (144-balanced within
~0.3%).

## AMD prebuilt binary (650M/10)

The AMD Zen STREAM prebuilt (`2024_10_08`, fixed 650M doubles/array, 10 iterations)
also benefits from CCD-balanced placement: 144-thread balanced gives a
**reproducible ~2.5% Triad gain** over the default 176 threads. Independently
reproduced against a representative 176 baseline:

| Config | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 176 threads (default) | 691 | 688 | 751 | 755 |
| 144 threads, CCD-balanced | 702 | 701 | 775 | 774 |

This ~2.5% is consistent with the source build, which shows ~2% at 280M and ~2.9% at
560M — so 144-balanced gives a steady ~2-3% Triad gain across both binaries and the
tested sizes, once methodology is controlled. The prebuilt still isn't directly
comparable to source (different binary, array size, and iteration count — 10 vs 100),
so treat its numbers on their own terms. Offer 144-balanced as an optional tuning and
keep 176 the default. The 176-vs-144 comparison also bundles placement with thread
count; the clean isolation of placement itself is the balanced-vs-uneven-at-144 result
(~12-14%), not this row.

## Array size

280M doubles/array (2.24 GB each, 6.72 GB total) is the baseline used here — keep it
for comparability and regression across runs. Note it sits only just above aggregate
L3 (24 × 96 MiB ≈ 2.3 GiB), short of the 4×-LLC that STREAM's official rule wants, so
it is cache-sensitive: cache-served reads inflate the reported rate, which is why the
280M Triad (~818 GB/s) reads *higher* than published sustained-bandwidth figures. The
larger-array numbers here (~764 GB/s at 560M, ~755 at 1.3B) are the ones that line up
with sustained DRAM specs. For a strict larger-than-cache DRAM measurement, use 1.3B
doubles/array (10.4 GB each), which satisfies the rule. Don't treat different sizes as
interchangeable DRAM numbers — STREAM reports algorithmic bytes ÷ time, not
memory-controller traffic.

## THP

Force THP `always` on **both** knobs — `enabled` *and* `defrag`. STREAM's arrays are
static/BSS, so `madvise` mode backs *none* of them (0% huge pages in probes) while
`always` gives ~99.9% coverage — a real bandwidth difference, not a nominal sysfs flip.
Leaving `defrag` at `madvise` while setting only `enabled` silently under-backs the
arrays and can mask a real placement gain (this is what produced a spurious ~0.3% at
560M before it was caught). The runner sets both and restores the prior values on exit.

When comparing two configs, also keep cache-drop handling identical across them — a
mismatch (dropping for one config but not the other) is an uncontrolled variable, not a
fair comparison. The runner drops consistently for every trial.

## Optional 144-thread CCD-balanced tuning

On this node/workload, 144 threads placed six per physical CCD gave ~2% higher
best-rate Triad and ~17% higher average-time (sustained) Triad than the 176-thread
default. Offer it as a manual try; keep 176 the default and don't apply it
automatically. The mask takes six CPUs per physical CCD, 36 per NUMA, 144 total:

```text
for NUMA base in 0, 44, 88, 132:
    for offset in 0, 8, 16, 24, 32, 38:
        take base+offset .. base+offset+5
```

Use the physical topology, not guest L3 IDs and not CPUs 0-143. HBv4/HX only — the
reusable idea is "balance work across physical CCDs while keeping enough
concurrent memory requests," so re-derive the mask for any other SKU rather than
copying this list.

## Diagnosing a low result

Recover the user's actual binary, build flags, launch command and raw log first.
Don't swap in a faster or differently sized workload and call it fixed. Then
compare against the target above, changing one factor at a time:

- **Metric** — which kernel; MB/s vs GB/s; best-iteration vs average-time vs median.
- **Array/iterations** — 280M/100 is the baseline; don't compare against 650M or 1.3B.
- **Build** — AOCC 4.0.0, original flags, `-march` target, binary hash.
- **Run** — threads requested vs counted, actual affinity, stray OMP/GOMP/KMP
  variables, NUMA policy, THP mode.

If the optimal config hits target but the user's doesn't, the gap is almost always
their configuration — usually compiler flags, thread/affinity, or huge pages. If
the evidence is thin, say **inconclusive**; a low number alone is not a hardware
fault.
