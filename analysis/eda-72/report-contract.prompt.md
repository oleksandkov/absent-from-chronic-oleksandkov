# Report Contract: eda-72

## Type

EDA

## Date

2026-07-18 | Last updated: 2026-07-19

## Status

active

## Mission

Extend the EDA-71 chronic-absence outcome profile by examining how the non-student
predisposing variables from Section 3 of the Data Primer differ across the exhaustive,
mutually exclusive No Days, Chronic Days, and Non-Chronic Days groups. Preserve exact
positive-day support while testing a hybrid work-week scale and paired raw/weighted
composition displays.

## Data Sources

### Primary

- `data-private/derived/cchs-2-tables/cchs_analytic.parquet` - respondent-level pooled
  CCHS 2010/2014 analytical sample (n = 63,843), outcome variables, predisposing
  variables, and pooled survey weight

### Supporting

- `analysis/eda-71/` - G2 family outcome partition and exact chronic-day distributions
- `analysis/eda-71/eda-71.R` - `g23_chronic_vs_other_only_split_distribution`
- `analysis/data-primer-1/univariate-distributions.html` - Section 3 predisposing
  variable definitions and univariate distributions
- `analysis/eda-62/` - first-pass predisposing-variable profiles
- `data-public/metadata/CACHE-manifest.md` - source table, grain, weight, and outcome
  definitions

## Research Questions

1. How are the non-student predisposing variables distributed among the 45,006
   respondents in the No Days group?
2. How do exact chronic-day values map to work-week bins and to a hybrid scale that
   keeps days 1-5 exact before coarsening the tail?
3. How does the predisposing composition of the 3,626 respondents in the Chronic Days
   group differ from the 45,006 respondents in the No Days group?
4. Within the Chronic Days group, how does chronic-day intensity vary across
   predisposing-variable levels?
5. Which predisposing levels have visibly different exact chronic-day distributions?
6. How do the other two pairwise composition contrasts complete the three-group
  comparison matrix?
7. How do Chronic Days and Non-Chronic Days frequency distributions compare when
  days 1-5 remain exact and the tail is coarsened into work-week bins?

## Target Graph Families

- g0: No Days predisposition overview, including an A4-landscape browser/print design
- g1: Mapping of exact chronic days to weekly and first-week-exact coarsened scales,
  including Chronic and Non-Chronic positive-day frequency comparisons
- g2: Three-group composition, exhaustive pairwise contrasts, chronic-day intensity,
  and exact-day distributions with raw and weighted composition context

## Artifact Inventory

| ID | Type | Title | Purpose |
| --- | --- | --- | --- |
| g0 | Graph | Predisposition Profile Among Respondents With No Days | Compact overview of the largest outcome group |
| g01 | Graph | A4 Predisposition Profile Among Respondents With No Days | A4-landscape design for browser and print review |
| g1 | Graph | Mapping Exact Chronic Days to Coarser Work-Week Scales | Make all proposed coarsening rules explicit on the raw 1-31 support |
| g11 | Graph | Chronic-Day Distribution at Three Scales | Retain EDA-71 G22's left cohort partition while comparing exact, weekly, and hybrid chronic-day bars |
| g12 | Graph | Missed-Day Distributions on the Hybrid Work-Week Scale | Compare Chronic and Non-Chronic frequency bars with days 1-5 exact and the tail coarsened |
| g2 | Graph | Predisposition Composition: No Days and Chronic Days | Compare weighted within-group percentages |
| g20 | Graph | Predisposition Composition Across All Outcome Groups | Add Non-Chronic Days using the EDA-71 outcome palette |
| g21 | Graph | Chronic Minus No Days Composition Difference | Rank percentage-point contrasts by predictor level |
| g211 | Graph | Non-Chronic Minus No Days Composition Difference | Add the second pairwise contrast in the three-group matrix |
| g212 | Graph | Chronic Minus Non-Chronic Composition Difference | Complete the three pairwise contrasts among mutually exclusive groups |
| g22 | Graph | Mean Chronic Days by Predisposition Level | Add numeric chronic-day intensity within chronic reporters |
| g23 | Graph | Exact Chronic-Day Distribution by Predisposition Level | Continue EDA-71 g23 with predictor-stratified positive-day distributions |
| g24 | Graph | Chronic-Day Distribution and Predisposition Composition | Add raw respondent-count and weighted-share tiles that each sum to 100% within predictor |
| out1 | Output | Respondent Grain Proof | Verify one row per respondent identifier |

Numbering follows the requested analytic sequence. The user-requested `g0` family is
retained as the pre-analysis overview; `g1` holds the scale-design question because the
No Days cohort itself has no positive day values to coarsen.

## Output Format

HTML with code folding and a table of contents. Graphs g01, g2, g20, g21, g211, g212,
g22, g23, and g24 use A4 landscape dimensions (11.69 x 8.27 inches) for browser and
print review.

## Scope Boundaries

### Included

- Three mutually exclusive outcome labels: No Days, Chronic Days, and Non-Chronic Days
- All three pairwise comparisons among No Days (n = 45,006), Chronic Days
  (n = 3,626), and Non-Chronic Days (n = 15,211)
- All Section 3 predisposing variables available in the Ellis output except student status
- Raw and pooled-weight descriptive summaries
- Exact chronic days and two explicit coarsening schemes

### Excluded

- Student status, because it is suppressed and all-missing in the PUMF
- Inferential tests, regression models, causal claims, and confidence intervals
- Treating the coarsened work-week categories as literal elapsed calendar weeks

## Notes

- Group definitions are fixed as follows: No Days is `days_absent_total == 0`; Chronic
  Days is `days_absent_chronic > 0`; Non-Chronic Days is
  `days_absent_chronic == 0 & days_absent_total > 0`.
- Chronic Days may include respondents who also reported non-chronic absence days.
- Five reported workdays are treated as one work week only as a display coarsening rule.
  It is not a claim about questionnaire timing or employment schedule.