# Report Contract: eda-62

## Type

EDA

## Date

2026-05-22 | Last updated: 2026-05-22

## Status

active

## Mission

Profile the 11 predisposing variables (socio-demographic background) from the Andersen
Behavioral Model framework. Examines distribution of each variable (weighted), relationship
to the primary outcome (`days_absent_total`), missing-data patterns, and demographic
interaction structures (age×sex, education×immigration).

## Data Sources

### Primary

- `data-private/derived/cchs-2-tables/cchs_analytic.parquet` — respondent-level analytical
  dataset (n = 63,843) with predisposing factor variables, primary outcome
  `days_absent_total`, and pooled survey weight `wts_m_pooled`

### Supporting

- `data-public/metadata/CACHE-manifest.md` — variable definitions (§Predictor Variables → Predisposing)
- `analysis/data-primer-1/` — canonical data documentation
- `data-private/raw/2026-02-19/stats_instructions_v3.md` — §2.2 predisposing factors

## Research Questions

1. What is the weighted distribution of each predisposing variable in the employed population?
2. How does each predisposing variable relate to the primary outcome (`days_absent_total`) —
   mean days, median days, and zero-proportion?
3. What is the missing-data pattern across the 11 predisposing variables?
4. What demographic interactions exist — age×sex, education×immigration cross-tabs?

## Target Graph Families

- g1: Variable distributions — weighted frequency bar charts, cycle-stratified
- g2: Outcome relationship — mean/median `days_absent_total` by variable level
- g3: Missing data profile — missingness tile across predisposing variables
- g4: Demographic interactions — age×sex and education×immigration cross-tabs

## Output Format

HTML with code-fold and table of contents (interactive exploration)

## Upstream EDAs

None (this is a first-pass variable profile)

## Scope Boundaries

- **Included**: Univariate profiles of all 11 predisposing variables; bivariate relationship
  with `days_absent_total`; demographic cross-tabulation
- **Excluded**: Multivariate modelling, interaction effects with exposure, causal inference
