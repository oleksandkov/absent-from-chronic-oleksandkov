# Report Contract: eda-61

## Type

EDA

## Date

2026-05-22 | Last updated: 2026-05-22

## Status

active

## Mission

Profile the 17 chronic-condition exposure variables (`cc_*`) that form the primary
predictor domain in the Andersen Behavioral Model framework. Examines individual condition
prevalence (weighted), relationship of each condition to the primary outcome
(`days_absent_total`), missing-data patterns, and multimorbidity co-occurrence structure.

## Data Sources

### Primary

- `data-private/derived/cchs-2-tables/cchs_analytic.parquet` — respondent-level analytical
  dataset (n = 63,843) with 17 chronic-condition logical flags (`cc_*`), primary outcome
  `days_absent_total`, and pooled survey weight `wts_m_pooled`

### Supporting

- `data-public/metadata/CACHE-manifest.md` — variable definitions (§Predictor Variables → Needs)
- `analysis/data-primer-1/` — canonical data documentation
- `data-private/raw/2026-02-19/stats_instructions_v3.md` — §2.2 primary exposure, §4.3 bivariate

## Research Questions

1. What is the weighted prevalence of each chronic condition in the employed population?
2. How does each chronic condition relate to the primary outcome (`days_absent_total`) —
   mean days, median days, and zero-proportion?
3. What is the missing-data pattern across the 17 `cc_*` variables?
4. What is the multimorbidity structure — how many conditions do respondents report,
   and which condition pairs most frequently co-occur?

## Target Graph Families

- g1: Condition prevalence — weighted and unweighted bar charts, cycle-stratified
- g2: Outcome relationship — mean/median `days_absent_total` by condition presence
- g3: Missing data profile — missingness tile across all 17 conditions
- g4: Multimorbidity — condition-count distribution and pairwise co-occurrence matrix

## Output Format

HTML with code-fold and table of contents (interactive exploration)

## Upstream EDAs

None (this is a first-pass variable profile)

## Scope Boundaries

- **Included**: Univariate profiles of all 17 `cc_*` variables; bivariate relationship
  with `days_absent_total`; co-occurrence structure
- **Excluded**: Multivariate modelling, interaction effects, causal inference
