# Absent from Chronic

## Purpose

A research documentation site for the study *"Predictors of Work Absenteeism Associated with
Chronic Conditions Among Canadian Workers"* - a descriptive epidemiology study of the Loss of Productivity (LOP) module in thekl Canadian Community Health Survey (CCHS) 2010–2011 and 2013–2014 cycles.

The site provides a structured, navigable record of statistical analysis requirements, data
pipeline documentation, variable selection rationale, and exploratory descriptive findings
organized by the Andersen Behavioral Model domains. Its organizing principle is evidence: every
section corresponds to a layer of work that responds to requirements in the Project Proposal
(`stats_instructions_v3.md`).

The audience is a single expert reader (the PI) who wants to verify coverage — not a general
public site. Tone is professional and direct. Content is shown essentially as the analyst produced
it.

---

## Navigation

### index (Home Page)

- **Protocol**: Narrative Bridge
- **Intent**: Orient the reader with a clear statement of what this site contains and where to
  find evidence of each addressed requirement. Establish that the pipeline is built, the data is
  clean, and the five Andersen Model domains are profiled.
- **Goal**: Home page — the first thing a visitor sees.
- **Spirit**: Professional and direct. Lead with the study title and purpose, anchored by the LOP
  days distribution chart (`g01_lop_days_histogram.png`) under an **Outcome in Focus** heading.
  Include a study identification block near the top with the full study name and author line:
  Marc-Andre Blanchette, Oleksandr Koval, Andriy Koval.
  Immediately below G01, place `g23_chronic_vs_other_only_raw_split_distribution.png` to show
  distribution shape context. Show
  the pipeline architecture image (`pipeline-architecture.jpg`) to convey infrastructure maturity.
  Include a brief navigation
  guide pointing visitors to each section. No marketing language.
- **Image 1**: `analysis/eda-71/prints/g23_chronic_vs_other_only_raw_split_distribution.png` — place immediately below G01 in
  the **Outcome in Focus** section.
- **Image 2**: `images/pipeline-architecture.jpg` — copied from
  `libs/images/pipeline-architecture.jpg` by the pre-render hook.
- **Inputs**: `README.md` (project overview), `data-public/metadata/CACHE-manifest.md`
  (dataset summary: 63,843 rows, 69 columns, two CCHS cycles pooled),
  `ai/project/mission.md` (study purpose).

---

### Project

#### Project Proposal

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
- **Note**: QMD is transferred to `content/data-primer/variable-inclusion.qmd` and
  rendered as part of the Quarto site build. Strip `embed-resources: true` and `theme:` from
  YAML (inherited from site `_quarto.yml`).

#### Univariate Distributions

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/data-primer-1/univariate-distributions.html`
- **Label**: Univariate Distributions (data-primer-1)

---

### Outcome

#### LOP Day Decomposition

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-5/eda-5.html`
- **Label**: Outcome: LOP Day Decomposition (eda-5)

#### Distribution Shapes

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-71/eda-71.html`
- **Label**: Outcome: Distribution Shapes (eda-71)

#### Rescaling

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-72/eda-72.html`
- **Label**: Outcome: Rescaling (eda-72)

---

### Predictors

#### Exposure

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-61/eda-61.html`
- **Label**: Exposure: Chronic Conditions (eda-61)

#### Predisposing

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-62/eda-62.html`
- **Label**: Predisposing: Socio-demographic (eda-62)

#### Facilitating

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-63/eda-63.html`
- **Label**: Facilitating: Health System & Behaviours (eda-63)

#### Needs

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-64/eda-64.html`
- **Label**: Needs: Perceived Health & Limitations (eda-64)

#### Missingness

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-65/eda-65.html`
- **Label**: Missingness (eda-65)

---

### Model

#### Bivariate Models

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/model-00/model-00.html`
- **Label**: Bivariate Models (model-00)
- **Page**: `content/model/bivariate-models.qmd`

#### Lasso Rehearsal with Predisposing

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/model-0/model-0.html`
- **Label**: Lasso Rehearsal with Predisposing (model-0)
- **Page**: `content/model/lasso-rehearsal.qmd`

#### Variable Selection with Lasso

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/model-1/model-1.html`
- **Label**: Variable Selection with Lasso (model-1)
- **Page**: `content/model/variable-selection.qmd`

**Section notes**:

- The `Model` dropdown sits between `Predictors` and `Site Map` in the navbar.
- Entry order is `model-00`, `model-0`, `model-1` — rehearsal-to-commitment order, not numeric order.
- The post-render hook `scripts/copy-analysis-html.R` must copy all three HTML targets into
  `_site/content/model/` as `model-00.html`, `model-0.html`, and `model-1.html`.

---

### Site Map

- **Protocol**: Narrative Bridge
- **Intent**: Help Marc-Andre navigate the site and understand what each section contains and how
  it maps to the statistical analysis requirements.
- **Goal**: Site map — an oriented index of all pages with explicit Project Proposal linkage.
- **Spirit**: Concise and functional. Structure the page in this exact order:
  **Navigation Structure**, **Content Type**, **Proposal Coverage**. In **Navigation Structure**,
  use an ASCII tree in a plain-text code block with branch-drawing characters (`├──`, `└──`, `│`)
  and consistent indentation. In **Content Type**, use a three-column table with this exact schema:
  **Output Type**, **Produced by Protocol**, **Meaning and Notes**. The table must use output types
  (VERBATIM, REDIRECT, ADAPTED, COMPOSED), not protocol names as the primary type labels.
  In **Proposal Coverage**, make the **Page** column values URL links to the corresponding site page,
  then map each linked page to relevant Project Proposal section(s). In the **Coverage status** column,
  write a brief descriptive statement of what the page addresses relative to the proposal requirements.
  Avoid generic labels such as "Documented" or "EDA complete" when a specific proposal-linked
  description is available. Include the `Outcome` navbar section and its `Rescaling` page in
  both the navigation tree and proposal coverage table. Include the `Model` navbar section and
  all three of its pages (`model-00`, `model-0`, `model-1`) in both the navigation tree and the
  proposal coverage table; map them to §5.3 (bivariate analysis) and §5.4 (variable selection).
  Every REDIRECT page label must carry the
  report ID of its target (e.g. `eda-5`, `eda-71`, `model-00`) so readers can trace a page back to
  the corresponding script folder in the reproducible project.
- **Regeneration mode**: CONTINUE FROM EXISTING DRAFT. `content/site-map.qmd` already exists and
  is approved. Do not rewrite it from scratch. Apply only additive edits: insert the `Model`
  branch into the ASCII navigation tree (after `Predictors`, before `Site Map`) and append three
  rows to the **Proposal Coverage** table. Leave the **Content Type** table, all existing tree
  branches, and all existing coverage rows byte-identical.
- **Inputs**: Contract navigation structure (this file),
  `_frontend-1/content/site-map.qmd` (existing approved draft — base for additive edits),
  `analysis/eda-72/eda-72.html` (outcome rescaling analysis),
  `analysis/model-00/model-00.html` (bivariate series),
  `analysis/model-0/model-0.html` (lasso rehearsal on predisposing),
  `analysis/model-1/model-1.html` (variable selection across the full candidate set),
  `data-private/raw/2026-02-19/stats_instructions_v3.md` (section headings for mapping).

---

## Exclusions

- `*.R` — source scripts, not publishable
- `*_cache/` — Quarto render cache (including `analysis/model-0/model-0_cache/`)
- `analysis/*/data-local/` — intermediate model artefacts, not publishable
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

*Absent from Chronic* | Marc-Andre Blanchette, Oleksandr Koval, Andriy Koval | 2026

---

## Repo URL

https://github.com/RG-FIDES/absent-from-chronic
