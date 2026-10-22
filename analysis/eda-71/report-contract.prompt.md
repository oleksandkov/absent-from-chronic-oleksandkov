# Report Contract: eda-71

## Type
EDA

## Date
2026-06-19 | Last updated: 2026-06-19

## Status
active

## Mission
Characterize the distributional properties of the LOP (Loss of Productivity) outcome
variables to build intuition for statistical models that use these measures as criterion
variables. Where EDA-5 decomposed the LOP components into prevalence and contribution
profiles, EDA-71 focuses on the **modeling-context lens**: frequency distribution shapes
across day-count bins, zero-inflation severity, heavy-tail structure of the composite
outcome, and inter-component correlation.

## Data Sources

### Primary
- `data-private/derived/cchs-2-tables/cchs_analytic.parquet` — pooled CCHS 2010/2014
  analytical sample (n = 63,843; all 8 LOP component columns + derived outcomes)

### Supporting
- `analysis/eda-5/` — LOP Component Decomposition (prevalence, contribution, co-occurrence)
- `analysis/data-primer-1/univariate-distributions.html` — Section 1.2: LOP Component Variables
- `data-public/metadata/CACHE-manifest.md` — variable definitions and sample flow
- `ai/project/glossary.md` — domain terminology

## Research Questions
1. How does each of the 8 LOP component variables distribute across positive day-count
   bins? How do the marginal-prevalence curves differ in height and tail decay? (g1)
2. What is the zero-inflation fraction for each LOP component, and how does it differ
   across the 8 reasons? (g2)
3. How does the composite outcome `days_absent_total` distribute — zero mass, right-tail
   shape, and key quantiles? (g3)
4. How correlated are the 8 LOP components, and what does this imply for using the total
   as a single model criterion? (g4)

## Target Graph Families
- g1: Frequency distribution curves — marginal prevalence at each positive day-count bin,
  one geom_line per LOP reason (IMPLEMENTED)
- g2: Zero-inflation profile — weighted % with zero days per component, ordered bar
- g3: Composite outcome distribution — annotated histogram of days_absent_total with
  zero-mass and key-quantile overlays
- g4: Component correlation matrix — tile heatmap of pairwise Spearman correlations

## Output Format
HTML (code-fold, interactive TOC)

## Upstream EDAs
N/A (EDA)

## Scope Boundaries

### Included
- All 8 LOP component variables (lopg040, lopg070, lopg082–lopg086, lopg100)
- Derived composite outcomes: days_absent_total, days_absent_chronic
- Pooled CCHS 2010–11 & 2013–14 analytical sample (n = 63,843)
- Weighted descriptive statistics (wts_m_pooled)

### Excluded
- Inferential analysis (regression modelling, hypothesis tests)
- Sub-group comparisons by chronic condition or demographics (addressed in eda-61–65)
- Bootstrap confidence intervals (not available for CCHS PUMF)

## Notes
- EDA-5 covers LOP component decomposition (prevalence, contribution, co-occurrence,
  data quality). EDA-71 builds on that with a modeling-context lens.
- The 405 respondents excluded at Ellis step 4 (element-wise LOP missingness) are not
  in the analytical sample; all LOP columns are complete in ds0.
- Bootstrap weights unavailable for CCHS 2010 and 2014 PUMF; all variance-sensitive
  summaries use wts_m_pooled only.
