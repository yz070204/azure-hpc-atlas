---
name: hpc-atlas-vm-readiness
description: Perform self-service and first-line readiness or performance triage for Azure HPC VMs. Use for requests such as "check this VM", "check readiness", "check IB", or "why is my performance bad", HPC health checks, running or interpreting Azure HPC diagnostics under /opt/azurehpc/diagnostics, slow benchmarks, MPI jobs or HPC applications, missing capabilities, unexpected CPU or NUMA topology, or missing InfiniBand.
---

# HPC Atlas VM readiness

Use this skill to coordinate a minimal, evidence-based self-triage
investigation on the affected VM. It does not replace SKU-specific
specification, topology, or workload skills.

The investigation should be useful even when no support case exists. Resolve
safe software, placement, launch, and benchmark issues in place when the
evidence is clear; prepare an escalation bundle only when self-triage cannot
resolve or classify the issue.

## Required behavior

- Begin with read-only discovery.
- Detect the VM size rather than trusting an assumed size.
- Establish the expected capability before running subsystem diagnostics.
- Run one diagnostic branch at a time.
- Record exact commands and preserve relevant output.
- Ask before any state-changing or potentially disruptive action.
- Ask before privileged broad log collection; keep raw evidence private and
  local, and never upload it automatically.
- Do not classify a case as a hardware failure.

Read `references/evidence-matrix.md` when choosing a diagnostic branch. Read
`references/escalation-bundle.md` before preparing an escalation.
Read `references/azure-hpc-diagnostics.md` before invoking the installed
collector or interpreting one of its bundles.

## Natural-language entry points

Users do not need a support case, diagnostic command, or detailed prompt.
Route short requests by intent, not exact wording or capitalization:

| Example prompt | Starting branch |
|---|---|
| "Check this VM" or "Check this HPC VM" | Read-only identity and general readiness |
| "Check readiness" | Read-only identity and general readiness |
| "Check IB" or "Check IB on this VM" | Exact SKU and documented IB capability, then device/driver/link checks only if supported |
| "Why is my performance bad?" or "Why is my MPI job slow?" | Read-only inventory and workload/measurement context, then the implicated performance branch |
| "Use the HPC diagnostics in /opt" | Assess collector usefulness and obtain approval before broad collection |
| "Review this HPC diagnostic archive: <path>" | Interpret existing evidence and identify collection gaps |

Use the affected VM identified in the conversation, or the current VM when
none is specified. Do not interpret a short prompt as permission to scan
other nodes, run benchmarks, change settings, or upload evidence.

For an unspecified health check, start with identity, CPU/NUMA, and relevant
device readiness. Report the checked scope, not a whole-node health verdict.
Do not invent a performance symptom or launch benchmarks to fill in missing
workload information. Reuse relevant existing evidence before collecting more.

For a vague performance complaint, use available context and read-only
evidence to identify the workload, launch command, observed metric, and
comparison baseline. If essential context remains missing, report what is
known and request only the missing information needed for the next step.
Do not assume WRF, STREAM, or an IB bottleneck, and do not treat a readiness
pass as proof of good application performance. Use
`hpc-atlas-workload-optimization` when workload-specific profiling or
controlled tuning is needed.

## Phase 1: Frame and inventory

Collect only information relevant to the symptom:

| Area | Evidence |
|---|---|
| Identity | Azure VM size, region if relevant, hostname or anonymized node ID |
| Software | Distribution, kernel, image version, compiler, MPI, libraries |
| Compute | Online CPUs, sockets, cores, NUMA nodes, CPU model |
| Device | Relevant PCI, RDMA, NVMe, or network device visibility |
| Workload | Name, version, input, launch command, rank/thread count |
| Measurement | Metric, observed result, expected result, run count |
| History | Previously working state, comparison node, recent changes |

Do not collect large logs before identifying which subsystem is implicated.

## Phase 2: Capability gate

Consult the relevant SKU specification.

1. If the detected SKU lacks the expected feature, return
   `capability-mismatch`.
2. If the SKU is outside validated coverage, state that limitation and avoid
   applying HBv4-specific thresholds.
3. If the capability should exist, proceed to live readiness checks.

For HBv4 public limits use `azure-hbv4-vm-specifications`. For exact full-size
HBv4/HX placement use `azure-hbv4-hx176-topology`.

## Phase 3: Topology and launch validation

Before a performance benchmark, verify:

- Expected number of online CPUs and NUMA nodes
- CPU affinity and ordering
- Whether guest L3 grouping reflects the active distribution policy
- Memory placement policy
- Rank or thread count
- MPI binding and mapping
- Benchmark binary, build flags, and workload input
- Idle-node conditions and competing processes

A valid hardware capability with incorrect launch placement is
`configuration-or-software`, not a node-health issue.

For full-size HBv4/HX, do not infer physical CCD or shared-L3 placement from
guest `lscpu -e` cache IDs. Use `lscpu` to identify the active guest
distribution-policy pattern, then use the validated topology skill for the
physical mapping.

The full-size topology skill also defines the required 176-CPU `lscpu -e`
signature. Any mismatch must be reported. Capture the complete output, SKU,
image, and kernel; check for an identified OS or boot configuration cause;
otherwise classify the evidence as `possible-platform-or-node-health` and
prepare an escalation bundle.

## Phase 4: Minimal diagnostic

Select the smallest test that distinguishes the leading hypotheses.

### Optional installed Azure HPC diagnostics

Check for `/opt/azurehpc/diagnostics/gather_azhpc_vm_diagnostics.sh`. Its best
use is a timestamped VM/driver/RDMA evidence snapshot when targeted checks
leave a question unresolved, the user requests a bundle, or escalation needs
one. It is not the default first command, a comprehensive health checker, or
a calibrated HBv4 performance test.

Follow the diagnostics reference for source/version inspection, approval,
CPU-only collection with `--offline --no-update --mem-level=0`, and output
review. Those flags do not make the collector safe on GPU VMs. Do not run its
GPU path without separate review and approval.

If absent, blocked by privileges, or incomplete, say so and continue with
available targeted read-only checks. Do not automatically install, update,
repair, or rerun a larger diagnostic. A successful process exit or archive
creation is not a readiness pass.

### InfiniBand readiness or missing InfiniBand

Treat "Check IB" or "Check IB on this VM" as a capability-first request, not an instruction
to assume InfiniBand exists. Detect the exact SKU from live metadata and
verify its documented InfiniBand/RDMA capability before running IB tools.
Do not infer support solely from the SKU name, an installed driver, or the
collector's SKU heuristics. If the exact SKU or its capability cannot be
verified, report `inconclusive` and identify the missing evidence rather than
declaring IB unsupported.

Progress in this order:

1. Confirm the detected SKU includes RDMA/InfiniBand.
2. Check whether the ConnectX device is visible on PCI.
3. Check loaded modules, driver/kernel compatibility, RDMA devices, and link
   state.
4. Run a minimal fabric diagnostic only if visibility and driver state do not
   explain the symptom.

Stop when one step establishes the cause. Do not run a full benchmark merely
to prove that an unsupported VM size lacks InfiniBand.

When the specification confirms that the detected SKU does not support IB,
return `capability-mismatch` and stop this branch before PCI/driver diagnostics
or broad log collection. State the exact SKU and capability source, explain
that absent IB is expected for this size, and recommend an IB-capable SKU if
the workload requires RDMA. Do not install drivers, resize the VM, or prepare
a platform/node-health escalation for an unsupported capability.

### Low STREAM bandwidth

Use `hbv4-stream-performance` for the full-size HBv4 build/run procedure and
experimental baselines. Diagnose the actual build/run first, without silently
switching workloads. Ordinary run requests default to original source at
176 threads with THP always; explicit AMD prebuilt requests use its original
176-thread launch with THP always. Mention optional 144-thread CCD balancing,
but run it only when requested. A direct STREAM run request should proceed with
the STREAM skill's documented bounded runner behavior.

Progress in this order:

1. Confirm full-size versus constrained-core SKU.
2. Compare live CPU/NUMA topology with the expected topology.
3. Inspect thread count, affinity, first-touch behavior, and NUMA placement.
4. Confirm STREAM source/build, array size, iteration count, and metric.
5. If needed and approved, repeat under matching conditions before changing placement.
6. Compare only against a baseline with matching conditions.

Do not interpret one low run without affinity and test provenance as evidence
of node health.

### Low application performance

Explain the user's performance gap, not just whether a different benchmark
runs well. Use `hbv4-wrf-conus-performance` for its calibrated WRF CONUS
workload and `hpc-atlas-workload-optimization` for controlled experiments.

#### Reconstruct the actual run

Before asking the user to re-enter parameters, inspect relevant evidence
already available in the conversation and workload directory: launch/job
scripts, application configuration, run logs, and scheduler records for the
identified job. Where permitted, inspect that job's live command, effective
affinity, resource allocation, and relevant environment variables.

Capture ranks, threads, process grid, binding, memory policy, executable and
library identity, input, output/checkpoint settings, and storage paths.
Distinguish requested settings from effective runtime settings and label each
source. A current script or shell is not proof of what an earlier job used.
Do not search unrelated directories, other users' shell histories, or dump
whole process environments. Redact secrets in arguments and settings. If
historical launch evidence is missing, report the gap instead of guessing.

Compare the actual settings with a validated recipe only when SKU, workload
version, input, and scale match. Otherwise propose a candidate configuration
as a hypothesis. Provide the exact relevant differences and their expected
effects; do not call a recipe universally optimal.

#### Separate configuration, session state, and contention

Check CPU usage, memory pressure, swapping, I/O wait, and competing jobs or
processes using available read-only tools. Also check scheduler/cgroup CPU
and memory limits and the job's effective CPU set. Record activity during
the measured interval where possible; one idle snapshot after a slow run
cannot rule out earlier contention.

A fresh shell can help isolate inherited MPI/OpenMP variables, modules,
library paths, limits, or affinity, but it does not make the VM idle or
remove scheduler/cgroup restrictions. Define a clean session as a separate,
documented launch environment with explicit required modules, paths, and
relevant variables, preserving required scheduler and authentication context.
Capture differences before changing anything; do not blindly clear the
environment, rewrite shell startup files, or assume a new login resets it.

For contention, prefer waiting for an idle interval or requesting an approved
exclusive allocation. Do not kill competing jobs, disable services, clear
system caches, reboot, or redeploy to manufacture a clean baseline.

#### Attribute the improvement

Obtain approval and a bounded run budget before reproducing the application's
own metric. Preserve the user's baseline command and outputs. Compare one
factor at a time: original versus candidate settings under equivalent load;
inherited versus explicitly controlled launch environment with the same
settings; or busy versus idle conditions with the same configuration when
safe evidence is available. Do not create interfering workloads just to
reproduce contention.

Keep binary, input, metric, correctness requirements, and warm-up/cache
conditions equivalent unless one is the explicit tested factor. Record
individual results and repeat enough to distinguish the effect from variance.
If configuration, environment, and load all changed together, a faster result
shows recovery under those conditions, not which change caused it.

Report a compact comparison:

| Run | Command and effective settings | Session/load conditions | Metric and repetitions | Variance | Correctness |
|---|---|---|---|---|---|
| User baseline |  |  |  |  |  |
| Controlled candidate |  |  |  |  |  |

Finish with the evidence-backed explanation of why the baseline missed the
comparison result, the best validated command/configuration and its scope,
the measured improvement, and how to reproduce it. Distinguish confirmed
causes, contributing factors, and untested hypotheses. Reproduced contention
or environment/configuration effects are `configuration-or-software`; merely
seeing another process is not enough to establish causation.

If only the candidate works and the original failure cannot be reproduced,
report the demonstrated result but leave the original cause `inconclusive`.
A good controlled run does not rule out an intermittent problem. If no run
was approved, provide a proposed command and remaining evidence needs, not a
claimed optimization or resolution.

## Classification rules

| Classification | Minimum evidence |
|---|---|
| `expected` | Detected SKU, test conditions, and result agree with the applicable reference |
| `capability-mismatch` | Detected SKU is authoritative and the specification excludes the requested capability |
| `configuration-or-software` | A reproducible configuration, placement, driver, build, or workload difference explains the symptom |
| `inconclusive` | Required evidence is missing, results conflict, or the symptom cannot be reproduced |
| `possible-platform-or-node-health` | Capability is expected, configuration checks are clean, and controlled repeats show a node-local discrepancy |

Use `possible-platform-or-node-health` conservatively. Prefer a same-image,
same-command comparison on another node when practical, but do not require
disruptive redeployment without user approval.

## Output

Produce:

```text
Detected environment:
Symptom:
Expected behavior:
Tests performed:
Key evidence:
Evidence location and collection gaps:
Classification:
Confidence:
Smallest next step:
```

For quantitative comparisons, add a compact table containing command,
placement, run count, observed result, expected range, and variance.

If escalation is required, use the escalation reference and include the
evidence already collected.

If the issue is resolved during self-triage, also report:

```text
Cause:
Change made or recommended:
Before result:
After result:
How to prevent recurrence:
```
