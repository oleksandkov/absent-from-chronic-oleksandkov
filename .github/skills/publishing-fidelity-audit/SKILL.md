---
name: publishing-fidelity-audit
description: 'Run protocol fidelity checks for Publishing Orchestra frontends, summarize drift, and propose remediation. Use when: validating VERBATIM fidelity, verifying REDIRECT targets, checking ADAPTED transform compliance, and confirming COMPOSED grounding structure.'
argument-hint: 'Optional: target frontend workspace path (default: latest _frontend-N) and strictness mode.'
user-invocable: false
---

# Publishing Fidelity Audit

Runs deterministic protocol checks against a generated frontend workspace and produces a structured fidelity summary.

## Scope

This skill verifies and reports only. It does not author content and does not modify source files.

## When to Use

- After Writer assembly and render
- Before publishing `_site/`
- During regression checks after rule or agent changes
- When reviewing unexplained output drift

## Inputs

| Input | Source | Required |
| --- | --- | --- |
| Frontend workspace | `_frontend-N/` | Yes |
| Contract | `_frontend-N/publishing-contract.prompt.md` | Yes |
| Edited pages | `_frontend-N/content/` | Yes |
| Rendered site | `_frontend-N/_site/` | Yes |
| Transform log | `_frontend-N/TRANSFORM_LOG.md` | Required for ADAPTED |

## Procedure

### Step 1 — Run Audit Script

Execute:

```r
source("_frontend-N/scripts/audit-fidelity.R")
```

Expected output artifact:

- `_frontend-N/FIDELITY_REPORT.md`

### Step 2 — Validate Protocol Results

Confirm report includes, at minimum:

- VERBATIM: body equivalence result (frontmatter excluded)
- REDIRECT: target existence and copied target checks
- ADAPTED: transform whitelist and TRANSFORM_LOG coverage checks
- COMPOSED: brief-field completeness and source-grounding section presence

### Step 3 — Summarize Status

Classify overall state:

- PASS: no protocol failures
- WARN: no fails, one or more warnings
- FAIL: at least one protocol failure

If status is FAIL, list concrete remediation actions per failed page.

## Output

- `_frontend-N/FIDELITY_REPORT.md`
- Chat summary of pass/warn/fail status and required fixes

## Related Files

| File | Role |
| --- | --- |
| `.github/publishing-orchestra.md` | Publishing system design reference |
| `.github/agents/publishing-writer.agent.md` | Writer execution contract |
| `.github/instructions/publishing-rules.instructions.md` | Protocol rule definitions |
| `.github/templates/publishing-contract-template.md` | Contract schema and fidelity metadata |
