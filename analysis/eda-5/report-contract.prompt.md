# Report Contract: eda-5

## Type

EDA

## Date

2026-05-22 | Last updated: 2026-05-22

## Status

active

## Mission

Decompose the primary outcome variable (`days_absent_total`) into its 8 constituent LOP
reason categories, directly addressing Sections 4.1 (outcome construction) and 4.2
(distributional statistics) of the Project Proposal. Examines prevalence of each
reason category, relative contribution to the overall absent-day burden, co-occurrence
patterns across reason pairs, conditional intensity among reporters, and the structural
role of the chronic-condition component.

## Data Sources

### Primary

- `data-private/derived/cchs-2-tables/cchs_analytic.parquet` — respondent-level analytical
  dataset (n = 63,843) with all 8 raw LOP component columns (`lopg040`, `lopg070`,
  `lopg082`–`lopg086`, `lopg100`), derived outcomes `days_absent_total` and
  `days_absent_chronic`, and pooled survey weight `wts_m_pooled`

### Supporting

- `data-public/metadata/CACHE-manifest.md` — variable definitions and LOP component mapping
- `data-private/raw/2026-05-15/2026-05-15-transcript-clean.md` — Marc-André review session
  feedback (element-wise exclusion, bootstrap limitation, zero encoding)
- `analysis/data-primer-1/` — canonical data documentation (variable reference, grain proof)

## Research Questions

1. What is the weighted prevalence of each of the 8 LOP reason categories (what proportion
   of workers report ≥1 absent day for each reason)?
2. How much does each LOP component contribute to the weighted mean of `days_absent_total`
   in absolute and relative terms?
3. How many reason categories does a typical respondent report simultaneously, and what is
   the co-occurrence pattern across reason pairs?
4. Among reporters of a given reason, how many days does that reason typically produce
   (conditional intensity)?
5. What structural role does the chronic-condition component play among workers with any
   absence?
6. Are all 8 LOP components complete in the analytical sample, validating the element-wise
   exclusion step that removed 405 respondents with incomplete LOP data?
7. Within the respondents who missed at least one day, how does the group reporting chronic
   days compare with the collapsed non-chronic reference group — and does that split
   reconcile exactly with the outcome-group partition used in eda-72?

## Target Graph Families

- **G0** (§4.2): Orientation — zero vs non-zero split, then two ways of opening the
  non-zero group (by reason, then by outcome group)
  - g0: horizontal stacked bar (zero vs ≥1 day); the ≥1-day segment is a gradient strip
    in the day-range ramp, tying it to g01–g06 and g07–g09
  - g01: histogram of total missed days among non-zero group, coloured by day range
  - g02: day-range breakdown stacked bar (1–5, 6–10, 11–15, 16–30, 31+)
  - g03: faceted histograms of days absent by LOP reason, plus a Total facet
  - g04: same facets with free x and y scales
  - g05: reason-only facets, x fixed to 1–31 and y fixed to the observed maximum
  - g06: g05 structure with y as weighted days contributed per bin
  - g07: three-group outcome partition (No Days / Chronic Days / Non-Chronic Days),
    definitions and colours carried over unchanged from eda-72
  - g08: three-facet histogram — chronic, non-chronic, and the two combined
  - g09: chronic and non-chronic overlaid on within-group percentages
- **G1** (§4.1): Prevalence of each LOP reason — % of sample reporting ≥1 day per reason
  - g1: horizontal bar chart, ordered by weighted prevalence
  - g11: faceted by survey cycle (2010–2011 vs 2013–2014)
- **G2** (§4.1): Component contribution — weighted mean days per reason and relative share
  - g2: dot-strip lollipop, absolute contribution + % label
  - g21: stacked bar, relative shares of the component sum
- **G3** (§4.1): Co-occurrence — how many reasons per respondent; pairwise rates
  - g3: bar chart of reason-count distribution (0, 1, 2, …)
  - g31: tile heatmap of pairwise co-occurrence rates
- **G4** (§4.2): Conditional intensity — days produced per reason, among reporters only
  - g4: horizontal bar (weighted mean) + diamond (median), reporters only
  - g41: distribution of `days_absent_total` (non-zeros, log y-scale)
- **G5** (§4.2): Chronic condition's structural role among absent workers
  - g5: three-group classification bar (no chronic / mixed / entirely chronic)
  - g51: bubble chart — `days_absent_chronic` vs `days_absent_total` (both > 0)
- **G6** (§4.1 data quality): LOP component availability — zero vs positive vs missing
  - g6: 100% stacked bar per component confirming zero preserved, 0 missing
  - g61: weighted mean days per component (raw value, all respondents)

## Output Format

HTML (interactive, code-fold, table of contents)

## Upstream EDAs

- eda-1: style reference only
- eda-72: source of the three-group outcome partition (No Days / Chronic Days /
  Non-Chronic Days) and its colour convention; g07–g09 adopt both unchanged so the two
  reports interlock
- eda-3 (pending): will cover primary vs sensitivity outcome comparison and §4.1 weighted
  distributional statistics; this EDA complements that planned analysis

## Scope Boundaries

- **Included**: all 8 raw LOP variables, derived outcomes, element-wise exclusion validation
- **Excluded**: inferential tests, predictor variables (Section 5 territory)
- **Excluded**: sensitivity outcome side-by-side comparison (eda-3 territory when created)
- **Excluded**: bootstrap CI computation (not available for pre-2016 CCHS PUMF cycles;
  documented as known limitation per 2026-05-15 review session with Marc-André)

## Marc-André Feedback Addressed

| # | Feedback item | Where addressed |
|---|--------------|-----------------|
| 1 | Element-wise exclusion: verify that missing on one LOP component does not unnecessarily drop cases | G6: LOP availability chart; text note citing 405-row exclusion from CACHE manifest step 4 |
| 2 | Zero is a valid response — not NA | G6: g6 bar confirms 0 missing + shows zero-day share per component |
| 3 | Bootstrap weights not available for pre-2016 PUMF | Data Context callout citing CACHE-manifest bootstrap note |
| 4 | ~70% zero inflation is expected | G0: g0 stacked bar with zero vs non-zero share |
| 5 | Chronic condition accounts for greatest mean absent days | G5: g5 three-group bar; G2: g2 lollipop |
