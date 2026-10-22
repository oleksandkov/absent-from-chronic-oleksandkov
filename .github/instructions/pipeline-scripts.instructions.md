---
description: >
  Structural and semantic rules for pipeline scripts in the manipulation/ directory.
  Covers Ferry Pattern constraints, Ellis Pattern requirements, validation binding,
  and the relationship between scripts and companion documents.
applyTo: "manipulation/**"
---

# Pipeline Script Rules

These rules supplement `r-scripts.instructions.md` with pipeline-specific conventions.

## Boundary Rule

Files under `manipulation/` are project-specific. They may define local source systems, schemas,
helper utilities, lane sequences, and validation bindings.

Framework files under `.github/` must not hardcode those project details.

## Script Naming

Pipeline scripts use the general pattern `{order}-{lane}-{topic}.{ext}`.

- **Order**: execution sequence number
- **Lane**: `ferry` or `ellis`
- **Topic**: project-defined purpose or entity
- **Extension**: `.R` or `.sql`

Examples:

- `0-ferry-to-cache.R`
- `1-ellis-event.R`
- `2-ellis-interval.sql`

Each project must provide at least one numbered Ferry lane and at least one numbered Ellis lane.

## Ferry Pattern Constraints

Ferry lanes transport source data into project staging with minimal semantic change.

Allowed by default:

- source extraction via SQL, API, or file reads
- technical filtering required for scope or volume control
- column selection
- technical normalization such as encoding fixes or safe column-name cleaning
- writing durable staging artifacts

Forbidden by default:

- taxonomy application
- analytical variable derivation
- outcome construction
- semantic recoding that changes meaning
- business-rule filtering that belongs in Ellis

If a Ferry lane intentionally performs a more opinionated operation, document the exception in
`manipulation/pipeline-project-spec.md`.

## Ellis Pattern Requirements

Ellis lanes are responsible for transformation into analysis-ready outputs.

Every Ellis lane should make these elements clear:

- declared inputs
- declared outputs
- transformation logic
- validation checkpoints
- how it fits the numbered lane sequence

Expected Ellis work may include:

- joins across staged datasets
- taxonomy or factor recoding
- derived variables
- missing-value handling
- materialization to project-defined targets
- diagnostic summaries or assertions

Project-specific helpers are allowed, but they must be documented locally in `manipulation/`.

## Companion Documents

Pipeline scripts have companion markdown documents that must stay synchronized:

- `data-public/metadata/INPUT-manifest.md` — what enters the pipeline
- `data-public/metadata/CACHE-manifest.md` — what the canonical analysis-ready output contains
- `manipulation/pipeline-project-spec.md` — project-specific lane and artifact contract
- `manipulation/pipeline-validation.dcf` — CACHE validation binding
- `manipulation/pipeline.md` — execution guide and architecture diagram

When modifying a lane script, consider whether one or more companion documents also needs updating.

## Validation Binding

The CACHE validation workflow must bind through `manipulation/pipeline-validation.dcf`.

That file should provide, at minimum:

- `dsn`
- `database_label`
- `target_object`
- `target_label`
- `manifest_path`
- `report_path`

Optional fields may provide an exclusion query or provenance query.

## Mixed-Language Pipelines

Mixed-language pipelines are supported.

- Use `.R` for orchestration, file-based wrangling, or package-based transformations.
- Use `.sql` for set-based transformations or database-native materialization.
- Keep the numbered sequence explicit when switching languages.

## Registration in flow.R

If the project uses `flow.R` or another orchestrator, keep the registered paths synchronized with
the actual numbered lane files.

The framework does not require every pipeline to use `flow.R`, but if the project does, the
registration should mirror the active lane sequence.

## Diagnostic Output

Diagnostic outputs may be written to prints folders or derived directories when useful.

Keep the pattern consistent within the project and document it in `manipulation/pipeline.md`.
