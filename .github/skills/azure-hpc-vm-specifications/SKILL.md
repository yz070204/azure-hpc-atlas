---
name: azure-hpc-vm-specifications
description: Published specifications for Azure HBv4, HX, and HBv5 VMs, including cores, memory, storage, networking, supported features, and constrained-core sizes. Use for factual hardware questions and capacity comparisons; use the separate topology and workload skills for placement and performance.
user-invocable: false
---

# Azure HPC VM specifications

Read only the reference for the requested family; read both for a comparison.

| Family | Reference | Full-size topology skill |
|---|---|---|
| HBv4 / HX | [HBv4 and HX](references/hbv4-hx.md) | `azure-hbv4-hx176-topology` |
| HBv5 | [HBv5](references/hbv5.md) | `azure-hbv5-368-topology` |

## InfiniBand capability gate (Azure H-series)

The `r` size suffix denotes RDMA/InfiniBand capability across Azure H-series. Sizes without `r` are not InfiniBand-enabled; installing an HPC image or RDMA drivers does not add that capability. If InfiniBand is required but the detected size lacks `r`, classify `capability-mismatch` and stop before IB diagnostics or benchmarks. Recommend only documented public IB-enabled sizes within this advisor's supported scope. This naming rule does not extend topology or workload validation to other sizes or families.

## Shared features

All three families support Generation 2, Accelerated Networking, ephemeral OS disks, and Premium Storage with caching. Generation 1, live migration, memory-preserving updates, and nested virtualization are not supported.

Each supports up to 32 Standard or Premium managed data disks, Azure NetApp Files, Azure Files, and Azure Managed Lustre. No VM-level remote-disk IOPS or throughput figure is published.

MPI frameworks include UCX, libfabric, and PGAS. Orchestrators include Azure CycleCloud, Azure Batch, and AKS. Family-specific MPI and OS details are in the references.

## Answering rules

- State the exact size. Separate published specifications, measured guest topology, and supplied host mappings.
- Peaks are limits, not guaranteed performance. Specifications do not imply validated workload coverage; do not reuse HBv4/HX benchmark targets for HBv5.
- Constrained-core sizes retain memory, cache, networking, and local storage. Do not apply full-size topology mappings to them; HBv5's smaller sizes have bandwidth limits noted in its reference.
- Distinguish GB/TB from GiB/TiB, Ethernet from InfiniBand, and temporary local disks from durable remote storage. Local disks must not be the only copy of data.
- Keep source discrepancies explicit; do not guess missing values. For changing details such as prices, availability, quota, and supported images, check current Azure documentation.
