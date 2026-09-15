# Installed Azure HPC diagnostics

## Role and selection

The Azure HPC image may include
`/opt/azurehpc/diagnostics/gather_azhpc_vm_diagnostics.sh`, from
[Azure/azhpc-diagnostics](https://github.com/Azure/azhpc-diagnostics).
Treat it as an optional evidence collector, not a health certification.

| Situation | Best use |
|---|---|
| General readiness request | Targeted identity, topology, PCI, and RDMA checks first |
| Missing InfiniBand | Capability gate, then PCI/modules/link checks; collect a bundle only if useful |
| Low application or STREAM performance | Validate the application's metric and placement; the bundle only supplies context |
| Unresolved driver/kernel issue or escalation | Approved local collection preserves correlated system and device evidence |
| Existing archive supplied | Inspect relevant members locally before requesting another run |

The inspected version has no subsystem-only or journal time-window option.
Even with benchmarks disabled it collects the full available system journal,
agent logs, network addresses, BIOS data, sysctls, and Hyper-V KVP data. This
can be large, sensitive, and costly to compress. Prefer a narrow,
time-bounded log query when that alone can answer the question.

## Inspect before execution

1. Detect the live Azure SKU using IMDS, with `Metadata:true`, proxy bypass,
   and a bounded request. Failure to obtain metadata is an evidence gap, not
   proof that a capability is absent. Establish expected capabilities from
   the applicable SKU reference, not this script's SKU-name heuristics.
2. Check that the script exists and read its option parsing, metadata,
   collection, update, benchmark, and GPU paths. Record its SHA-256 and
   reported version. Installed copies can differ; recheck these instructions
   against the local source before using them.
3. For the inspected version, query help and version without update access:

   ```bash
   diag=/opt/azurehpc/diagnostics/gather_azhpc_vm_diagnostics.sh
   sha256sum "$diag"
   bash "$diag" --offline --no-update --version
   bash "$diag" --offline --no-update --help
   ```

   Bare `--help` or `--version` can check for updates first in this version.
   Do not source the script: top-level option parsing and other code still run.
4. Confirm no GPU branch will execute before using the CPU-only recipe below.
   Check both SKU and device inventory; the script's GPU SKU list is dated.
   Do not assume an unrecognized GPU SKU makes collection safe or complete.
5. Check destination space, journal size (`journalctl --disk-usage` where
   permitted), node activity, and privileges. Avoid shared workload storage.
   Explain that broad collection writes files and causes disk/CPU load, then
   obtain approval for sudo and broad local logs. This is separate from
   approval to benchmark, change settings, or share data.

## Approved CPU-only collection

Use only after the above gates, on a non-GPU VM. The user must approve the
collector's confirmation as well; an assistant may supply that single answer
only after obtaining explicit approval, not pipe an unbounded `yes`.

Example for a Bash terminal, with a private destination outside the repository:

```bash
umask 077
out=$(mktemp -d "${TMPDIR:-/tmp}/azhpc-diag.XXXXXX") || exit 1
printf 'Local evidence: %s\n' "$out"
sha256sum /opt/azurehpc/diagnostics/gather_azhpc_vm_diagnostics.sh \
  >"$out/collector.sha256"
set -o pipefail
sudo -n env no_proxy=169.254.169.254 NO_PROXY=169.254.169.254 \
  timeout --signal=TERM --kill-after=10s 300s \
  bash /opt/azurehpc/diagnostics/gather_azhpc_vm_diagnostics.sh \
  --offline --no-update --mem-level=0 --dir="$out" \
  2>&1 | tee "$out/runner.log"
rc=${PIPESTATUS[0]}
printf 'Collector exit status: %s\n' "$rc" | tee "$out/exit-status.txt"
```

Record the exact invocation, UTC time, detected SKU/image/kernel, and tool
identity alongside the output. Use a durable private session directory instead
of `/tmp` if evidence must survive temporary-file cleanup. Do not grant broad
permissions to make root-owned evidence easier to read.

- `--offline` skips Internet-dependent steps, not link-local IMDS requests.
  The inspected metadata calls have no internal deadline or proxy bypass;
  the environment and outer timeout above bound that risk.
- `--no-update` prevents self-update prompts. Do not replace the installed
  script as part of first-line discovery.
- `--mem-level=0` disables STREAM, not general memory/configuration collection.
- The 300-second deadline is a collection budget, not a health threshold.
  A timeout, denial, or failure is incomplete collection. Preserve partial
  output and explain the blocker; do not retry automatically with more time.
- The collector requires root. If `sudo -n` is unavailable or denied, stop
  this branch and use unprivileged targeted checks. Do not request credentials
  in chat.
- A declined confirmation can exit zero without collecting anything.
  Verify an archive actually exists and is readable. Successful compression
  removes the unpacked directory in this version; failed or timed-out runs
  can leave it behind.

Do not use `--gpu-level=0` as a supposed GPU-disable switch. In the inspected
source, GPU collection can still invoke debug dumps, start `nv-hostengine`,
and toggle persistence mode before the DCGM level switch. Even the default
GPU level 1 is not strictly read-only. GPU runs require a separate
workload-aware procedure and approval; this CPU-only recipe is not validated
for them.

## Interpret the bundle

List archive members first. Inspect only relevant members locally; for an
externally supplied archive, avoid blind extraction as root, absolute paths,
`..` entries, and link traversal. Never execute archive contents. Do not feed
raw logs to web tools or attach them to a public issue.

Start with `transcript.log`, the outer `runner.log`, and `hpcdiag.err`, then:

| Evidence | Interpretation and limits |
|---|---|
| `CPU/lscpu.txt` | Summary only; does not validate the exact per-CPU topology |
| `VM/lspci.txt`, `VM/lsmod.txt` | Correlate device visibility and loaded modules; a VF may have a generic ConnectX label |
| `Infiniband/ibstatus.out`, `ibstat.out`, `ibv_devinfo.out` | Correlate device, firmware, link layer, state, and reported rate |
| `Infiniband/<device>/pkeys/*` | Inspect relevant values when partition membership is implicated; file existence/count alone is not proof of working MPI |
| `Memory/limits.conf`, `zone_reclaim_mode` | Configuration snapshot, not effective limits of the user's job or a bandwidth measurement |
| `VM/dmesg.log`, `journald.log`, `waagent.log` | Read only the symptom's time window and relevant driver/kernel/agent messages |

The collector continues after many subcommand failures. Exit zero and an
archive are not sufficient: check relevant file presence, nonempty content
where expected, errors, and skipped sections. `hpcdiag.err` also contains
shell tracing and expanded command data; its existence or size alone does
not indicate a failure. Empty optional KVP pools or absent extension-status
logs are not automatically faults. A message such as "No Infiniband Driver
Detected" can reflect a missing utility; verify PCI/sysfs/modules separately.

Supplement the archive only where needed:

```bash
LC_ALL=C lscpu -e=CPU,NODE,SOCKET,CORE,CACHE,ONLINE
```

Preserve the complete output and compare covered full-size HBv4/HX SKUs with
the topology skill. Add effective job limits, MPI/library identity, binding,
or a controlled two-node communication test only when the symptom requires
them. Active/LinkUp and a reported 400 Gb/s rate establish local link
readiness, not measured bandwidth, MPI connectivity, or application health.

Do not enable `--tuning` or apply its suggestions automatically. The
inspected source contains generic recommendations to set zone reclaim mode,
change limits, or disable SELinux. They are not workload-specific evidence
and do not justify changing memory policy or weakening security.

For this installed version, STREAM's CPU-list table covers only
`Standard_HB60rs` and `Standard_HB120rs_v2`. HBv4 is unsupported and skipped.
`--offline` with a positive memory level is rejected. Do not enable downloads
or use a different SKU's affinity list to bypass these restrictions. For HBv4
performance, follow the triage memory branch and a separately validated
benchmark with recorded build, placement, input, repetitions, and baseline.

## Observed validation, 2026-09-15

One approved run of the installed copy on `Standard_HB176rs_v4`, Ubuntu HPC
24.04 image `24.04.2026082101`, kernel `6.8.0-1064-azure`:

- Reported version: `20220316-Unknown`; this is the script's version string,
  not proof of a particular upstream commit.
- SHA-256: `84ff4d57e89b6ccda3e21ff92f822dee3827aa9237732a6782aac5d03444d47d`.
- Flags: `--offline --no-update --mem-level=0 --dir=<private-output>`.
- Exit zero; readable archive with 152 files, about 3.04 MB compressed.
  `VM/journald.log` alone was about 369 MB uncompressed. Sizes and duration
  are node-specific, not expected limits.
- RDMA device `mlx5_ib0`, CA type `MT4126`, firmware `28.47.1026`,
  InfiniBand Active/LinkUp, reported `400 Gb/sec (4X NDR)`.
- Supplemental extended topology matched all 176 rows of the required
  full-size signature: four NUMA nodes, 44 CPUs each, policy-1 guest L3 groups.
- No STREAM, GPU diagnostic, MPI traffic test, or application benchmark ran.
  No automatic setting changes or uploads were performed.

Classification: `expected` for the observed CPU/NUMA and local IB readiness
only. Performance and cross-node connectivity remain untested. This single
run validates the collector's usefulness as supporting evidence on this
image, not every SKU, image, or future script revision. Keep raw archives
and identifiers out of the skill and repository.
