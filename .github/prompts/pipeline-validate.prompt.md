---
description: >
  Phase 3 of the Pipeline Orchestra. Generates CACHE-manifest from actual Ellis output,
  runs validator checks through the project binding, and updates the pipeline guide.
agent: Pipeline Engineer
---

# Pipeline Validate

Generate documentation and validation checks from stable Ellis output. This is Phase 3 of the
Pipeline Orchestra.

## When to Use

- Ellis produces stable output and needs documentation
- `CACHE-manifest.md` needs to be created or refreshed
- The validator reports discrepancies that need interpretation
- `manipulation/pipeline.md` needs to reflect current architecture

## Prerequisites

- The relevant Ellis lane has been run successfully
- `manipulation/pipeline-validation.dcf` exists and points at the canonical validation target
- The project has a `CACHE-manifest.md`, even if only scaffolded

## Process

### Step 1: Read Context

1. Read `.github/pipeline-orchestra.md`.
2. Read `manipulation/pipeline-project-spec.md`.
3. Read `manipulation/pipeline-validation.dcf`.
4. Read the Ellis lane that produced the validation target.
5. Read existing `data-public/metadata/CACHE-manifest.md`.
6. Read `manipulation/pipeline.md`.
7. Read `.github/skills/validate-cache-manifest/SKILL.md`.

### Step 2: Inspect Ellis Output

Inspect the actual target artifact declared in `manipulation/pipeline-validation.dcf`.

Do not rely solely on code inspection.

Check, as applicable:

- table schema
- file schema
- row counts
- key uniqueness
- parity between database and file outputs

### Step 3: Generate CACHE-Manifest

Create or update `data-public/metadata/CACHE-manifest.md` from the real output.

Organize it by analytical meaning rather than by code order whenever practical.

### Step 4: Run Manifest Validation

Use the `validate-cache-manifest` skill.

Interpret discrepancies as:

- undocumented columns to add
- phantom columns to remove
- type or provenance changes to explain

### Step 5: Scaffold Lightweight Test Assertions

If lightweight tests are missing, suggest a focused check for the current canonical output.

### Step 6: Update Pipeline Documentation

Update `manipulation/pipeline.md` when the validation target, lane sequence, or architecture has
changed.

### Step 7: Report to Human

Tell the human whether validation passed, what changed in the manifest, and what still needs to be
verified.
