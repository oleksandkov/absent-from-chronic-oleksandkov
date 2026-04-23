# INPUT Manifest

Describes the raw input datasets consumed by the data pipeline **before** Ferry/Ellis processing.  
Updated: 2026-03-20

---

## Summary

| File | Cycle | Rows (approx.) | Columns (approx.) | Received |
|------|-------|---------------:|------------------:|----------|
| `CCHS2010_LOP.sav` | 2010–2011 | 62,909 | 1,500+ | 2026-02-19 |
| `CCHS_2014_EN_PUMF.sav` | 2013–2014 | 63,522 | 1,500+ | 2026-02-19 |

---

## Source File Details

### File 1 — CCHS 2010–2011

| Attribute | Value |
|-----------|-------|
| **Filename** | `CCHS2010_LOP.sav` |
| **Survey cycle** | 2010–2011 Combined |
| **Survey name** | Canadian Community Health Survey (CCHS) |
| **Administrator** | Statistics Canada |
| **Data type** | SPSS system file (.sav) with value/variable labels |
| **Location** | `./data-private/raw/2026-02-19/CCHS2010_LOP.sav` |
| **Approximate rows** | 62,909 |
| **Approximate columns** | 1,500+ |
| **Received date** | 2026-02-19 |
| **Access type** | PUMF (Public Use Microdata File) |
| **LOP module** | Yes — includes "Length of Physical Disability" (LOP) variables (`LOPG*`) |

### File 2 — CCHS 2013–2014

| Attribute | Value |
|-----------|-------|
| **Filename** | `CCHS_2014_EN_PUMF.sav` |
| **Survey cycle** | 2013–2014 Combined |
| **Survey name** | Canadian Community Health Survey (CCHS) |
| **Administrator** | Statistics Canada |
| **Data type** | SPSS system file (.sav) with value/variable labels |
| **Location** | `./data-private/raw/2026-02-19/CCHS_2014_EN_PUMF.sav` |
| **Approximate rows** | 63,522 |
| **Approximate columns** | 1,500+ |
| **Received date** | 2026-02-19 |
| **Access type** | PUMF (Public Use Microdata File) |
| **LOP module** | Yes — includes `LOPG*` absenteeism variables |

---

## Variable Coverage

The Ferry lane (`1-ferry.R`) imports **all columns** from both files with zero semantic transformation.

The Ellis lane (`2-ellis.R`) applies a **white-list** selecting only variables relevant to the
work-absenteeism analysis. White-listed variables fall into two tiers:

Current Lane 2 sample mode:
- Default: **exclusion criteria applied** (`apply_sample_exclusions = TRUE`) — ~64,141 respondents
- Optional full-pooled mode: exclusions disabled (`apply_sample_exclusions = FALSE`) — 126,431 respondents

### Tier 1: CONFIRMED (error if missing)
Variables verified against the PDF data dictionaries and the study's
`required-variables-and-sample.md` specification.

| CCHS Variable | Description | Source Module |
|---------------|-------------|---------------|
| `LOPG040` | Days absent — own chronic condition (primary outcome; also sensitivity outcome) | LOP |
| `LOPG070` | Days absent — injury | LOP |
| `LOPG082` | Days absent — cold | LOP |
| `LOPG083` | Days absent — flu / influenza | LOP |
| `LOPG084` | Days absent — stomach flu (gastroenteritis) | LOP |
| `LOPG085` | Days absent — respiratory infection | LOP |
| `LOPG086` | Days absent — other infectious disease | LOP |
| `LOPG100` | Days absent — other physical / mental health reason | LOP |
| `LOP_015`  | Currently employed in past 3 months (1=Yes; inclusion criterion) | LOP |
| `DHHGAGE`  | Age group (coded 1–16; inclusion: codes 2–15, approx. age 15–75) | DHH |
| `ADM_PRX`  | Proxy respondent flag (1=Proxy; exclusion criterion) | ADM |
| `GEODPMF`  | Health region / strata identifier | GEO |
| `WTS_M`    | Survey weight (master weight; labelled WGHT_FINAL in stat instructions) | WTS |

### Tier 2: INFERRED (warning if missing — graceful drop)
Variables inferred from standard CCHS PUMF naming conventions.  
**Verify exact names against the data dictionary PDFs** if any are missing after running `2-ellis.R`.

- **CCC module (19 vars):** `CCC_015` (asthma), `CCC_031` (arthritis), `CCC_051` (back problems),
  `CCC_071` (hypertension), `CCC_081` (migraine), `CCC_091` (COPD), `CCC_101` (diabetes),
  `CCC_121` (heart disease), `CCC_131` (cancer), `CCC_141` (ulcer), `CCC_151` (stroke),
  `CCC_171` (bowel disorder), `CCC_011` (fibromyalgia), `CCC_041` (chronic fatigue),
  `CCC_061` (chemical sensitivities), `CCC_280` (mood disorder), `CCC_290` (anxiety disorder),
  `CCC_300` (other mental illness), `CCC_185` (digestive disease)
- **Predisposing (11 vars):** `DHH_SEX`, `DHHGMS`, `DHHDGHSZ`, `EDUDH04`, `SDCFIMM`,
  `SDCDGCB`, `DHHDGLVG`, `DHHDFC5`, `DHHDFC11`, `DHHDFC12P`, `SDCDGSTUD`
- **Facilitating (12 vars):** `INCDGHH`, `GEODGPRV`, `HCU_1AA`, `LBFDGHP`, `LBFDGFT`, `FVCDGTOT`,
  `ALCDGTYP`, `SMKDSTY`, `HWTDGBMI`, `PACDPAI`, `GEN_07`, `NOC_31`
- **Needs (5 vars):** `GEN_01`, `GEN_02A`, `GEN_09`, `RAC_1`, `INJ_01`
- **ID (1 var):** `ADM_RNO`
- **Bootstrap weights (500 vars):** `BSW001`–`BSW500` (pattern `^BSW`)

---

## Known Limitations

- **Variable name differences between cycles**: Some CCHS variables change names slightly
  between cycles. The Ellis lane includes a harmonization step; any harmonization decisions
  are documented in `manipulation/2-ellis.R` under `# ---- SECTION 1 / harmonize`.
- **DHHGAGE coding**: Age codes 1–16+ vary by cycle. The Ellis exclusion filter uses
  `dhhgage %in% 2:15` (approximately age 15–75). Verify these codes against the PDF
  data dictionaries for each cycle.
- **Missing value codes**: Special NA codes (6, 7, 8, 9, 96, 97, 98, 99) are recoded to `NA`
  throughout by the Ellis lane. Original SPSS codes are stripped during Ferry import.
- **LOP module availability**: Not all provinces include the LOP module in both cycles.
  Check `GEODPMF` × `cycle` cross-tabulation for potential geographic exclusions.

---

## Pipeline Traceability

```
CCHS2010_LOP.sav          ──┐
                             ├──► 1-ferry.R ──► cchs-1.sqlite (cchs_2010_raw, cchs_2014_raw)
CCHS_2014_EN_PUMF.sav     ──┘              └──► cchs-1-raw/*.parquet (backup)
                                                      │
                                                      ▼
                                             2-ellis.R (white-list + recode)
                                                      │
                                            ┌─────────┴────────────┐
                                            ▼                       ▼
                                   cchs-2.sqlite             cchs-2-tables/
                                  (cchs_analytical,          cchs_analytical.parquet
                                   sample_flow)              sample_flow.parquet
                                                      │
                                                      ▼
                                             3-ellis.R (clarity + splits)
                                                      │
                                            ┌─────────┴────────────┐
                                            ▼                       ▼
                                   cchs-3.sqlite             cchs-3-tables/
                                  (cchs_analytical,          cchs_analytical.parquet
                                   cchs_employed,            cchs_employed.parquet
                                   cchs_unemployed,          cchs_unemployed.parquet
                                   sample_flow,              sample_flow.parquet
                                   data_dictionary)          data_dictionary.parquet
```

---

*This manifest is updated manually when new raw data files are received.*


