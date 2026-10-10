# HBv5 STREAM reference

Example results from one quiet full-size `Standard_HB368rs_v5` (2026-10-09).
They reflect this specific build and method, not a performance specification
or health threshold. Numbers can vary with OS, compiler and software versions.
For published HBv5 figures, see the
[official performance page](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/high-performance-compute/hbv5-performance).

## Environment

- Ubuntu HPC image `24.04.2026092501`, kernel `6.8.0-1067-azure`; 368 cores,
  SMT off, 16 NUMA nodes, 48 L3 groups.
- AOCC 4.0.0, unmodified STREAM source, non-temporal stores, doubles, NTIMES=100.
- Static OpenMP, 256M worker stacks, parallel first-touch, THP=always.
- Three interleaved runs per config; caches dropped and CPU idle (<5%) before each.

## Results from source build

STREAM best-iteration rates, decimal TB/s, median of three runs.

| Array (doubles) | Threads / placement | Copy | Scale | Add | Triad |
|---|---|---:|---:|---:|---:|
| 560M (default) | 368, all-core | 5.77 | 5.81 | 6.28 | 6.24 |
| 560M (default) | 336, seven/CCD* | 5.97 | 6.02 | 6.46 | 6.42 |
| 560M (default) | 288, six/CCD | 5.87 | 5.90 | 6.38 | 6.37 |
| 800M | 368, all-core | 5.71 | 5.75 | 6.08 | 6.01 |
| 800M | 336, seven/CCD* | 5.96 | 5.95 | 6.45 | 6.42 |
| 800M | 288, six/CCD | 5.84 | 5.89 | 6.24 | 6.18 |

## MLC Stream-Triad Results

Intel MLC 3.13 `--loaded_latency -W10` (STREAM-Triad-like traffic, 2 MiB pages),
median of three 10-second runs: **6.77 TB/s** at 368 threads, 6.74 TB/s at 336
(seven/CCD).

## Notes

- Strict STREAM sizing: 4 x 1.5 GiB LLC ≈ 800M doubles/array (6 GiB).
  560M is below this and is a different workload, not more bandwidth.
- Placement masks are vCPU lists from supplied CCD membership, not host core IDs.
- Larger stacks (8192M) or disabling NUMA balancing gave no meaningful gain.
- Constrained-core sizes, TuneD and other OSes were not tested.
