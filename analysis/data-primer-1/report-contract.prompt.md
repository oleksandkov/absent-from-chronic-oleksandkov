---
mode: agent
description: Compose analysis/data-primer-1/ univariate distributions and variable traceability reports for the cchs_analytic dataset.
---

# Report Contract: data-primer-1

## Type: Data Primer

## Date: 2026-05-20

## Status: active

## Mission

Provide a complete univariate distribution profile and §2.2 variable traceability record
for every variable in `cchs_analytic` (63,843 rows × 70 cols) produced by
`manipulation/2-ellis.R`. Serves as the canonical data reference for all subsequent EDAs
and Reports in this project.

## Data Sources

- **Primary:** `data-private/derived/cchs-2-tables/cchs_analytic.parquet` (63,843 rows × 70 cols)
- **Supporting:** `data-public/metadata/CACHE-manifest.md`
- **Traceability source:** `data-private/raw/2026-02-19/stats_instructions_v3.md` (§2.2 variable list)

## Research Questions

1. What is the distribution of workdays absent (primary outcome and LOP components)?
2. What is the prevalence of each of the 17 available chronic conditions in the analytic
   sample?
3. How are the predisposing, facilitating, and needs variables distributed?
4. Which §2.2 requested variables are present, absent, or substituted in the current
   PUMF-based implementation?

## Output Documents

| File | Format | Purpose |
|------|--------|---------|
| `univariate-distributions.qmd` | HTML, code-fold | Distributions of all 70 variables |
| `variable-inclusion.qmd` | HTML, static | §2.2 traceability table |

## Target Sections — univariate-distributions

| Section | Topic | Key variables |
|---------|-------|---------------|
| 1.1 | Primary / sensitivity outcomes | `days_absent_total`, `days_absent_chronic` |
| 1.2 | LOP components | `lopg040` – `lopg100` (8 vars) |
| 2 | Chronic conditions prevalence | 17 `cc_*` (logical TRUE/FALSE) |
| 3 | Predisposing (tabset) | `age_group_3`, `sex`, `marital_status`, `household_size`, `education`, `immigration_status`, `visible_minority`, `home_ownership`, `living_arrangements`; raw codes: `dhhgage`; binary child-presence flags: `dhhgle5`, `dhhg611`, `dhhgl12` |
| 4 | Facilitating (tabset) | `income_hh`, `has_family_doctor`, `employment_type`, `work_schedule`, `smoking_status`, `bmi_category`, `physical_activity`, `alcohol_type`, `fruit_veg_daily`, `occupation_category`, `work_stress`, `province` |
| 5 | Needs (tabset) | `health_perceived`, `mental_health_perceived`, `health_vs_prior_year`, `injured_past_12m`, `adl_meals`–`adl_finances` |
| 6 | Survey design | `wts_m`, `wts_m_pooled`, `cchs_cycle_f`, `flag_complete_ccc`, `flag_complete_predictors`, `flag_analytic_complete` |

## Dual-File Pattern Rules

- **Lab (`.R`):** All computation + `print(knitr::kable(...))` display calls. QMD chunk bodies are **empty**.
- **Chunk naming:** `section-*` for computation, `display-*` for output tables.
- **Output cache:** `data-local/univariate-distributions.rds`
- `cc_*` variables are **logical** (TRUE/FALSE), not factor "Yes"/"No". `prevalence_table()` must check `x == TRUE`.

## Variable Name Mapping (backup → current pipeline)

| Backup | Current |
|--------|---------|
| `cc_asthma` (factor Yes/No, backup) | `cc_asthma` (logical TRUE/FALSE) |
| `age_group` | `age_group_3` |
| `income_5cat` | `income_hh` |
| `wts_m_original` | `wts_m` |
| `cycle_f` | `cchs_cycle_f` |
| `geodgprv` (integer) | `province` (factor, 13 levels) |
| `fvcdgtot` | `fruit_veg_daily` |
| `self_health_general` | `health_perceived` |
| `self_health_mental` | `mental_health_perceived` |
| `health_vs_lastyear` | `health_vs_prior_year` |
| `injury_past_year` | `injured_past_12m` |
| `gen_09` (raw int) | `work_stress` (ordered factor) |
| `adl_01`–`adl_06` | `adl_meals`, `adl_errands`, `adl_housework`, `adl_personal_care`, `adl_moving_indoors`, `adl_finances` |
| absent | `employment_type`, `occupation_category`, `smoking_status`, `living_arrangements` (new or now populated) |

## Output Format: HTML

## Scope Boundaries

- Descriptive statistics only; no modelling or inferential analysis.
- Data primer is composed once; re-run when pipeline changes (new Ellis output).
- `variable-inclusion.qmd` is static; it does not load data at render time.
- Cross-references between the two documents use relative `.html` links.
