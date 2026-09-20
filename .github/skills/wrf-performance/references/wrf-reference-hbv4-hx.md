# HBv4/HX WRF reference

Load this when diagnosing a result or tuning, not for a routine run. Numbers are observations on one `Standard_HB176rs_v4` node, not guarantees; rerun after image, compiler, MPI, or WRF changes.

## Current recipe (WRF 4.2.2, v4.2 CONUS)

| Item | Value |
|---|---|
| WRF commit | `fb60d61cc44e2a2e8b8311f0b79185724010d510` (v4.2.2) |
| Dataset | `https://www2.mmm.ucar.edu/wrf/users/benchmark/v422/v42_bench_conus2.5km.tar.gz` |
| Dataset SHA-256 | `dcae9965d1873c1c1e34e21ad653179783302b9a13528ac10fab092b998578f6` |
| Namelist with 16×11 grid, SHA-256 | `9ee91fe71336adb99b7a4da2dcb9af29b416c5fe69b3a4c2f74da7a82c9c50f4` |
| Case | 1501×1201×50 grid, 15 s timestep, `radt=3`, one-hour restart |
| Dependencies (`build-deps.sh`) | zlib 1.3.2, HDF5 1.14.6, NetCDF-C 4.9.2, NetCDF-Fortran 4.5.4 |
| Compiler | GCC 13+ (needed for `-march=znver4`) |

### Single-node baseline

Measured 2026-09-20 on one `Standard_HB176rs_v4`: Ubuntu 24.04.4,
kernel `6.8.0-1064-azure`, GCC/GFortran 13.3.0, HPC-X Open MPI 4.1.9a1,
NetCDF-C 4.9.2, and NetCDF-Fortran 4.5.4. The run used 176 ranks bound in
order to CPUs 0-175, a 16x11 process grid, and
`-O3 -march=znver4 -Ofast -ftree-vectorize -funroll-loops`.

| Runs | Last-149 s/step | Step SD | Wall time | Final output write |
|---:|---:|---:|---:|---:|
| 1 | **2.413096** | 2.223501 | **12:56.39** | 23.22274 s |

This is one run, so it establishes a reference point but no run-to-run variance.
`step_sd_seconds` is variation between timesteps, not measurement uncertainty.
The run completed all 240 timesteps and wrote the final output. Numerical comparison
is `REVIEW_REQUIRED` because no scientific acceptance tolerance is defined for the
expected floating-point differences from `-Ofast`.

The NetCDF pair matches the recorded 4.4.2 results. The original 4.2.2 recipe used zlib 1.2.13, HDF5 1.12.2, NetCDF-C 4.7.4, and NetCDF-Fortran 4.5.3; those are superseded (zlib 1.2.13 is no longer on zlib.net, HDF5 1.12 is end of life). Other versions work too and are recorded in the manifests; they barely affect the timing metric (it excludes I/O), but list them as a difference when comparing.

## Historical results: WRF 4.4.2

Ubuntu 24.04, GCC/GFortran 13.3, Open MPI 5.0.10, NetCDF-C 4.9.2, NetCDF-Fortran 4.5.4, WRF commit `6233639c599119e76fca17dba9ea211af53a0ba9`. Fastest `wrf.exe` SHA-256: `fdbe76eb664a59de4cf73a8a8b6aa70d8f3821a7c0d2d4a907e4e6647da3716d` (specific to that environment).

### v4.2 dataset (`radt=3`), 176 ranks, CPUs 0-175, grid 16×11

| Fortran flags | Last-149 s/step | Wall time |
|---|---:|---:|
| `-O3 -march=znver2` | 2.742287 | 15:30.33 |
| `-O3 -march=znver4` | 2.738733 | 15:29.30 |
| `-O3 -march=znver2 -Ofast` | 2.612883 | 15:07.79 |
| `-O3 -march=znver4 -Ofast` | **2.580346** | **14:52.13** |

`-Ofast` gave the main gain: 4.72% with `znver2`, 5.78% with `znver4`. `znver4` over `znver2` gave 0.13% at `-O3` and 1.25% at `-Ofast`.

### v4.4 dataset (`radt=10`, lighter than v4.2)

Dataset: `https://www2.mmm.ucar.edu/wrf/users/benchmark/v44/v4.4_bench_conus2.5km.tar.gz`

| Layout | Last-149 s/step | Wall time |
|---|---:|---:|
| 144 ranks, 12×12 | 2.347363 | 14:04.02 |
| 176 ranks, 16×11 | 2.207473 | 13:56.51 |
| 168 ranks, 14×12, local NVMe | 2.185455 | 13:37.00 |

The 168-rank lead (~1%) is from one trial. Keep 176 as the baseline and repeat finalists before adopting a change.

## Storage

The timing metric excludes initialization and output writes, so storage doesn't change it. At 168 ranks on the v4.4 case:

| Storage | Last-149 s/step | Wall time | Final output write |
|---|---:|---:|---:|
| Managed temp disk | 2.184939 | 13:48.62 | 31.86 s |
| Two local NVMe, RAID0 | 2.185455 | 13:37.00 | 29.80 s |

RAID0 cut wall time ~12 s. It's temporary and non-redundant; creating it formats the devices, so ask first.

Multi-node (not covered by this skill's recipe): stage the executable, tables, and inputs to the same local path on every node (or use a shared filesystem, which may bottleneck startup and output), verify the RDMA transport, and report timing, restart-read time, each `Timing for Writing`, and wall time separately.
