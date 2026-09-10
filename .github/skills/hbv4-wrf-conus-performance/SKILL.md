---
name: hbv4-wrf-conus-performance
description: Run, compare, and tune single-node WRF CONUS 2.5 km on Azure Standard_HB176rs_v4. Use for WRF builds, CONUS benchmarks, MPI pinning, process grids, compiler flags, or report-compatible timing.
user-invocable: false
---

# HBv4 WRF CONUS performance

Reuse the measured workflow instead of rediscovering it.

## Workflow

1. Run `scripts/inventory.sh`. Continue only for a full
   `Standard_HB176rs_v4` with 176 physical cores and four NUMA nodes.
   Treat reported tool versions and paths as the current image state, not
   fixed requirements.
2. Read `references/results.md` before retuning. Read `references/build.md`
   before building, replacing, or comparing an executable.
3. Distinguish the datasets:
   - v4.2: `v422/v42_bench_conus2.5km.tar.gz`, `radt=3`.
   - v4.4: `v44/v4.4_bench_conus2.5km.tar.gz`, `radt=10`.
   Never compare their timestep rates as the same workload.
4. For published v4.2 comparisons, use 176 ranks, ordered CPUs `0-175`,
   `nproc_x=16`, `nproc_y=11`, and the exact v4.2 restart namelist.
5. Calculate the report metric with:
   `scripts/summarize.sh <run-directory>`. It averages field 9 of the last
   149 rank-0 `Timing for main` records; file I/O and initialization are
   excluded.
6. Use `-O3 -march=znver4` for conservative scientific runs. For benchmark
   performance, the measured winner is `-O3 -march=znver4 -Ofast`; disclose
   relaxed floating-point semantics and validate output.
7. Run competing configurations sequentially on an idle node. Keep dataset,
   binary except for the tested flag, rank count, process grid, storage, and
   metric fixed. Repeat finalists before claiming a sub-1% win.
8. Preserve commands, `configure.wrf`, `namelist.input`, logs, output checks,
   and exact versions. Run `scripts/build-manifest.sh <WRF-source-directory>`
   for every executable used in a reported comparison.

## Guardrails

- Do not call 168 ranks universally optimal; its measured v4.4 lead over 176
  was about 1% from one trial and is not a report-compatible configuration.
- Do not attribute NVMe gains to `Timing for main`; that metric excludes WRF
  output writes.
- NVMe and RAID0 are optional. Use them only to improve staging, restart-read,
  history-output, or end-to-end wall time; they are not required for compute
  timestep calibration.
- For multi-node runs, require a common path or identical per-node staging.
  NFS is acceptable for convenience and small tests, but do not assume it is
  performance-optimal. Measure metadata, restart-read, and output throughput.
- Discover artifacts from environment overrides and mounted filesystems. Never
  require a particular workspace or mount path.
- Base HPC images evolve. Discover the active compiler, MPI, NetCDF, module,
  executable, and library paths on every run; do not reuse a historical
  `/opt/...` path or assume the calibrated versions are still installed.
- Search `/opt` first because Azure HPC images commonly install their optimized
  stacks there, then fall back to the active environment and other discovered
  filesystems. Treat `/opt` as a priority, not a requirement.
- Keep each build on one coherent toolchain. Verify that MPI wrappers resolve
  to the intended compiler and that `wrf.exe` links to the intended MPI and
  NetCDF libraries.
- Verify MPI launch and binding syntax against the discovered Open MPI/HPC-X
  version rather than assuming options from an earlier image.
- Never claim scientific equivalence from successful completion alone.
- Ask before formatting disks or changing persistent/global system settings.

## Expected output

Report dataset, WRF/compiler/MPI versions, ranks, process grid, flags,
last-149 seconds/timestep, wall time, output validity, and comparison basis in
one compact table.

## Human reproduction harness

Prefer `scripts/run-conus-v42.sh` over an ad hoc launch. It verifies the
official v4.2 archive checksum, full-size HBv4 topology, idle state, fixed
WRF commit and flags, namelist values, 16×11 decomposition, and ordered
rank-to-vCPU binding. It
records input, build, run, and output hashes; refuses to reuse a run directory;
and fails if inputs change or all 176 ranks do not complete.

```bash
export PATH=<coherent-mpi-prefix>/bin:$PATH
curl -fL -o v42_bench_conus2.5km.tar.gz \
  https://www2.mmm.ucar.edu/wrf/users/benchmark/v422/v42_bench_conus2.5km.tar.gz

.github/skills/hbv4-wrf-conus-performance/scripts/run-conus-v42.sh \
  <WRF-source-directory> \
  "$PWD/v42_bench_conus2.5km.tar.gz" \
  <new-run-directory>
```

The WRF source must already be built as documented in `references/build.md`.
The harness intentionally requires a new run directory and never edits the
archive. Its only namelist change is adding the fixed `nproc_x=16` and
`nproc_y=11` decomposition; the resulting namelist has a pinned checksum.
Physics, domain, timestep, and simulation period remain unchanged. Inspect
`build-manifest.txt`, `run-manifest.txt`,
`benchmark-results.txt`, `numerical-differences.csv`, and `inputs.sha256` in
the run directory. Numerical differences are marked `REVIEW_REQUIRED`; the
harness does not invent a scientific acceptance threshold.
