# Report Contract: eda-64

## Type

EDA

## Date

2026-05-22 | Last updated: 2026-05-22

## Status

active

## Mission

Profile the 10 needs variables (perceived health status and functional limitations) from
the Andersen Behavioral Model framework. Examines distribution of each variable (weighted),
relationship to the primary outcome (`days_absent_total`), missing-data patterns, and
health gradient structure (perceived health × ADL stacking). ADL items are shown both
individually and as a collapsed functional limitation summary.

## Data Sources

### Primary

- `data-private/derived/cchs-2-tables/cchs_analytic.parquet` — respondent-level analytical
  dataset (n = 63,843) with needs factor variables, primary outcome
  `days_absent_total`, and pooled survey weight `wts_m_pooled`

### Supporting

- `data-public/metadata/CACHE-manifest.md` — variable definitions (§Predictor Variables → Needs)
- `analysis/data-primer-1/` — canonical data documentation
- `data-private/raw/2026-02-19/stats_instructions_v3.md` — §2.2 needs factors

## Research Questions

1. What is the weighted distribution of each needs variable in the employed population?
2. How does each needs variable relate to the primary outcome (`days_absent_total`) —
   mean days, median days, and zero-proportion?
3. What is the missing-data pattern across the 10 needs variables?
4. What health gradient patterns exist — perceived health × ADL functional limitation stacking?

## Target Graph Families

- g1: Variable distributions — weighted frequency bar charts, cycle-stratified
- g2: Outcome relationship — mean/median `days_absent_total` by variable level
- g3: Missing data profile — missingness tile across needs variables
- g4: Health gradient — perceived health × ADL stacking patterns

## Output Format

HTML with code-fold and table of contents (interactive exploration)

## Upstream EDAs

None (this is a first-pass variable profile)

## Scope Boundaries

- **Included**: Univariate profiles of all 10 needs variables; bivariate relationship
  with `days_absent_total`; ADL items shown individually AND as collapsed summary;
  health gradient analysis
- **Excluded**: Multivariate modelling, interaction effects with exposure, causal inference
