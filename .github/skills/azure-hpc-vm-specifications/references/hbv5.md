# HBv5 specifications

Published specifications for HBv5. The separate `azure-hbv5-368-topology` skill contains the measured full-size guest signature and supplied host NUMA/CCD membership. HBv5 workload benchmarks remain unvalidated here.

## Hardware

| Component | HBv5 |
|---|---|
| CPU | AMD EPYC 9V64H (9004-series, Zen 4), x86-64 |
| Host | Four 96-core processors; 384 cores, 16 reserved for Azure |
| SMT | Disabled |
| Frequency | 3.5 GHz base; published single-core and all-core peak 4 GHz |
| Memory | 432 GB HBM on every size |
| Memory bandwidth | Up to 6.7 TB/s; smaller-size limits below |
| L3 cache | 1.5 GB in the size table; 32 MB per CCD in the overview |
| Temp disk | One 480 GiB SSD |
| Local NVMe | Eight devices; conflicting capacities below |
| Azure Ethernet | Up to 180 Gb/s aggregate; up to eight vNICs |
| InfiniBand | Four 200 Gb/s ConnectX-7 NDR adapters; 800 Gb/s aggregate, SR-IOV/RDMA |
| Accelerators | None |

## Sizes

The overview's table lists 16 vNUMA nodes for every size. Memory, cache, networking, and local disks are unchanged across variants.

| vCPUs | Size | Published cores/vNUMA |
|---:|---|---:|
| 368 | `Standard_HB368rs_v5` | 23 |
| 336 | `Standard_HB368-336rs_v5` | 21 |
| 288 | `Standard_HB368-288rs_v5` | 18 |
| 240 | `Standard_HB368-240rs_v5` | 15 |
| 192 | `Standard_HB368-192rs_v5` | 12 |
| 144 | `Standard_HB368-144rs_v5` | 9 |
| 96 | `Standard_HB368-96rs_v5` | 6 |
| 48 | `Standard_HB368-48rs_v5` | 3 |

**Bandwidth caveat:** all size rows list 6.7 TB/s, but the overview says four cores per CCD are needed to saturate memory bandwidth. It states the 144-, 96-, and 48-core sizes cannot achieve full server bandwidth.

## Architecture and source conflicts

- Overview: 48 CCDs, 12 per socket; eight cores and 32 MB L3 per CCD.
- Published BIOS: NPS=4, `L3 as NUMA` disabled, C-states enabled, Power determinism mode.
- The table and architecture section give 16 NUMA domains, four per socket, with 23 guest cores per domain on the full-size VM.
- Conflicting prose says four guest NUMA domains, six CCDs per domain, and four reserved cores per NUMA, while also stating 16 reserved cores per server. Keep this discrepancy explicit. Use the separate topology evidence for placement, not an inferred interpretation of the prose.

## Storage and networking notes

The eight NVMe devices are unformatted blocks that bypass the hypervisor. Striped together, Microsoft reports up to 50 GB/s read and 30 GB/s write, not per-device limits.

**NVMe capacity conflict:** the size table lists 14,304 GiB; its host table says 14.304 TiB and 1.9 TB/disk; the introduction says 14.3 TiB. The overview says 15 TiB total and eight 1.8 TB disks. Quote the source rather than choosing a reconciled capacity. Check live devices with `lsblk -b -d -o NAME,SIZE,MODEL`.

The overview describes 200 Gb/s Ethernet hardware with **180 Gb/s Accelerated Networking**. InfiniBand has one NIC per socket; check all four adapters. **800 Gb/s is aggregate, not a single-port rate.** Features include Adaptive Routing, DCT/RC/UD, MPI collective offload, and a nonblocking fat-tree fabric.

The overview recommends `UCX_MAX_RNDV_RAILS=1` for multi-node jobs. Its UCX 1.14.0 rc4 and HPC-X 2.18 versions are September 2025 examples, not current-version or minimum-version claims. Discover the installed stack before tuning.

## Software

| Item | Published information |
|---|---|
| MPI | HPC-X, Open MPI, MVAPICH2, MPICH |
| Max MPI job | 110,400 cores / 300 VMs in one scale set with `singlePlacementGroup=true` |
| OS baselines | RHEL 8.10+, AlmaLinux 8.10+, Ubuntu 22.04+, SLES 15 SP7+, Windows Server 2022 |
| Performance recommendations | AlmaLinux HPC 9.7, Ubuntu HPC 24.04, Windows Server 2025 |

Earlier InfiniBand guidance on the page names older Ubuntu HPC images; verify current image/driver support. Its tuned, THP, NUMA-balancing, and cache-dropping suggestions are not automatic readiness actions; ask before installing or changing settings.

## Sources

Previously checked 2026-10-07:
- [HBv5 sizes](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/high-performance-compute/hbv5-series) (page date 2026-09-25)
- [HBv5 overview](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv5-series-overview) (page date 2026-09-26)
