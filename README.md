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

## Run WRF without an AI assistant

Start with the [WRF CONUS runbook](.github/skills/hbv4-wrf-conus-performance/SKILL.md).
It follows **Check -> Build -> Run -> Review**, with explicit paths, checkpoints,
and recovery steps. The default uses WRF 4.2.2 and the v4.2 CONUS dataset on
one HBv4 node, preferring the original dependency versions and documenting any
approved exceptions. A separate four-node MPI/IB workflow is deferred.
This is not a universal WRF installer. A Bash build script uses the selected
stack, checks compatibility, and preserves stage logs; the run script
handles launch and post-run reporting. Neither requires an AI subscription.
Historical results and alternative configurations are kept separate from the
default path.

## Run STREAM without an AI assistant

Follow the [HBv4 STREAM runbook](.github/skills/hbv4-stream-performance/SKILL.md)
for **Check -> Build -> Run -> Review**. The HPC Atlas agent routes STREAM
requests to this concise skill; preparation, manual commands and experimental
evidence are loaded separately when needed.

| Request | Default |
|---|---|
| Run STREAM | Original AOCC 4.0.0 source, 280M doubles per array / 100 iterations, **176 threads**, THP allocation/defrag **always** (`source-original`) |
| Run AMD prebuilt STREAM | AMD 2024_10_08, fixed 650M / 10, **176 threads**, both THP settings **always** (`prebuilt-original`) |
| Explain a slow result | Inspect actual build/run parameters and compare matching experimental conditions before proposing changes |

**Optional tuning, not a default:** for the 280M/100-iteration benchmark, `tuned-144`
profile distributes six threads per physical CCD and reached approximately
842,000 MB/s median Triad on the tested HBv4. The
[tuning evidence](.github/skills/hbv4-stream-performance/references/tuning.md)
records controls, repeated finalists, variability and scope; this is not a
universal bandwidth threshold or a decisive win over the close 96-thread option.
The independent
[AMD prebuilt study](.github/skills/hbv4-stream-performance/references/prebuilt-tuning.md)
also supports balanced placement; `prebuilt-144` preserves its fixed 650M/10
workload and reached approximately 775,000 MB/s median Triad. Do not compare
that number directly with the differently sized source workload. After either
default run, the agent explains the observed 144-thread benefit and provides
the relevant [manual command](.github/skills/hbv4-stream-performance/references/usage.md#optional-144-thread-runs);
it does not automatically run a tuning sweep or change the baseline.

The standalone helpers retain build/run provenance, verify numerical output
and runtime thread binding, and summarize repeated Copy/Scale/Add/Triad
bandwidth measurements. The [script layout](.github/skills/hbv4-stream-performance/references/usage.md#script-layout)
keeps compiler and launch commands in the entry scripts, with separate
checks, logging and THP helpers. A reusable Bash/awk checker in the topology
skill replaces embedded topology code; Python handles result parsing only.
AMD license authorization and an approved idle-node
run budget are required. Original and tuned profiles require separate THP
approval and restore the original values afterward. The original source
recipe additionally requires explicit approval to drop host caches before each
trial; prebuilt and tuned profiles do not drop caches. The explicitly selected
`normalized-176` comparison profile leaves THP unchanged. No cloud uploads or
system compiler replacement are performed.

Results are workload-specific observations, not performance guarantees.
Use matching array sizes and launch settings for comparisons. See the
[diagnosis reference](.github/skills/hbv4-stream-performance/references/diagnosis.md)
for measured baselines, array sizing and interpretation.
