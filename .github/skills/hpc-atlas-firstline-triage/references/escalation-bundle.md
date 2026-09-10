# HPC Atlas escalation bundle

Prepare this bundle only after minimal triage cannot resolve the issue or the
evidence supports `possible-platform-or-node-health`.

## Case summary

```text
Timestamp and time zone:
Azure VM size:
Region:
OS image and version:
Kernel:
Symptom:
First occurrence:
Repeatability:
Previously working:
Primary classification:
Confidence:
```

## Expected versus observed

| Item | Expected | Observed | Source or command |
|---|---|---|---|
| Capability |  |  |  |
| Topology |  |  |  |
| Device state |  |  |  |
| Performance metric |  |  |  |

## Reproduction

Include:

- Exact workload or diagnostic command
- Working directory and relevant input identity
- Rank/thread count and placement
- Compiler, MPI, and linked-library versions where relevant
- Number of repetitions and individual results
- Whether the node was otherwise idle

## Evidence attachments

Attach only relevant outputs:

- VM identity and SKU evidence
- OS and kernel information
- CPU/NUMA topology
- Affinity and memory-placement evidence
- Relevant PCI, driver, RDMA, network, or storage state
- Benchmark provenance and raw result
- Same-command comparison from another node, if available

Do not attach credentials, access tokens, customer workload data, or broad
system logs unrelated to the symptom.

## Actions already attempted

List each action, result, and whether it changed system state. Explicitly note
whether the VM was rebooted, redeployed, resized, or moved to another node.

## Escalation question

End with one concrete question for the receiving owner, for example:

```text
Can you investigate why the expected ConnectX-7 PCI function is absent on this
node when the same image and SKU expose it on the comparison node?
```

Avoid vague requests such as "please check the hardware."
