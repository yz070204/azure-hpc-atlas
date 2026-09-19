---
name: wrf-performance
description: Build, run, and triage WRF performance on Azure HPC VMs with the CONUS 2.5 km benchmark. Validated single-node recipe for full-size HBv4/HX (WRF 4.2.2, v4.2 CONUS, 176 ranks).
user-invocable: false
---

# WRF performance

Validated for a single full-size HBv4/HX node. Other SKUs and multi-node runs are not covered; don't reuse this recipe's numbers for them.

## Detect the platform (do this first)
Read the VM size from IMDS:

```bash
curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text"
```

| VM size | Recipe |
|---|---|
| `Standard_HB176*_v4`, `Standard_HX176*` (no hyphen after `176`) | This recipe (same CPU and topology; HX only adds memory) |
| Anything else | Stop and report: no validated recipe |

## When to do what
- **"Run the WRF benchmark" / "is WRF performance OK here?"** → Optimal run, then compare to the [reference](references/wrf-reference-hbv4-hx.md).
- **"Why is my WRF slow?"** → Diagnostic workflow on the user's own run; don't just re-benchmark.
- **"How do I make WRF faster?"** → Improving the result.

The benchmark downloads WRF source and a ~14 GiB dataset, builds WRF, and runs about 15 minutes on all 176 cores. If the user asked to run it, that is the approval: do the whole flow (download, build, run, summarize) without further prompts. Ask first only when you propose it yourself (e.g. as a deeper check during triage).

## Recipe

| Item | Value |
|---|---|
| WRF | 4.2.2, commit `fb60d61cc44e2a2e8b8311f0b79185724010d510` |
| Input | Official v4.2 CONUS 2.5 km restart case (`radt=3`), one simulated hour |
| Toolchain | GCC 13+, Open MPI/HPC-X, NetCDF-C 4.9.2 / NetCDF-Fortran 4.5.4 |
| Flags | `-O3 -march=znver4 -Ofast -ftree-vectorize -funroll-loops` |
| Launch | 176 ranks × 1 thread, `--map-by core --bind-to core`, grid 16×11 |
| Metric | Mean of the last 149 rank-0 `Timing for main` records (s/step) |

`-Ofast` relaxes floating-point rules. The run compares key output fields against the dataset's reference output and reports `comparison_status=REVIEW_REQUIRED`: no acceptance tolerance is defined, so completion is not scientific validation.

## Optimal run
Select GCC 13+ and HPC-X/Open MPI first (e.g. `module load mpi/hpcx`). If `nf-config` isn't available, build NetCDF into the work directory with `build-deps.sh` (nothing is installed system-wide). Use a large local disk for `WORK_ROOT`.

```bash
SKILL_DIR=<repo>/.github/skills/wrf-performance
WRF_SRC=$WORK_ROOT/WRF-v4.2.2
ARCHIVE=$WORK_ROOT/v42_bench_conus2.5km.tar.gz
RUN_DIR=$WORK_ROOT/conus-v42-run-01          # must not exist yet

# NetCDF, only if nf-config is missing (zlib, HDF5, NetCDF-C/Fortran into one prefix).
if ! command -v nf-config >/dev/null; then
  bash "$SKILL_DIR/scripts/build-deps.sh" "$WORK_ROOT/deps"
  export PATH=$WORK_ROOT/deps/bin:$PATH LD_LIBRARY_PATH=$WORK_ROOT/deps/lib:$LD_LIBRARY_PATH
fi

# Source and dataset, only if missing.
[[ -d $WRF_SRC ]] || git clone --branch v4.2.2 --depth 1 --recurse-submodules https://github.com/wrf-model/WRF.git "$WRF_SRC"
[[ -f $ARCHIVE ]] || curl -fL -o "$ARCHIVE" https://www2.mmm.ucar.edu/wrf/users/benchmark/v422/v42_bench_conus2.5km.tar.gz

# Build only if $WRF_SRC/main/wrf.exe is missing.
bash "$SKILL_DIR/scripts/build-wrf.sh" "$WRF_SRC"

# Run and summarize.
bash "$SKILL_DIR/scripts/run-conus.sh" "$WRF_SRC" "$ARCHIVE" "$RUN_DIR"
```

- `build-deps.sh` downloads and builds zlib, HDF5, NetCDF-C, and NetCDF-Fortran (pinned versions) into one prefix and writes `deps-manifest.txt`.
- `build-wrf.sh` configures GNU dmpar with the pinned flags, compiles `em_real` (`NPROCS` jobs, default 8), and writes `build-manifest.txt` (commit, flags, tool and NetCDF versions, `wrf.exe` hash, linkage). It refuses an already-configured tree; use a fresh checkout to rebuild.
- `run-conus.sh` checks the commit, flags, and dataset checksum; prepares a new run directory with the 16×11 grid; verifies ranks land on CPUs 0-175 in order; runs WRF; then calls `summarize.sh`.
- `summarize.sh <run-dir>` checks completion and input integrity, computes the timing metric, and runs the numerical comparison. Rerun it alone if WRF finished but reporting failed.

## Diagnostic workflow (user's results look off)
1. Detect the platform (above).
2. Run the readiness quick checks, including the topology checker; a topology or frequency problem explains everything downstream.
3. Recover what the user actually ran: `wrf.exe` and its `configure.wrf` flags, WRF version, dataset (v4.2 `radt=3` vs v4.4 `radt=10` are not comparable), `nproc_x`/`nproc_y`, launch command and binding, and rank-0 `rsl.error.0000`.
4. Compare with the reference for the **same** WRF version, dataset, and rank count.
5. If approved, run the optimal recipe. If it matches the reference but the user's run doesn't, the gap is their configuration: usually flags (missing `-Ofast` or wrong `-march`), unpinned or misordered ranks, a different grid, or contention.

## Reporting
One table: dataset, WRF version/commit, compiler/MPI/NetCDF versions (from the manifests), ranks and grid, flags, mean s/step, wall time, comparison status, and any differences from the reference run. `step_sd_seconds` is variation between timesteps, not run-to-run uncertainty. Don't call a comparison apples-to-apples while known differences remain.

## Improving the result
From the [reference](references/wrf-reference-hbv4-hx.md) (WRF 4.4.2 measurements):
- `-Ofast` is the main compiler lever (~5% over `-O3`); `znver4` vs `znver2` adds 0.1-1.3%.
- 168 ranks (14×12) beat 176 by ~1% in a single trial on the v4.4 case; repeat before adopting.
- Local NVMe RAID0 doesn't change the timing metric; it only trims wall time slightly.

Change one factor at a time, keep the numerical comparison, and repeat finalists before claiming a gain under ~1%.

## If something fails
| Failure | Next step |
|---|---|
| Build fails | Read `configure.log` / `compile.log` in the source tree; fix the cause. Never clean or rebuild speculatively; change toolchain or flags only in a fresh checkout. |
| Checksum mismatch | Wrong or corrupt dataset/namelist. Never replace the expected checksum. |
| Run directory exists | Review it, or choose a new directory. Never delete it automatically. |
| WRF or binding fails | Keep the logs (`mpi.stdout`, `rsl.error.*`), fix the cause, rerun in a new directory. |
| Same failure twice | Report the command, error, and log path instead of retrying. |
