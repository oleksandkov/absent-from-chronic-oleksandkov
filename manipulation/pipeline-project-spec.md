# CCHS Absenteeism Pipeline Spec

This document holds the project-specific pipeline contract for the CCHS
absenteeism pipeline. It declares the numbered lane sequence, the source
systems, the canonical analysis-ready output, and the validation binding.

## Cohort Parameters

- **Study design**: pooled cross-sectional analysis of two CCHS annual components
- **Cycles pooled**: 2010-2011 (`CCHS2010_LOP.sav`) and 2013-2014 (`CCHS_2014_EN_PUMF.sav`)
- **Analytic unit**: one row per CCHS respondent
- **Cohort filters** (applied in `2-ellis.R`, audited in the `sample_flow` table):
  - Age 15–75 (`DHHGAGE` codes 2–15)
  - Employed in the past 3 months (`LOP_015 = 1`)
  - Non-proxy respondent (`ADM_PRX = 1`)
  - Complete outcome data (all 8 LOP components present)
- **Weight pooling rule**: `wts_m_pooled = wts_m / 2` (two cycles pooled)
- **Reference analytic n**: 64,141 (prior analysis); observed n: 63,843 (−298, within tolerance)

The authoritative source for these parameters is `manipulation/2-ellis.R`, with
human-validated summaries in `data-public/metadata/CACHE-manifest.md`. This
pipeline has no date-window or database-schema parameters; the cohort is defined
entirely by the sample-exclusion filters above.

## Config-Spec Accord Rule

`config.yml` and this file must remain in accord for all pipeline parameters.

The relevant `config.yml` keys are `default.raw_data.*` (raw input paths) and
`default.database.cchs.*` (Ferry and Ellis output locations). If conflicting
values are detected between `config.yml` and `manipulation/pipeline-project-spec.md`,
agents must stop and consult the user for a ruling before proceeding.

## Status

This specification describes an active, validated pipeline.

- All four numbered lanes are implemented in `manipulation/` and are the active sequence.
- The Test lane (`3-test-ellis-cache.R`) reports 24/24 passing as of the 2026-05-20 run.
- `cchs_analytic` is the canonical CACHE-manifest target because it is the
  analysis-ready respondent-level table consumed by downstream `analysis/`.

## Stable Components for This Project

The project-specific stable components are:

1. A Metadata lane that harvests SPSS variable/value labels into codebook CSVs.
2. A Ferry lane that transports both `.sav` files into the project cache with zero transformation.
3. An Ellis lane that harmonizes cross-cycle variables and builds the analysis-ready table.
4. A Test lane that verifies artifact existence, cross-format parity, and data quality.
5. INPUT and CACHE manifests aligned to the same canonical outputs.
6. A validator binding that points at the primary analysis-ready output.

## Numbered Lane Sequence

| Order | Path | Language | Role | Status |
| --- | --- | --- | --- | --- |
| 0 | `manipulation/0-extract-metadata.R` | R | Harvest SPSS variable/value labels into codebook CSVs | Validated |
| 1 | `manipulation/1-ferry.R` | R | Full transport of both `.sav` files into the SQLite cache (zap labels, zero transformation) | Validated |
| 2 | `manipulation/2-ellis.R` | R | Alias resolution, white-list enforcement, sample exclusion, weight pooling, outcome construction, factor recoding | Validated |
| 3 | `manipulation/3-test-ellis-cache.R` | R | Assert artifact existence, SQLite ↔ Parquet parity, data quality, and sample-flow integrity | Validated (24/24) |

## Source Systems

The pipeline relies on two SPSS PUMF files from Statistics Canada:

| File | Config key | Cycle |
| --- | --- | --- |
| `CCHS2010_LOP.sav` | `default.raw_data.cchs_2010` | Annual component 2010-2011 |
| `CCHS_2014_EN_PUMF.sav` | `default.raw_data.cchs_2014` | Annual component 2013-2014 |

The human-validated inventory belongs in `data-public/metadata/INPUT-manifest.md`.

## Canonical Outputs

The pipeline produces these core outputs under the paths defined in `config.yml`
(`default.database.cchs.*`):

- `cchs_analytic` — analysis-ready respondent-level table (canonical target)
- `sample_flow` — audit table recording the sample-exclusion sequence

Physical locations:

- SQLite: `data-private/derived/cchs-2.sqlite` (tables `cchs_analytic`, `sample_flow`)
- Parquet: `data-private/derived/cchs-2-tables/cchs_analytic.parquet`, `sample_flow.parquet`

For documentation and validation, treat `cchs_analytic` as the canonical target.

## Output Grain Expectations

- `cchs_analytic`: one row per CCHS respondent surviving the cohort filters
- `sample_flow`: one row per exclusion step, with monotonically non-increasing n

## Validation Rule

CACHE validation binds through `manipulation/pipeline-validation.dcf`, which must
always point at the currently canonical output object.

This is a local-first, file-based pipeline; the binding targets the Parquet
artifact (`target_type: parquet`, `target_path:
data-private/derived/cchs-2-tables/cchs_analytic.parquet`) rather than a database
object. If the project changes its primary output from `cchs_analytic` to another
table, update the binding first and then refresh `CACHE-manifest.md`.
