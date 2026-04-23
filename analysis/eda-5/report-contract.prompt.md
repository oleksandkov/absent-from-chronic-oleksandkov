# Report Contract: eda-5

## Type
EDA

## Date
2026-03-22 | Last updated: 2026-03-22

## Status
active

## Mission
Provide an alternative take on Section 4.1 of the statistical instructions by decomposing
the primary outcome variable into its 8 constituent LOP reason categories. Where eda-3
examined the total and the chronic-only sensitivity outcome side-by-side, this EDA looks
inside the total: prevalence of each reason, relative contribution to the overall burden,
and co-occurrence across reason categories.

## Data Sources

### Primary
- `data-private/derived/cchs-2-tables/cchs_analytical.parquet` — respondent-level analytical
  dataset with all 8 raw LOP component columns (`lopg040`, `lopg070`, `lopg082`–`lopg086`,
  `lopg100`) retained alongside the derived `days_absent_total` and `days_absent_chronic`

### Supporting
- `data-public/metadata/CACHE-manifest.md` — variable definitions and LOP component mapping
- `data-private/raw/2026-02-19/stats_instructions_v3.md` — Section 4.1 construction logic
- `analysis/eda-3/eda-3.qmd` — sibling EDA (Q4-1, Q4-2) for context

## Research Questions
1. What is the weighted prevalence of each of the 8 LOP reason categories (what proportion
   of workers report ≥1 absent day for each reason)?
2. How much does each LOP component contribute to the weighted mean of the primary outcome
   (days_absent_total) in absolute and relative terms?
3. How many reason categories does a typical respondent report simultaneously, and what is
   the co-occurrence pattern across reason pairs?

## Target Graph Families
- g1: Prevalence bar chart — % weighted respondents reporting ≥1 day per LOP reason category,
  ordered by prevalence, with error bars (bootstrap SE)
- g2: Contribution plot — weighted mean days per reason category (stacked or dot strip),
  illustrating the absolute and relative share of each component in the total outcome
- g3: Co-occurrence count distribution — histogram of how many reason categories each
  respondent reported (0, 1, 2, 3, …), plus a tile heatmap of pairwise co-occurrence rates

## Output Format
HTML (interactive, code-fold, table of contents)

## Upstream EDAs
- eda-3: covers Q4-1 (primary vs. sensitivity outcome comparison) and Q4-2 (weighted
  distributional statistics). This EDA is complementary, not duplicative.

## Scope Boundaries
- Included: all 8 raw LOP variables (`lopg040`, `lopg070`, `lopg082`–`lopg086`, `lopg100`)
  and their derived sum (`days_absent_total`)
- Excluded: modeling, inferential tests, predictor variables — those belong to Section 5 EDAs
- Excluded: sensitivity outcome analysis (already in eda-3)
- Cycle-by-cycle breakdowns may be shown as a secondary facet, not the primary focus
