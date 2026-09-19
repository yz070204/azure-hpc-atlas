---
name: hpc-atlas-workload-optimization
description: Find and validate speedups for HPC workloads that have no dedicated workload skill. Use for making an application faster, choosing ranks/threads, pinning and NUMA placement, MPI transport, compiler flags, or I/O bottlenecks.
user-invocable: false
---

# HPC Atlas workload optimization

Find the biggest speedup with the fewest runs. Follow the agent rules and report format. To diagnose a specific slow run (what actually ran, contention, limits), use Application performance in `hpc-atlas-vm-readiness` first. Workload skills with calibrated recipes (e.g. WRF) take precedence. Every change is a hypothesis until measured.

## 1. Set up
- **Metric and correctness:** one primary metric (time per iteration, wall time) and one correctness check (residuals, output diff, validation case). Never change inputs or numerics to go faster.
- **Short case:** a few iterations/timesteps of the real input, long enough to get past startup (about a minute of steady state). Screen candidates with it; confirm only finalists on the full run.
- **Baseline:** exact command, environment, binary, input, ranks × threads, and actual placement (`--report-bindings` for HPC-X/Open MPI, `I_MPI_DEBUG=4` for Intel MPI). Discard a warm-up run.
- **App knowledge:** look up the application's own parallel settings once (decomposition, threading, solver options) before experimenting, instead of guessing.
- Get approval and a run budget before experiments.

## 2. Classify the bottleneck (cheapest probe first)
| Probe | Signal | Likely bound |
|---|---|---|
| The app's own timing breakdown | One phase dominates | Start there |
| Short case at ¼, ½, and all cores, spread evenly across NUMA nodes | Stops improving well before all cores | Memory bandwidth |
| Same | Near-linear | Compute |
| MPI time share (app timers or an MPI profiler) grows with node count | Communication share rising | Communication |
| `vmstat 1` high `wa`, read/write phases dominate | I/O wait | I/O |
| Uneven per-rank time or CPU use | Some ranks idle | Load imbalance |

Rank counts must be valid for the app's decomposition (e.g. the domain split must match the rank count).

## 3. Try changes in payoff order
One change per experiment. Skip layers the bottleneck doesn't point to.

1. **Placement (most common large win).** Pin every rank, spread ranks evenly across NUMA nodes and L3 caches (CCDs), never oversubscribe. Verify actual placement, not just the requested flags (`ps -eLo pid,psr,comm`). Hybrid MPI+OpenMP: keep each rank's threads inside one CCD (`OMP_PLACES=cores`, `OMP_PROC_BIND=close`), threads per rank ≤ cores per CCD.
   - HPC-X/Open MPI: `--map-by ppr:<n>:numa --bind-to core` (hybrid: `--map-by ppr:<n>:numa:pe=<threads>`). Intel MPI: `I_MPI_PIN_PROCESSOR_LIST` or `I_MPI_PIN_DOMAIN`. MPICH: `-bind-to core`.
2. **Rank count (memory-bound codes).** Fewer ranks per VM gives each rank more L3 and memory bandwidth and can be faster. Try counts that keep ranks per CCD equal (the topology skill lists valid counts, e.g. 144 on HBv4). For per-core-licensed apps, constrained-core VM sizes do the same with fewer licenses. Compare cost per run, not just time.
3. **Working set vs L3.** Large-cache CPUs (e.g. HBv4/HX with 3D V-Cache) gain most when the per-VM working set fits in L3; small cases gain less. For multi-node runs, scaling can beat expectations once data per VM fits in cache, so test more nodes before assuming they won't help.
4. **MPI transport.** Confirm inter-node traffic uses InfiniBand, not TCP (check UCX/HPC-X output and `UCX_NET_DEVICES`); TCP fallback is a large slowdown. Intra-node: on AMD, HPC-X with xpmem has shown ~10% loss from page faults. Test with the xpmem module unloaded (system change, ask first); UCX falls back to another shared-memory transport automatically.
5. **Build.** Build on the target SKU; a binary built for a newer CPU can crash with "illegal instruction" on an older one. Use the CPU vendor's optimized math libraries (e.g. AOCL on AMD) where the app uses BLAS/FFT, and check `ldd` for accidental reference libraries. Flags already validated in a workload skill (e.g. the STREAM skill) take precedence.

   | Flag | Purpose |
   |---|---|
   | `-O3` | High optimization; safe default |
   | `-march=native` | Target the CPU you're building on |
   | `-march=znver2` / `znver3` / `znver4` | Target a specific SKU: HBv2 (Zen 2) / HBv3 (Zen 3) / HBv4, HX (Zen 4, adds AVX-512). `znver4` needs GCC 13+ or AOCC 4+ |
   | `-fopenmp` | Enable OpenMP threading |
   | `-Ofast` / `-ffast-math` | Faster floating point, but can change numerical results; only with output validation against the baseline |

6. **I/O.** Put scratch and checkpoints on local NVMe (fast but not durable; copy results out). Reducing output or checkpoint frequency needs user agreement. Shared storage choice (Azure Files, NetApp Files, Managed Lustre) is a design decision: recommend, don't change.
7. **System settings (ask first).** Transparent huge pages can help memory-bound codes; test as a one-factor experiment and restore afterwards.
8. **Application settings.** Options that do the same work faster (solver, decomposition method). Anything that reduces work (tolerances, output) needs user sign-off.

## 4. Measure and decide
- Screen with 1–2 runs of the short case per candidate. Confirm the best 1–2 against the baseline with ≥5 runs; report the median.
- Improvement = 100 × (baseline − candidate) / baseline for time metrics. A gain within run-to-run variance is not a win.
- Stop when the next change's likely gain is below variance or the budget is used.

## SKU notes
- **HBv4/HX:** 176 cores, no SMT, 4 NUMA nodes, 3D V-Cache L3 per CCD. HX has the same CPU and topology with more memory, so the same placement rules apply. Use `azure-hbv4-hx176-topology` for exact CCD/NUMA mapping and valid rank counts; pinning is reliable because the VM exposes the physical topology.
- **Other SKUs:** same method. Take topology and valid rank counts from that SKU's skill; never reuse HBv4 numbers.

## Report
Use the agent report format, plus:

| Experiment | Change | Ranks × threads / placement | Metric (median, n) | Variance | Correct? | Keep? |
|---|---|---|---|---|---|---|

Then give the bottleneck, the best validated launch command with its environment and scope (SKU, input, scale), improvement over baseline, and the next most promising experiment. Without measured runs, call recommendations hypotheses. If a result is repeatable, suggest capturing it in a workload skill.
