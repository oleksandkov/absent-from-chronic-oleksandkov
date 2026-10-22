# Pipeline Orchestra

**Version**: 1.1
**Scope**: Single-agent specification for Ferry/Ellis pipeline development, validation, and audit workflows.

## Orchestra Sitemap

> **Note:** This sitemap is a convenience copy. The authoritative source is the whitelist map in `.github/migration.md`.

```text
.github/
├── pipeline-orchestra.md
├── agents/
│   └── pipeline-engineer.agent.md
├── copilot/
│   └── pipeline-orchestra-SKILL.md
├── hooks/
│   ├── ellis-validation-reminder.json
│   └── scripts/
│       └── check-ellis-validation.ps1
├── prompts/
│   ├── pipeline-audit.prompt.md
│   ├── pipeline-bootstrap.prompt.md
│   ├── pipeline-diagram.prompt.md
│   ├── pipeline-ellis.prompt.md
│   └── pipeline-validate.prompt.md
├── instructions/
│   └── pipeline-scripts.instructions.md
├── skills/
    └── validate-cache-manifest/
        ├── SKILL.md
        ├── references/
        │   ├── extract-table-metadata.sql
        │   └── report-template.md
        └── scripts/
            └── validate-cache-manifest.R
└── templates/
    └── pipeline-diagram-template.mmd
```

---

## Overview

The **Pipeline Orchestra** is a single-agent system that guides a project through the lifecycle
of pipeline development: raw input discovery, Ferry transport, Ellis transformation, validation,
and artifact audit.

The framework in `.github/` is intentionally project-agnostic. All project-specific rules,
inventories, source systems, table names, and validation bindings belong in `manipulation/`
and the manifests under `data-public/metadata/`.

## Boundary Rule

The boundary is strict:

- `.github/` contains transferable framework logic only.
- `manipulation/` contains project-specific pipeline rules, inventories, diagrams, and validator bindings.
- `data-public/metadata/` contains project-specific manifests such as `INPUT-manifest.md` and `CACHE-manifest.md`.

If a framework file in `.github/` needs a project-specific table name, schema, helper, or lane
sequence, that information must be discovered from `manipulation/`, not hardcoded.

## Stable Components

Every project using this orchestra must provide these minimum components:

| Artifact | Location | Requirement |
| --- | --- | --- |
| Numbered Ferry lane(s) | `manipulation/` | At least one |
| Numbered Ellis lane(s) | `manipulation/` | At least one |
| Pipeline guide | `manipulation/pipeline.md` | Required |
| Project spec | `manipulation/pipeline-project-spec.md` | Required |
| Validator binding | `manipulation/pipeline-validation.dcf` | Required for CACHE validation |
| Input manifest | `data-public/metadata/INPUT-manifest.md` | Required |
| Cache manifest | `data-public/metadata/CACHE-manifest.md` | Required |

Mixed-language Ellis implementations are supported. A project may use `.R`, `.sql`, or a sequence
that combines both.

## Adapter Layer

The adapter layer lives in `manipulation/` and answers the questions the generic framework
cannot assume:

- Which source systems and raw objects feed the project
- Which numbered Ferry and Ellis lanes are active
- Which outputs are provisional versus canonical
- Which output object should be treated as the CACHE-manifest validation target
- Which exclusions or provenance queries the validator should use

The generic framework reads this adapter layer before proposing edits or validations.

## Four Phases

### Phase 1: Discovery + Ferry

Purpose: move source data into project staging with minimal semantic change.

The agent should:

1. Read the project adapter files in `manipulation/`.
2. Discover existing numbered Ferry lanes.
3. Ask a short adaptive interview about source systems, connectivity, transport volume, and versioning.
4. Scaffold or refine the next Ferry lane.
5. Draft or refresh `INPUT-manifest.md` from actual source and ferry artifact inspection.

### Phase 2: Ellis Development

Purpose: transform staged data into clean, documented, analysis-ready outputs.

The agent should:

1. Read the declared lane sequence in `manipulation/pipeline-project-spec.md`.
2. Discover existing numbered Ellis lanes.
3. Ask about joins, derivations, exclusions, helper utilities, and validation expectations.
4. Scaffold or refine the appropriate Ellis lane.
5. Keep comments and checkpoints aligned with the local project spec.

### Phase 3: Validation + Documentation

Purpose: document real outputs and verify the CACHE manifest against actual artifacts.

The agent should:

1. Inspect the actual target table and/or file artifacts.
2. Generate or refresh `CACHE-manifest.md` from output reality, not code intention.
3. Run the validator bound by `manipulation/pipeline-validation.dcf`.
4. Record discrepancies and update `manipulation/pipeline.md` when the architecture changes.

### Phase 4: Quality Audit

Purpose: detect drift between lane code, manifests, validation config, and pipeline guide.

The agent should:

1. Read all active numbered Ferry and Ellis lanes.
2. Cross-check them against `INPUT-manifest.md`, `CACHE-manifest.md`,
   `manipulation/pipeline-project-spec.md`, `manipulation/pipeline-validation.dcf`, and
   `manipulation/pipeline.md`.
3. Report discrepancies with file locations and concrete remediation steps.
4. Avoid modifying files unless explicitly instructed.

## Ferry Pattern

Ferry lanes transport data with minimal semantic change.

Allowed examples:

- extraction from databases, APIs, or files
- source-side filtering needed to bound scope or volume
- technical fixes such as encoding normalization or column-name sanitation
- writing to staging tables or files

Not allowed in Ferry by default:

- analytical variable construction
- taxonomy application or semantic recoding
- outcome computation
- business-rule filtering that changes substantive meaning

## Ellis Pattern

Ellis lanes inspect, standardize, derive, validate, and document.

Expected capabilities:

- explicit input and output declarations
- factor or taxonomy recoding where needed
- derived variable creation
- quality assertions and diagnostics
- output to project-defined durable targets

The framework does not prescribe project-specific helpers or table names. Those belong in the
project adapter files.

## Prompt Entry Points

The generic framework exposes these prompt entry points:

- `pipeline-bootstrap.prompt.md`
- `pipeline-ellis.prompt.md`
- `pipeline-validate.prompt.md`
- `pipeline-audit.prompt.md`
- `pipeline-diagram.prompt.md`

Each prompt must discover project specifics from `manipulation/` before suggesting code or docs.

## Validation Contract

The CACHE validator is generic. It must read the project binding from
`manipulation/pipeline-validation.dcf`, which supplies:

- target DSN
- target object
- manifest path
- report path
- optional exclusion query
- optional provenance query

This keeps `.github/skills/validate-cache-manifest/` transferable across repositories.

## Acceptance Criteria

The framework is correctly separated when all of these are true:

1. `.github/` contains no project-specific schemas, tables, helper names, or lane filenames.
2. The project-specific lane sequence is fully described in `manipulation/`.
3. `manipulation/pipeline.md` contains the canonical architecture diagram.
4. `INPUT-manifest.md` and `CACHE-manifest.md` exist and reflect the current project contract.
5. `manipulation/pipeline-validation.dcf` is sufficient to run CACHE validation without editing `.github/`.

## Relationship to Other Orchestras

Pipeline Orchestra prepares analysis-ready data.

- Composing Orchestra consumes analysis-ready data to build reports in `analysis/`.
- Publishing Orchestra consumes curated analytical outputs to build websites in `_frontend-*`.

These systems are complementary and sequential, but they must remain decoupled.
