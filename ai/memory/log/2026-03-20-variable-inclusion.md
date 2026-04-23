# Session Log: Variable Inclusion Traceability Document

**Date**: 2026-03-20
**Persona**: Research Scientist
**Project**: absent-from-chronic

---

## Session Objective

Author `analysis/data-primer-1/variable-inclusion.md` — a traceability record linking
every variable requested in §2.2 of `stats_instructions_v3.md` to its concrete
implementation in the Ellis lane (`manipulation/2-ellis.R`), including exact PUMF column
names per cycle and the analytical database column name produced by Ellis.

---

## Document Created

**Path**: `analysis/data-primer-1/variable-inclusion.md`

**Purpose**: Evidence document demonstrating how Ellis delivered on §2.2 requirements.
Designed for the data-primer-1 context and for the independent biostatistician to verify
variable availability and naming before analysis begins.

---

## Structure

The document contains seven sections, one per row of the §2.2 requirements table. Each
section is preceded by the verbatim §2.2 passage and followed by a five-column table:

| Column | Content |
|--------|---------|
| **Requested** | Conceptual variable description from §2.2 |
| **2011** | Exact PUMF column name in CCHS 2010–2011 (post `clean_names()`) |
| **2014** | Exact PUMF column name in CCHS 2013–2014 (post `clean_names()`) |
| **In Study** | Column name in `cchs_analytical.parquet` produced by Ellis |
| **Note** | Status (✅ / ⚠️ / ❌) and any discrepancy explanation |

The 2011/2014 columns were populated by querying the ferry parquet files directly
(`data-private/derived/cchs-1-raw/cchs_2010_raw.parquet` and `cchs_2014_raw.parquet`)
and running a batch presence check via a temporary R script (since removed).

The "In Study" names were traced by reading the full Ellis factor-recoding section
(Steps 3–5, lines ~830–1340 of `manipulation/2-ellis.R`).

---

## Sections and Key Findings

### §1 — Outcome (Total Days Absent)
- 8 LOP raw components: ✅ identical names in both cycles (`lopg040`–`lopg100`)
- Derived column: `days_absent_total` (row-wise sum; 0–90 day enforced cap)

### §2 — Outcome (Sensitivity — Chronic Only)
- Source: `lopg040` → Ellis stores as `days_absent_chronic`

### §3 — Primary Exposure (19 Chronic Conditions)
- 17 of 19 ✅ available; recoded to `cc_*` binary factors
- ⚠️ 2 wrong white-list codes: `ccc_015` → `ccc_035` (asthma), `ccc_011` → `ccc_036` (fibromyalgia)
- ❌ 2 absent from PUMF: `ccc_300` (other mental illness), `ccc_185` (digestive disease)

### §4 — Predisposing Variables
- ✅ Delivered: `age_group`, `sex`, `marital_status`, `education`, `immigration_status`, `visible_minority`
- ⚠️ Alias fix pending: household size, 3× children counts, homeownership (wrong DG-infix in white-list)
- ❌ `sdcdgstud` (student status) absent from PUMF; column exists as all-NA via `ensure_columns()`

### §5 — Facilitating Variables
- ✅ Delivered: `has_family_doctor`, `job_stress`, `smoking_status`, `physical_activity`, province (`geodgprv`)
- ⚠️ Alias fix pending: `income_5cat`, `employment_type`, `work_schedule`, `alcohol_type`, `bmi_category`, `fvcdtot`
- ❌ `noc_31` (occupation) absent from PUMF; all-NA column via `ensure_columns()`

### §6 — Needs Variables
- ✅ All 5 delivered: `activity_limitation`, `injury_past_year`, `self_health_general`,
  `self_health_mental` (via `gen_02` alias), `health_vs_lastyear`

### §7 — Survey Design Variables
- ✅ `wts_m_pooled` (halved per SC guideline), `geodpmf` (strata proxy)
- ❌ Bootstrap weights (`bsw001`–`bsw500`): **critical blocker** — in separate Statistics Canada
  supplement file, absent from PUMF `.sav`
- ❌ Cluster / PSU identifier: suppressed in PUMF

---

## Summary of Gaps (from document)

| Variable | Reason | Impact |
|----------|--------|--------|
| `ccc_300`, `ccc_185` | PUMF-suppressed | 2 of 19 chronic conditions missing |
| `sdcdgstud` | PUMF-suppressed | 1 predisposing predictor all-NA |
| `noc_31` | PUMF-suppressed | 1 facilitating predictor all-NA |
| Bootstrap weights | Separate supplement file not obtained | Critical: §5.3–5.10 CIs impossible |
| Cluster identifier | PUMF-suppressed | Complex-sample design incomplete |

---

## Next Steps

- Apply 13 alias fixes to `manipulation/2-ellis.R` (pending user confirmation)
- Re-run Ellis after fixes to populate the ⚠️ columns
- Obtain bootstrap weight supplement file from Statistics Canada
- Commission `analysis/data-primer-1/` EDA via `@report-composer`
