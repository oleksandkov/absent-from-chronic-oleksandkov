# Pipeline Process Guide

How to develop, maintain, and quality-check the data pipeline using the Pipeline Orchestra.

---

## Overview

The data pipeline transforms raw CCHS PUMF `.sav` files into analysis-ready Parquet and
SQLite assets. Seven tightly coupled artifacts must stay in sync:

| # | Artifact | Location | Role |
|---|----------|----------|------|
| 0 | `0-extract-metadata.R` | `manipulation/` | Harvest variable/value labels from SPSS files |
| 1 | `1-ferry.R` | `manipulation/` | Transport raw data into SQLite staging (zero transformation) |
| 2 | `2-ellis.R` | `manipulation/` | White-list, recode, validate, produce analysis-ready output |
| 3 | `3-test-ellis-cache.R` | `manipulation/` | Three-way alignment test (code, disk, manifest) |
| — | `INPUT-manifest.md` | `data-public/metadata/` | Documents raw inputs before any transformation |
| — | `CACHE-manifest.md` | `data-public/metadata/` | Documents Ellis output (variable inventory, diagnostics) |
| — | `pipeline.md` | `manipulation/` | Execution guide, architecture diagram, troubleshooting |

The **Pipeline Orchestra** (`@pipeline-engineer`) is a single-agent system that guides creation
and maintenance of these artifacts through four phases.

---

## Architecture

```text
┌──────────────────────────────────────────────────────────┐
│  Pipeline Orchestra                                      │
│                                                          │
│  Agent: @pipeline-engineer                               │
│                                                          │
│  Phase 1 ─ Discovery + Ferry   (pipeline-bootstrap)      │
│  Phase 2 ─ Ellis Development   (pipeline-ellis)          │
│  Phase 3 ─ Validation + Docs   (pipeline-validate)       │
│  Phase 4 ─ Quality Audit       (pipeline-audit)          │
└──────────────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
  ┌─────────────┐    ┌──────────────────┐
  │ manipulation │    │ data-public/     │
  │  0-extract   │    │  metadata/       │
  │  1-ferry     │    │  INPUT-manifest  │
  │  2-ellis     │    │  CACHE-manifest  │
  │  3-test      │    └──────────────────┘
  │  pipeline.md │
  └─────────────┘
```

### Relationship to Other Orchestras

| Concern | Pipeline Orchestra | Composing Orchestra | Publishing Orchestra |
|---------|--------------------|---------------------|----------------------|
| **Creates** | Pipeline scripts + manifests | Analytical reports in `analysis/` | Curated website in `_frontend-N/` |
| **Agent** | `@pipeline-engineer` | `@report-composer` | `@publishing-interviewer` + `@publishing-writer` |
| **Trigger** | Raw data arrives or Ellis changes | Post-Ellis, human requests EDA/Report | Human requests website |
| **Entry point** | Phased prompts in `.github/prompts/` | `composing-new.prompt.md` | `publishing-new.prompt.md` |

The three systems are **complementary and sequential**: Pipeline creates data that Composing
analyses and Publishing curates for the web. They share no runtime artifacts.

---

## The Four Phases

### Phase 1 — Discovery + Ferry

**When**: Raw data files arrive for the first time (or new sources are added).

**Entry point**: Invoke `@pipeline-engineer` or use `.github/prompts/pipeline-bootstrap.prompt.md`.

**What the agent does**:

1. Interviews the human (3–5 questions):
   - What raw files do you have? (paths, formats, received dates)
   - What is the research question or requirements document?
   - Multiple data sources to pool? Cross-cycle harmonization needed?
   - Any known variable naming issues across sources?
2. Scaffolds or updates `0-extract-metadata.R` — metadata extraction from raw files
3. Scaffolds or updates `1-ferry.R` — zero-transformation import into staging SQLite
4. Drafts `INPUT-manifest.md` from extraction results

**Human actions**:

1. Place raw files in `data-private/raw/{date}/`
2. Update `config.yml` with file paths
3. Run `0-extract-metadata.R` → inspect codebook CSVs
4. Run `1-ferry.R` → inspect staging database

**Outputs**: `0-extract-metadata.R`, `1-ferry.R`, draft `INPUT-manifest.md`

### Phase 2 — Ellis Development

**When**: Ferry output exists and you are ready to build the transformation logic.

**Entry point**: Invoke `@pipeline-engineer` or use `.github/prompts/pipeline-ellis.prompt.md`.

**What the agent does**:

1. Interviews the human:
   - What variables does the research require? (point to requirements doc)
   - What outcome variable(s) need construction?
   - What exclusion criteria define the analytical sample?
   - What factor recoding is needed?
2. Scaffolds `2-ellis.R` with:
   - Two-tier white-list (CONFIRMED + INFERRED)
   - Factor recode blocks
   - Outcome construction logic
   - Sample exclusion pipeline with `sample_flow` audit table
   - Survey weight handling
3. Human runs Ellis, inspects output
4. **Iterate**: human reports issues → agent refines → re-run → repeat

**Outputs**: `2-ellis.R` (iteratively refined)

### Phase 3 — Validation + Documentation

**When**: Ellis produces stable output and you need documentation and tests.

**Entry point**: Invoke `@pipeline-engineer` or use `.github/prompts/pipeline-validate.prompt.md`.

**What the agent does**:

1. Reads actual Ellis output (Parquet schema, row counts, factor levels)
2. Generates `CACHE-manifest.md` from output reality (not code inspection alone)
3. Scaffolds `3-test-ellis-cache.R` with assertions aligned to the manifest
4. Runs the test script to verify three-way alignment
5. Updates `pipeline.md` with execution guide and diagnostic checkpoints

**Outputs**: `CACHE-manifest.md`, `3-test-ellis-cache.R`, updated `pipeline.md`

### Phase 4 — Quality Audit

**When**: Periodically, or after any Ellis modification.

**Entry point**: Invoke `@pipeline-engineer` or use `.github/prompts/pipeline-audit.prompt.md`.

**What the agent does**:

1. Verifies consistency: Ellis code ↔ CACHE-manifest ↔ test script ↔ `pipeline.md`
2. Checks for drift: Has Ellis been modified since the last manifest update?
3. Validates INPUT-manifest still matches raw data
4. Reports discrepancies and suggests specific fixes

**Outputs**: Audit report with discrepancies and recommended actions

---

## Jump-Starting a New Pipeline

Step-by-step for a human starting from only raw `.sav` files:

1. **Setup**: Place raw files in `data-private/raw/{date}/`, update `config.yml` paths
2. **Activate persona**: Run the "Activate Data Engineer Persona" VS Code task
3. **Phase 1**: Invoke `@pipeline-engineer` and answer interview questions about data sources
4. **Run discovery**: Execute `0-extract-metadata.R` (VS Code task or `Rscript`)
5. **Run ferry**: Execute `1-ferry.R`, inspect staging database
6. **Phase 2**: Continue with `@pipeline-engineer` for Ellis development (iterative)
7. **Phase 3**: Once Ellis is stable, request validation and documentation
8. **Phase 4**: Run periodic audit to catch drift

---

## Subsequent Development and Tweaking

### Ellis Logic Changes

When the research requirements change or you discover data issues:

1. Modify `2-ellis.R` directly or re-engage `@pipeline-engineer` Phase 2
2. Re-run Ellis: `Rscript manipulation/2-ellis.R`
3. Re-run Phase 3 to regenerate `CACHE-manifest.md` and update `3-test-ellis-cache.R`
4. Run Phase 4 audit to confirm all 7 artifacts are in sync

### New Data Source Added

1. Re-engage Phase 1 to update `1-ferry.R` and `INPUT-manifest.md`
2. Flow through Phases 2–4 as above

### Periodic Quality Check

Run Phase 4 audit at any time. The agent reads all 7 artifacts and reports inconsistencies
without modifying anything (unless instructed to fix).

---

## Key Principles

- **Agent advises and scaffolds; human executes scripts** — The agent never auto-runs data
  scripts. The human runs each script, inspects results, and reports back.
- **CACHE-manifest from output, not code** — The manifest is generated by reading actual
  Parquet/SQLite artifacts, avoiding code-reality drift.
- **Sequential numbering** — Scripts numbered 0–3 for execution order clarity.
- **Ferry = zero transformation** — Only `haven::read_sav()`, `zap_labels()`, `clean_names()`.
  No column selection, no recoding, no filtering.
- **Ellis = thorough validation** — Every variable recoded, documented, and tested.
  Two-tier white-list (CONFIRMED = hard error; INFERRED = graceful warning).
- **Test = three-way alignment** — Validates code ↔ disk artifacts ↔ CACHE-manifest.

---

## Automation Constructs

| Construct | Location | Purpose |
|-----------|----------|---------|
| Agent | `.github/agents/pipeline-engineer.agent.md` | Guides pipeline lifecycle |
| Prompt | `.github/prompts/pipeline-bootstrap.prompt.md` | Phase 1 entry |
| Prompt | `.github/prompts/pipeline-ellis.prompt.md` | Phase 2 entry |
| Prompt | `.github/prompts/pipeline-validate.prompt.md` | Phase 3 entry |
| Prompt | `.github/prompts/pipeline-audit.prompt.md` | Phase 4 entry |
| Instruction | `.github/instructions/pipeline-scripts.instructions.md` | Conventions for `manipulation/**` |
| Design doc | `.github/pipeline-orchestra.md` | System architecture reference |

---

## Execution Options

**Option A — Full pipeline** (all scripts in sequence):

```r
source("flow.R")
```

**Option B — Step-by-step** (recommended for development):

```r
source("manipulation/0-extract-metadata.R")   # ~1 min
source("manipulation/1-ferry.R")              # ~2–5 min
source("manipulation/2-ellis.R")              # ~1–2 min
source("manipulation/3-test-ellis-cache.R")   # <30 sec
```

**Option C — VS Code tasks**:

- "Run Extract Metadata (Lane 0)"
- "Run Ferry Lane 1"
- "Run Ellis Lane 2"
- "Run Test Ellis Cache (Lane 3)"
- "Run Pipeline (flow.R)"
