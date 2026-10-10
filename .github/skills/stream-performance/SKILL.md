---
name: stream-performance
description: Run STREAM and triage memory-bandwidth performance on Azure HPC VMs. Validated HBv4/HX recipes and single-VM full-size HBv5 measurements; HBv2/HBv3 recipes have no comparison targets.
user-invocable: false
---

# STREAM performance

Validated on full-size Azure HBv4/HX, with a single-VM recipe and measured
[HBv5 reference](references/stream-reference-hbv5.md) for `Standard_HB368rs_v5`.
HBv2/HBv3 have recipes but no comparison targets; constrained-core sizes are not covered.

## Detect the platform (do this first)
Read the VM size from Azure IMDS, then map it to a platform token — don't guess the
mapping:

```bash
curl -fsS --max-time 10 --noproxy '*' -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text"
```

| VM size | platform token |
|---|---|
| `Standard_HB176*_v4` | `hbv4` |
| `Standard_HX176*` | `hx` |
| `Standard_HB368rs_v5` exactly | `hbv5` |
| `Standard_HB*_v3` | `hbv3` |
| `Standard_HB*_v2` | `hbv2` |

HBv4 and HX are distinct SKUs but the same 176-core silicon, so they share one recipe.
Reject hyphenated constrained-core sizes. If the size matches no known family,
**stop and report it** — do not fall through to a guessed recipe (a wrong recipe yields bad-but-plausible numbers, not an error).

**Recipes vs targets:** HBv4/HX comparison targets are in their
[reference](references/stream-reference-hbv4-hx.md); HBv5 measurements are single-VM
observations, not pass/fail thresholds. For HBv2/HBv3 you can run and report, but there's no baseline to diagnose against yet — say
so rather than comparing to an HBv4 number.

## When to do what
- **"Run STREAM" / "check memory bandwidth"** → run the optimal config below and report.
- **"Why is my STREAM slow?" / user brings their own numbers** → find their run directory
  (scan from `~`, confirm which directory holds their binary, run script, or logs), then
  run the diagnostic workflow — don't just re-benchmark.

## Optimal run
AOCC 4.0.0, 560M doubles/array, 100 iterations, **176 threads**, `GOMP_CPU_AFFINITY=0-175`,
THP `always` (HBv4/HX; other families use their own thread/affinity recipe automatically).
For HBv5 use **368 threads**, `GOMP_CPU_AFFINITY=0-367`; keep 560M as the
shared default.
Reuse a binary with matching arrays/iterations and compiler details in `build.json`;
build only if missing or parameters differ. `build-stream.sh` takes `$WORK_ROOT` as
its first argument (optional second: numeric array elements), installs AOCC and
compiles `stream` there (never in the caller's cwd), and reuses an already-cached AOCC install in that dir on a rerun instead of re-downloading:

Reuse the existing STREAM `$WORK_ROOT`; create one only if none exists.
AOCC 4.0.0 stays in `$WORK_ROOT/aocc-compiler-4.0.0`, separate from system compilers.
Downloading this private compiler and STREAM
source is part of the quick check; do not ask for separate approval or classify the
check as inconclusive merely because AOCC is missing. Run the helpers as subprocesses,
not by sourcing them; never use sudo for the build or change system compiler settings.

```bash
bash "$SKILL_DIR/scripts/build-stream.sh" "$WORK_ROOT"   # only if stream isn't already built
bash "$SKILL_DIR/scripts/run-stream.sh" "$WORK_ROOT" hbv4 3
```

The runner sets THP `always` on both `enabled` and `defrag`, drops caches before each
trial, runs STREAM 3× into separate logs in a unique directory, prints a median/range
summary, and restores THP to its original value on exit. It changes host state (THP, page cache) without
prompting — both are benign here (THP is restored on exit; page cache repopulates on its
own) — and the summary states exactly what was done.
Before each trial, three one-second overall CPU samples must all be below 5%.
The runner verifies exact effective thread/CPU placement and records build/run
metadata; HBv5 also requires the exact IMDS size and shared topology checker.

## Diagnostic workflow (user's own results look off)
1. Detect and report the **VM size / platform** (see "Detect the platform" above — same
   IMDS command).
2. Check **NUMA topology + total memory** against the
   [HBv4/HX topology](../azure-hbv4-hx176-topology/SKILL.md) or
   [HBv5 topology](../azure-hbv5-368-topology/SKILL.md); flag any mismatch.
3. Check for **other memory consumers / pressure**, including cgroup limits.
4. Run the detected family's recipe and compare only matched conditions against
   its reference; do not apply HBv4/HX targets to HBv5.
5. If a matched reference run performs well but the user's does not, investigate
   their **config** — compiler flags, run parameters (threads/affinity), or huge pages.
   Compare against the detected family's reference.

## Reporting
Present a Copy/Scale/Add/Triad table with **median + range in MB/s** (from the runner's
summary), plus build, array/iterations, threads, affinity, THP, validation, and log path.
Separate best-iteration rates from average-time-derived rates; `summarize.py`
reports both. Don't cherry-pick a peak. Low bandwidth alone isn't proof of bad
hardware; if the evidence is thin, say inconclusive.

## Improving the result (when asked how to go faster)
The real lever is placement: 144 threads balanced six per physical CCD gives ~2-3% higher
Triad on HBv4/HX (see [reference](references/stream-reference-hbv4-hx.md)). Offer it as a manual note and keep
176 the default — the runner does not execute it; the mask is documented in the reference.
Do **not** suggest shrinking the array to get a bigger number — that's cache inflation,
not real bandwidth, and would drift the reported figure away from Azure's published specs.
