# Session Log: CCHS Data Pipeline Implementation

**Date**: 2026-02-19  
**Persona**: Data Engineer  
**Project**: absent-from-chronic  

---

## Session Objective

Build a complete Ferry → Ellis data pipeline for two pooled CCHS microdata files
to produce an analysis-ready dataset for a study on chronic-condition work absenteeism
among Canadian employed adults (Blanchette et al., 2026).

---

## Files Created / Modified

| File | Action | Purpose |
|------|--------|---------|
| `config.yml` | Modified | Added CCHS raw data paths + DB output paths |
| `manipulation/1-ferry.R` | Created | Ferry lane — zero-transform SPSS import |
| `manipulation/2-ellis.R` | Created | Ellis lane — white-list + recode + pool |
| `manipulation/2-test-ellis-cache.R` | Created | Alignment test (3-way: code ↔ disk ↔ manifest) |
| `flow.R` | Modified | Phase 1 now runs ferry + ellis |
| `data-public/metadata/INPUT-manifest.md` | Populated | Documents two CCHS source files |
| `manipulation/pipeline.md` | Created | Execution guide + troubleshooting reference |

---

## Data Sources

| File | Cycle | Approx. rows | Location |
|------|-------|--------------|----------|
| `CCHS2010_LOP.sav` | 2010–2011 | 62,909 | `data-private/raw/2026-02-19/` |
| `CCHS_2014_EN_PUMF.sav` | 2013–2014 | 63,522 | `data-private/raw/2026-02-19/` |

Both are Statistics Canada PUMF files in SPSS (.sav) format with embedded value/variable labels.

---

## Pipeline Architecture

```
CCHS .sav files (x2)
        │
        ▼  1-ferry.R   [Ferry Pattern — zero semantic transformation]
  cchs-1.sqlite         → tables: cchs_2010_raw, cchs_2014_raw
  cchs-1-raw/*.parquet  → Parquet backups
        │
        ▼  2-ellis.R   [Ellis Pattern — white-list, harmonize, recode]
  cchs-2.sqlite         → tables: cchs_analytical, sample_flow
  cchs-2-tables/*.parquet → primary outputs (factors preserved)
        │
        ▼  2-test-ellis-cache.R   [Alignment verification]
  Console report (pass/fail per test)
```

---

## White-List Design

A key design decision was to filter to only variables needed for the analysis before
any transformation. This was driven by the research team's `required-variables-and-sample.md`
and `stats_instructions_v3.md` specifications.

### Two-Tier Structure

**Tier 1 — CONFIRMED** (13 variables): Hard error if missing. Verified against PDF data dictionaries.

| Variable | Role |
|----------|------|
| `LOPG010`–`LOPG045` (8 vars) | Work-absenteeism outcomes (LOP module) |
| `LOP_015` | Employment filter |
| `DHHGAGE` | Age filter + predictor |
| `ADM_PRX` | Proxy exclusion |
| `GEODPMF` | Province |
| `WTS_M` | Survey weight |

**Tier 2 — INFERRED** (~60 variables): Warning + graceful drop if missing. Inferred from
standard CCHS PUMF naming conventions; must be verified against PDF data dictionaries
if any are flagged as missing at runtime.

- CCC module (19): `CCC_015` → `CCC_185` (chronic condition diagnoses)
- Predisposing (7): sex, marital status, household size, education, immigration, birthplace, living arrangement
- Facilitating (11): income, family doctor, labour force, fruit/veg, alcohol, smoking, BMI, physical activity, perceived need
- Needs (5): self-rated health (general + mental), health trend, activity limitation, injury
- ID (1): `ADM_RNO`
- Bootstrap weights (500): matched via `^bsw` pattern

### `select_whitelist()` Function
Implements the tier logic:
- Errors with a named list if any CONFIRMED vars are absent
- Warns with a named list if any INFERRED vars are absent, then drops them
- Reports bootstrap weight count found

---

## Transformations in 2-ellis.R

### SECTION 1: Import + White-list + Harmonize + Stack
1. Load `cchs_2010_raw` and `cchs_2014_raw` from `cchs-1.sqlite`
2. Apply `select_whitelist()` independently per cycle
3. Add `cycle` integer flag (0 = 2010–2011, 1 = 2013–2014)
4. Harmonize any variable name discrepancies between cycles
5. `bind_rows()` → `ds0` (pooled, ~126k rows before exclusions)

### SECTION 2, Step 1 — Outcomes
- `days_absent_total`: `rowSums()` across 8 LOP variables (max 90; NA if all 8 are NA)
- `days_absent_chronic`: `lopg040` direct copy (primary outcome for most models)
- `outcome_all_na`: logical flag for rows with missing on all outcome components

### SECTION 2, Step 2 — Exclusions (sequential)
Produces `sample_flow` tibble (5 rows: step / description / n_remaining / n_excluded / pct_remaining).

| Step | Criterion | Note |
|------|-----------|------|
| 1 | Raw stacked sample | Baseline |
| 2 | Age 15–75 (`dhhgage %in% 2:15`) | **VERIFY codes against PDFs** |
| 3 | Employed (`lop_015 == 1`) | |
| 4 | Non-proxy (`adm_prx != 1`) | |
| 5 | Complete outcome | Any non-missing LOP var |

Reference final sample: **~64,141** respondents.

### SECTION 2, Step 3 — Factor Recoding
All categorical predictors recoded from integer codes to labelled factors using `case_when()` + `factor()`.
Ordered factors used where appropriate (education, income, BMI, physical activity, self-rated health).
CCC variables (19) recoded to `cc_*` binary factors (Yes/No) via loop.

Special NA codes `c(6, 7, 8, 9, 96, 97, 98, 99)` → `NA` throughout.

### SECTION 2, Step 4 — Survey Weight Pooling
Per Statistics Canada recommendation for pooling two CCHS cycles:

```r
wts_m_pooled     <- wts_m / 2        # for all respondents
bsw001_pooled    <- bsw001 / 2       # applied to all 500 bootstrap weights
```

`wts_m_original` retained for verification. Bootstrap columns identified by `^bsw` pattern
and divided by 2 via `mutate(across(matches(bootstrap_pattern), ~ . / 2))`.

### SECTION 2, Step 5 — Type Enforcement
Final column selection and type coercion to ensure clean parquet schema.

### SECTION 3 — Validation
`checkmate` assertions + diagnostic prints comparing outcome distribution to reference values:
- Weighted mean `days_absent_total` ≈ 1.35
- % zeros ≈ 70.59%
- Variance ≈ 17.7

### SECTION 4–5 — Output
- **Parquet** (PRIMARY): preserves R factor types + ordered levels — for analysis
- **SQLite** (secondary): factors converted to character — for ad hoc SQL queries

---

## Test Script Structure (2-test-ellis-cache.R)

Five test sections using `run_test()` wrapper (prints ✅ / ❌ per assertion):

1. **Artifact existence**: Ellis script, manifest, SQLite, Parquet dir, expected file names
2. **SQLite ↔ Parquet parity**: row counts and column names match for both tables
3. **cchs_analytical quality**: sample size range, required columns, outcome bounds, weight ratio ≈ 0.5, factor structure
4. **sample_flow quality**: 5 rows, monotone `n_remaining`, final row matches `cchs_analytical` rows
5. **Manifest alignment**: CACHE-manifest.md contains CCHS content (is not just a blank stub)

---

## flow.R Update

Replaced placeholder Phase 1 block (all commented-out) with:

```r
# PHASE 1: DATA MANIPULATION
"run_r", "manipulation/1-ferry.R",   # Ferry: CCHS .sav → cchs-1.sqlite
"run_r", "manipulation/2-ellis.R",   # Ellis: white-list → cchs-2.sqlite + Parquet
```

Phase 3 (EDA-1 Quarto report) was left intact.

---

## Outstanding Items for Next Session

- [ ] **Run the pipeline** — `source("flow.R")` or run ferry + ellis individually
- [ ] **Verify INFERRED variable names** against PDF data dictionaries (CCC, GEN, DHH, etc.)
- [ ] **Verify DHHGAGE age codes** — confirm codes 2–15 map to age 15–75 in both cycle PDFs
- [ ] **Populate CACHE-manifest.md** — run Ellis first, then document actual output schema
- [ ] **Update EDA-1** (`analysis/eda-1/eda-1.qmd`) to load from `cchs-2.sqlite` or Parquet

---

## Key Configuration Paths (config.yml)

```yaml
raw_data:
  cchs_2010: ./data-private/raw/2026-02-19/CCHS2010_LOP.sav
  cchs_2014: ./data-private/raw/2026-02-19/CCHS_2014_EN_PUMF.sav

path_db:
  cchs:
    ferry_sqlite:    ./data-private/derived/cchs-1.sqlite
    ellis_sqlite:    ./data-private/derived/cchs-2.sqlite
    ellis_parquet_dir: ./data-private/derived/cchs-2-tables/
```
