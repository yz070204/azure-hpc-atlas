# Escalation bundle

Write `escalation.md` in the investigation folder (`~/hpc-atlas-output/<timestamp>/`) with this template. Include only evidence relevant to the symptom.

```markdown
## Summary
- Time (UTC):
- VM size / region:
- Image version / kernel:
- Symptom; first seen; repeatable; previously working:
- Classification / confidence:

## Expected vs observed
| Item | Expected | Observed | Command/source |
|---|---|---|---|

## Reproduction
Exact command, input, ranks/threads and binding, compiler/MPI versions, each repetition's result, whether the node was idle.

## Evidence
Full output of the key commands. What was ruled out.

## HPC diagnostics
Archive path, collector version and SHA-256, flags, exit status, failed or skipped sections.

## Actions taken
Each action, its result, and whether it changed state (reboot, redeploy, resize).

## Question for Azure support
One concrete question, e.g. "Why is the expected ConnectX-7 PCI function absent on this node when the same image and SKU expose it on another node?"
```

When handing over, tell the user to attach the investigation folder's contents, and that the diagnostics archive contains the full system journal, network addresses, and VM identifiers, so they should review it before attaching. Never include credentials, tokens, or customer data.
