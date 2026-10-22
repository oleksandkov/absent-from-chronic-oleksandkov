# Report Contract: eda-63

## Type

EDA

## Date

2026-05-22 | Last updated: 2026-05-22

## Status

active

## Mission

Profile the 12 facilitating variables (health-system access and health behaviours) from
the Andersen Behavioral Model framework. Examines distribution of each variable (weighted),
relationship to the primary outcome (`days_absent_total`), missing-data patterns, and
behaviour clustering (smoking×BMI×activity co-profiles). Province is shown both at
granular (13 levels) and regional grouping levels.

## Data Sources

### Primary

- `data-private/derived/cchs-2-tables/cchs_analytic.parquet` — respondent-level analytical
  dataset (n = 63,843) with facilitating factor variables, primary outcome
  `days_absent_total`, and pooled survey weight `wts_m_pooled`

### Supporting

- `data-public/metadata/CACHE-manifest.md` — variable definitions (§Predictor Variables → Facilitating)
- `analysis/data-primer-1/` — canonical data documentation
- `data-private/raw/2026-02-19/stats_instructions_v3.md` — §2.2 facilitating factors

## Research Questions

1. What is the weighted distribution of each facilitating variable in the employed population?
2. How does each facilitating variable relate to the primary outcome (`days_absent_total`) —
   mean days, median days, and zero-proportion?
3. What is the missing-data pattern across the 12 facilitating variables?
4. What behaviour clustering patterns exist — smoking×BMI×activity co-profiles?

## Target Graph Families

- g1: Variable distributions — weighted frequency bar charts, cycle-stratified
- g2: Outcome relationship — mean/median `days_absent_total` by variable level
- g3: Missing data profile — missingness tile across facilitating variables
- g4: Behaviour clustering — smoking×BMI×physical activity cross-profiles

## Output Format

HTML with code-fold and table of contents (interactive exploration)

## Upstream EDAs

None (this is a first-pass variable profile)

## Scope Boundaries

- **Included**: Univariate profiles of all 12 facilitating variables; bivariate relationship
  with `days_absent_total`; province at both granular and regional level; behaviour co-profiles
- **Excluded**: Multivariate modelling, interaction effects with exposure, causal inference
