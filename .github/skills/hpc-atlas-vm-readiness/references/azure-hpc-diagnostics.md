# Azure HPC diagnostics collector

Script: `/opt/azurehpc/diagnostics/gather_azhpc_vm_diagnostics.sh` ([Azure/azhpc-diagnostics](https://github.com/Azure/azhpc-diagnostics)). It snapshots system, driver, IB, and log evidence into an archive. It is not a health checker or a performance test.

## Before running
1. Confirm the script exists. Record its SHA-256 and version with `bash <script> --offline --no-update --version` (without those flags, `--version` may try to self-update). Don't source it.
2. Confirm a CPU-only VM (no GPU in SKU or `lspci`). Don't run on GPU VMs: its GPU path changes state even with `--gpu-level=0`.
3. Check free disk space and `journalctl --disk-usage`. It collects the full journal, agent logs, network addresses, and BIOS data, so output can be large and sensitive; mention this in the report.

## Run
```bash
out=~/hpc-atlas-output/<timestamp>   # the investigation folder
echo y | sudo -n bash /opt/azurehpc/diagnostics/gather_azhpc_vm_diagnostics.sh \
  --offline --no-update --mem-level=0 --dir="$out"
```
- `echo y` answers the script's confirmation prompt. No user approval is needed for this run.
- `--offline`: no Internet steps. `--no-update`: no self-update. `--mem-level=0`: skip its built-in STREAM, which covers only old SKUs.
- Output: `<out>/<vmId>.<timestamp>.tar.gz` (the script prints the path). Confirm it exists; exit 0 alone isn't success.
- If `sudo -n` fails, skip this step and run the checks directly. Never ask for a password in chat.
- If it reports a VM extension still installing, wait and retry later; don't stop the extension.
- A failure means incomplete collection: keep partial output, report it, don't auto-retry.
- Never use `--tuning` or apply its suggestions (generic zone-reclaim, limits, and SELinux changes).

## What the archive covers
Start with `transcript.log` (VM size, image, and any "common issues" found). `hpcdiag.err` is shell tracing, so its size alone isn't a failure. Don't extract a user-supplied archive as root, never execute its contents, and don't paste raw logs into web tools.

| File | Use for | Limit |
|---|---|---|
| `CPU/lscpu.txt` | CPU model, vCPU count, NUMA node count | Summary only; not the `lscpu -e` topology signature |
| `VM/dmesg.log` | Machine-check, EDAC, driver errors | Only since boot; `journald.log` covers longer |
| `VM/lspci.txt`, `VM/lsmod.txt` | Device visibility, modules | A VF may show a generic ConnectX label |
| `Infiniband/ibstat.out`, `ibv_devinfo.out` | Link state, rate, firmware | Link up ≠ working MPI |
| `Memory/zone_reclaim_mode`, `limits.conf` | Config snapshot | Not the job's effective limits |

**Not collected** (run directly): `lscpu -e`, total memory, local disks, STREAM, CPU frequency, steal time, VM tags.

The script collects IB data only when the VM size name has `r` after the size family (e.g. `...176rs`). If the SKU spec says the size has IB but the archive has no `Infiniband/` folder, run `ibstat` directly. "No Infiniband Driver Detected" can mean a missing utility; verify with `lspci` and modules.

The script keeps going after subcommand failures, so check that the files you need exist and aren't empty. If its options or prompts don't match this page (e.g. a flag is rejected), stop and report it rather than guessing new flags.
