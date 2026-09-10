---
name: hpc-atlas-firstline-triage
description: Perform self-service and first-line readiness or performance triage for Azure HPC VMs. Use when a user asks why a VM, benchmark, MPI job, or HPC application is slow; when a VM is missing an expected capability, has unexpected CPU or NUMA topology, cannot see InfiniBand, or needs evidence-based classification before escalation.
---

# HPC Atlas first-line triage

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
- Do not classify a case as a hardware failure.

Read `references/evidence-matrix.md` when choosing a diagnostic branch. Read
`references/escalation-bundle.md` before preparing an escalation.

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

### Missing InfiniBand

Progress in this order:

1. Confirm the detected SKU includes RDMA/InfiniBand.
2. Check whether the ConnectX device is visible on PCI.
3. Check loaded modules, driver/kernel compatibility, RDMA devices, and link
   state.
4. Run a minimal fabric diagnostic only if visibility and driver state do not
   explain the symptom.

Stop when one step establishes the cause. Do not run a full benchmark merely
to prove that an unsupported VM size lacks InfiniBand.

### Low STREAM bandwidth

Progress in this order:

1. Confirm full-size versus constrained-core SKU.
2. Compare live CPU/NUMA topology with the expected topology.
3. Inspect thread count, affinity, first-touch behavior, and NUMA placement.
4. Confirm STREAM source/build, array size, iteration count, and metric.
5. Run a controlled repeat under the validated placement.
6. Compare only against a baseline with matching conditions.

Do not interpret one low run without affinity and test provenance as evidence
of node health.

### Low application performance

First reproduce the application's own metric under documented conditions.
Then isolate only the subsystem supported by evidence. Use the
`hbv4-wrf-conus-performance` skill for its calibrated WRF CONUS workload.

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
