# CACHE Manifest

Definitive reference for datasets produced by the Ellis lane (`manipulation/2-ellis.R`).
Describes file structure, variable inventory, factor levels, and transformation logic.
Manually maintained — update after re-running Ellis with changed flags or white-list.

Updated: 2026-03-20

---

## Overview

| Dataset | Path | Format | Rows (default mode) | Columns |
|---------|------|--------|--------------------:|---------|
| `cchs_analytical` | `data-private/derived/cchs-2-tables/cchs_analytical.parquet` | Parquet | 63,843 | 62 |
| `cchs_analytical` | `data-private/derived/cchs-2.sqlite` | SQLite | 63,843 | 62 |
| `sample_flow` | `data-private/derived/cchs-2-tables/sample_flow.parquet` | Parquet | 5 | 5 |
| `sample_flow` | `data-private/derived/cchs-2.sqlite` | SQLite | 5 | 5 |

**Run mode:** `apply_sample_exclusions = TRUE` (§3.1 exclusion criteria applied).
Full pooled mode (`apply_sample_exclusions = FALSE`) yields ~126,431 rows.

**Source cycles pooled:**

| Cycle | CCHS label | Raw rows | After exclusions |
|-------|-----------|----------|-----------------|
| `cycle = 0` | CCHS 2010–2011 | ~62,909 | 32,621 |
| `cycle = 1` | CCHS 2013–2014 | ~63,522 | 31,222 |

**Survey weight pooling (Statistics Canada guideline):**

```
wts_m_pooled   = wts_m / 2      # for each respondent
bsw001_pooled  = bsw001 / 2     # same rule applied to all 500 bootstrap weights
```

`wts_m_original` is retained alongside `wts_m_pooled` for verification.

---

## Reference Diagnostics (`cchs_analytical`, default mode)

Verified from actual run on 2026-03-20. Ten INFERRED white-list variables were absent from both
CCHS PUMF cycles (`ccc_300`, `ccc_185`, `dhhdglvg`, `dhhdfc5`, `dhhdfc11`, `dhhdfc12p`, `sdcdgstud`,
`alcdgtyp`, `hwtdgbmi`, `noc_31`); five of these are added as NA columns for factor recode
compatibility; two CCC conditions and three household child-count variables are entirely absent.
Bootstrap weights (`bsw*`) were also absent. Diagnostics reflect the current data files.

| Diagnostic | Actual value |
|------------|-------------|
| Unweighted sample size | 63,843 |
| Weighted mean `days_absent_total` | ≈ 1.25 |
| Weighted variance `days_absent_total` | ≈ 15.4 |
| Dispersion (variance / mean) | > 1 → overdispersion → negative binomial recommended |
| % zeros in `days_absent_total` (unweighted) | ≈ 70.5% |
| Maximum `days_absent_total` | 63 (observed); 90 = enforced cap |
| Out-of-range values set to NA | 2,448 respondents |

---

## cchs_analytical — Variable Inventory

### Outcome Variables

| Column | Type | Description |
|--------|------|-------------|
| `days_absent_total` | numeric | Primary outcome: row-wise sum of 8 LOP components (NA-safe; all-NA rows → 0) |
| `days_absent_chronic` | numeric | Sensitivity outcome: `lopg040` only (days absent due to own chronic condition) |
| `outcome_all_na` | logical | `TRUE` if all 8 LOP variables were `NA` before summing |

**Source LOP variables (retained raw for transparency):**

| Column | Description |
|--------|-------------|
| `lopg040` | Days absent — own chronic condition |
| `lopg070` | Days absent — injury |
| `lopg082` | Days absent — cold |
| `lopg083` | Days absent — flu / influenza |
| `lopg084` | Days absent — stomach flu (gastroenteritis) |
| `lopg085` | Days absent — respiratory infection |
| `lopg086` | Days absent — other infectious disease |
| `lopg100` | Days absent — other physical / mental health reason |

Valid range: 0–90 days. Values outside this range are set to `NA` with a warning.

---

### Chronic Condition Variables (17 binary factors)

All variables coded: `"Yes"` / `"No"` (factor). Special numeric codes (6, 7, 8, 9, 96–99) → `NA`.
Two conditions requested in §2.2 (`ccc_300` — other mental illness; `ccc_185` — digestive disease)
are suppressed in the PUMF and entirely absent from this dataset.

| Column | Condition |
|--------|-----------|
| `cc_asthma` | Asthma |
| `cc_fibromyalgia` | Fibromyalgia |
| `cc_arthritis` | Arthritis (excluding fibromyalgia) |
| `cc_back_problems` | Back problems (excluding fibromyalgia/arthritis) |
| `cc_hypertension` | Hypertension (high blood pressure) |
| `cc_migraine` | Migraine headaches |
| `cc_copd` | COPD / chronic bronchitis / emphysema |
| `cc_diabetes` | Diabetes |
| `cc_heart_disease` | Heart disease |
| `cc_cancer` | Cancer (any type) |
| `cc_ulcer` | Intestinal / stomach ulcer |
| `cc_stroke` | Effects of stroke |
| `cc_bowel_disorder` | Bowel disorder (Crohn's disease / colitis / IBS) |
| `cc_fibromyalgia` | Fibromyalgia |
| `cc_chronic_fatigue` | Chronic fatigue syndrome (CFS) |
| `cc_chemical_sensitiv` | Multiple chemical sensitivities (MCS) |
| `cc_mood_disorder` | Mood disorder (depression / bipolar / mania / dysthymia) |
| `cc_anxiety_disorder` | Anxiety disorder (phobia / OCD / panic disorder) |

Source CCHS variables (17 found): `ccc_031` (asthma), `ccc_041` (fibromyalgia), `ccc_051` (arthritis),
`ccc_061` (back problems), `ccc_071` (hypertension), `ccc_081` (migraine), `ccc_091` (COPD),
`ccc_101` (diabetes), `ccc_121` (heart disease), `ccc_131` (cancer), `ccc_141` (ulcer),
`ccc_151` (stroke), `ccc_171` (bowel disorder), `ccc_251` (chronic fatigue), `ccc_261` (chemical
sensitivities), `ccc_280` (mood disorder), `ccc_290` (anxiety disorder).
Two absent from PUMF: `ccc_300` (other mental illness), `ccc_185` (digestive disease).

---

### Demographic / Predisposing Factors

| Column | Type | Levels / Notes |
|--------|------|----------------|
| `age_group` | ordered factor | `"15-24"` < `"25-54"` < `"55-75"` |
| `sex` | factor | `"Male"`, `"Female"` |
| `marital_status` | ordered factor | `"Single"` < `"Married"` < `"Common-law"` < `"Widowed-Div-Sep"` |
| `education` | ordered factor | `"Less than secondary"` < `"Secondary graduate"` < `"Some post-secondary"` < `"Post-secondary graduate"` |
| `immigration_status` | factor | `"Non-immigrant"`, `"Immigrant"`, `"Non-permanent resident"` |
| `visible_minority` | factor | `"White"`, `"Visible minority"` |
| `homeownership` | factor | `"Owner"`, `"Renter/other"` — **ALL-NA** in current output (`dhhdglvg` absent from PUMF; correct name is `dhhglvg`) |
| `student_status` | factor | `"Not a student"`, `"Part-time student"`, `"Full-time student"` — **ALL-NA** (`sdcdgstud` absent from PUMF) |
| `dhhdfc5` | — | **ABSENT** from dataset; `dhhdfc5` not in PUMF (correct name: `dhhgle5`) |
| `dhhdfc11` | — | **ABSENT** from dataset; `dhhdfc11` not in PUMF (correct name: `dhhg611`) |
| `dhhdfc12p` | — | **ABSENT** from dataset; no PUMF equivalent found |
| `dhhdghsz` | integer / numeric | Household size (number of persons; raw, continuous) |

Source variables: `dhhgage`, `dhh_sex`, `dhhgms`, `edudh04`, `sdcfimm`, `sdcdgcb` (→ `sdcgcgt`),
`dhhdglvg` (absent), `sdcdgstud` (absent), `dhhdghsz` (→ `dhhghsz`).

---

### Health-System / Facilitating Factors

| Column | Type | Levels / Notes |
|--------|------|----------------|
| `income_5cat` | ordered factor | `"< $20k"` < `"$20k-$39k"` < `"$40k-$59k"` < `"$60k-$79k"` < `"$80k+"` |
| `has_family_doctor` | factor | `"Yes"`, `"No"` |
| `employment_type` | factor | `"Employee"`, `"Self-employed"`, `"Unpaid family worker"` |
| `work_schedule` | factor | `"Full-time"`, `"Part-time"` |
| `alcohol_type` | ordered factor | `"Never drinker"` < `"Former drinker"` < `"Occasional drinker"` < `"Regular drinker"` — **ALL-NA** (`alcdgtyp` absent from PUMF; correct name: `alcdttm`) |
| `smoking_status` | ordered factor | `"Never"` < `"Former"` < `"Occasional"` < `"Daily"` |
| `bmi_category` | ordered factor | `"Underweight"` < `"Normal weight"` < `"Overweight"` < `"Obese"` — **ALL-NA** (`hwtdgbmi` absent from PUMF; correct name: `hwtgisw`) |
| `physical_activity` | ordered factor | `"Active"` < `"Moderately active"` < `"Inactive"` |
| `job_stress` | ordered factor | `"Not at all stressful"` < `"Not very stressful"` < `"A bit stressful"` < `"Quite a bit stressful"` < `"Extremely stressful"` |
| `occupation_category` | factor | 10 levels defined (Management → Manufacturing/Utilities) — **ALL-NA** (`noc_31` absent from PUMF; correct variable is `lbsgsoc`, 5-category) |
| `geodgprv` | integer | Province / territory of residence (raw code; 10–13 categories) |
| `fvcdgtot` | numeric | Total daily fruit & vegetable servings (raw, continuous) |

Source variables: `incdghh` (→ `incghh`), `geodgprv` (→ `geogprv`), `hcu_1aa`, `lbfdghp` (→ `lbsg31`),
`lbfdgft` (→ `lbsdpft`), `fvcdgtot` (→ `fvcgtot`), `alcdgtyp` (absent), `smkdsty`, `hwtdgbmi` (absent),
`pacdpai`, `gen_07`, `noc_31` (absent).

---

### Health Status / Needs Factors

| Column | Type | Levels / Notes |
|--------|------|----------------|
| `self_health_general` | ordered factor | `"Excellent"` < `"Very good"` < `"Good"` < `"Fair"` < `"Poor"` |
| `self_health_mental` | ordered factor | Same 5-level scale as `self_health_general` |
| `health_vs_lastyear` | ordered factor | `"Much better"` < `"Somewhat better"` < `"About the same"` < `"Somewhat worse"` < `"Much worse"` |
| `activity_limitation` | factor | `"Yes"`, `"No"` |
| `injury_past_year` | factor | `"Yes"`, `"No"` |

Source variables: `gen_01`, `gen_02a`, `gen_09`, `rac_1`, `inj_01`.

---

### Survey Design Variables

| Column | Type | Description |
|--------|------|-------------|
| `wts_m_pooled` | numeric | Master survey weight ÷ 2 (pooling adjustment) |
| `wts_m_original` | numeric | Raw master survey weight (retained for verification) |
| `geodpmf` | integer / character | Health region / strata identifier (raw from CCHS) |
| `cycle` | integer | Survey cycle: `0L` = 2010–2011, `1L` = 2013–2014 |
| `cycle_f` | factor | `"CCHS 2010-2011"`, `"CCHS 2013-2014"` |
| `bsw001`–`bsw500` | numeric | Bootstrap weights (500 columns); each divided by 2 for pooling |

---

### Sample Construction Variables (retained raw)

| Column | Type | Description |
|--------|------|-------------|
| `lop_015` | integer | Currently employed in past 3 months (1=Yes, 2=No) |
| `dhhgage` | integer | Age group code (1–16) |
| `adm_prx` | integer | Proxy respondent flag (1=Proxy, 2=Not proxy) |
| `adm_rno` | integer | Respondent sequence number (deduplication check; if present) |

---

## sample_flow — Exclusion Audit Table

Records the step-by-step effect of §3.1 inclusion/exclusion criteria.
Always 5 rows (6 if `apply_completeness_exclusion = TRUE`).

**Actual values from 2026-03-20 run:**

| Step | Description | n_remaining | n_excluded | pct_remaining |
|------|-------------|------------:|-----------:|--------------:|
| `1_start` | Starting pool (both CCHS cycles pooled) | 126,431 | 0 | 100.0% |
| `2_after_age_15_75` | Exclude respondents outside age 15–75 | 112,352 | 14,079 | 88.9% |
| `3_after_employed` | Exclude respondents not employed (past 3 months) | 64,248 | 48,104 | 50.8% |
| `4_after_no_proxy` | Exclude proxy respondents | 64,248 | 0 | 50.8% |
| `5_after_complete_outcome` | Exclude respondents with missing outcome | 63,843 | 405 | 50.5% |

**Column schema:**

| Column | Type | Description |
|--------|------|-------------|
| `step` | character | Step label: `"1_start"`, `"2_after_age_15_75"`, `"3_after_employed"`, `"4_after_no_proxy"`, `"5_after_complete_outcome"` |
| `description` | character | Human-readable criterion (or "No exclusion applied" when flag is `FALSE`) |
| `n_remaining` | integer | Sample count after this step |
| `n_excluded` | integer | Records removed in this step |
| `pct_remaining` | numeric | Percentage of starting pool remaining |

---

## Missing Value Handling

Special CCHS response codes recoded to `NA` throughout all factor variables:

| Codes | Meaning |
|-------|---------|
| 6, 7, 8, 9 | Not applicable / Don't know / Refusal / Not stated (single-digit) |
| 96, 97, 98, 99 | Same meanings (two-digit) |

Original SPSS value labels are stripped during Ferry import (`haven::zap_labels()`).
Numeric raw values are available only in the ferry staging database (`cchs-1.sqlite`).

---

## Variable Harmonization (Cross-Cycle Aliases)

Some variables changed names between the 2010–2011 and 2013–2014 PUMF files.
Ellis maps known aliases to canonical names before white-listing:

| Canonical name | Aliases tried | Affected cycles |
|----------------|--------------|----------------|
| `edudh04` | `edudr04` | Both cycles |
| `sdcdgcb` | `sdcgcgt` | Both cycles |
| `geodgprv` | `geogprv` | Both cycles |
| `hcu_1aa` | `hcu_1a`, `hcudgmd` | Both cycles |
| `lbfdghp` | `lbsg31` | Both cycles |
| `lbfdgft` | `lbsdpft` | Both cycles |
| `incdghh` | `incghh` | Both cycles |
| `fvcdgtot` | `fvcgtot` | Both cycles |
| `dhhdghsz` | `dhhghsz` | Both cycles |
| `gen_02a` | `gen_02b` | Both cycles |
| `inj_01` | `injdgyrs` | Both cycles |

If a variable is still not found after alias resolution, it is dropped with a warning (INFERRED tier).

---

## Notes and Limitations

- **10 INFERRED variables absent from both CCHS PUMF cycles** (as of 2026-03-20 run):
  `ccc_300`, `ccc_185`, `dhhdglvg`, `dhhdfc5`, `dhhdfc11`, `dhhdfc12p`, `sdcdgstud`,
  `alcdgtyp`, `hwtdgbmi`, `noc_31`. Of these, 5 (`alcdgtyp`, `hwtdgbmi`, `dhhdglvg`,
  `sdcdgstud`, `noc_31`) are added as NA columns so that factor recode blocks do not error;
  their output factor columns (`alcohol_type`, `bmi_category`, `homeownership`,
  `student_status`, `occupation_category`) are all-NA. The remaining 5 (`ccc_300`, `ccc_185`,
  `dhhdfc5`, `dhhdfc11`, `dhhdfc12p`) are entirely absent from the dataset.
- **Bootstrap weights absent**: No `bsw*` columns found in either CCHS PUMF cycle.
  Bootstrap weights are required for correct variance estimation with the survey package.
  They are distributed as a separate supplemental file by Statistics Canada and were not
  bundled with the PUMF `.sav` files in this project.
- **LOP module availability**: Not all provinces/territories include the LOP module in all cycles.
  Verify `geodpmf × cycle` cross-tabulation for geographic gaps before provincial models.
- **DHHGAGE boundary**: Age code 15 covers 75–79 years; the dataset cannot distinguish exactly
  age 75 from 76–79 within this category (PUMF regrouping).
- **Education cross-cycle label discrepancy**: `EDUDH04` / `EDUDR04` code 3 is labelled
  "Other post-secondary" in 2010 and "Some post-secondary" in 2014. The recode adopts
  "Some post-secondary" as the common label. See `cchs_value_label_diffs.csv`.
- **LBSGSOC cross-cycle label discrepancy**: The 5-category occupation variable uses
  descriptive labels in 2010 (e.g. "MANAG./ART, EDUC") and generic labels in 2014
  ("GROUP 1" – "GROUP 5"). Numeric codes 1–5 are consistent across cycles.
- **CCC conditions**: 2 of 19 requested conditions (`ccc_300` — other mental illness;
  `ccc_185` — digestive disease) are suppressed in the PUMF for confidentiality.
  Thesis Appendix 3 may specify acceptable substitutes.

