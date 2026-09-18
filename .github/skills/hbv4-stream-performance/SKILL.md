---
name: hbv4-stream-performance
description: Run STREAM optimally on a full-size Azure HBv4/HX VM (176-core EPYC 9V33X), and triage when measured bandwidth is lower than expected.
user-invocable: false
---

# STREAM on HBv4 / HX

Applies to the full-size SKU of the Azure HBv4 and HX families, plus HBv2/HBv3. STREAM
measures memory bandwidth, so it runs on any full-size member of a family.

## Detect the platform (do this first)
Read the VM size from Azure IMDS, then map it to a platform token — don't guess the
mapping:

```bash
curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text"
```

| VM size | platform token |
|---|---|
| `Standard_HB176*_v4` | `hbv4` |
| `Standard_HX176*` | `hx` |
| `Standard_HB*_v3` | `hbv3` |
| `Standard_HB*_v2` | `hbv2` |

HBv4 and HX are distinct SKUs but the same 176-core silicon, so they share one recipe.
If the size matches no known family, **stop and report it** — do not fall through to a
guessed recipe (a wrong recipe yields bad-but-plausible numbers, not an error).

**Recipes vs targets:** the run recipe is defined for all four families, but measured
comparison targets in [reference](references/stream-reference-hbv4-hx.md) exist only for **HBv4/HX**. For
HBv2/HBv3 you can run and report, but there's no baseline to diagnose against yet — say
so rather than comparing to an HBv4 number.

## When to do what
- **"Run STREAM" / "check memory bandwidth"** → run the optimal config below and report.
- **"Why is my STREAM slow?" / user brings their own numbers** → find their run directory
  (scan from `~`, confirm which directory holds their binary, run script, or logs), then
  run the diagnostic workflow — don't just re-benchmark.

## Optimal run
AOCC 4.0.0, 560M doubles/array, 100 iterations, **176 threads**, `GOMP_CPU_AFFINITY=0-175`,
THP `always` (HBv4/HX; other families use their own thread/affinity recipe automatically).
560M is the default because its bandwidth matches Azure's published sustained figures.
Reuse a verified binary; build only if missing (see `scripts/build-stream.sh`). Put
`stream` and `setenv_AOCC.sh` in `$WORK_ROOT`, pass the detected token, then run 3 trials:

```bash
bash "$SKILL_DIR/scripts/run-stream.sh" "$WORK_ROOT" hbv4 3
```

The runner sets THP `always` on both `enabled` and `defrag`, drops caches before each
trial, runs STREAM 3× into separate logs, prints a median/range summary, and restores
THP to its original value on exit. It changes host state (THP, page cache) without
prompting — both are benign here (THP is restored on exit; page cache repopulates on its
own) — and the summary states exactly what was done.

## Diagnostic workflow (user's own results look off)
1. Detect and report the **VM size / platform** (see "Detect the platform" above — same
   IMDS command).
2. Check **NUMA topology + total memory** against the
   [topology skill](../azure-hbv4-hx176-topology/SKILL.md); flag any mismatch.
3. Check for **other memory consumers / pressure**, including cgroup limits.
4. Run STREAM with the **optimal config** above and compare to the targets in
   [reference](references/stream-reference-hbv4-hx.md).
5. If the optimal run hits target but the user's doesn't, the gap is almost certainly
   their **config** — compiler flags, run parameters (threads/affinity), or huge pages.
   Compare against [reference](references/stream-reference-hbv4-hx.md).

## Reporting
Present a Copy/Scale/Add/Triad table with **median + range in MB/s** (from the runner's
summary), plus build, array/iterations, threads, affinity, THP, validation, and log path.
Don't cherry-pick a peak. Low bandwidth alone isn't proof of bad hardware; if the
evidence is thin, say inconclusive.

## Improving the result (when asked how to go faster)
The real lever is placement: 144 threads balanced six per physical CCD gives ~2-3% higher
Triad on HBv4/HX (see [reference](references/stream-reference-hbv4-hx.md)). Offer it as a manual note and keep
176 the default — the runner does not execute it; the mask is documented in the reference.
Do **not** suggest shrinking the array to get a bigger number — that's cache inflation,
not real bandwidth, and would drift the reported figure away from Azure's published specs.
