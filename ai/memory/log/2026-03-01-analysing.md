# Session Log: EDA-3 

**Date**: 2026-03-01
**Persona**: Grapher
**Project**: absent-from-chronic

---

## Session Objective

Build `analysis/eda-3/eda-3.R` and `analysis/eda-3/eda-3.qmd` — replicating the EDA-2 analytical structure for `absence_days_chronic` instead of `absence_days_total`.

---

## Analysis Defined

**Key variable**: `absence_days_chronic` — days absent from work due to a chronic health condition, from `cchs_employed` table in `cchs-3.sqlite`.

**Analytical design**: Identical to EDA-2 in structure. Same seven graph families (g1–g7), same demographic breakdowns (sex, age, survey cycle, education, marital status, immigration status), same data pipeline pattern (`ds0` → `ds1` → per-variable subsets `ds5`/`ds6`/`ds7`), same conventions (`coord_cartesian(xlim = c(1,40))`, 5-day bins, firebrick median + darkorange mean lines, `geom_label(inherit.aes=FALSE)` for faceted panels).

### Files Created / Updated

| File | Status |
|------|--------|
| `analysis/eda-3/eda-3.R` | Complete — all g1-g7 graph families implemented |
| `analysis/eda-3/eda-3.qmd` | Complete — full Quarto report ready to render |
| `analysis/eda-3/README.md` | Created |

### Structure: `eda-3.R`

Boilerplate inherited from `eda-2.R`:

- `load-packages` — full tidyverse + DBI/RSQLite stack
- `httpgd` — VS Code interactive plot setup
- `load-sources` — `common-functions.R`, `operational-functions.R`
- `declare-globals` — paths re-pointed to `eda-3/`
- `declare-functions` — stub

Analysis sections (all implemented):

- `load-data` — `SELECT * FROM cchs_employed` from `cchs-3.sqlite`
- `tweak-data-0` — coerce `absence_days_chronic` to integer; derive `has_any_chronic` flag
- `inspect-data-0/1/2` — overview, glimpse, key variable summary
- `tweak-data-1` — create `ds1` (filter `absence_days_chronic > 0`, drop NAs); log exclusion counts
- `inspect-data-3` — ds1 central tendency
- `analytic-chronic-ratio` — overall zero vs. 1+ vs. NA table (`chronic_ratio_tbl`)
- `g1-data-prep` / `g1-scatter` / `g1-hist` — overall distribution
- `g2-data-prep` / `analytic-sex-ratio` / `g2-hist-sex` — by `sex_label`
- `g3-data-prep` / `g3-hist-age` — by `age_group_3`; stats saved to `data-local/g3_stats_age.csv`
- `g4-data-prep` / `g4-scatter-cycle` / `g4-hist-cycle` — by `survey_cycle_label`
- `g5-data-prep` / `g5-hist-edu` — by `education_level` (via `ds5`)
- `g6-data-prep` / `g6-hist-marital` — by `marital_status_label` (via `ds6`)
- `g7-data-prep` / `g7-hist-immigration` — by `immigration_status_label` (via `ds7`)

### Structure: `eda-3.qmd`

- Subtitle: "EDA 3 — CCHS 2010-11 & 2013-14: Distribution of Chronic Absence Days"
- `read_chunk` points to `analysis/eda-3/eda-3.R`
- Full Mission, Data, Analysis (g1–g7), and Session Info sections complete
- All chunk labels match `eda-3.R` section names; cache enabled

### Next Step

Run `source("analysis/eda-3/eda-3.R")` from repo root, then `quarto render analysis/eda-3/eda-3.qmd`.

---