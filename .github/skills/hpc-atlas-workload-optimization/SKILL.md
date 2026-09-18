---
name: hpc-atlas-workload-optimization
description: Profile and optimize unfamiliar CPU, memory, MPI, OpenMP, storage, and mixed HPC workloads on Azure without requiring a hard-coded application recipe. Use when asked to make an HPC application or benchmark faster, choose ranks or threads, tune affinity or NUMA placement, improve scaling, compare builds, or investigate a performance bottleneck.
user-invocable: false
---

# HPC Atlas workload optimization

Use this skill to optimize workloads that do not yet have a dedicated,
validated application skill. Treat every proposed optimization as a hypothesis
until a controlled measurement supports it.

Dedicated SKU and workload skills take precedence for facts within their
validated scope. This generic method fills the gaps; it must not invent an
expected performance threshold.

## Inputs to discover

Collect the smallest useful workload description:

| Area | Information |
|---|---|
| Goal | Throughput, latency, time to solution, scaling efficiency, cost, or another metric |
| Correctness | Numerical tolerance, determinism, validation tests, and required outputs |
| Workload | Application, version/commit, input dataset, phases, and representative run length |
| Build | Compiler, flags, target ISA, linked math/MPI/I/O libraries, and executable identity |
| Parallel model | Serial, processes, MPI, threads, OpenMP, hybrid, or task runtime |
| Launch | Exact command, ranks, threads, process grid, affinity, and memory policy |
| Platform | Azure SKU, CPU/NUMA topology, memory, storage path, and network fabric |
| Baseline | Raw measurements, repetition count, variability, and comparison basis |
| Constraints | Licensing, memory capacity, runtime, node count, budget, and allowed changes |

Use information supplied by the user, but label its scope and provenance.
Separate documented facts, observed measurements, and hypotheses.

## Optimization workflow

### 1. Define success

Choose one primary performance metric and one correctness check. Examples
include seconds per iteration, total wall time, jobs per hour, parallel
efficiency, or cost per completed simulation.

Do not optimize a proxy unless its relationship to the user's objective is
clear. Do not exclude initialization or I/O without stating that the metric
does so.

### 2. Create a reproducible baseline

Record:

- Exact command and environment
- Executable checksum or equivalent build identity
- Input identity
- Rank/thread count and placement
- Node count and VM size
- Storage location
- Relevant software versions
- Individual run results, not only the average

Run on an otherwise idle node when possible. Warm-up behavior and cache state
must be consistent between comparisons.

When investigating a user's slow run, reconstruct its actual parameters from
scoped launch scripts, job records, logs, and permitted runtime evidence
before proposing replacements. Preserve provenance and distinguish requested
settings from effective settings. Do not assume the current shell or an
edited script represents the historical run. Avoid unrelated users' data,
whole-environment dumps, and secrets.

Use the low-application-performance procedure in `hpc-atlas-vm-readiness`
to separate configuration, inherited session state, resource limits, and
competing work. A fresh shell is not an idle VM and may retain affinity or
cgroup limits. Use an explicit launch environment and an approved idle or
exclusive interval rather than killing jobs, disabling services, or rebooting.
Obtain approval and a bounded run budget before workload experiments.

### 3. Characterize before tuning

Determine the dominant behavior using the lightest available evidence:

- CPU utilization and frequency behavior
- Instructions, vectorization, and compute intensity where tooling permits
- Memory bandwidth, locality, allocation, and NUMA traffic
- Thread or rank imbalance and synchronization
- MPI message size, communication time, and scaling
- InfiniBand versus Ethernet path
- Storage throughput, metadata activity, and I/O wait
- Application phase timing

If profiling tools are unavailable, use controlled scaling and placement
experiments instead of guessing.

### 4. Form a ranked hypothesis

State:

```text
Hypothesis:
Evidence:
One-factor change:
Expected signal:
Correctness check:
Rollback:
```

Prefer changes that are reversible, low risk, and capable of disproving the
hypothesis.

### 5. Tune one layer at a time

Consider these layers only when evidence points to them:

#### Work decomposition

- Rank count, thread count, and hybrid MPI/OpenMP balance
- Process grid or domain decomposition
- Load balance and communication surface area
- Problem size per rank and memory capacity

#### CPU and memory placement

- Compact versus distributed placement
- NUMA-local memory and first-touch initialization
- Rank ordering and thread affinity
- Avoiding accidental oversubscription
- CCD/cache sharing when a validated topology skill applies

#### Build and libraries

- CPU architecture target and vectorization
- Optimized MPI, math, FFT, I/O, or communication libraries
- Linkage consistency and accidental fallback libraries
- Profile-guided or link-time optimization when reproducible

Do not enable relaxed floating-point options such as `-Ofast` without explicit
disclosure and output validation.

#### Communication

- Correct network fabric and RDMA path
- MPI transport selection and binding
- Collective behavior, message aggregation, and process placement
- Strong- and weak-scaling limits

#### Storage and I/O

- Persistent versus local temporary storage
- Staging, checkpoint, restart, and output phases
- File-per-rank versus collective I/O
- Striping and concurrency

Never format or overwrite a disk without explicit user approval. Local NVMe
performance must not be presented as durable storage.

#### Application configuration

- Algorithmic options, tolerances, output frequency, checkpoint interval, and
  diagnostics
- Changes that reduce work versus changes that make the same work faster

Preserve the user's scientific and operational requirements.

### 6. Measure and decide

Change one primary factor per experiment. Keep all other conditions fixed.
Repeat finalists when run-to-run variance could change the conclusion.

Measure node activity alongside runs when contention is suspected. Separate
configuration changes, launch-environment changes, and busy/idle conditions;
changing them together cannot establish which caused an improvement. Preserve
the original baseline and explain why it underperformed when the evidence
supports attribution. If only a candidate run succeeds, distinguish that
success from an unresolved original failure.

Use:

```text
improvement_percent = 100 * (baseline_time - candidate_time) / baseline_time
```

for lower-is-better elapsed-time metrics. State the formula for other metrics.
Do not claim a win smaller than measurement variability.

### 7. Promote validated knowledge

When an optimization is repeatable:

- Record the exact scope: SKU, image, workload version, input, and node count.
- Record the baseline and candidate commands.
- Preserve correctness evidence.
- Mark the result as an observation, recommendation, or requirement.
- Add a dedicated workload skill only when the procedure is stable enough to
  reuse.

A result from one application, input, or image is not a universal HPC rule.

## Using user-supplied expertise

Classify new information before incorporating it:

| Kind | Examples | Treatment |
|---|---|---|
| Platform invariant | Core count, NUMA topology, device capability | Verify scope and source; place in a SKU skill |
| Workload requirement | Valid process grids, required library, correctness tolerance | Place in a workload skill |
| Measured baseline | STREAM bandwidth, timestep rate, scaling curve | Preserve environment and run provenance |
| Diagnostic rule | Meaning of a device or driver state | Record prerequisites and counterexamples |
| Candidate tuning | Rank count, compiler flag, affinity | Keep as a hypothesis until controlled validation |

If supplied information conflicts with live evidence, report the conflict and
investigate it. Do not silently prefer either source.

## Output

Report experiments in one table:

| Experiment | Change | Placement/build | Result | Variance | Correctness | Decision |
|---|---|---|---:|---:|---|---|

Then provide:

```text
Bottleneck assessment:
Best validated configuration:
Original-run gap and supporting evidence:
Improvement over baseline:
Confidence and scope:
Remaining uncertainty:
Next highest-value experiment:
```

If no controlled measurement was performed, call recommendations
`hypotheses`, not optimizations.
Use "best validated configuration" only within the tested workload, input,
SKU, scale, and candidate set; do not claim a universal optimum. Include an
exact reproducible launch command, relevant environment, and load conditions.
