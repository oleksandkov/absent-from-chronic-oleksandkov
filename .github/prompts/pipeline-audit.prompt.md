---
description: >
  Phase 4 of the Pipeline Orchestra. Cross-checks all pipeline artifacts for consistency
  and drift. Reports discrepancies without modifying files unless instructed.
agent: Pipeline Engineer
---

# Pipeline Audit

Audit the pipeline for consistency across all pipeline artifacts. This is Phase 4 of the Pipeline
Orchestra.

## When to Use

- After any substantive Ellis change
- Before publishing or handing data to downstream analysis
- When documentation may be stale
- After collaborating changes land in the repo

## Process

### Step 1: Read All Pipeline Artifacts

Read completely:

1. `manipulation/README.md`
2. `manipulation/pipeline-project-spec.md`
3. `manipulation/pipeline-validation.dcf`
4. all numbered Ferry lanes in `manipulation/`
5. all numbered Ellis lanes in `manipulation/`
6. `data-public/metadata/INPUT-manifest.md`
7. `data-public/metadata/CACHE-manifest.md`
8. `manipulation/pipeline.md`

Also read any orchestrator or config file the project actually uses, such as `config.yml` or
`flow.R`.

### Step 2: Cross-Check Consistency

Verify alignment across these pairs:

- Ferry lanes ↔ `INPUT-manifest.md`
- Ellis lanes ↔ `CACHE-manifest.md`
- active lane sequence ↔ `manipulation/pipeline-project-spec.md`
- validator target ↔ `manipulation/pipeline-validation.dcf`
- script inventory ↔ `manipulation/pipeline.md`
- script configuration ↔ project config files

### Step 3: Check for Drift

- lane code newer than validation report
- manifest entries that no longer reflect the real target object
- `pipeline.md` still pointing at retired or draft lanes
- config or schema changes not reflected in manifests

### Step 4: Report Findings

Present a structured audit report with:

- passed checks
- discrepancies
- drift indicators
- prioritized remediation steps

### Step 5: Fix Only When Asked

Do not modify files during the audit unless the user explicitly asks for edits.
