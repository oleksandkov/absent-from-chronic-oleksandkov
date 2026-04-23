# Data Pipeline: absent-from-chronic

Execution guide for the CCHS work-absenteeism data pipeline.

---

## Overview

```
CCHS .sav files (data-private/raw/)
         │
         ▼  1-ferry.R   ← zero semantic transformation
  cchs-1.sqlite + cchs-1-raw/*.parquet   (staging)
         │
         ▼  2-ellis.R   ← white-list + harmonize + recode
  cchs-2.sqlite + cchs-2-tables/*.parquet   (analysis-ready)
         │
         ▼  2-test-ellis-cache.R   ← alignment verification
  console report (pass/fail)
```

---

## Scripts

| # | File | Pattern | Output |
|---|------|---------|--------|
| 1 | `manipulation/1-ferry.R` | Ferry | `data-private/derived/cchs-1.sqlite` + `cchs-1-raw/` Parquet backup |
| 2 | `manipulation/2-ellis.R` | Ellis | `data-private/derived/cchs-2.sqlite` + `cchs-2-tables/` Parquet |
| 3 | `manipulation/2-test-ellis-cache.R` | Test | Console test report (three-way alignment check) |
| — | `manipulation/example/ferry-lane-example.R` | Example | `cchs-1.sqlite` (demo only; does not affect main pipeline) |
| — | `manipulation/example/ellis-lane-example.R` | Example | `cchs-2.sqlite` (demo only; does not affect main pipeline) |

> **Note on Ellis Lane 3**: Derived output directories `cchs-3-tables/` and `cchs-3.sqlite`
> exist in `data-private/derived/` from a prior run of a clarity-layer script.
> The corresponding `manipulation/3-ellis.R` source file is not currently present in the
> repository. If you need to regenerate the Lane 3 outputs, consult the CACHE-manifest or
> the cchs-3-column-dictionary for its column schema.


## 1-ferry

### High-Level Summary

`1-ferry.R` is a **pure transport** script. Its sole job is to move raw CCHS
PUMF microdata from SPSS (`.sav`) format into a local SQLite staging database,
with a Parquet backup alongside. It does **nothing analytical**: no variable
selection, no recoding, no filtering, no renaming beyond mechanical
snake_case sanitization. The guiding discipline is that every decision about
*what the data means* is deferred to the Ellis lane; Ferry only answers the
question *"how do we get the data off disk into a queryable form?"*.

Two CCHS cycles are handled in one script:

| Cycle | Source file | SQLite table |
|-------|-------------|--------------|
| 2010–2011 | `CCHS2010_LOP.sav` | `cchs_2010_raw` |
| 2013–2014 | `CCHS_2014_EN_PUMF.sav` | `cchs_2014_raw` |

If the 2014 file is absent, the script continues with a zero-row placeholder
(same schema as 2010) so that downstream scripts can still be developed and
tested against a structurally complete database.

**Permitted operations**

| Operation | Tool | Reason permitted |
|-----------|------|-----------------|
| Read SPSS | `haven::read_sav()` | Ingestion only |
| Strip value/variable labels | `haven::zap_labels()` / `haven::zap_label()` | SQLite cannot store SPSS label attributes |
| Sanitize column names | `janitor::clean_names()` | Mechanical normalization, no meaning change |
| Write SQLite | `DBI::dbWriteTable()` | Primary staging output |
| Write Parquet | `arrow::write_parquet()` | Backup / fast-read fallback |

**Forbidden operations** (all deferred to Ellis)

- Variable selection / white-listing
- Renaming beyond `clean_names` normalization
- Factor or value recoding
- Sample exclusions or filtering
- Derived variable construction

---


---

## Running the Pipeline

### Option A: Full pipeline via flow.R
```r
source("flow.R")
```
Runs ferry → ellis → all downstream analyses in sequence.

### Option B: Individual scripts
```r
source("manipulation/1-ferry.R")            # ~2–5 min depending on file size
source("manipulation/2-ellis.R")            # ~1–2 min
# source("manipulation/3-ellis.R")          # ~1 min — optional clarity layer
source("manipulation/2-test-ellis-cache.R") # <30 sec
```

### Option C: VS Code Tasks
Use the tasks defined in `.vscode/tasks.json`:
- **Run Ferry Lane 1** — `Rscript manipulation/1-ferry.R`
- **Run Ellis Lane 2** — `Rscript manipulation/2-ellis.R`
- **Test Ellis ↔ CACHE-Manifest Alignment** — `Rscript manipulation/2-test-ellis-cache.R`

### Option D: Interactive Pipeline (run-interactive-flow.ps1)
The interactive runner asks three questions before launching `flow.R`:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/ps1/run-interactive-flow.ps1
```

**Q1 — Ellis mode** (`run-as-is` / `default` / `strict`): controls three pipeline
flags in `2-ellis.R` (`strict_cycle_integrity`, `apply_sample_exclusions`,
`apply_completeness_exclusion`).

**Q2 — EDA selection**: dynamically scans `analysis/` for folders that contain
both an `.R` file and a `.qmd` file, and lets you choose which EDAs to activate
(uncomment) in `flow.R`. Selecting **None (0)** comments out **all** active EDA
lines in `flow.R` so they will be skipped.

**Q3 — Run mode**: apply all changes and launch, or run `flow.R` as-is.

---

## Inputs

| File | Location | Cycle |
|------|----------|-------|
| `CCHS2010_LOP.sav` | `data-private/raw/2026-02-19/` | 2010–2011 |
| `CCHS_2014_EN_PUMF.sav` | `data-private/raw/2026-02-19/` | 2013–2014 |

Paths are configured in `config.yml` under `raw_data`.

---

## Outputs

### Ferry outputs (staging — not for analysis)

| Artifact | Location | Description |
|----------|----------|-------------|
| `cchs-1.sqlite` | `data-private/derived/` | Raw tables: `cchs_2010_raw`, `cchs_2014_raw` |
| `cchs-1-raw/*.parquet` | `data-private/derived/cchs-1-raw/` | Parquet backups of raw tables |

### Ellis outputs (analysis-ready)

| Artifact | Location | Format | Description |
|----------|----------|--------|-------------|
| `cchs_analytical.parquet` | `data-private/derived/cchs-2-tables/` | Parquet | Main analysis dataset (`apply_sample_exclusions = TRUE` by default; 63,843 rows, 62 cols) |
| `sample_flow.parquet` | `data-private/derived/cchs-2-tables/` | Parquet | Exclusion audit trail (5 rows) |
| `cchs-2.sqlite` | `data-private/derived/` | SQLite | Same tables as Parquet (factors as character) |

### Ellis Lane 3 outputs (clarity layer — from prior run)

| Artifact | Location | Format | Description |
|----------|----------|--------|-------------|
| `cchs_analytical.parquet` | `data-private/derived/cchs-3-tables/` | Parquet | Full pooled sample (mirrors Lane 2) |
| `cchs_employed.parquet` | `data-private/derived/cchs-3-tables/` | Parquet | Employed-respondent split |
| `cchs_unemployed.parquet` | `data-private/derived/cchs-3-tables/` | Parquet | Non-employed-respondent split |
| `data_dictionary.parquet` | `data-private/derived/cchs-3-tables/` | Parquet | Variable-level metadata / data dictionary |
| `sample_flow.parquet` | `data-private/derived/cchs-3-tables/` | Parquet | Exclusion audit trail |
| `cchs-3.sqlite` | `data-private/derived/` | SQLite | Same tables as above (factors as character) |

---

## Pipeline Flags

Three boolean flags in `2-ellis.R` → `# ---- declare-globals` control key pipeline behaviours.
They can also be managed via the interactive runner (`scripts/ps1/run-interactive-flow.ps1`).

| Flag | Default | Effect |
|------|---------|--------|
| `strict_cycle_integrity` | `FALSE` | If `TRUE`, stop with an error when either CCHS cycle loads as empty; otherwise emit a warning and continue with available cycles. |
| `apply_sample_exclusions` | `TRUE` | If `TRUE`, apply §3.1 inclusion criteria (age 15–75, employed in past 3 months, non-proxy, non-missing outcome). If `FALSE`, retain full pooled sample (~126,431). |
| `apply_completeness_exclusion` | `FALSE` | If `TRUE`, additionally drop any respondent with `NA` on any CCC indicator or key predictor. If `FALSE`, handle missing data downstream (e.g., multiple imputation). |

---

## White-List Design

Ellis uses a **two-tier white-list** to select only variables needed for the analysis.
This keeps the analysis-ready dataset focused and avoids processing ~1,400 irrelevant columns.

### Tier 1: CONFIRMED (hard error if missing)
13 variables verified against PDF data dictionaries. If any are absent, Ellis fails loudly.
See `vars_confirmed` in `2-ellis.R` → `declare-globals` section.

### Tier 2: INFERRED (graceful warning if missing)
~48 variables inferred from standard CCHS PUMF naming conventions. If any are absent,
Ellis logs a warning with a list of missing names and drops them. Analysis continues.
Bootstrap weights (`bsw001`–`bsw500`) are pattern-matched separately.

| Category | Example variables | Count |
|----------|-------------------|-------|
| CCC module (chronic conditions) | `ccc_031`, `ccc_041`, `ccc_051`, … `ccc_290` (+ `ccc_300`, `ccc_185` absent from PUMF) | 19 (17 found) |
| Predisposing | `dhh_sex`, `dhhgms`, `edudh04`, `dhhdglvg`, `dhhdfc5`, `dhhdfc11`, `dhhdfc12p`, `sdcdgstud`, … | 11 (7 found) |
| Facilitating | `incdghh`, `geodgprv`, `hcu_1aa`, `lbfdghp`, `gen_07`, `alcdgtyp`, `hwtdgbmi`, `noc_31`, … | 12 (9 found) |
| Needs | `gen_01`, `gen_02a`, `gen_09`, `rac_1`, `inj_01` | 5 |
| Identifiers | `adm_rno` | 1 |
| Bootstrap weights | `bsw001`–`bsw500` (pattern `^bsw`) | 500 |

**To update the white-list:**
1. Open `manipulation/2-ellis.R`
2. Navigate to `# ---- declare-globals`
3. Modify `vars_confirmed` or the relevant `vars_inferred_*` vector
4. Re-run Ellis and the test script

---

## Exclusion Criteria (sample_flow)

`2-ellis.R` applies **§3.1 exclusion criteria by default** (`apply_sample_exclusions = TRUE`).
Full pooled sample mode (no exclusions) is available by setting `apply_sample_exclusions = FALSE`.

| Step | Criterion | Expected % retained |
|------|-----------|---------------------|
| 1 | Raw CCHS stacked sample | 100% |
| 2 | Age 15–75 (`dhhgage %in% 2:15`) | ~89% |
| 3 | Currently employed (`lop_015 == 1`) | ~51% |
| 4 | Non-proxy respondent (`adm_prx != 1`) | ~51% |
| 5 | Complete outcome (any LOP var non-missing) | ~50.5% |

Reference final sample:
- **Default mode (`apply_sample_exclusions = TRUE`)**: `63,843`
- **Full pooled mode (`apply_sample_exclusions = FALSE`)**: `126,431`

---

## Survey Weight Pooling

Two CCHS cycles are pooled into a single dataset. Per Statistics Canada guidelines:

```
wts_m_pooled = wts_m / 2     # for each respondent
bsw001_pooled = bsw001 / 2   # same for all 500 bootstrap weights
```

`wts_m_original` is kept alongside `wts_m_pooled` for verification.

---

## Diagnostic Checkpoints

After running `2-ellis.R`, verify these values match expectations:

| Diagnostic | Reference |
|------------|-----------|
| Final sample size (default — exclusions applied) | 63,843 |
| Final sample size (full pooled — no exclusions) | 126,431 |
| Weighted mean `days_absent_total` | ≈ 1.25 |
| % zeros in `days_absent_total` | ≈ 70.5% |
| Variance of `days_absent_total` | ≈ 15.4 |
| White-list misses (INFERRED tier) | 10 in current PUMF files (see Known Limitations in CACHE-manifest) |

---

## Troubleshooting

**"Variable X not found" (confirmed tier)**  
→ The variable was renamed in this cycle's PUMF. Check the PDF data dictionary and add
  a harmonization step in `2-ellis.R` under `# ---- SECTION 1 / harmonize`.

**White-list inferred warnings**  
→ Some CCHS predictor variables may have slightly different names (e.g., `GEN_02` vs
  `GEN_02A`). Open the data dictionary for that module and update `vars_inferred_*` in
  `2-ellis.R` → `declare-globals`.

**DHHGAGE codes outside 2–15 seen in data**  
→ Verify age category coding against the PDF data dictionary for each cycle.
  Adjust `dhhgage %in% 2:15` in `tweak-data-2-exclusions` accordingly.

**SQLite and Parquet row counts don't match**  
→ Run `manipulation/2-test-ellis-cache.R` — it will identify the parity failure specifically.
  Re-run `2-ellis.R` to regenerate both outputs atomically.

---

## Data Documentation

| File | Contents |
|------|----------|
| `data-public/metadata/INPUT-manifest.md` | Raw source file descriptions |
| `data-public/metadata/CACHE-manifest.md` | Analysis-ready dataset descriptions (manually maintained) |
| `data-public/metadata/cchs-3-column-dictionary-uk.md` | Lane 3 column dictionary (Ukrainian) |
| `manipulation/pipeline.md` | This file |

---

*Last updated: 2026-03-20 (post Ellis revision — 62-column, 63,843-row output)*
