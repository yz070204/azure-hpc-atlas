# STREAM preparation and manual commands

Load this reference only for missing artifacts, exact launch details or an
explicit tuning request. The [main skill](../SKILL.md) defines routing:
176-thread original source by default, 176-thread original AMD prebuilt when
requested. The 144-thread profiles are optional, not automatic.

## Script layout

The entry scripts keep the actual compiler and launch commands visible:
settings, checks, environment, execution, then results.

| File | Responsibility |
|---|---|
| [`scripts/build-stream.sh`](../scripts/build-stream.sh) | Original compiler flags and build steps |
| [`scripts/run-stream.sh`](../scripts/run-stream.sh) | Profile settings, explicit launch commands and trial loop |
| [`scripts/lib/checks.sh`](../scripts/lib/checks.sh) | Approval, input, binary/runtime identity and host-readiness checks |
| [`scripts/lib/records.sh`](../scripts/lib/records.sh) | Build/run manifests, exact command logging and library hashes |
| [`scripts/lib/thp.sh`](../scripts/lib/thp.sh) | Save, enable and restore approved THP settings |
| [`scripts/summarize.py`](../scripts/summarize.py) | Numerical/affinity validation and result statistics |
| [Shared topology checker](../../azure-hbv4-hx176-topology/scripts/check-topology.sh) | Read-only Bash/awk validation of the documented full-size guest signature |

The shell helpers are sourced by the entry scripts, not executed separately.
They use the settings declared at the top of those scripts. The topology
checker is standalone and benchmark-independent. Python is used only for
STREAM result parsing, not embedded in build/run scripts or topology checks.
Keep the sibling skill directories together when copying this workflow.

## Prepare paths and prerequisites

From the repository root:

```bash
export SKILL_DIR="$PWD/.github/skills/hbv4-stream-performance"
export WORK_ROOT=/absolute/path/to/existing/writable/directory
test -f "$SKILL_DIR/SKILL.md" && test -d "$WORK_ROOT" && test -w "$WORK_ROOT"
```

Discover the chosen compiler rather than assuming an image path:
`/opt` first, then modules/PATH and scoped work directories. Set `AOCC_ROOT`
to the verified extracted AOCC 4.0.0 directory. A newer image compiler is
not an approved replacement. Record identity and compatibility.

Check `lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE`, `numactl --show`,
`/proc/self/status` allowed CPUs/memory nodes, effective cgroup ancestor limits,
`free -h`, `vmstat 1 3`, and `df -h "$WORK_ROOT"`.
The allocation must expose CPUs 0-175 and memory nodes 0-3. Low load is not
proof of exclusive access. The runner validates the full topology for original
and balanced profiles, but cannot establish exclusive allocation or all cgroup
limits. Bash, awk, Python 3 standard library, curl, tar, coreutils, lscpu, vmstat,
numactl and authorized `sudo -n` are required. Do not install missing tools
without approval.

Original arrays occupy 6.72 GB total; prebuilt arrays occupy 15.6 GB.
Require at least 24 GiB available for these profiles, including cgroup capacity.
The prebuilt requires AVX-512 and compatible runtime libraries.

## Download only missing approved artifacts

Obtain authorization to use AMD's licensed packages; an agent cannot accept
an EULA for the user. Retain bundled terms, inspect archive member paths, and
extract into a new work directory with `tar --no-same-owner`. Do not overwrite
existing source/builds or commit vendor archives/binaries.

| Artifact | URL | SHA-256 |
|---|---|---|
| AMD prebuilt | https://download.amd.com/developer/eula/pre-built/stream/amd-zen-stream-2024_10_08.tar.gz | `279b83c7dbc3b2bdf80bafdd5456ae4fbf9fc35d7ca73f271c1a6914c7461b46` |
| AOCC 4.0.0 | https://download.amd.com/developer/eula/aocc-compiler/aocc-compiler-4.0.0.tar | `2729ec524cbc927618e479994330eeb72df5947e90cfcc49434009eee29bf7d4` |
| Pinned STREAM source | https://raw.githubusercontent.com/jeffhammond/STREAM/6703f7504a38a8da96b353cadafa64d3c2d7a2d3/stream.c | `c388924eb140fda95f534cdb808ae7f1f8ebb18da41d8aec1b512a3c8d303c9b` |

Download with `curl -fL -o artifact.part URL`, check SHA-256, then rename.
Stop on a mismatch; do not replace the expected hash with an unexpected one.
These are retrieved-artifact identities, not vendor signatures.

## Source build

After license and relaxed-floating-point approval:

```bash
STREAM_LICENSE_ACCEPTED=yes STREAM_RELAXED_FP_APPROVED=yes \
STREAM_ARRAY_SIZE=280000000 STREAM_NTIMES=100 \
bash "$SKILL_DIR/scripts/build-stream.sh" \
  "$AOCC_ROOT" "$WORK_ROOT/stream.c" "$WORK_ROOT/build-original"
```

The Bash helper records the documented flags, double precision, source copy,
compiler identity, libraries and executable checksum in the build directory:

```text
-fopenmp -mcmodel=large -DSTREAM_TYPE=double
-DSTREAM_ARRAY_SIZE=280000000 -DNTIMES=100
-ffp-contract=fast -fnt-store -O3 -Ofast -ffast-math -ffinite-loops
-march=native -zopt -fremap-arrays -mllvm -enable-strided-vectorization
-fvector-transform
```

`-Ofast` and fast math relax numerical semantics; require successful STREAM
validation. Do not remove unsupported flags or substitute upstream Clang.
`-march=native` binds the binary to the build CPU's capabilities. This helper
uses process-local compiler paths and needs no global installation.

## Exact run profiles

| Profile | Threads / affinity | Arrays / iterations | THP | Cache drop |
|---|---|---|---|---|
| **`source-original` (default)** | 176, `GOMP_CPU_AFFINITY=0-175` | 280M / 100 | always | Before every trial, separately approved |
| **`prebuilt-original`** | 176, `OMP_PROC_BIND=true OMP_PLACES=cores` | 650M / 10 | always | No |
| `tuned-144` | 144, physical-CCD-balanced GOMP list | 280M / 100 | always | No |
| `prebuilt-144` | 144, physical-CCD-balanced GOMP list | 650M / 10 | always | No |
| `normalized-176` (comparison only) | 176, OMP core binding, `numactl --localalloc` | Selected binary's dimensions | Unchanged | No |

All except `prebuilt-original` set `OMP_SCHEDULE=static`, `OMP_DYNAMIC=false`,
`OMP_THREAD_LIMIT=512`, `OMP_STACKSIZE=256M`. Source original retains these
settings; prebuilt original deliberately adds none of them. Every profile
uses a clean launch environment with only the explicitly selected runtime
path; this reproduces stated benchmark parameters, not unknown historical
shell variables. Original/default profiles require inherited default NUMA
policy and do not add a memory-policy wrapper.

THP means both allocation and defrag. Set `STREAM_THP_APPROVED=yes` only after
explicit approval; the helper saves/restores prior values. For source original,
also obtain `STREAM_CACHE_DROP_APPROVED=yes` before the `sync`/`drop_caches=3`
operation. Restoring THP does not undo cache drops. If approval is absent,
stop; do not silently run a different profile or pretend the original ran.
These helpers do not require cloud provisioning, SSH configuration or uploads.

The source profiles require the pinned source, original dimensions, AOCC
4.0.0 version/runtime and matching binary manifest. Prebuilt profiles check
the AMD executable hash and reject a runtime-library argument. Keep build flags
with provenance; inspecting the active compiler cannot prove how an old binary
was built. `normalized-176` intentionally permits separate comparison builds.

## Optional 144-thread runs

Show the relevant command after a default run when explaining the optional
improvement. Do not execute it merely because this reference is loaded.
After approval, using **new** result directories:

```bash
# Same original source binary; optional placement change, no cache drops.
STREAM_PROFILE=tuned-144 STREAM_RUN_APPROVED=yes STREAM_THP_APPROVED=yes \
bash "$SKILL_DIR/scripts/run-stream.sh" \
  "$WORK_ROOT/build-original/stream" "$WORK_ROOT/run-source-144" 3 "$AOCC_ROOT/lib"

# Same AMD prebuilt; optional placement change.
STREAM_PROFILE=prebuilt-144 STREAM_RUN_APPROVED=yes STREAM_THP_APPROVED=yes \
bash "$SKILL_DIR/scripts/run-stream.sh" \
  "$WORK_ROOT/amd-zen-stream-2024_10_08/amd_zen_stream" \
  "$WORK_ROOT/run-prebuilt-144" 3
```

The helper selects six CPUs starting at offsets `0,8,16,24,32,38` within each
NUMA base `0,44,88,132`: six per physical CCD, 36 per NUMA, 144 total.
Do not use the first 144 CPUs, guest cache IDs, or another SKU's mapping.
The profile checks the full expected guest topology before applying this list.

Source 144 versus original also omits cache drops. Prebuilt 144 versus
prebuilt original changes affinity and additional OpenMP controls, not just
thread count; the isolated evidence is in the detailed studies.

## Output and recovery

Read `summary.json`, `run-manifest.txt`, `libraries.txt`, build manifests,
`stream-N.log`, load samples, and `thp-active.txt`/`thp-restored.txt`.
The run manifest records the exact command for each trial.
The runner verifies every kernel, numerical validation even when exit status
is zero, actual expected singleton CPU binding, and required profile dimensions.
Timeout, non-finite/missing data or inconsistent output stops the batch.
Do not bypass checks or reuse an existing output directory.

Default is three trials, each 120 seconds plus five-second termination grace.
Report medians of best-iteration rates and ranges. `average_rate_metrics`
uses algorithmic bytes divided by printed, rounded average time; it is not
hardware-measured DRAM traffic. If restoration fails or the process is killed
before its exit handler runs, restore from `thp-original.txt` with authorization
and verify live settings before proceeding.

## Explicit matched comparison

Only when a build-method comparison is requested, build a **separate**
650M/10 source binary and select `normalized-176` for both candidates:

```bash
STREAM_LICENSE_ACCEPTED=yes STREAM_RELAXED_FP_APPROVED=yes \
STREAM_ARRAY_SIZE=650000000 STREAM_NTIMES=10 \
bash "$SKILL_DIR/scripts/build-stream.sh" \
  "$AOCC_ROOT" "$WORK_ROOT/stream.c" "$WORK_ROOT/build-matched"

STREAM_PROFILE=normalized-176 STREAM_RUN_APPROVED=yes \
bash "$SKILL_DIR/scripts/run-stream.sh" \
  "$WORK_ROOT/build-matched/stream" "$WORK_ROOT/run-matched-source" 3 "$AOCC_ROOT/lib"

STREAM_PROFILE=normalized-176 STREAM_RUN_APPROVED=yes \
bash "$SKILL_DIR/scripts/run-stream.sh" \
  "$WORK_ROOT/amd-zen-stream-2024_10_08/amd_zen_stream" \
  "$WORK_ROOT/run-matched-prebuilt" 3
```

Obtain a six-trial budget and verify the prebuilt identity separately; the
normalized profile does not enforce a specific binary/dimension hash.
Keep host conditions matched, preferably interleaving one-trial candidates.
THP is unchanged: the initial study used `madvise`; record differences rather
than changing global settings implicitly. Neither launch is an original
default reproduction, and this build must never replace `build-original`.
