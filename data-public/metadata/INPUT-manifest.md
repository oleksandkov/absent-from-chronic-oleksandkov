# CCHS Pipeline — INPUT Manifest

This document describes the raw input data for the CCHS absenteeism pipeline.
It covers two SPSS PUMF files received from Statistics Canada and serves as
the reference for `1-ferry.R` (transport) and `0-extract-metadata.R` (labelling).

## Raw Input Summary

| Field | CCHS 2010-2011 | CCHS 2013-2014 |
|-------|----------------|----------------|
| File name | `CCHS2010_LOP.sav` | `CCHS_2014_EN_PUMF.sav` |
| Format | SPSS `.sav` (labelled) | SPSS `.sav` (labelled) |
| Received date | 2026-02-19 | 2026-02-19 |
| Path (config key) | `raw_data.cchs_2010` | `raw_data.cchs_2014` |
| Survey cycle | Annual component 2010-2011 | Annual component 2013-2014 |
| Source | Statistics Canada DLI / PUMF | Statistics Canada DLI / PUMF |
| Respondents (raw) | ~62,909 | ~63,522 |
| Variables | ~600+ | ~600+ |

## Companion Documentation

PDF documentation files (converted to `.txt` by `manipulation/0-extract-dictionary/0-extract-dictionary.py`):

| File | Derived text |
|------|-------------|
| `CCHS_2010_DataDictionary_Freqs-ver2.pdf` | `CCHS_2010_DataDictionary_Freqs-ver2.txt` |
| `CCHS_2014_DataDictionary_Freqs.pdf` | `CCHS_2014_DataDictionary_Freqs.txt` |
| `CCHS_2010_Record_Layout.pdf` | `CCHS_2010_Record_Layout.txt` |
| `CCHS_2014_Record_Layout.pdf` | `CCHS_2014_Record_Layout.txt` |
| `CCHS_2010_Derived_Variables.pdf` | `CCHS_2010_Derived_Variables.txt` |
| `CCHS_2014_Derived_Variables.pdf` | `CCHS_2014_Derived_Variables.txt` |

Extracted CSVs produced by `0-extract-metadata.R` and written to `data-private/derived/`:

- `codebook-variable-labels.csv` — variable name + label for both cycles
- `codebook-value-labels.csv` — value codes + labels for all labelled variables
- `codebook-cycle-comparison.csv` — variable-by-variable cross-cycle presence check
- `codebook-research-vars-check.csv` — spot-check of all research variables

## Modules Required

Both cycles include the following modules essential to this study:

| Module | Prefix | Purpose |
|--------|--------|---------|
| Loss of Productivity (LOP) | `LOP_`, `LOPG` | Outcome: days absent from work |
| Chronic Conditions (CCC) | `CCC_` | Primary exposure: 19 chronic conditions |
| General Health (GEN) | `GEN_` | Self-perceived health (needs domain) |
| Demographics (DHH) | `DHH`, `DHHG` | Age, sex, household, home ownership (predisposing) |
| Sociodemographics (SDC) | `SDCG` | Immigration, ethnicity (predisposing) |
| Income (INC) | `INCG` | Household income (facilitating) |
| Education (EDU) | `EDUD` | Education level (predisposing) |
| Health behaviours | `HWT`, `ALC`, `SMKG`, `PACD`, `FVCG` | BMI, alcohol, smoking, activity, diet |
| Activities of Daily Living (ADL) | `ADL_` | Functional limitations (needs domain) |
| Health Care Utilization (HCU) | `HCU_` | Regular medical doctor (facilitating) |
| Labour Force (LBS) | `LBSD` | Full/part-time status (facilitating) |
| Survey design | `WTS_M`, `ADM_PRX` | Master weight, proxy indicator |

LOP module inclusion is confirmed via the flag variable `DOLOP` (both cycles).

## Known Cross-Cycle Variable Name Differences

The following variables require alias resolution in `2-ellis.R`:

| Construct | CCHS 2010 name | CCHS 2014 name | Harmonized name |
|-----------|----------------|----------------|-----------------|
| Has regular family doctor | `ACC_50A` | `HCU_1AA` | `hcu_1aa_h` |
| Country of birth (grouped) | `SDCGCBG` | `SDCGCB13` | `sdcgcbg_h` |

All other white-listed research variables use identical names in both cycles
(confirmed by `0-extract-metadata.R` spot-check).

## Known Cross-Cycle Encoding Differences (Identical Names)

Some variables share a name across cycles but differ in label text or in how
not-stated responses are stored. These need no alias resolution, but they do
constrain how `2-ellis.R` may recode them.

| Variable | 2010-2011 | 2013-2014 | Consequence for Ellis |
|----------|-----------|-----------|-----------------------|
| `DHH_OWN` | Label "Dwelling - owned by a member of hhld"; `1 = YES`, `2 = NO`; not-stated is **SPSS system missing** (1,475 rows) | Label "Owned, Rented"; `1 = OWNER`, `2 = RENTED`; not-stated is **explicit codes 7 / 8 / 9** (1,809 rows) | Integer coding is identical, so no alias is needed. The recode must map only `1` and `2` and send everything else to `NA`, so that both missingness representations are caught. |

> **Verified 2026-08-01** by `scripts/qc-home-ownership.R`. `DHH_OWN` is present
> in both PUMF files, covers 99.74% of the final analytic table, and shows no
> optional-content aliasing (every province × cycle cell exceeds 99.3%). It
> satisfies the Project Proposal §2.2 "homeownership" requirement, which earlier
> documentation incorrectly reported as unavailable in the PUMF.

## Cross-Variable Dependencies

`immigration_status` in `2-ellis.R` requires **both** `SDCFIMM` and `SDCGRES`:

| Variable | Codes used | Role |
|----------|------------|------|
| `SDCFIMM` (Immigrant flag) | 1=YES, 2=NO | Identifies non-immigrants (SDCGRES=6 is stored as SPSS system missing → NA after Ferry) |
| `SDCGRES` (Length in Canada) | 1=0-9 yrs, 2=10+ yrs | Distinguishes recent from long-term among immigrants |

Both variables are in the `vars_inferred` (Tier 2) white-list in `2-ellis.R`.

## Survey Design Notes

- **Weights**: Master weight `WTS_M` is available in both PUMF files.
- **Bootstrap weights**: Not available in the PUMF files for these cycles
  (bootstrap weights for CCHS begin with the 2015 cycle). Variance estimation
  must use master weight only; complex survey design variables (strata, PSUs)
  are also not released in PUMF.
- **Pooling adjustment**: When combining two annual cycles, each respondent's
  master weight is divided by 2 per Statistics Canada guidance
  (`wts_m_pooled = wts_m / 2` in `2-ellis.R`).
- **Proxy interviews**: `ADM_PRX = 1` indicates a proxy respondent and must be
  excluded from the analytic sample.

## Analytic Scope

- **Population**: Canadian residents aged 15-75 who reported paid employment
  in the 3 months preceding the survey (LOP module respondents).
- **Initial exploration n**: 64,141 (unweighted), pooled from both cycles.
- **Study reference**: Blanchette M.-A., Koval O., Koval A. (2026)
  "Predictors of Work Absenteeism Associated with Chronic Conditions Among
  Canadian Workers."
