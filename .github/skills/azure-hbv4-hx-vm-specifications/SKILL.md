---
name: azure-hbv4-hx-vm-specifications
description: Answer factual questions about Azure HBv4 and HX VM sizes, including CPU, frequency, memory, cache, local and remote storage, networking, InfiniBand, supported features, operating systems, and constrained-core variants. Use for HBv4/HX capacity planning, HBv4 vs HX comparisons, and basic hardware or platform specifications; use the separate HBv4/HX topology skill for exact vCPU-to-Pcore and CCD mappings.
user-invocable: false
---

# Azure HBv4 and HX VM specifications

Public specifications and capacity planning for HBv4 and HX. For exact full-size vCPU, physical-core, NUMA, and CCD placement, use `azure-hbv4-hx176-topology`.

HBv4 and HX share the same host hardware, CPU, topology, cache, storage, and networking. **The main difference is memory: HBv4 has 768 GB, HX has 1,408 GB.** HX is aimed at memory-capacity-bound workloads (e.g. EDA).

## Shared specifications

| Component | HBv4 and HX |
|---|---|
| CPU | AMD EPYC 9V33X (Genoa-X, Zen 4), x86-64, AMD 3D V-Cache |
| Host CPUs | Two 96-core processors; 192 physical cores before Azure reserves 16 |
| VM vCPUs | 176, 144, 96, 48, or 24 depending on size |
| SMT | Disabled; one vCPU = one physical core |
| Frequency | 2.55 GHz base; published single-core and all-core peak 3.7 GHz (see note) |
| Memory bandwidth | 780 GB/s |
| L3 cache | 2,304 MB, up to 5.7 TB/s cache bandwidth |
| Effective memory speed | Microsoft reports an average of 1.2 TB/s for many workloads |
| Local temp disk | One 480 GiB SSD device (page file) |
| Local NVMe | Two 1,800 GiB unformatted block NVMe devices |
| Remote disks | Up to 32 Standard or Premium managed disks |
| Azure network | Up to 80,000 Mb/s aggregated expected bandwidth; up to eight vNICs |
| InfiniBand | One 400 Gb/s NVIDIA ConnectX-7 NDR adapter, SR-IOV/RDMA |
| Accelerators | None |

**Frequency note:** the size tables list 3.7 GHz as both single-core and all-core peak. That is a published maximum, not an expected all-core value: under a full all-core load, measured frequency can run slightly below the 2.55 GHz base (confirmed by AMD). Only a lightly loaded core should be expected to approach 3.7 GHz.

Don't combine the two 1,800 GiB NVMe devices into one 3,600 GiB device unless discussing a user-created striped array.

## HBv4 vs HX

| | HBv4 | HX |
|---|---|---|
| Memory (every size) | 768 GB | 1,408 GB |
| Size names | `Standard_HB176rs_v4`, `Standard_HB176-<n>rs_v4` | `Standard_HX176rs`, `Standard_HX176-<n>rs` (no `_v4`) |
| Everything else | Same | Same |

## Available sizes

Constrained-core variants keep the same memory, memory bandwidth, cache, InfiniBand, Azure Ethernet, and local SSD; only the exposed core count changes. Every size has 4 vNUMA nodes.

| vCPUs | HBv4 size | HX size | Cores per vNUMA | GB/vCPU HBv4 | GB/vCPU HX |
|---:|---|---|---:|---:|---:|
| 176 | `Standard_HB176rs_v4` | `Standard_HX176rs` | 44 | 4.36 | 8.00 |
| 144 | `Standard_HB176-144rs_v4` | `Standard_HX176-144rs` | 36 | 5.33 | 9.78 |
| 96 | `Standard_HB176-96rs_v4` | `Standard_HX176-96rs` | 24 | 8.00 | 14.67 |
| 48 | `Standard_HB176-48rs_v4` | `Standard_HX176-48rs` | 12 | 16.00 | 29.33 |
| 24 | `Standard_HB176-24rs_v4` | `Standard_HX176-24rs` | 6 | 32.00 | 58.67 |

GB/vCPU values are arithmetic ratios for comparison, not published limits.

## CPU and NUMA architecture
- Two 96-core EPYC 9V33X per host: 192 Zen 4 cores in 24 CCDs, 8 cores and 96 MB L3 per CCD.
- Azure reserves 16 physical cores for the hypervisor, symmetrically across both sockets, leaving up to 176 for the VM.
- BIOS: NPS=2, `L3 as NUMA` disabled, C-states enabled. The host and VM expose four NUMA domains (two per socket); six consecutive CCDs form one NUMA domain, each with six DRAM channels.
- The VM's virtual NUMA topology maps to the physical NUMA topology.
- Don't apply the exact 176-vCPU affinity map to constrained-core sizes; use these characteristics and inspect that VM's OS topology.

## Local storage
- One 480 GiB SSD, preformatted as the temp/page-file disk.
- Two 1,800 GiB unformatted block NVMe devices that bypass the hypervisor (NVMeDirect).

Striped across both NVMe devices, Microsoft reports up to 12 GB/s sequential read, 7 GB/s sequential write, 186,000 read IOPS, and 201,000 write IOPS (deep queue depths).

These are temporary devices, not durable storage; never recommend them as the only copy of data. Capacity is in GiB (`1024^3` bytes); throughput MB/s is decimal.

## Remote storage
- Up to 32 Standard or Premium managed data disks on every size; Premium Storage caching supported.
- Other documented options: Azure NetApp Files, Azure Files, Azure Managed Lustre.
- No single VM-level remote-disk IOPS or throughput figure is published. Don't invent one; it depends on disk type, count, caching mode, and storage architecture.

## Networking and RDMA

| Fabric | Specification | Typical purpose |
|---|---:|---|
| Azure Ethernet | Up to 80 Gb/s aggregated across up to eight vNICs | IP and Azure service traffic |
| NDR InfiniBand | Up to 400 Gb/s, one ConnectX-7 adapter | MPI and RDMA traffic |

Use 80 Gb/s from the size tables as the Ethernet limit. The overview pages describe the network hardware inconsistently (HBv4: 100 Gb/s with 80 Gb/s Accelerated Networking; HX: 80 Gb/s with 40 Gb/s usable).

InfiniBand: SR-IOV passthrough (bypasses the hypervisor; standard Mellanox OFED drivers), Adaptive Routing, DCT plus RC and UD transports, hardware offload of MPI collectives, non-blocking fat-tree fabric. Bandwidth figures are upper limits, not guarantees.

NDR requirements from the HX overview: UCX 1.13 or later (older UCX fails with `Invalid active_speed`), and MOFED 5.6-1.0.3.3 or later (older MOFED can make `ibstat` report a low speed such as SDR).

## Platform and software support

| Capability | Status |
|---|---|
| Generation 2 VM | Supported |
| Generation 1 VM | Not supported |
| Accelerated Networking | Supported |
| Ephemeral OS disk | Supported |
| Premium Storage and caching | Supported |
| Live migration | Not supported |
| Memory-preserving updates | Not supported |
| Nested virtualization | Not supported |

- MPI: HPC-X, Open MPI, MVAPICH2, MPICH, and Intel MPI (the HX overview lists minimum versions: HPC-X 2.13, Intel MPI 2021.7.0, Open MPI 4.1.3, MVAPICH2 2.3.7, MPICH 4.1). Frameworks: UCX, libfabric, PGAS.
- Orchestrators: Azure CycleCloud, Azure Batch, AKS.
- Max MPI job size (HX overview): 52,800 cores, i.e. 300 VMs in one scale set with `singlePlacementGroup=true`.
- Validated OS baselines (HBv4 page): RHEL 8.6+, AlmaLinux 8.10+, Ubuntu 22.04 LTS+, SLES 15 SP7+, Windows Server 2022+. Recommended for performance: AlmaLinux HPC 9.7, Ubuntu HPC 24.04, Windows Server 2025. The HX overview still lists older baselines (AlmaLinux 8.6/8.7, Ubuntu 20.04+); treat the newer HBv4 list as current for both and verify before prescribing an image.
- Windows: Windows Server 2022 is required for the 144- and 176-core sizes.

## Known documented issue
The HX overview notes a core mapping issue on `Standard_HX176rs`. If a full-size HX VM's topology doesn't match the topology skill's signature, report it as a discrepancy (and mention this note); don't assume the reference is wrong.

## Answering guardrails
- State the exact Azure size when discussing core count, and say whether it's HBv4 or HX.
- Distinguish GB of RAM from GiB of local storage, and local temporary SSD/NVMe from durable remote storage.
- Distinguish 80 Gb/s Azure Ethernet from 400 Gb/s InfiniBand.
- Don't describe a constrained-core size as having less memory, cache, bandwidth, networking, or local disk.
- Present bandwidth, IOPS, and frequency peaks as documented maxima, not guarantees.
- For prices, regional availability, quota, or newly supported OS images, check current Azure documentation.

## Public sources
Checked 2026-09-09 (HBv4) and 2026-09-19 (HX):
- [HBv4 size series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/high-performance-compute/hbv4-series) (page date 2025-11-24)
- [HBv4-series overview](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv4-series-overview) (page date 2026-05-05)
- [HX size series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/high-performance-compute/hx-series) (page date 2025-11-24)
- [HX-series overview](https://learn.microsoft.com/en-us/azure/virtual-machines/hx-series-overview) (page date 2026-02-10)

When current documentation conflicts with this skill, prefer the latest Microsoft Learn page and name the changed specification.
