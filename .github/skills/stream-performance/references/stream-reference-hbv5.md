# HBv5 STREAM reference

Measured on one quiet full-size `Standard_HB368rs_v5` on 2026-10-09.
These are example measurements, not universal targets or hardware-health
thresholds. Constrained-core sizes are not covered. STREAM and MLC results
are separate benchmarks.

## Environment and method

- Ubuntu HPC image `24.04.2026092501`, Ubuntu 24.04.5, kernel
  `6.8.0-1067-azure`; EPYC 9V64H, 368 cores, SMT off, 16 NUMA nodes,
  48 L3 groups, 424.94 GiB guest-visible memory; topology checker passed.
- STREAM: private AOCC 4.0.0 (clang 14.0.6 build 434/libomp), unmodified
  source, existing native/non-temporal-store flags, doubles, OFFSET=0,
  NTIMES=100. Build metadata records compiler, flags and source revision.
- Three independent runs per configuration, interleaved within each batch;
  all samples retained. Before every run: three one-second CPU samples <5%,
  sync and drop_caches=3. THP enabled/defrag=always.
- Static OpenMP scheduling, 256M worker stacks, parallel first-touch initialization.
  Numerical validation and exact effective singleton CPU bindings passed.
  Actual STREAM page placement/huge-page backing was not independently measured.

All STREAM table values are **decimal GB/s, median (minimum-maximum)** across
three runs; multiply by 1000 for MB/s. Best-iteration rates are STREAM's own
minimum-time rates, not average-time bandwidth. Average-time-derived rates
use printed six-decimal timing and therefore have rounding uncertainty.

## 560M/100 - default

| Config | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 368 threads, all-core | 5765.7 (5765.7-5787.9) | 5806.7 (5803.1-5814.8) | 6277.4 (6265.6-6315.4) | 6236.5 (6236.5-6242.7) |
| 288 threads, six/CCD | 5867.4 (5867.4-5917.3) | 5902.5 (5894.1-5906.2) | 6381.9 (6361.0-6397.1) | 6372.5 (6363.9-6381.9) |

## 805,306,368/100 - strict 4x-LLC

| Config | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 368 threads, all-core | 5714.0 (5709.2-5731.6) | 5752.3 (5717.0-5798.6) | 6081.4 (6060.9-6083.2) | 6006.1 (5996.8-6024.9) |
| 288 threads, six/CCD | 5838.1 (5827.4-5867.2) | 5889.0 (5886.4-5905.1) | 6236.7 (6236.2-6242.5) | 6178.7 (6141.7-6178.7) |

## 280M/100 - smaller-array experiment

| Config | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 368 threads, all-core | 5872.0 (5872.0-5872.0) | 5864.7 (5855.6-5870.2) | 6227.5 (6187.9-6228.9) | 6262.1 (6234.4-6269.1) |
| 288 threads, six/CCD | 5935.1 (5925.7-5942.6) | 5965.2 (5957.7-5972.8) | 6339.6 (6291.5-6430.7) | 6345.3 (6315.4-6413.1) |

## Average-time-derived rates

These use bytes moved divided by each run's printed average time, then the
median/range across three runs. All-core averages vary more than best-iteration
rates; do not turn these observations into a guaranteed sustained-bandwidth target.

### 560M

| Config | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 368 threads, all-core | 4906.9 (4674.0-4915.0) | 4947.5 (4944.8-5391.1) | 5785.6 (5614.0-5846.0) | 5658.9 (5474.5-5899.9) |
| 288 threads, six/CCD | 5582.6 (5541.1-5714.3) | 5663.7 (5486.8-5699.7) | 6176.5 (6173.6-6245.4) | 6182.2 (6008.0-6233.8) |

### 4x-llc

| Config | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 368 threads, all-core | 5005.8 (4990.3-5123.2) | 5185.1 (4895.5-5195.5) | 5537.9 (5347.9-5545.9) | 5486.0 (5236.3-5676.2) |
| 288 threads, six/CCD | 5688.7 (5678.7-5696.2) | 5724.1 (5706.3-5759.9) | 6087.4 (6013.5-6114.3) | 6013.5 (5908.7-6028.5) |

### 280M

| Config | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 368 threads, all-core | 5056.4 (4864.3-5510.5) | 4735.7 (4720.8-4859.0) | 5481.2 (5376.0-6021.5) | 5540.0 (5254.1-5590.7) |
| 288 threads, six/CCD | 5496.9 (5436.9-5607.0) | 5544.6 (5483.5-5600.0) | 6087.0 (5773.2-6251.2) | 6182.2 (5709.4-6199.3) |

## Array sizes and placement

HBv5 LLC is **48 x 32 MiB = 1.5 GiB**. STREAM's strict rule applies to each
array: `4 x 48 x 32 x 1024^2 / 8 = 805,306,368 doubles`, or 6 GiB per array
and 18 GiB total. 560M (4.48 GB/array) and 280M (2.24 GB/array) are below
this criterion; these sizes are distinct workloads, not increased hardware bandwidth.

All-core uses 368 threads and CPUs 0-367. In each NUMA block `23*n`, supplied
CCD groups start at offsets 0/8/16. Six/CCD selects the first six from each
(288 threads); seven/CCD selects offsets 1-7, 9-15, 16-22 (336 threads).
These are vCPU masks based on supplied membership, not host Pcore IDs.
Comparisons change thread count and distribution together. Keep all-core default.

## Separate 560M seven-per-CCD comparison

Fresh 368/288/336 trials reused the identical 560M/100 binary and method above.
Three repetitions rotated 368/288/336, 336/368/288, 288/336/368. Do not mix this
batch with the preceding array-size matrix. Values remain decimal GB/s.

### Best-iteration rates

| Threads / placement | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 368, all-core | 5751.6 (5725.3-5796.0) | 5780.8 (5772.8-5829.2) | 6262.8 (6260.0-6280.2) | 6265.6 (6231.0-6268.4) |
| 288, six/CCD | 5886.7 (5875.7-5891.4) | 5879.4 (5879.4-5883.1) | 6384.8 (6376.1-6387.7) | 6360.3 (6339.6-6366.8) |
| 336, seven/CCD | 5972.8 (5969.0-6001.4) | 6016.8 (5976.6-6021.6) | 6461.7 (6442.5-6464.6) | 6415.3 (6415.3-6439.5) |

### Average-time-derived rates

| Threads / placement | Copy | Scale | Add | Triad |
|---|---:|---:|---:|---:|
| 368, all-core | 4578.4 (4545.9-4778.7) | 4652.1 (4623.3-4786.3) | 5483.5 (5343.9-5728.9) | 5327.0 (5233.6-5707.0) |
| 288, six/CCD | 5628.1 (5476.8-5678.1) | 5710.6 (5653.0-5714.3) | 6245.4 (6210.7-6248.3) | 6196.4 (6137.0-6236.7) |
| 336, seven/CCD | 5784.4 (5554.9-5791.9) | 5795.6 (5762.1-5825.7) | 6327.7 (6318.8-6330.7) | 6213.6 (6026.9-6268.7) |

336 improved median best-iteration Triad by 2.4% over matched all-core and 0.9%
over 288. Average-time Triad was only 0.3% above 288 with overlapping ranges;
no clear average-time winner was established. Seven/CCD was measured only at
560M; four/CCD was not tested. Keep worker stacks at 256M.

At 560M/100 and 336 threads, increasing stacks to 8192M or disabling automatic
NUMA balancing showed no meaningful gain; retain defaults.
No full TuneD or matched AlmaLinux comparison was performed.

## MLC bandwidth cross-check

The same Ubuntu VM ran **Intel MLC 3.13**. Values are **decimal TB/s,
median (minimum-maximum)** of three
10-second runs. W7/W10 were interleaved within each thread-count batch; 368
and 336 were separate sequential batches, not an interleaved thread-count A/B.

| Threads / placement | W7 | W10, STREAM-triad-like |
|---|---:|---:|
| 368, all-core | 6.662067 (6.653960-6.678732) | 6.771250 (6.760497-6.783917) |
| 336, seven/CCD | 6.591105 (6.590503-6.593180) | 6.737940 (6.717809-6.739691) |

W7 issues two reads from one read buffer plus one non-temporal write; W10
reads from separate read buffers. MLC does not consume loaded values in
subsequent computation or numerically execute STREAM Triad. Its higher result
is not a STREAM speedup or proof of an OS/page-size effect.

```bash
"$MLC" --loaded_latency -b45000 -k0-367 -d0 -T -W7 -e -L -t10 -B
"$MLC" --loaded_latency -b45000 -k0-367 -d0 -T -W10 -e -L -t10 -B
# For 336, replace -k with the seven/CCD CPU list described above.
```

`-b45000` is 45,000 KiB per read/write buffer region per worker; `-d0` injects
no delay, `-T` disables latency measurement, `-e` leaves prefetchers unchanged,
`-L` requests reserved 2 MiB HugeTLB pages. No AVX2/AVX-512 override was used.
Actual 2 MiB page backing and requested worker affinity were verified.
MLC runs used THP madvise/madvise, NUMA balancing=1 and zone reclaim=1,
without TuneD. All runs exited zero; per-worker rates matched the aggregate
within rounding. This is operational, not numerical STREAM validation.

The [official HBv5 performance page](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/high-performance-compute/hbv5-performance)
separately lists approximately **6.6 TB/s STREAM Triad**. MLC W10 does not
establish that STREAM meets that expectation or define a health threshold.
See [Intel MLC documentation](https://www.intel.com/content/www/us/en/developer/articles/tool/intelr-memory-latency-checker.html)
and the measured version's bundled README for option definitions.

## Reproduce

```bash
SKILL_DIR=.github/skills/stream-performance
bash "$SKILL_DIR/scripts/build-stream.sh" "$WORK_ROOT" 560000000
bash "$SKILL_DIR/scripts/run-stream.sh" "$WORK_ROOT" hbv5 3
bash "$SKILL_DIR/scripts/run-stream.sh" "$WORK_ROOT" hbv5 3 ccd-balanced
# Repeat the build/run pair at 805306368 and 280000000 elements.
# Seven/CCD: use 560M and placement ccd-balanced-7.
```

Interleave one-trial invocations for comparisons and aggregate only matched
workloads/CPU masks. Restore the 560M binary afterward. Unique run directories
retain logs, build/run metadata, linkage, topology and utilization.
