---
description: >
  Evaluate whether the local project-agnostic .github harness is byte-equivalent to a
  reference (upstream) repository, using the whitelist defined in migration.md. Reports
  differences and proposes concrete remediation.
---

# Evaluate Harness Equivalence

Verify that the project-agnostic support system in `.github/` matches an upstream
reference repository, and surface any drift for human decision.

## When to Use

- After migrating the harness into or out of this repository
- To confirm this repo is not behind the upstream agnostic support system
- To audit the three-orchestra infrastructure for drift

## Prerequisites

- A reference repository checkout is available locally (its `.github` is the baseline)
- `.github/migration.md` contains the Master Agnostic File Map
- `pwsh` and (ideally) `git` are available

## Process

### Step 1: Establish the Reference

Ask the human for the reference repository path if it is not already known (for example
`../sda-ceis-impact-dev`). The reference is the source of truth for agnostic files.

### Step 2: Run the Skill

Read `.github/skills/evaluate-harness-equivalence/SKILL.md` and run its script:

```powershell
pwsh -File .github/skills/evaluate-harness-equivalence/scripts/evaluate-harness-equivalence.ps1 `
  -ReferenceRoot <reference-repo-path> -ShowDiff
```

### Step 3: Report and Recommend

Summarize the report grouped by category (DIFFERING, MISSING LOCALLY, MISSING IN
REFERENCE, WHITELIST DRIFT). For each finding:

- State whether the local repo is behind, ahead, or intentionally divergent.
- Recommend a concrete action (adopt reference version, copy missing file, push upstream,
  or fix `migration.md`).
- Flag any difference that stems from repo-specific content leaking into an agnostic file,
  where the local version may be the more correct one.

### Step 4: Reconcile (if requested)

Only on explicit approval, apply the recommended changes. Preserve any documented,
intentional deviations. After reconciling, re-run the script to confirm equivalence
(exit code 0).

## Notes

- The script derives its file list from `migration.md`; if the harness surface changed,
  update the maps there first.
- Use `-MapName` to scope the check to a single orchestra's map.
