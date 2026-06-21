# Absent from Chronic — Research Documentation

## Purpose

A research documentation site for the study *"Predictors of Work Absenteeism Associated with
Chronic Conditions Among Canadian Workers"*, built for Marc-Andre Blanchette — the study's lead
research scientist and principal investigator.

The site provides a structured, navigable record of statistical analysis requirements, data
pipeline documentation, variable selection rationale, and exploratory descriptive findings
organized by the Andersen Behavioral Model domains. Its organizing principle is evidence: every
section corresponds to a layer of work that responds to requirements in `stats_instructions_v3.md`.

The audience is a single expert reader (the PI) who wants to verify coverage — not a general
public site. Tone is professional and direct. Content is shown essentially as the analyst produced
it.

---

## Navigation

### index (Home Page)

- **Protocol**: Narrative Bridge
- **Intent**: Orient Marc-Andre with a clear statement of what this site contains and where to
  find evidence of each addressed requirement. Establish that the pipeline is built, the data is
  clean, and the five Andersen Model domains are profiled.
- **Goal**: Home page — the first thing a visitor sees.
- **Spirit**: Professional and direct. Lead with the study title and purpose, anchored by the LOP
  days distribution chart (`g01_lop_days_histogram.png`). Show the pipeline architecture image
  (`pipeline-architecture.jpg`) to convey infrastructure maturity. Include a brief navigation
  guide pointing visitors to each section. No marketing language.
- **Image 1**: `images/g01_lop_days_histogram.png` — copied from
  `analysis/eda-5/prints/g01_lop_days_histogram.png` by the pre-render hook.
- **Image 2**: `images/pipeline-architecture.jpg` — copied from
  `libs/images/pipeline-architecture.jpg` by the pre-render hook.
- **Inputs**: `README.md` (project overview), `data-public/metadata/CACHE-manifest.md`
  (dataset summary: 63,843 rows, 69 columns, two CCHS cycles pooled),
  `ai/project/mission.md` (study purpose).

---

### Project

#### Statistical Instructions

- **Protocol**: Technical Bridge
- **Source**: `./data-private/raw/2026-02-19/stats_instructions_v3.md`
- **Transforms**:
  - Present the document as-is. Strip any preamble referencing internal AI agent instructions or
    repository workflow notes that are not part of the scientific content.
  - Retain all numbered sections (§1–§6), all tables, all R code blocks (these are methodology
    context relevant to the PI).
  - Do not reference `data-private/` paths in the rendered page — present as if the document is
    standalone.

---

### Pipeline

#### Pipeline Guide

- **Protocol**: Technical Bridge
- **Source**: `./manipulation/pipeline.md`
- **Transforms**:
  - Retain the pipeline flow diagram and scripts table as-is.
  - Inject mermaid shortcode where fenced mermaid blocks exist.
  - Strip R console code blocks and PowerShell commands (not relevant to PI audience).
  - Remove references to `data-private/` paths.
  - Rewrite any local file links to plain text (no paths point outside the site).

#### CACHE Manifest

- **Protocol**: Direct Line (VERBATIM)
- **Source**: `./data-public/metadata/CACHE-manifest.md`

#### INPUT Manifest

- **Protocol**: Direct Line (VERBATIM)
- **Source**: `./data-public/metadata/INPUT-manifest.md`

---

### Data Primer

#### Variable Inclusion

- **Protocol**: Direct Line (VERBATIM)
- **Source**: `./analysis/data-primer-1/variable-inclusion.qmd`
- **Note**: QMD is transferred to `edited_content/data-primer/variable-inclusion.qmd` and
  rendered as part of the Quarto site build. Strip `embed-resources: true` and `theme:` from
  YAML (inherited from site `_quarto.yml`).

#### Univariate Distributions

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/data-primer-1/univariate-distributions.html`

---

### Analysis

#### Outcome

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-5/eda-5.html`
- **Label**: Outcome (LOP Day Decomposition)

#### Exposure

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-61/eda-61.html`
- **Label**: Exposure (Chronic Conditions)

#### Predisposing

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-62/eda-62.html`
- **Label**: Predisposing (Socio-demographic)

#### Facilitating

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-63/eda-63.html`
- **Label**: Facilitating (Health System & Behaviours)

#### Needs

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-64/eda-64.html`
- **Label**: Needs (Perceived Health & Limitations)

---

### Site Map

- **Protocol**: Narrative Bridge
- **Intent**: Help Marc-Andre navigate the site and understand what each section contains and how
  it maps to the statistical analysis requirements.
- **Goal**: Site map — an oriented index of all pages with stats instructions coverage.
- **Spirit**: Concise and functional. Open with the **Navigation Structure** — an ASCII tree
  annotating every page with its content type (VERBATIM, REDIRECTED, TECHNICAL BRIDGE,
  NARRATIVE BRIDGE) and source provenance. Follow with a **Stats Instructions Coverage** section
  mapping each page to the requirement it addresses (e.g., Data Primer → §2.2 variable
  selection; Outcome → §4.1–§4.2 outcome construction; Exposure/Predisposing/Facilitating/Needs
  → §2.2 predictor domains and §4.3 bivariate associations).
- **Inputs**: Contract navigation structure (this file),
  `data-private/raw/2026-02-19/stats_instructions_v3.md` (section headings for mapping).

---

## Exclusions

- `*.R` — source scripts, not publishable
- `*_cache/` — Quarto render cache
- `data-private/` — private data, never publish (except `stats_instructions_v3.md` via Technical Bridge)
- `analysis/eda-1/` — mtcars scaffold, always excluded
- `README.md` inside subfolders (only root README used as input to landing page)
- `.github/` — internal workflow files
- `ai/memory/`, `ai/scripts/`, `ai/templates/` — internal AI support files
- `renv/`, `scripts/`, `utility/` — developer infrastructure
- `analysis/frontend-1/` — intent folder, not content

---

## Theme

flatly

---

## Footer

*Absent from Chronic* — Statistical Analysis Replication | Marc-Andre Blanchette, Research Scientist

---

## Repo URL

https://github.com/RG-FIDES/absent-from-chronic
