---
name: hbv4-wrf-conus-performance
description: Build and run the single-node WRF 4.2.2 and v4.2 CONUS 2.5 km comparison on Azure Standard_HB176rs_v4. Use for WRF builds, CONUS benchmarks, MPI pinning, process grids, compiler flags, and report-compatible timing; preserve original dependencies where possible and disclose substitutions.
user-invocable: false
---

# HBv4 WRF CONUS performance

This is a human-readable runbook as well as an agent skill. No AI subscription
is needed to follow it. Work through **Check -> Build -> Run -> Review**.
Stop at a failed checkpoint; do not improvise a different benchmark.

## Choose the scope

The default is the **single-node validation comparison**, not a general WRF installer:

| Item | Default |
|---|---|
| VM | One `Standard_HB176rs_v4`, 176 exposed cores, four NUMA nodes |
| WRF | v4.2.2 at the commit in [build.md](references/build.md) |
| Input | Official v4.2 CONUS 2.5 km restart dataset, `radt=3` |
| Launch | 176 MPI ranks, one thread each, ordered CPUs 0-175, grid 16x11 |
| Build flags | `-O3 -march=znver4 -Ofast -ftree-vectorize -funroll-loops` |
| Metric | Mean of the last 149 rank-0 `Timing for main` records |

`-Ofast` relaxes floating-point semantics. Obtain agreement before using it;
successful completion is not scientific validation. Use the approved `znver4`
target on HBv4 and record that difference from older `znver2` builds. Prior
WRF 4.4.2 measurements showed a smaller ISA-target effect than the `-Ofast`
effect; that is not a guarantee for every build or input. Keep `-Ofast`
consistent when comparing the default benchmark. Conservative `-O3`, WRF
4.4.2, v4.4 input (`radt=10`), other ranks, and multi-node runs are separate
experiments. The current runner deliberately
rejects different source commits or flags. Do not loosen its checks to make
an alternative configuration pass.

Keep WRF and dataset versions fixed. Prefer the original dependency versions:
zlib 1.2.13, HDF5 1.12.2, NetCDF-C 4.7.4 and NetCDF-Fortran 4.5.3. Discover
their locations rather than requiring old image paths. If unavailable or
affected by an identified security/support concern, document the evidence,
proposed replacement and user approval before substituting; do not silently
use whatever is on PATH or downgrade image-owned packages.

Compiler and MPI versions must also be matched to the chosen prior run where
known; a module name alone does not pin a version. Record unknown baseline
versions as comparison gaps. The default launch requires compatible Open
MPI/HPC-X. Historical timings in [results.md](references/results.md) retain
their original WRF 4.4.2 or external-report labels; matching WRF/data alone
does not make a different toolchain an exact software-stack reproduction.
When given an older cluster-validation script or constants file, use the
[translation table](references/build.md#translating-a-cluster-validation-recipe)
before reusing its settings. Build jobs, MPI ranks, node count, source version,
and dataset version are separate choices; do not source the infrastructure
constants or silently replace the comparison recipe.

Start with one node. A later, separate four-node skill can exercise
cross-node MPI/InfiniBand with matched software, input, placement and timing.
Do not add that launch here or reuse its 144-ranks-per-node setting as the
single-node default. A successful single-node run does not validate IB
communication; a future multi-node run must verify the selected RDMA transport.

## Before starting

Humans: use a Bash terminal on the affected VM. Agents: reuse explicit paths
and known artifacts from the conversation; ask only for essential missing
choices. Obtain approval for downloads, builds, and a bounded benchmark run.
Do not install packages, change global settings, or format storage implicitly.

Run this setup from the **azure-hpc-atlas repository root**. Enter an existing
large writable directory, not a small root disk or another user's workspace:

```bash
export SKILL_DIR="$PWD/.github/skills/hbv4-wrf-conus-performance"
test -f "$SKILL_DIR/SKILL.md" || { echo "Start from the repository root" >&2; exit 1; }
read -r -p "Existing work directory (absolute path): " WORK_ROOT
[[ "$WORK_ROOT" = /* && -d "$WORK_ROOT" && -w "$WORK_ROOT" ]] ||
  { echo "Choose an existing writable absolute directory" >&2; exit 1; }
export WORK_ROOT
export WRF_SRC="$WORK_ROOT/WRF-v4.2.2"
export ARCHIVE="$WORK_ROOT/v42_bench_conus2.5km.tar.gz"
export RUN_DIR="$WORK_ROOT/conus-v42-run-01"
set -o pipefail
```

These names are defaults, not required locations. Set `WRF_SRC` and `ARCHIVE`
to existing artifacts when available; `RUN_DIR` must not exist for a new run.
Keep these absolute variables in subsequent commands, including after `cd`.
An agent whose tool starts a new shell must explicitly restore the variables
and selected toolchain rather than assume exports persisted.

## 1. Check

```bash
bash "$SKILL_DIR/scripts/inventory.sh"
LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE
df -h "$WORK_ROOT" "$(dirname "$ARCHIVE")" "$(dirname "$RUN_DIR")"
test -w "$(dirname "$ARCHIVE")" && test -w "$(dirname "$RUN_DIR")"
python3 -c 'import numpy; import netCDF4; print("Comparison dependencies available")'
```

**Continue only when:**

- Inventory exits zero with `applicability=PASS`. It checks aggregate
  SKU/core/NUMA counts, not the full topology. Compare the extended CPU output
  with [the topology reference](../azure-hbv4-hx176-topology/SKILL.md).
- The selected dependency versions match the comparison target or have a
  documented approved exception, and the active tools pass the discovery
  checks in [build.md](references/build.md).
  Check Python comparison dependencies now, not after a long run.
- Space covers the archive (about 14 GiB), extracted inputs, retained reference
  output, generated output, source/build files, logs, and a safety margin.
  The runner does not enforce that budget. Recheck before extraction.
- The node is otherwise idle or an approved allocation is available.
  `active_wrf=0` alone is insufficient: check other workloads, memory pressure,
  and I/O activity. Do not kill jobs or disable services to obtain an idle node.

The inventory currently searches `/opt`, home, and local mounts for candidates;
its output is discovery, not proof of a usable build. A fresh shell is not
an idle VM. For unexplained contention or environment differences, use
[first-line triage](../hpc-atlas-firstline-triage/SKILL.md).

## 2. Build or reuse

Follow [build.md](references/build.md) only if no suitable executable exists.
Prefer `scripts/build-wrf.sh`: a Bash script with environment preparation,
configuration and compilation steps. It checks the selected stack, performs
a small MPI/NetCDF Fortran link probe, discovers the GNU dmpar menu entry,
and preserves logs. It never installs dependencies, downloads source/data,
purges modules, or chooses a historical `/opt` prefix. No Python is needed
for building; Python is used only by the numerical output comparator.

The build reference supplies the default benchmark command with explicit
`-Ofast` consent and flags. The helper itself defaults to conservative `-O3`;
that default is not accepted by the comparison runner.

**Checkpoint:** the source/flags match the default, the compile log shows a
successful build, required libraries resolve, and a build manifest is saved.
An existing executable needs the same evidence; inspecting today's
`configure.wrf` or compiler cannot prove how an old binary was built. Do not
rebuild merely because a historical checksum or tool version differs.

## 3. Run

After approval and the space check, download only if the archive is absent:

```bash
if [[ ! -e "$ARCHIVE" ]]; then
  curl -fL -o "$ARCHIVE.part" \
    https://www2.mmm.ucar.edu/wrf/users/benchmark/v422/v42_bench_conus2.5km.tar.gz &&
    mv "$ARCHIVE.part" "$ARCHIVE"
fi
```

A failed transfer leaves `.part`; do not treat it as a complete archive.
The runner checks the official archive SHA-256 before extraction. It checks
the source commit, flags, canonical namelist and ordered rank binding, then
automatically creates manifests, runs WRF, verifies completion and inputs,
summarizes timing, and compares output:

```bash
bash "$SKILL_DIR/scripts/run-conus-v42.sh" "$WRF_SRC" "$ARCHIVE" "$RUN_DIR"
```

Do not run the helper scripts separately during a successful normal run.
The runner adds only the fixed 16x11 decomposition to the namelist; physics,
domain, timestep, and simulation period remain unchanged.

## 4. Review

Start with these files in `RUN_DIR`:

| File | What to read |
|---|---|
| `benchmark-results.txt` | `mean_seconds`, wall time, WRF completion, comparison status |
| `numerical-differences.csv` | Candidate-minus-reference differences for the selected fields |
| `mpi.stdout`, `launcher.log`, `rsl.error.0000` | Launch failures, wall time, rank-0 diagnostics |
| `build-manifest.txt`, `run-manifest.txt`, `inputs.sha256`, `affinity-preflight.txt` | Provenance, unchanged inputs, and rank placement; retain dependency exceptions with the report |

**Checkpoint:** all 176 ranks completed, input hashes match, timing contains
149 valid numeric records, and comparison completed. `REVIEW_REQUIRED` is
expected: no scientific acceptance tolerance is defined. The comparator
checks selected variables, not every output field; execution success and
numerical acceptance are separate.

The timing metric excludes initialization and output writes. Its
`step_sd_seconds` describes variation between timesteps, not uncertainty
across independent runs. Report dataset, source/toolchain, ranks/grid, flags,
mean seconds/step, wall time, numerical-review status and dependency/version
differences from the named prior run in one table. Do not call the result
"apples-to-apples" when known build, dependency or launch differences remain.
For tuning, keep conditions equivalent, change one factor at a time, preserve
correctness, and repeat finalists before claiming a sub-1% improvement.

## If a checkpoint fails

| Failure | Smallest safe next step |
|---|---|
| Missing metadata/tool/dependency, wrong SKU, busy node, or inadequate space | Explain the failed check; resolve that prerequisite before proceeding |
| Configure or compile failure | Inspect the stage log and preserve the source; follow the build reference for a justified fix, not automatic cleanup or speculative retries |
| Archive or namelist checksum mismatch | Preserve the evidence; verify the selected dataset/path. Never replace the expected checksum with the observed one |
| Run directory already exists | Inspect it first. Review a completed run, or select a new directory for an approved rerun; never delete it automatically |
| Launch, binding, or WRF failure | Preserve logs, fix the evidenced cause, and obtain approval for a new run directory |
| WRF completed but reporting/comparison failed | Fix the reporting prerequisite and rerun verification only, without rerunning WRF |

To repeat verification of an intact harness-created run:

```bash
bash "$SKILL_DIR/scripts/verify-conus-v42.sh" "$RUN_DIR"
```

Preserve previous report files first if they are evidence; verification rewrites
them. The current summarizer needs `launcher.log` and does not reject every
malformed timing value. Missing logs or implausible values are reporting gaps,
not a reason to claim success or rerun the simulation automatically.

Resume from the last successful checkpoint, **not** from an assumed WRF restart:
the runner cannot resume a partial simulation or reuse a run directory.
Keep valid downloads/builds. Retry only when a specific cause has been
addressed; if the same failure recurs, report the blocker, command, and log
location rather than loop through rebuilds or change the benchmark.

Agents: if the build helper fails, inspect the relevant log and make the
smallest evidence-backed fix to the helper or selected environment, preserving
local changes. Validate the fix before retrying. Do not bypass checks, change
the source version or scientific flags, install dependencies without approval,
or replace the script with an unrecorded ad hoc build. An unsupported interface
is a reason to explain the blocker, not to promise automatic repair.
