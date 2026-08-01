# Report Contract: eda-72

## Type

EDA

## Date

2026-07-18 | Last updated: 2026-07-31

## Status

active

## Mission

Establish two things that later results and group comparisons will be read against.
First, the three mutually exclusive, exhaustive outcome groups constructed to reason
about the numerical nature of the outcome: No Days, Chronic Days, Non-Chronic Days.
Second, the distribution of `days_absent` and what coarsening does to it, including the
correction that chronic days are a **component of** `days_absent_total` rather than a
parallel measure. The predisposing domain is then used as a worked illustration of how
any variable set can be evaluated against the three groups.

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

1. How do the three outcome groups partition the analytic sample, and how are they
   defined from the two day counts?
2. How does `days_absent_total` distribute among the 18,837 respondents who missed any
   work, and how do the exact, five-day, and hybrid scales change what a reader sees?
3. How does the chronic component sit inside that measure, in support and in shape?
4. How do the two positive-day groups compare when both are placed on the same measure?
5. How can a set of candidate variables be evaluated against the three groups, using
   the predisposing domain as the worked example?
6. Within the Chronic Days group, how does chronic-day intensity vary across
   predisposing-variable levels?
7. What does the largest outcome group, No Days, look like on the predisposing domain?

## Target Graph Families

- g1: The three outcome groups and the rescaling of `days_absent`, including the
  chronic component as a labelled subset
- g2: A worked illustration of evaluating a variable set against the three groups,
  using the predisposing domain
- g3: Reference profile of the No Days group (formerly numbered g0)

## Artifact Inventory

| ID | Type | Title | Purpose |
| --- | --- | --- | --- |
| g1 | Graph | Mapping Exact Days Absent to Coarser Work-Week Scales | Make every coarsening rule explicit on the raw 1-63 support of `days_absent_total` |
| g11 | Graph | Days Absent at Three Scales | Pair the three-group partition with `days_absent_total` at the exact, weekly, and hybrid scales (n = 18,837) |
| g111 | Graph | The Chronic Component at the Same Three Scales | Repeat the g11 construction on `days_absent_chronic` (n = 3,626) to expose the 0-31 ceiling |
| g12 | Graph | Days Absent by Outcome Group, Hybrid Scale | Compare Chronic and Non-Chronic groups on one common measure |
| g121 | Graph | Two Measures on the Same Respondents | Count the Chronic Days group twice, by total and by chronic component, to show the subset relation |
| g2 | Graph | Predisposition Composition: No Days and Chronic Days | Compare weighted within-group percentages |
| g20 | Graph | Predisposition Composition Across All Outcome Groups | Add Non-Chronic Days using the outcome palette |
| g21 | Graph | Chronic Minus No Days Composition Difference | Rank percentage-point contrasts by predictor level |
| g211 | Graph | Non-Chronic Minus No Days Composition Difference | Add the second pairwise contrast in the three-group matrix |
| g212 | Graph | Chronic Minus Non-Chronic Composition Difference | Complete the three pairwise contrasts among mutually exclusive groups |
| g22 | Graph | Mean Chronic Days by Predisposition Level | Add numeric chronic-day intensity within chronic reporters |
| g23 | Graph | Exact Chronic-Day Distribution by Predisposition Level | Predictor-stratified positive-day distributions |
| g24 | Graph | Chronic-Day Distribution and Predisposition Composition | Add raw respondent-count and weighted-share tiles that each sum to 100% within predictor |
| g3 | Graph | Predisposition Profile Among Respondents With No Days | Reference profile of the largest outcome group |
| g31 | Graph | A4 Predisposition Profile Among Respondents With No Days | A4-landscape design for browser and print review |
| out1 | Output | Respondent Grain Proof | Verify one row per respondent identifier |

**Retired IDs**: `g0` and `g01` were renamed to `g3` and `g31` on 2026-07-31 when the
No Days reference profile moved from first position to last. Per the project's artifact
rules, `g0` and `g01` are retired and are never reused.

Numbering is nominal within families; it records the order in which the analysis was
built, not a ranking of importance. The one exception is placement: g1 and g2 carry the
report's two subjects, and g3 is deliberately last because it is lookup material.

## Output Format

HTML with code folding and a table of contents. Graphs g11, g111, g12, g121, g2, g20,
g21, g211, g212, g22, g23, g24, and g31 use A4 landscape dimensions
(11.69 x 8.27 inches) for browser and print review. Graph g1 uses A4 width at reduced
height (11.69 x 4.6). Graph g3 uses the compact 8.5 x 5.5 default.

## Scope Boundaries

### Included

- Three mutually exclusive outcome labels: No Days, Chronic Days, and Non-Chronic Days
- All three pairwise comparisons among No Days (n = 45,006), Chronic Days
  (n = 3,626), and Non-Chronic Days (n = 15,211)
- The distribution of `days_absent_total` (support 0-63) and of its chronic component
  `days_absent_chronic` (support 0-31), shown separately and side by side
- All Section 3 predisposing variables available in the Ellis output except student status
- Raw and pooled-weight descriptive summaries
- Exact day values and two explicit coarsening schemes

### Excluded

- Student status, because it is suppressed and all-missing in the PUMF
- Inferential tests, regression models, causal claims, and confidence intervals
- Treating the coarsened work-week categories as literal elapsed calendar weeks
- Substantive conclusions from the g2 family; it is a methodological illustration

## Notes

- Group definitions are fixed as follows: No Days is `days_absent_total == 0`; Chronic
  Days is `days_absent_chronic > 0`; Non-Chronic Days is
  `days_absent_chronic == 0 & days_absent_total > 0`.
- Chronic Days may include respondents who also reported non-chronic absence days.
- **Measure correction (2026-07-31)**: earlier drafts labelled `days_absent_chronic`
  as "missed days" and compared it against `days_absent_total` across groups. Chronic
  days are a component of the total, not a parallel measure, and
  `days_absent_chronic <= days_absent_total` is asserted in `tweak-data-0`. The primary
  day-count displays (g11, g12) now use `days_absent_total`; the chronic component
  appears as labelled micro-variants (g111, g121).
- **Colour convention**: the outcome-group palette is grey (No Days), reddish brown
  (Chronic Days), dark blue (Non-Chronic Days). Sequential ramps inherit from it: a
  bluish ramp means the whole `days_absent` measure, a reddish ramp means the chronic
  component.
- Five reported workdays are treated as one work week only as a display coarsening rule.
  It is not a claim about questionnaire timing or employment schedule.