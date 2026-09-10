---
name: azure-hbv4-vm-specifications
description: Answer factual questions about Azure HBv4 VM sizes, CPU, memory, cache, local and remote storage, networking, InfiniBand, supported features, operating systems, and constrained-core variants. Use for HBv4 capacity planning and basic hardware or platform specifications; use the separate HBv4/HX topology skill for exact vCPU-to-Pcore and CCD mappings.
user-invocable: false
---

# Azure HBv4 VM specifications

Use this skill for public Azure HBv4-series specifications and basic capacity
planning. For exact full-size vCPU, physical-core, NUMA, and CCD placement, use
the sibling `azure-hbv4-hx176-topology` skill.

## Quick reference

| Component | HBv4 specification |
|---|---|
| CPU | AMD EPYC 9V33X (Genoa-X), x86-64, AMD 3D V-Cache |
| Host CPUs | Two 96-core processors; 192 physical cores before Azure reserves |
| VM vCPUs | 176, 144, 96, 48, or 24 depending on size |
| SMT | Disabled; one exposed vCPU corresponds to one physical core |
| Frequency | 2.55 GHz base; up to 3.7 GHz single-core and all-core peak |
| Memory | 768 GB for every HBv4 size |
| Memory bandwidth | 780 GB/s |
| L3 cache | 2,304 MB, with up to 5.7 TB/s cache bandwidth |
| Effective memory speed | Microsoft reports an average of 1.2 TB/s for many workloads |
| Local temp disk | One 480 GiB SSD device |
| Local NVMe | Two 1,800 GiB unformatted block NVMe devices |
| Remote disks | Up to 32 Standard or Premium managed disks |
| Azure network | Up to 80,000 Mb/s aggregated expected bandwidth; up to eight vNICs |
| InfiniBand | One 400 Gb/s NVIDIA ConnectX-7 NDR adapter with SR-IOV/RDMA |
| Accelerators | No GPU, FPGA, or other accelerator |

Do not combine the two 1,800 GiB NVMe devices into a single 3,600 GiB device
unless discussing a user-created striped array.

## Available sizes

All constrained-core variants retain the same 768 GB memory, memory bandwidth,
cache, InfiniBand, Azure Ethernet, and local SSD resources. Only the exposed
core count changes.

| Azure size | vCPUs | vNUMA nodes | Cores per vNUMA | Memory | Approx. GB/vCPU |
|---|---:|---:|---:|---:|---:|
| `Standard_HB176rs_v4` | 176 | 4 | 44 | 768 GB | 4.36 |
| `Standard_HB176-144rs_v4` | 144 | 4 | 36 | 768 GB | 5.33 |
| `Standard_HB176-96rs_v4` | 96 | 4 | 24 | 768 GB | 8.00 |
| `Standard_HB176-48rs_v4` | 48 | 4 | 12 | 768 GB | 16.00 |
| `Standard_HB176-24rs_v4` | 24 | 4 | 6 | 768 GB | 32.00 |

The GB/vCPU values are arithmetic ratios for comparison, not separately
published Azure limits.

## CPU and NUMA architecture

- Each HBv4 host contains two 96-core AMD EPYC 9V33X processors.
- The host has 192 physical Zen 4 cores and 24 CCDs, with eight cores and
  96 MB of L3 cache per CCD.
- Azure reserves 16 physical cores for the hypervisor, leaving up to 176 cores
  for the full-size VM.
- BIOS topology uses NPS=2, so the host and VM expose four NUMA domains, two
  per socket.
- A group of six consecutive CCDs forms one NUMA domain.
- `L3 as NUMA` is disabled and C-states are enabled.
- The VM's virtual NUMA topology maps to the underlying physical NUMA
  topology rather than presenting an unrelated abstraction.

Do not apply the exact 176-vCPU affinity map to a constrained-core size. Use
the public topology characteristics here and inspect that VM's OS topology.

## Local storage

HBv4 provides three physically local SSD devices:

1. One 480 GiB SSD device, preformatted for use as the VM's temporary/page-file
   disk.
2. Two 1,800 GiB unformatted block NVMe devices that bypass the hypervisor.

When the two NVMe devices are configured as a striped array, Microsoft reports
up to:

| Metric | Reported maximum |
|---|---:|
| Sequential read bandwidth | 12 GB/s |
| Sequential write bandwidth | 7 GB/s |
| Read IOPS | 186,000 |
| Write IOPS | 201,000 |

These are local temporary devices, not durable managed disks. Do not recommend
them as the only copy of persistent data. Capacity in the size table is GiB
(`1024^3` bytes), while throughput MB/s uses decimal units.

## Remote storage

- Up to 32 remote data disks are supported on every HBv4 size.
- Standard and Premium Azure managed disks are supported.
- Premium Storage caching is supported.
- Other documented storage options include Azure NetApp Files, Azure Files,
  and Azure Managed Lustre.
- The HBv4 size table does not publish a single VM-level remote-disk IOPS or
  throughput number. Do not invent one; consider the selected disk type,
  count, caching mode, and storage architecture.

## Networking and RDMA

Keep Azure Ethernet and InfiniBand figures separate:

| Fabric | Specification | Typical purpose |
|---|---:|---|
| Azure Ethernet | Up to 80 Gb/s expected aggregated bandwidth across up to eight vNICs | IP and Azure service traffic |
| NDR InfiniBand | Up to 400 Gb/s through one ConnectX-7 adapter | MPI and RDMA traffic |

The overview's hardware summary also describes the Azure network hardware as
100 Gb/s with 80 Gb/s Azure Accelerated Networking. Use 80 Gb/s as the
published VM-size expected network-bandwidth limit.

InfiniBand details:

- NVIDIA ConnectX-7 NDR adapter
- SR-IOV passthrough, allowing traffic to bypass the hypervisor
- Adaptive Routing
- Dynamically Connected Transport (DCT), plus RC and UD transports
- Hardware offload for MPI collectives
- Non-blocking fat-tree fabric for RDMA workloads

Maximum bandwidth values are upper limits, not performance guarantees.

## Platform and software support

| Capability | Status |
|---|---|
| Generation 2 VM | Supported |
| Generation 1 VM | Not supported |
| Accelerated Networking | Supported |
| Ephemeral OS disk | Supported |
| Live migration | Not supported |
| Memory-preserving updates | Not supported |
| Nested virtualization | Not supported |
| Premium Storage and caching | Supported |

Documented MPI implementations include HPC-X, Open MPI, MVAPICH2, and MPICH.
Additional frameworks include UCX, libfabric, and PGAS. Supported
orchestrators include Azure CycleCloud, Azure Batch, and Azure Kubernetes
Service.

Microsoft's published validated OS baselines are:

- RHEL 8.6 or later
- AlmaLinux 8.10 or later
- Ubuntu 22.04 LTS or later
- SUSE Linux Enterprise Server 15 SP7 or later
- Windows Server 2022 or later

The currently documented performance recommendations are AlmaLinux HPC 9.7,
Ubuntu HPC 24.04, and Windows Server 2025. Treat version recommendations as
time-sensitive and verify the current public documentation before prescribing
an image for a new deployment.

## Answering guardrails

- State the exact Azure size when discussing core count.
- Distinguish GB of RAM from GiB of local storage.
- Distinguish local temporary SSD/NVMe from durable remote storage.
- Distinguish 80 Gb/s Azure Ethernet from 400 Gb/s InfiniBand.
- Do not interpret a constrained-core size as having less memory, cache,
  memory bandwidth, networking, or local disk.
- Present bandwidth and IOPS as documented maxima, not guarantees.
- Do not transfer these specifications to HX-series VMs; consult HX public
  documentation separately.
- For prices, regional availability, quota, or newly supported OS images,
  consult current Azure documentation because those values change.

## Public sources

Checked on 2026-09-09:

- [HBv4 size series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/high-performance-compute/hbv4-series)
  - Page date: 2025-11-24
  - Microsoft Learn update observed: 2026-04-02
- [HBv4-series VM overview, architecture, topology](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv4-series-overview)
  - Page date: 2026-05-05
  - Microsoft Learn update observed: 2026-06-24

When current facts conflict with this skill, prefer the latest Microsoft Learn
documentation and identify the changed specification.
