# Report Audit Checklist

Use this checklist before completing an analytical report (EDA or Report). It verifies all artifacts are properly tracked, named, and synchronized.

**When to use**: Before final render, before commit to git, before handoff

**Who uses**: Report developer or second reviewer

---

## Part 1: Artifact Identification

- [ ] All artifacts (graphs, tables, figures, outputs) have been inventoried
- [ ] Artifact Inventory in `report-contract.prompt.md` is present and current
- [ ] No duplicate IDs within report (no two g2s, etc.)
- [ ] All IDs follow the positional convention: g1/g2/g21/g211 (graphs), t1/t11 (tables), fig01/fig02 (figures), out1/out11 (outputs)
- [ ] Numbering treated as nominal unless a semantic convention is documented in project-specific instructions

## Part 2: R Script Synchronization

- [ ] All artifact chunks named consistently with IDs:
  - `# ---- g2-data-prep ----`
  - `# ---- g2 ----`
  - `# ---- g21 ----` (level-2 variant)
  - `# ---- g211 ----` (level-3 micro-variant)
  - `# ---- t1 ----` (tables)
  - `# ---- out1 ----` (outputs)
- [ ] No duplicate chunk names in `.R` file
- [ ] All Data Context chunks present and populated:
  - `# ---- data-context-tables ----`
  - `# ---- data-context-person ----`
  - `# ---- data-context-distributions ----`
- [ ] Graph chunks include `print()` and `ggsave()`:

```r
ggsave(paste0(prints_folder, "g2_descriptive_name.png"), g2_plot, ...)
print(g2_plot)
```

- [ ] Graph titles include ID: `"Graph g2: Description"`
- [ ] Table titles include ID: `"Table t1: Description"`
- [ ] Output blocks lead with a `cat()` header: `"Output out1: Description"`
- [ ] Filenames include ID: `g2_descriptive.png` (not just `descriptive.png`)

## Part 3: QMD Document Synchronization

- [ ] `.qmd` chunk labels match `.R` chunk names exactly:
  - `.qmd`: `{r g2-data-prep}` ↔ `.R`: `# ---- g2-data-prep ----`
  - `.qmd`: `{r g2}` ↔ `.R`: `# ---- g2 ----`
- [ ] No duplicate chunk labels in `.qmd` file
- [ ] Level-3 micro-variants (e.g., `g211`) appear as `####` subsections under their level-2 parent
- [ ] Data Context section includes all three chunks:
  - `{r data-context-tables}`
  - `{r data-context-person}`
  - `{r data-context-distributions}`
- [ ] Data Context appears after data-loading, before Analysis

## Part 4: Rendered Output

- [ ] Each graph title/caption visible and includes artifact ID:
  - "Graph g2: Age and Income Distribution"
- [ ] Each table caption visible and includes artifact ID:
  - "Table t1: Summary Statistics by Program Type"
- [ ] Each figure caption visible and includes artifact ID:
  - "Figure fig01: Regional Service Coverage Map"
- [ ] Each output block leads with its ID:
  - "Output out1: Grain proof for support_by_year"
- [ ] Outputs are raw text (enhanced displays are classified as tables `t*`)
- [ ] No artifacts appear without their IDs

## Part 5: Contract and Documentation

- [ ] `report-contract.prompt.md` exists and is current:
  - [ ] Mission is clear (1–2 sentences)
  - [ ] Research questions specific (3–5 questions)
  - [ ] Data sources listed (Primary + Supporting)
  - [ ] Artifact Inventory present and matches actual artifacts
  - [ ] Status appropriate (draft, active, or complete)
- [ ] All research questions covered by artifacts in report
- [ ] Dropped RQs marked ~~strikethrough~~ in contract

## Part 6: Data Context Verification

- [ ] Data Context section present in `.qmd`
- [ ] Link to data primer present: `[Data Primer](../data-primer-1/data-primer-1.html)`
- [ ] `data-context-tables` shows:
  - Which Ellis parquet tables used
  - Why each selected (grain, variables, time coverage)
- [ ] `data-context-person` shows:
  - 1–2 representative individuals
  - Their data across all tables
  - Grain verification (e.g., person × year, no duplicates)
- [ ] `data-context-distributions` shows:
  - Only variables relevant to this report's RQs
  - Simple counts or summary stats (not complex analyses)

## Part 7: Code Quality

- [ ] Script runs top-to-bottom without errors in fresh R session

```r
rm(list = ls(all.names = TRUE))
source("analysis/{name}/{name}.R")
```

- [ ] All data via `arrow::read_parquet()` (not environment cache)
- [ ] All paths use `local_root`, `data_private_derived`, `prints_folder`
- [ ] No superlatives or unsupported claims in text
  - ❌ "brilliant", "revolutionary", "clearly shows"
  - ✅ "Distribution of", "Comparison of", "Trend in"
- [ ] Comments are clear and honest (not marketing)

## Part 8: Reproducibility

- [ ] `.R` script structure clear:
  - [ ] Section markers (SECTION: title)
  - [ ] Load packages, sources, globals
  - [ ] Load data from Ellis parquet
  - [ ] Inspection and grain verification
  - [ ] Analysis chunks (g*, t*, fig*, out*)
  - [ ] Save to disk
- [ ] Package loading complete (greedy, with fallbacks)
- [ ] Working directories correct
- [ ] No warnings or errors in `.R` execution
- [ ] Report renders cleanly

```r
quarto render analysis/{name}/{name}.qmd
```

## Part 9: File Organization

- [ ] Directory structure complete:

```text
analysis/{name}/
├── report-contract.prompt.md      [OK]
├── {name}.R                       [OK]
├── {name}.qmd                     [OK]
├── data-local/                    [OK]
├── prints/                        [OK]
├── figure-png-iso/                [OK]
└── local-functions.R              [if needed]
```

- [ ] All `.png` files in `prints/` named with artifact IDs: `g1_*.png`, `g2_*.png`
- [ ] No orphaned or stray files

## Part 10: Final Sign-Off

- [ ] Developer review: All items checked ✓
- [ ] Second reviewer (if applicable): All items verified ✓
- [ ] Ready for commit or handoff

---

## Passing Audit Result

If all checkboxes complete:

```text
Artifact audit PASSED
├─ Artifact IDs unique and immutable
├─ Chunk names synchronized (.R ↔ .qmd)
├─ All IDs visible in rendered output
├─ Data Context complete
├─ Contract and inventory current
└─ Code runs cleanly in fresh session

Ready for: Git commit | Handoff | Publication
```

---

## Quick Reference

| Category | Check |
| --- | --- |
| **IDs** | All g*, t*, fig*, out* unique, immutable, positional hierarchy (≤9 per level) |
| **Sync** | `.R` chunk names = `.qmd` labels exactly |
| **Output** | Every artifact visible in title/caption with ID |
| **Contract** | Current, includes Artifact Inventory, all RQs addressed |
| **Data Context** | Present (tables, person, distributions) |
| **Code** | Runs top-to-bottom in fresh R session |
| **Reproducibility** | Uses `arrow::read_parquet()`, relative paths |
| **Quality** | No superlatives, honest language |
| **Structure** | Directory complete, files organized, no orphans |
| **Sign-Off** | Developer + reviewer ✓ all above |

---

## Reference Files

- `.github/instructions/artifact-naming.instructions.md` — Artifact ID system
- `.github/instructions/report-composition.instructions.md` — Reporting standards
- `.github/templates/composing-contract-template.md` — Contract schema
- `analysis/eda-1/` — Reference implementation
