---
description: >
  Rules for developing analytical reports (EDA and presentation Reports) within analysis/ directories.
  Covers the dual-file pattern (.R + .qmd), graph family conventions, data provenance, directory
  structure, and quality standards established by the Composing Orchestra system.
applyTo: "analysis/**"
---

# Report Composition Rules

These rules apply to all analytical content in `analysis/`. They codify the conventions from `analysis/eda-1/eda-style-guide.md` and the Composing Orchestra design (`.github/composing-orchestra.md`).

## Dual-File Discipline

Every analysis consists of an `.R` script and a `.qmd` document:

- **`.R` script** = analytical laboratory. All exploration, data wrangling, and visualization development happens here. Use `print()` for interactive display and Quarto rendering, plus `ggsave()` to save plots to disk.
- **`.qmd` document** = publication layer. Sources chunks from the `.R` script via `read_chunk()`. Chunk bodies remain **empty** — the `print()` statement in the sourced R chunk executes automatically during rendering. Provides narrative context around visualizations.
- **Synchronization**: When creating a new chunk in `.R`, create the corresponding `.qmd` chunk reference. Chunk names must match exactly between files.

```r
# In .R script setup, register chunks:
read_chunk("analysis/eda-N/eda-N.R")
```

## R Script Structure Conventions

Every `.R` script uses two levels of structural markers:

- **CHUNKS** — named with `# ---- chunk-name ----` (lowercase-hyphen). One chunk = one idea: data prep, one graph, or one table. Chunk names never change once assigned (graph numbers are stable).
- **SECTIONS** — named with `# ---- SECTION: Title ----` (all-caps `SECTION:` prefix). Mark logical groups of related chunks (e.g., attrition, year-0 profile). Collapsible in RStudio (Alt+O to fold all). A plain-comment description goes immediately below the header.
- **No decorative borders**: Never use `# ===...===` or similar ornamental comment lines anywhere in the script.

```r
# ---- SECTION: Attrition Narration -------------------------------------------
# Two-stage reduction to the incident cohort.
# Stage 0 — SIN-linkable; Stage 1 — Left-truncation (first record ≥ 2013).

# ---- attrition-stage0 --------------------------------------------------------
# ... chunk code ...

# ---- attrition-stage1 --------------------------------------------------------
# ... chunk code ...
```

## Graph Family Protocol

A **graph family** is a collection of visualizations sharing a common data-preparation ancestor.

### Structure

```text
g2-data-prep  →  g2  (level-1 graph)
                  g21 (level-2 variant / different facet)
                  g22 (level-2 variant / different facet)
                  g211 (level-3 micro-variant — aesthetic test of g21)
```

### Rules

- **One idea = one graph = one chunk**. Never combine unrelated analyses in a single chunk.
- **Data prep chunks** named `gN-data-prep` create the shared ancestor dataset.
- **Family members** descend by appending a digit: `g21`, `g22` (level 2), `g211` (level 3).
- **Graph numbering never changes** once assigned, even if a graph is later removed from the script.

### Numbering Convention

Numbering is **positional** and **nominal by default** — it encodes a shelf-and-bin position and the order in which artifacts were created, not prescribed importance. There are four artifact types:

- `g1`, `g2`, `g21`, `g211` — **Graphs** (ggplot2 visualizations; append a digit to descend a level)
- `t1`, `t11`, `t2` — **Tables** (enhanced displays: kable, gt, DT — independent families)
- `fig01`, `fig02` — **Figures** (non-ggplot visuals: imported images, maps, diagrams)
- `out1`, `out11` — **Outputs** (raw text-based console blocks)
- Objects: `g1_descriptive_name`, `g21_descriptive_name`, `t1_descriptive_name`

Keep at most nine items per level (`g1`–`g9`, `g21`–`g29`). A project may later document its own semantic meaning for the levels (e.g., level 1 = most reader-facing) in project-specific instructions; until then, treat numbering as nominal.

**Important**: See `.github/instructions/artifact-naming.instructions.md` for the complete artifact ID system, including the four artifact types, the **positional hierarchy**, the **nominal-numbering** principle, and the **three-point enforcement rule** (ID must appear in chunk name, .qmd label, and rendered output title/caption). This is mandatory for all new reports.

## Print Optimization

All visualizations default to:

- **Dimensions**: 8.5 × 5.5 inches (letter-size half-page portrait)
- **Resolution**: 300 DPI
- **Format**: PNG
- **Filename pattern**: Must include artifact ID (e.g., `g2_descriptive_name.png`, not just `descriptive_name.png`)

```r
ggsave(paste0(prints_folder, "g2_descriptive_name.png"),
       g2_plot, width = 8.5, height = 5.5, dpi = 300)
print(g2_plot)
```

**Both `print()` and `ggsave()` required**: Print for interactive feedback during development, `ggsave()` for reproducible disk export.

## Directory Structure

Every `analysis/eda-N/` or `analysis/report-N/` directory follows this layout:

```
analysis/eda-N/
├── report-contract.prompt.md    # Structured brief
├── eda-N.R                      # Analytical laboratory (includes data-context chunks)
├── eda-N.qmd                    # Publication layer (includes Data Context section)
├── data-local/                  # Intermediate processing files
├── prints/                      # High-quality plot exports
├── figure-png-iso/              # Quarto-generated figures
└── local-functions.R            # Analysis-specific helpers (created on demand)
```

The centralized data primer lives at `analysis/data-primer-1/` (its own `data-primer-1.R` + `data-primer-1.qmd`).
Private derived outputs go to `data-private/derived/eda-N/`.

## Data Provenance

Every `ds*` dataset and `g*` graph object must trace back through:

```
Ellis output (data-private/derived/manipulation/*.parquet)
  → CACHE database (data-public/metadata/CACHE-manifest.md)
    → Batch-91 source data
```

When loading data, use `arrow::read_parquet()` for Ellis outputs. Document which table(s) each dataset derives from.

## Data Context Section (Mandatory)

Every EDA or Report `.qmd` must contain a **Data Context** section placed immediately after the data-loading chunks and before the Analysis section. This section orients the reader to the data *for this specific analysis* and is **not** a copy of the data primer.

### Required Components

1. **Link to full documentation**: Start with a link to the central data primer

   ```qmd
   For complete data documentation, see the [Data Primer](../data-primer-1/data-primer-1.html).
   ```

2. **`data-context-tables` chunk**: Which Ellis parquet tables this analysis uses and why
   - List primary and supporting tables from the contract's Data Sources section
   - Explain why each table was selected (grain, variables, time coverage)
   - Example:

     ```
     This analysis uses:
     - primary_table.parquet: person-year records (grain: person × year)
     - supporting_table.parquet: person-level demographics and enrollment history
     ```

3. **`data-context-person` chunk**: Representative single-person view
   - Select 1–2 individuals whose data exemplifies the analysis grain
   - Show what their data looks like across all tables used
   - Confirms data structure for readers unfamiliar with the source
   - Example:

     ```
     example_person <- sample_dataset %>% slice_sample(n = 1) %>% pull(person_oid)
     primary_table %>% filter(person_oid == example_person)
     supporting_table %>% filter(person_oid == example_person)
     ```

4. **`data-context-distributions` chunk**: Distributions of variables appearing in this report's graphs
   - Show only variables relevant to this report's research questions
   - Use simple counts, summary stats, or basic tables (not graphs)
   - Grounds readers in data before they see visualized findings
   - Example:

     ```
     primary_table %>% count(category) %>% arrange(desc(n))
     supporting_table %>% summarise(age_mean = mean(age), age_sd = sd(age))
     ```

### Corresponding R Chunks

Every `.R` script must include three placeholder chunks for the Data Context (comment them out by default during scaffolding, populate during the interview):

```r
# ---- data-context-tables ------
# Which tables and variables this analysis uses (from contract Data Sources)

# ---- data-context-person ------
# What the data looks like for a representative individual

# ---- data-context-distributions -------
# Distributions of key variables relevant to this analysis
```

These must be executed in the `.qmd` via `read_chunk()` in the Data Context section.

### Grain Proof

Include code in `data-context-person` or a supplementary validation chunk that confirms the unit of analysis (grain):

```r
# Verify grain: should be person × year with no duplicates
primary_table %>%
  group_by(person_oid, year) %>%
  summarise(n = n(), .groups = "drop") %>%
  filter(n > 1) %>%
  nrow()  # Should be 0
```

## Artifact Types and Outputs

Reports produce four kinds of artifacts. Each must be identifiable in the rendered document so a reader can direct feedback to a specific artifact:

- **Graphs (`g`)**: ggplot2 visualizations. Title pattern: `"Graph g2: ..."`
- **Tables (`t`)**: tabular content through an enhanced display (kable, gt, DT). Caption pattern: `"Table t1: ..."`. Tables form independent families.
- **Figures (`fig`)**: non-ggplot visuals (imported images, maps, diagrams). Caption pattern: `"Figure fig01: ..."`
- **Outputs (`out`)**: raw text-based console blocks meaningful for understanding the CACHE-manifest, the data primer, or `method.md`. First-line pattern via `cat()`: `"Output out1: ..."`

**Output vs. Table bright line**: An output is *raw text*. The moment the same content is rendered through an enhanced display (e.g., `kable`), it becomes a **table** and takes a `t` prefix.

## Artifact Inventory

Every report contract (`report-contract.prompt.md`) must include an **Artifact Inventory** section listing all planned artifacts:

```markdown
## Artifact Inventory

| ID | Type | Title | Purpose |
| --- | --- | --- | --- |
| g1 | Graph | Age and Income Distribution | Baseline demographics |
| g2 | Graph | Service Receipt by Program | Service diversity |
| g21 | Graph | Service Receipt — Male | Gender stratification |
| g22 | Graph | Service Receipt — Female | Gender stratification |
| t1 | Table | Summary Statistics | Quantitative reference |
| t2 | Table | Sample Flow | Inclusion criteria |
| fig01 | Figure | Regional Map | Geographic context |
| out1 | Output | Grain Proof | Data-structure assurance |
```

- **Updated during development**: When artifacts are added, removed, or modified, update this inventory
- **Supports auditing**: Use this table to verify all g*, t*, fig*, out* IDs are accounted for before completion
- **Prevents drift**: Keeps actual artifacts in sync with planned scope
- **Numbering is nominal**: IDs reflect creation order or analytic flow by default; document any semantic convention in project-specific instructions

## Contract Fidelity

The `.R` script and `.qmd` document should address all research questions listed in `report-contract.prompt.md`. If scope changes during development, update the contract **and** the Artifact Inventory.

## Alberta Corporate Visual Identity

Use color palettes from `scripts/graphing/graph-presets.R`:

- `abcol` — Corporate palette (grey, magenta, brown, green, blue, yellow)
- `binary_colors` — High contrast, colorblind-safe
- `acru_colors_9` — Qualitative 9-category palette

## Package Loading

Follow the greedy loading pattern — load only what's needed:

```r
library(magrittr)    # pipes
library(ggplot2)     # graphs
library(dplyr)       # data wrangling
library(tidyr)       # data reshaping
library(arrow)       # parquet I/O
```

Use defensive loading for optional packages:

```r
if (requireNamespace("pkg", quietly = TRUE)) { library(pkg) }
```

## Quarto Chunk Standards

```qmd
{r g21}
#| code-summary: "Brief description of what this chunk shows"
#| echo: true
#| message: false
#| warning: false
#| cache: true
#| fig-cap: "Caption describing the visualization"
#| code-fold: true
```

**Note**: The chunk body is empty. The `print()` statement lives in the sourced R chunk and executes automatically when Quarto renders via `read_chunk()`. See [analysis/eda-1/eda-style-guide.md](../analysis/eda-1/eda-style-guide.md) for detailed rationale.

## Artifact Audit Checklist (Before Completion)

Before rendering or committing a completed report, verify:

- [ ] All artifact IDs (g*, t*, fig*, out*) are unique within the report
- [ ] Chunk names in `.R` and `.qmd` match exactly (check `data-context-tables`, `data-context-person`, `data-context-distributions`)
- [ ] Each artifact ID appears in three places: chunk name, .qmd label, rendered title/caption
- [ ] Level-3 micro-variants (e.g., `g211`) appear as subsections under their level-2 parent
- [ ] Artifact Inventory in contract matches actual artifacts in the report
- [ ] No artifacts use the same ID (no duplicate g2, t1, etc.)
- [ ] Data Context section is populated with all three required chunks
- [ ] Grain proof is included and confirms unit of analysis
- [ ] All graphs include `print()` and `ggsave()` in the `.R` file
- [ ] Outputs are raw text blocks (enhanced displays use the `t` table prefix instead)
- [ ] Report renders cleanly from `arrow::read_parquet()` in a fresh R session

## Quality Standards

- **Descriptive default**: Prefer descriptive statistics; prompt human before inferential analysis
- **No superlatives**: Avoid "brilliant", "revolutionary" — let evidence speak
- **No hallucination**: Never fabricate data patterns. If uncertain, document the uncertainty.
- **Humble epistemology**: Present findings as current best evidence, not absolute truth
- **Reproducibility**: All code must run in a fresh R session with documented dependencies
- **Transparency**: Document analytical decisions and their rationale
- **Artifact consistency**: All graphs, tables, figures, and outputs must have IDs that are visible in rendered output
