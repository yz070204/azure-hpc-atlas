# HPC Atlas

**AI-assisted Azure HPC VM troubleshooting, with domain knowledge as skills.**

HPC Atlas is a GitHub Copilot CLI agent plus a set of reusable skills that package the Azure HPC team's experience: readiness checks, topology validation, benchmark-driven performance tuning, and evidence-based triage that separates software or configuration issues from possible platform or node-health issues.

The skills are plain Markdown. Copilot can run them, and anyone can read them and follow along by hand.

> **Status:** HPC Atlas started as a Microsoft Global Hackathon 2026 project. SKU coverage is currently limited to full-size HBv4 and HX, and a few workloads; more SKUs and skills will be added over time. See [Supported VMs](#supported-vms) and [Roadmap](#roadmap).

## Quick start

**Prerequisites**
 
- A GitHub account with a Copilot plan. If you get Copilot through your organization, use the organization account to login.
- Each prompt uses AI credits from your Copilot plan.
  
Assumes the HBv4/HX full size VM runs on Azure HPC image, Ubuntu 24.04 (`microsoft-dsvm:ubuntu-hpc:2404:latest`).

**1. Install GitHub Copilot CLI**

```bash
curl -fsSL https://gh.io/copilot-install | bash
```

Sign in with your GitHub account when prompted on first launch.

**2. Clone this repo**

```bash
git clone https://github.com/yz070204/azure-hpc-atlas.git
```

**3. Start the agent**

```bash
copilot -C ./azure-hpc-atlas --agent hpc-atlas
```

Then just ask, for example:

- `check this VM`
- `why my VM does not have IB`
- `check stream memory bandwidth on this VM`
- `run WRF`

### Quick test mode

On a throwaway test VM with **no secrets, credentials, or customer data**, you can skip the per-command permission prompts:

```bash
copilot -C ./azure-hpc-atlas --agent hpc-atlas --yolo
```

`--yolo` allows all tools, paths, and URLs for the session. Don't use it on production VMs or anywhere sensitive data lives.

## What it does

| Area | What HPC Atlas does |
|---|---|
| Readiness and triage | Runs the Azure HPC diagnostics under `/opt/azurehpc/diagnostics`, checks InfiniBand, CPU frequency, and topology, and classifies the result |
| Topology | Validates vCPU, NUMA, and CCD layout against the published reference for full-size HBv4 and HX |
| STREAM | Builds and runs STREAM with the SKU's compiler flags and pinning, and compares against the published reference |
| WRF | Builds and runs the CONUS 2.5 km benchmark with a validated single-node recipe |
| General optimization | Profiles and tunes workloads without a dedicated skill: ranks and threads, pinning, MPI transport, compiler flags, I/O |
| Specifications | Answers factual questions about HBv4 and HX sizes and capabilities |

Every investigation ends with a verdict:

- `expected`: matches the SKU and validated conditions
- `capability-mismatch`: wrong VM size for the need, with a recommended size
- `configuration-or-software`: affinity, NUMA, drivers, MPI, or app settings, with a recommended fix
- `inconclusive`: not enough evidence, or contradictory evidence
- `possible-platform-or-node-health`: capability confirmed, config clean, discrepancy repeats; escalate to Azure support with the evidence bundle

## Supported VMs

- **Full coverage:** full-size HBv4 and HX (`Standard_HB176*_v4`, `Standard_HX176*`), e.g. `Standard_HB176rs_v4`, `Standard_HX176rs`
- **General guidance only:** constrained-core sizes (e.g. `Standard_HB176-144rs_v4`) and other HPC families

Each workload skill states its own validated scope.

## How it behaves

- Quick checks (diagnostics, topology, `ibstat`, short STREAM, CPU frequency, InfiniBand loopback) run without asking.
- It asks before heavier workloads, multi-node tests, installing packages, rebooting, or changing persistent settings.
- It never calls something a hardware failure from a single symptom or benchmark.
- It redacts credentials, tokens, and customer data, and never uploads anything. All output goes to `~/hpc-atlas-output/<UTC timestamp>/`; when escalating, it writes an `escalation.md` there for you to review and attach to your support case.

## Without Copilot

Everything is readable on its own. Open a skill's `SKILL.md`, follow the steps, and run the scripts next to it.

## Repository layout

```
.github/
  agents/
    hpc-atlas.agent.md                 # routes symptoms to skills; triage and report rules
  skills/
    hpc-atlas-vm-readiness/            # first-line readiness and triage, escalation bundle
    azure-hbv4-hx176-topology/         # vCPU/NUMA/CCD reference and check-topology.sh
    azure-hbv4-hx-vm-specifications/   # published HBv4 and HX specifications
    stream-performance/                # STREAM build, run, summarize, reference targets
    wrf-performance/                   # WRF build, CONUS run, output comparison
    hpc-atlas-workload-optimization/   # tuning for workloads without a dedicated skill
```

## Roadmap

- More HPC SKUs
- More application skills, e.g. OpenFOAM
- More skills drawn from real support cases
