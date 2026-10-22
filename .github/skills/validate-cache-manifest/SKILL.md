---
name: validate-cache-manifest
description: 'Validate CACHE-manifest.md against the physical target declared in manipulation/pipeline-validation.dcf. Use when: verifying manifest accuracy after Ellis changes, auditing pipeline documentation, checking for undocumented or phantom columns, or running pipeline quality checks.'
argument-hint: 'Optional: specify an alternate validation config path or alternate target object before sourcing the script.'
user-invocable: false
---

# CACHE Manifest Validation

Produces a structured validation report comparing the documented columns in
`data-public/metadata/CACHE-manifest.md` against the physical target declared in
`manipulation/pipeline-validation.dcf`.

## When to Use

- After modifying a numbered Ellis lane
- After materializing a new canonical analysis-ready output
- During Phase 4 (Quality Audit) of the Pipeline Engineer workflow
- When documentation currency is uncertain

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| Validation binding | `manipulation/pipeline-validation.dcf` | Yes |
| Physical target schema | Database object declared in the binding | Yes |
| CACHE-manifest.md | `data-public/metadata/CACHE-manifest.md` | Yes |
| Optional excluded column query | `pipeline-validation.dcf` | No |
| Optional provenance query | `pipeline-validation.dcf` | No |

## Procedure

### Step 1 — Execute Validation Script

Run [validate-cache-manifest.R](./scripts/validate-cache-manifest.R) via terminal:

```r
source(".github/skills/validate-cache-manifest/scripts/validate-cache-manifest.R")
```

The script reads `manipulation/pipeline-validation.dcf`, connects to the declared DSN,
extracts the physical columns from the declared target object, parses the documented columns from
`CACHE-manifest.md`, and writes a report to the configured report path.

If the connection fails, use the placeholder SQL in
[extract-table-metadata.sql](./references/extract-table-metadata.sql) and substitute the project's
actual target object.

### Step 2 — Review Report Output

Read the generated report and summarize:

- validation status
- coverage percentage
- undocumented column count
- phantom column count
- any provenance notes returned by the configured query

**Status thresholds:**

- **PASS**: 0 undocumented, 0 phantom
- **NEEDS ATTENTION**: 1–10 discrepancies, all classifiable
- **FAIL**: >10 discrepancies or unclassifiable columns

### Step 3 — Propose Manifest Edits (if requested)

If the user asks for fixes:

1. Add undocumented columns to the correct section of `CACHE-manifest.md`.
2. Remove phantom columns that no longer exist physically.
3. Update dates or provenance notes in the manifest if the project uses them.

## Output Location

The report path is defined by `manipulation/pipeline-validation.dcf`.

## Decision Points

- Cannot connect to the DSN? Use manual query results or a local file artifact if the project supports that fallback.
- Need to validate a different target? Override the binding or point the script at a different config file.
- Large discrepancy count? Re-check that the binding still points at the intended canonical output.

## Related Files

| File | Role |
|------|------|
| `manipulation/pipeline-validation.dcf` | Project-specific validator binding |
| `data-public/metadata/CACHE-manifest.md` | Document under validation |
| `manipulation/pipeline-project-spec.md` | Declares canonical output intent |
| `manipulation/pipeline.md` | Pipeline architecture reference |
