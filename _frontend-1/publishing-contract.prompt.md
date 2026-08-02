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
- **Goal**: Home page — the first thing a visitor sees. Present in `content/` but **absent from
  the navbar**; the navbar brand title links here.
- **Spirit**: Professional and direct. Lead with the study title and purpose. Immediately below
  the author line — and above **Outcome in Focus** — place a short **Start with the Proposal**
  section that links to the Project Proposal page (`docs/project-proposal.html`) and states in one
  or two sentences that it is the authoritative statement of what the analysis must deliver and
  the reference against which every other page should be read. Then anchor the page with the LOP
  days distribution chart (`g01_lop_days_histogram.png`) under an **Outcome in Focus** heading.
  Include a study identification block near the top with the full study name and author line:
  Marc-Andre Blanchette, Oleksandr Koval, Andriy Koval.
  Immediately below G01, place `g23_chronic_vs_other_only_raw_split_distribution.png` to show
  distribution shape context. Show
  the pipeline architecture image (`pipeline-architecture.jpg`) to convey infrastructure maturity.
  Include a brief navigation
  guide pointing visitors to each section. The navigation guide must describe the sections that
  actually exist in the navbar, in navbar order: **Data Primer**, **Predictors**, **Outcome**,
  **Model**, **Analysis**, **Pipeline**, **Docs**. It must not refer to a `Project` section.
  No marketing language.
- **Image 1**: `analysis/eda-71/prints/g23_chronic_vs_other_only_raw_split_distribution.png` — place immediately below G01 in
  the **Outcome in Focus** section.
- **Image 2**: `images/pipeline-architecture.jpg` — copied from
  `libs/images/pipeline-architecture.jpg` by the pre-render hook.
- **Inputs**: `README.md` (project overview), `data-public/metadata/CACHE-manifest.md`
  (dataset summary: 63,843 rows, 70 columns, two CCHS cycles pooled),
  `ai/project/mission.md` (study purpose).

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

- The `Model` dropdown sits between `Outcome` and `Analysis` in the navbar.
- Entry order is `model-00`, `model-0`, `model-1` — rehearsal-to-commitment order, not numeric order.
- The post-render hook `scripts/copy-analysis-html.R` must copy all three HTML targets into
  `_site/content/model/` as `model-00.html`, `model-0.html`, and `model-1.html`.

---

### Analysis

#### Story 1

- **Protocol**: Direct Line (REDIRECTED)
- **Source**: `./analysis/eda-81/eda-81.html`
- **Label**: Story 1
- **Page**: `content/analysis/story-1.qmd`

**Section notes**:

- The `Analysis` dropdown sits between `Model` and `Pipeline` in the navbar. It carries the
  interpretation layer: reports that read prior reports rather than the data directly.
- EDA-81 explains what the LASSO penalty is doing (`lambda.min` vs. `lambda.1se`) and aligns
  the `model-00` unadjusted estimates, the `model-1` selection verdicts, and the adjusted
  estimates on one shared row axis.
- Unlike the `Predictors`, `Outcome`, and `Model` sections, the label carries no report ID in
  parentheses. `Story 1` is a reader-facing sequence label, and the section is expected to grow
  with `Story 2`, `Story 3`, and so on.
- The post-render hook `scripts/copy-analysis-html.R` must copy the HTML target into
  `_site/content/analysis/` as `eda-81.html`.

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

### Docs

`Docs` is the final navbar section. It holds the two pages that describe the site and the
requirements it answers, in this order: `Site Map`, then `Project Proposal`.

#### Site Map

- **Protocol**: Narrative Bridge
- **Page**: `content/site-map.qmd` (unchanged location — the page moves only in the navbar, not
  on disk, so its existing relative links stay valid)
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
  description is available. The navigation tree must follow navbar order exactly —
  `Data Primer`, `Predictors`, `Outcome`, `Model`, `Analysis`, `Pipeline`, `Docs` — with `Index`
  shown above them as the home page. Every REDIRECT page label must carry the
  report ID of its target (e.g. `eda-5`, `eda-71`, `model-00`, `eda-81`) so readers can trace a
  page back to the corresponding script folder in the reproducible project. `Story 1` is the one
  exception in the navbar itself, but the tree must still annotate it with `eda-81`.
- **Regeneration mode**: CONTINUE FROM EXISTING DRAFT. `content/site-map.qmd` already exists and
  is approved. Do not rewrite it from scratch. Apply only these edits:
  1. Reorder the ASCII tree branches to navbar order and add an `Analysis` branch (one entry:
     `Story 1` → `analysis/eda-81/eda-81.html`) and a `Docs` branch (`Site Map`, then
     `Project Proposal`). Remove the standalone `Project` and `Site Map` top-level branches.
  2. Retarget the Project Proposal link in the **Proposal Coverage** table from
     `project/project-proposal.html` to `docs/project-proposal.html`.
  3. Append one **Proposal Coverage** row for `Story 1` (`analysis/story-1.html`), mapped to
     §5.3 and §5.4, describing it as the interpretation layer that explains the penalty and
     aligns unadjusted, selected, and adjusted evidence on one axis.
  Leave the **Content Type** table and all existing coverage row text byte-identical.
- **Inputs**: Contract navigation structure (this file),
  `_frontend-1/content/site-map.qmd` (existing approved draft — base for additive edits),
  `analysis/eda-81/eda-81.html` (interpretation layer over `model-00` and `model-1`),
  `data-private/raw/2026-02-19/stats_instructions_v3.md` (section headings for mapping).

#### Project Proposal

- **Protocol**: Technical Bridge
- **Source**: `./data-private/raw/2026-02-19/stats_instructions_v3.md`
- **Page**: `content/docs/project-proposal.qmd` — **relocated** from
  `content/project/project-proposal.qmd`. Delete the now-empty `content/project/` folder.
- **Transforms**:
  - Present the document as-is. Strip any preamble referencing internal AI agent instructions or
    repository workflow notes that are not part of the scientific content.
  - Retain all numbered sections (§1–§6), all tables, all R code blocks (these are methodology
    context relevant to the PI).
  - Do not reference `data-private/` paths in the rendered page — present as if the document is
    standalone.

---

## Navbar

The navbar carries seven sections, in this exact order:

1. **Data Primer**
2. **Predictors**
3. **Outcome**
4. **Model**
5. **Analysis**
6. **Pipeline**
7. **Docs**

The `index` page is **not** a navbar entry — the navbar brand title ("Absent from Chronic") is
its only link. There is no `Home` entry and no `Project` section.

---

## Exclusions

- `*.R` — source scripts, not publishable
- `*_cache/` — Quarto render cache (including `analysis/model-0/model-0_cache/`)
- `analysis/*/data-local/` — intermediate model artefacts, not publishable
- `analysis/*/prints/`, `analysis/*/figure-png-iso/` — figure exports consumed by the reports
  themselves; only images named explicitly in this contract are copied to the site
- `analysis/*/report-contract.prompt.md` — report-authoring contracts, internal to the Composing
  Orchestra
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
