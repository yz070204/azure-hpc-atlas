---
name: hpc-atlas-vm-readiness
description: First-line readiness and performance triage for Azure HPC VMs. Use for "check this VM", "check IB", "why is my job slow", HPC health checks, running or reading the Azure HPC diagnostics under /opt/azurehpc/diagnostics, unexpected CPU/NUMA topology, or missing InfiniBand.
---

# HPC Atlas VM readiness

Minimal, evidence-based triage on the affected VM. Follow the HPC Atlas agent rules, classification, and report format; this skill adds the workflow.

## Entry points
| Request | Start with |
|---|---|
| "Check this VM", "check readiness" | Triage; report the checked scope, not a whole-node health verdict |
| "Check IB", "run STREAM", or another single check | Steps 1–2, then only that check (and its follow-up if it fails) |
| "Why is my job slow?" | Triage, then Application performance |
| "Review this diagnostics archive" | `references/azure-hpc-diagnostics.md` |

Use the current VM unless another is named. Run the applicable quick checks below. If one is blocked, resolve it or request the necessary approval; do not report the check as complete. Don't invent a symptom or assume WRF, STREAM, or IB is the bottleneck.

## Triage
Create one investigation folder, `~/hpc-atlas-output/<UTC timestamp>/`, and put every output from this investigation in it.

1. **Identity:** VM size from IMDS, image version, OS/kernel. If IMDS fails, report an evidence gap; don't assume a size.
2. **Capability gate:** for Azure H-series InfiniBand requests, first apply the [InfiniBand capability gate](../azure-hpc-vm-specifications/SKILL.md#infiniband-capability-gate-azure-h-series): a size without the `r` suffix is `capability-mismatch`; recommend only documented public IB-enabled sizes within this advisor's supported scope and stop before IB diagnostics or benchmarks. Otherwise, check the detected SKU in its specification skill. Missing feature → `capability-mismatch`, stop. Capability can't be verified → `inconclusive`, not "unsupported"; don't infer undocumented capabilities from the SKU name or installed drivers. No skill covers the SKU → say so, run only generic checks, and don't borrow another SKU's thresholds.
3. **HPC diagnostics:** run the collector (no approval needed) per `references/azure-hpc-diagnostics.md` into the investigation folder, or reuse an existing archive if VM state hasn't changed. Steps 4–5 read from the archive where it covers a check and run commands only for what it doesn't. If absent, sudo is unavailable, or collection is incomplete, say so and run everything directly.
4. **Inventory vs spec:** compare with the SKU's specification skill: CPU model, vCPU count, NUMA node count (from the archive's `CPU/lscpu.txt`), total memory (`MemTotal` in `/proc/meminfo`; the guest sees slightly less than the spec), and local disks (`lsblk -d -o NAME,SIZE,MODEL`: count and size). If a topology skill covers the exact size (`azure-hbv4-hx176-topology` for full-size HBv4/HX, `azure-hbv5-368-topology` for `Standard_HB368rs_v5`), also compare the complete `LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE` output with its signature, which covers L3 distribution. For live validation, run `bash .github/scripts/check-topology.sh <family>` from the repo root, using `hbv4`, `hx`, or `hbv5` only after confirming the applicable full-size SKU. Save its output and exit status; do not write a separate parser. Guest L3 IDs may not reflect physical cache sharing, so follow the applicable skill. Always report a mismatch and rule out guest or boot-config causes before classifying `possible-platform-or-node-health`; HBv5 is a single-VM measured signature, and a numbering difference alone is not proof of a fault.
5. **Quick checks** (no approval needed). Sample overall CPU utilization three times (`vmstat 1 4`; ignore the first row; utilization = `100 - id`). If all samples are below 5%, run applicable benchmarks and note background activity; otherwise defer perf checks and report the load. Do not judge load by process count or load average alone.
   - InfiniBand (IB SKUs only): check link Active/LinkUp at the expected rate, from the archive's `Infiniband/ibstat.out`, or `ibstat` if the archive lacks it. Once the link is ready and the utilization gate above passes, run the local RDMA loopback below as a normal quick check.
   - Memory: run short STREAM using the detected SKU's supported recipe. Reuse a verified binary or build it if missing. The STREAM skill's private AOCC 4.0.0/source download needs no separate approval; request approval only for other dependency installs.
   - CPU (base and peak frequency from the SKU's specification skill; read per-core `cpu MHz` from `/proc/cpuinfo` midway through each load):
     - Turbo: busy-loop one CPU per NUMA node for 10 s (`for n in /sys/devices/system/node/node*/; do c=$(cut -d, -f1 $n/cpulist | cut -d- -f1); taskset -c $c timeout 10 sh -c 'while :; do :; done' & done; wait`). Loaded cores well above base mean turbo works; at or below base means turbo is off.
     - Uniformity: busy-loop every core for 10 s. All-core load can run slightly below base, so don't read this as turbo off; flag only cores well below the rest. Also check `steal` in `vmstat 1` during the load; it should be ~0.
   - If turbo is off, read VM tags: `curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/tagsList?api-version=2021-02-01"`. If a tag whose name contains `disableturboboost` (case-insensitive; this is not the full tag name) is set to `true`, classify `expected`: name that tag as the likely reason turbo is off and tell the user they can remove it if unintended. Otherwise repeat the check; if still low, classify `possible-platform-or-node-health` and escalate.
   - Only mention a tag the VM actually has; never suggest tag names.
   - Hardware errors: scan the archive's `VM/dmesg.log` for machine-check or EDAC errors (`dmesg` directly may need root).
   - A low result means repeat 2–3 times before drawing conclusions.
6. **Deeper check (ask first):** if quick checks are low or inconclusive, or the user reports application slowness, offer a heavier workload and state its expected runtime. Run only after approval.
   - A calibrated workload skill for the SKU (e.g. WRF): has a baseline, so it gives a verdict.
   - The user's own application, if already installed: compare with their earlier result or another node with the same input; without a baseline, report the result as a data point, not a verdict.
7. **Workload context** (performance complaints only): workload, version, input, launch command, ranks/threads, metric, baseline, recent changes. Read scripts, logs, and job records first; ask the user only for what's missing.

## Local InfiniBand RDMA loopback
After triage confirms an idle VM and an Active/LinkUp IB port, select `<dev>` and `<ib-port>` from `ibv_devinfo`. Start the server in a separate session; wait for "Waiting for client to connect" before running the client:

```bash
timeout 20 ib_write_bw -d <dev> -i <ib-port> -D 5 --report_gbits
timeout 20 ib_write_bw -d <dev> -i <ib-port> -D 5 --report_gbits localhost
```

The agent saves both outputs in the investigation folder, checks both exit statuses and a positive bandwidth result, and stops only its own test processes on error/interruption. If the default TCP port 18515 is occupied, use the same unused `-p` port on both commands; never stop another process. Ask before installing missing tools.

Report pass/fail and average Gb/s with message size, queue-pair count, and duration. There is no calibrated bandwidth threshold; this tests local adapter/driver operation, not fabric or MPI performance. Reuse a successful result if VM state is unchanged; repeat suspect results 2-3 times under matched idle conditions.

## If a quick check fails
**InfiniBand** (stop at the first step that explains it):
1. Is the ConnectX device visible in `lspci`? Are modules loaded and RDMA devices present (`ibv_devinfo`)?
2. Are port error counters increasing (`perfquery`, if available)?
3. Once the device and link are ready, run or review the local RDMA loopback above. Reuse its logs rather than rerunning a successful test unless VM state changed. Resolve a failed loopback before proceeding to a fabric test.
4. Real fabric test (ask first): `osu_bw` / `osu_latency` (pre-installed; find under `/opt`) over MPI between this VM and a second one the user provides.

Link up at the expected rate proves local link readiness, not MPI connectivity or bandwidth.

**STREAM:** before suspecting the node, check full-size vs constrained-core, topology, thread count, affinity, NUMA/first-touch placement, build, and array size. One low run without placement and provenance says nothing about node health; repeat under matched conditions.

## Application performance
Explain the user's gap, not whether another benchmark runs well. Use the SKU's calibrated workload skills where they match, and `hpc-atlas-workload-optimization` for tuning.

1. **Reconstruct the actual run** from job scripts, logs, scheduler records, and (where permitted) live process affinity: ranks, threads, binding, memory policy, binary/libraries, input, storage path. Label requested vs effective settings. If historical evidence is missing, say so instead of guessing. Don't search unrelated directories or other users' histories; redact secrets.
2. **Check contention and limits:** CPU/memory pressure, swap, I/O wait, competing jobs, cgroup/scheduler CPU sets. An idle snapshot after the run can't rule out contention during it. Don't kill jobs, clear caches, or reboot to get a clean baseline.
3. **Test one factor at a time** (approval and a bounded run budget): user baseline vs candidate with the same binary, input, metric, and correctness checks. Repeat enough to separate the effect from variance. If several things changed at once, don't claim which one caused it.
4. **Report** a comparison, then the confirmed cause vs untested hypotheses, the best validated command and its scope, and the measured improvement:

| Run | Effective settings | Load conditions | Metric (n runs) | Variance | Correct? |
|---|---|---|---|---|---|

If the original slowness can't be reproduced, the cause stays `inconclusive`. If no run was approved, give the proposed command, not a claimed fix.

## If resolved
Add to the report: cause, change made or recommended, before/after result, how to prevent recurrence.

## Escalation
Only when triage can't resolve the issue or evidence supports `possible-platform-or-node-health`. Follow `references/escalation-bundle.md`. A same-image, same-command comparison on another node strengthens the case when practical (with approval; never redeploy without approval).
