# azure-hpc-atlas
Copilot agent and reusable skills for self-service Azure HPC readiness checks, workload performance tuning, and evidence-based triage of software/configuration issues versus possible platform or node-health issues.

## First-line triage

On the affected VM, use the `hpc-atlas-firstline-triage` skill with prompts such as:

> Check this VM.

> Check readiness.

> Check IB.

> Why is my performance bad?

> Review this HPC diagnostic archive: <path>.

For IB checks, the skill first detects the exact VM size and verifies its
documented InfiniBand support. If unsupported, it explains the
`capability-mismatch` and stops instead of troubleshooting drivers or
escalating a node-health issue. Users do not need to include these steps in
their prompt.

General checks start with read-only readiness discovery. Performance questions
look for the user's actual launch parameters in relevant job scripts, logs,
and runtime evidence, then check configuration, inherited environment, resource
limits, and competing work. Approved controlled comparisons aim to explain
the performance gap and provide the best validated configuration, not merely
a faster unrelated benchmark. A clean shell and an idle VM are different
conditions; neither is assumed. Short prompts retain the same approval and
privacy safeguards.

The skill uses the installed Azure HPC diagnostics as an optional evidence
collector, not a blanket health test. It checks the local version, avoids
automatic updates and benchmarks, and interprets results against the detected
SKU. See the [collector procedure and limitations](.github/skills/hpc-atlas-firstline-triage/references/azure-hpc-diagnostics.md).
