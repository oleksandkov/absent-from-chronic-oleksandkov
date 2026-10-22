---
name: evaluate-harness-equivalence
description: 'Evaluate byte-equivalence of the project-agnostic .github harness against a reference (upstream) repository. Use when: verifying a repo is in sync with the agnostic support system defined in migration.md, auditing after a migration, or identifying drift with remediation suggestions.'
argument-hint: 'Provide the reference repo path (root or its .github). Optionally an alternate map name or output file.'
user-invocable: true
---

# Harness Equivalence Evaluation

Produces a structured report comparing the **project-agnostic** portion of the local
`.github/` harness against a reference (upstream / source-of-truth) repository, file by
file, byte-for-byte. The set of files to compare is derived from the whitelist tree in
`.github/migration.md`, so the check always tracks the documented agnostic surface.

## When to Use

- After migrating the harness into or out of a repository
- To verify a repo is not behind the upstream agnostic support system
- To detect drift in any whitelisted file and get remediation suggestions
- As a periodic audit of the three-orchestra infrastructure

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| Reference repo `.github` | `-ReferenceRoot` argument | Yes |
| Local repo `.github` | Auto-detected from script location (or `-LocalRoot`) | Yes |
| Whitelist tree | `.github/migration.md` :: Master Agnostic File Map | Yes |

## Procedure

### Step 1 — Identify the Reference Repository

Determine the upstream / source-of-truth repository whose `.github` is the comparison
baseline. This is typically a sibling checkout (for example `../sda-ceis-impact-dev`).
Confirm the path with the human if it is not obvious.

### Step 2 — Run the Equivalence Script

Run [evaluate-harness-equivalence.ps1](./scripts/evaluate-harness-equivalence.ps1):

```powershell
pwsh -File .github/skills/evaluate-harness-equivalence/scripts/evaluate-harness-equivalence.ps1 `
  -ReferenceRoot ../sda-ceis-impact-dev -ShowDiff
```

The script parses the whitelist from `migration.md`, hashes each listed file in both
repos, and prints a report. Exit code `0` means fully equivalent; `1` means at least one
difference, missing file, or whitelist drift was found.

Useful switches:

- `-ShowDiff` — include up to 40 changed lines per differing file
- `-IncludeIdentical` — also list the identical files by name
- `-MapName "Pipeline Orchestra"` — scope the check to one orchestra's map
- `-OutFile report.txt` — also write the report to disk

### Step 3 — Interpret the Report

The report groups findings into actionable categories:

| Category | Meaning | Default action |
|----------|---------|----------------|
| **DIFFERING** | Whitelisted file exists in both but is not byte-identical | Review the diff; adopt the reference version unless the local change is an intentional, documented deviation |
| **MISSING LOCALLY** | Agnostic file present in reference, absent locally | Copy from reference to restore completeness |
| **MISSING IN REFERENCE** | Agnostic file present locally, absent in reference | Local is ahead; candidate to push upstream |
| **WHITELIST DRIFT** | Listed in `migration.md` but absent in both repos | Fix `migration.md` or create the file |

### Step 4 — Draw Human Attention and Propose Fixes

For each non-equivalent file, summarize the nature of the difference and recommend a
concrete action. Distinguish genuine lag (local is behind and should adopt the reference)
from principled divergence (the reference leaked repo-specific content into an agnostic
file, so the local version is more correct). Never silently overwrite a documented,
intentional deviation.

## Decision Points

- **No reference available?** The check requires a second `.github` to compare against. Ask
  the human for the upstream path or a cloned copy.
- **Whitelist changed?** If files were added to or removed from the harness, update the
  maps in `migration.md` first — the script reads them as the source of truth.
- **Only one orchestra changed?** Pass `-MapName` for the relevant per-orchestra map to
  narrow the comparison.

## Related Files

| File | Role |
|------|------|
| `.github/migration.md` | Whitelist source of truth (parsed by the script) |
| `.github/agent-architecture.md` | Describes the agnostic three-orchestra harness |
| `.github/prompts/evaluate-harness-equivalence.prompt.md` | Human/agent entry point |
