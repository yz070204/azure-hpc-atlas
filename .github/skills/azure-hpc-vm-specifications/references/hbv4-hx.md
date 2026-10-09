# HBv4 and HX specifications

HBv4 and HX share CPU, cache, storage, and networking. **Memory is the main difference: HBv4 has 768 GB; HX has 1,408 GB.** HX targets memory-capacity-bound workloads such as EDA.

## Hardware

| Component | HBv4 / HX |
|---|---|
| CPU | AMD EPYC 9V33X (Genoa-X, Zen 4), x86-64, AMD 3D V-Cache |
| Host | Two 96-core processors; 192 cores, 16 reserved for Azure |
| SMT | Disabled |
| Frequency | 2.55 GHz base; published single-core and all-core peak 3.7 GHz |
| Memory | HBv4: 768 GB; HX: 1,408 GB, on every size |
| Memory bandwidth | 780 GB/s |
| L3 cache | 2,304 MB; up to 5.7 TB/s cache bandwidth |
| Effective memory speed | Microsoft reports an average of 1.2 TB/s for many workloads |
| Temp disk | One 480 GiB SSD |
| Local NVMe | Two 1,800 GiB devices |
| Azure Ethernet | Up to 80 Gb/s aggregate; up to eight vNICs |
| InfiniBand | One 400 Gb/s ConnectX-7 NDR adapter, SR-IOV/RDMA |
| Accelerators | None |

**Frequency:** the size tables list 3.7 GHz for both peaks. The existing HBv4/HX reference records full-load measurements slightly below 2.55 GHz, confirmed by AMD; lightly loaded cores can approach 3.7 GHz. Do not use the published peak as an all-core baseline.

## Sizes

All sizes have four vNUMA nodes and retain their family's memory, cache, networking, and local disks.

| vCPUs | HBv4 | HX | Cores/vNUMA |
|---:|---|---|---:|
| 176 | `Standard_HB176rs_v4` | `Standard_HX176rs` | 44 |
| 144 | `Standard_HB176-144rs_v4` | `Standard_HX176-144rs` | 36 |
| 96 | `Standard_HB176-96rs_v4` | `Standard_HX176-96rs` | 24 |
| 48 | `Standard_HB176-48rs_v4` | `Standard_HX176-48rs` | 12 |
| 24 | `Standard_HB176-24rs_v4` | `Standard_HX176-24rs` | 6 |

## Architecture

- Host: 24 CCDs, eight cores and 96 MB L3 per CCD. Azure reserves 16 cores symmetrically across both sockets.
- Published BIOS: NPS=2, `L3 as NUMA` disabled, C-states enabled.
- Four physical NUMA domains, two per socket; six CCDs and six DRAM channels per domain. Guest NUMA maps to physical NUMA.
- Exact full-size placement is in `azure-hbv4-hx176-topology`, not the specifications table.

## Storage and networking notes

The two NVMe devices are separate, unformatted blocks using NVMeDirect. Striped together, Microsoft reports up to 12 GB/s read, 7 GB/s write, 186,000 read IOPS, and 201,000 write IOPS at deep queue depths. These are aggregate limits, not per-device figures.

Use the size tables' **80 Gb/s Ethernet** figure. The overviews differ: HBv4 describes 100 Gb/s hardware with 80 Gb/s Accelerated Networking; HX describes 80 Gb/s hardware with 40 Gb/s usable. Do not silently reconcile these figures.

InfiniBand supports Adaptive Routing, DCT/RC/UD, MPI collective offload, and a nonblocking fat-tree fabric. The HX overview requires UCX 1.13+ and MOFED 5.6-1.0.3.3+: older UCX may fail with `Invalid active_speed`, and older MOFED may make `ibstat` report SDR.

## Software and documented issues

| Item | Published information |
|---|---|
| MPI | HPC-X, Open MPI, MVAPICH2, MPICH, Intel MPI |
| HX minimum versions | HPC-X 2.13; Intel MPI 2021.7.0; Open MPI 4.1.3; MVAPICH2 2.3.7; MPICH 4.1 |
| HX max MPI job | 52,800 cores / 300 VMs in one scale set with `singlePlacementGroup=true` |
| HBv4 OS baselines | RHEL 8.6+, AlmaLinux 8.10+, Ubuntu 22.04 LTS+, SLES 15 SP7+, Windows Server 2022+ |
| HBv4 performance recommendations | AlmaLinux HPC 9.7, Ubuntu HPC 24.04, Windows Server 2025 |
| Older HX OS list | AlmaLinux 8.6/8.7, Ubuntu 20.04+; verify current HX support before prescribing an image |
| Windows | Windows Server 2022 required for 144- and 176-core sizes |

The HX overview documents a core-mapping issue on `Standard_HX176rs`. If live topology differs from the topology reference, report the discrepancy and this note; do not assume either is wrong.

## Sources

Previously checked 2026-09-09 (HBv4) and 2026-09-19 (HX):
- [HBv4 sizes](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/high-performance-compute/hbv4-series) (page date 2025-11-24)
- [HBv4 overview](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv4-series-overview) (page date 2026-05-05)
- [HX sizes](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/high-performance-compute/hx-series) (page date 2025-11-24)
- [HX overview](https://learn.microsoft.com/en-us/azure/virtual-machines/hx-series-overview) (page date 2026-02-10)
