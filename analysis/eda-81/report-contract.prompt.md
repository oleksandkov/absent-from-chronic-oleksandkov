# Report Contract: eda-81

## Type

EDA

## Date

2026-08-02 | Last updated: 2026-08-02

## Status

active

## Mission

Make the four LASSO specifications of `model-1` and the bivariate series of `model-00`
readable to someone who did not build them. Two things are explained: what the
`lambda.1se` and `lambda.min` penalty rules actually do and why perceived health is
toggled on and off, and what each of the four models kept. Both are then joined in a
single three-panel artifact that reads left to right from unadjusted signal, through
selection, to adjusted estimate.

## Data Sources

### Primary

- `analysis/model-00/data-local/table-two.csv` — 98 level-wise bivariate rate ratios
  across 49 variables, series S1 (per-predictor complete case, `days_absent_total`)
- `analysis/model-1/data-local/selection-long.csv` — penalised coefficient per design
  column per specification, with the `retained` flag
- `analysis/model-1/data-local/nb-coefficients.csv` — stage-two negative binomial rate
  ratios and Wald intervals for all four specifications
- `analysis/model-1/data-local/fits/cv_exclude_perceived.rds` — `cv.glmnet` object for
  the predictor set without perceived health (Models 1 and 3)
- `analysis/model-1/data-local/fits/cv_include_perceived.rds` — `cv.glmnet` object for
  the predictor set with perceived health (Models 2 and 4)

### Supporting

- `scripts/modeling/candidate-registry.R` — the shared 52-row candidate registry,
  variable labels, Andersen domains, `perceived_health_vars`, `bivariate_only_vars`
- `analysis/model-1/model-1.qmd` — decision registry, specification table, review points
- `analysis/model-00/model-00.qmd` — bivariate protocol, decisions 8 and 9 on variance
- `analysis/data-primer-1/` — canonical variable definitions

## Research Questions

1. What does the LASSO penalty do to a coefficient, and what distinguishes the
   `lambda.min` rule from the `lambda.1se` rule in what they are willing to buy?
2. What is Poisson deviance, and what is a reader of `model-1` Graph g2 looking at
   when the curve rises on both sides of a minimum?
3. Why is perceived health toggled rather than simply included or excluded, and what
   does that toggle turn the four models into?
4. Which variables did each of the four specifications retain, and where do the four
   disagree?
5. For a variable retained by the primary model, how does its adjusted rate ratio
   compare with the unadjusted rate ratio the bivariate series reported for it?
6. Which variables carried a strong unadjusted signal and were nonetheless eliminated
   by the penalty?

## Target Graph Families

- **g0** — The penalty and the two rules that pick it. Cross-validated deviance,
  what the one-standard-error band is, what deviance measures, and how `lambda.1se`
  is read off the curve.
- **g1** — From unadjusted signal to selected model. The three-panel artifact aligning
  the bivariate forest, the selection grid, and the primary model's adjusted estimates
  on one shared row axis. **g11** extends this to five panels: the bivariate series plus
  all four specifications, dropping the dedicated selection column because in that
  layout the verdict is legible from the presence or absence of an estimate.

## Artifact Inventory

| ID | Type | Title | Purpose |
| --- | --- | --- | --- |
| t1 | Table | The Four Specifications as a 2 x 2 | State the two axes (predictor set, penalty rule) in plain language |
| t2 | Table | What Each Penalty Rule Cost and Bought | Lambda, CV deviance, and variables retained under each rule for both fits |
| g0 | Graph | Reading the Cross-Validation Curve | Annotated CV deviance curve with the SE band, both lambda marks, and the horizontal 1-SE read |
| g01 | Graph | The Same Curve, With the Price in Variables | Deviance over lambda stacked above variables-retained over lambda |
| g02 | Graph | What Poisson Deviance Counts | Per-respondent deviance contribution as a function of the predicted mean, for several observed day counts |
| g03 | Graph | Where the Standard Error Comes From | Zoom on the minimum showing the SE bars and the exact construction of `lambda.1se` |
| out1 | Output | Row Spine Join Audit | Confirm every bivariate level, selection variable, and NB term maps to exactly one spine row |
| g1 | Graph | Bivariate Signal, Selection, and the Primary Model | The three-panel artifact on a shared 119-row axis |
| g11 | Graph | Every Specification on One Row Axis | Five panels — bivariate plus all four specifications — with mirrored row labels at both outer edges |
| t3 | Table | The Primary Model's Term List | Model 1 adjusted rate ratios in readable form, with the bivariate estimate beside each |
| t4 | Table | Where Selection and Bivariate Signal Disagree | Variables significant bivariately but eliminated, and the reverse |

## Output Format

HTML

## Upstream Reports

- `analysis/model-00/` — bivariate series, Section 5.3
- `analysis/model-1/` — LASSO selection and negative binomial refit, Section 5.4

## Scope Boundaries

### Included

- Interpretation and exposition of results already produced by `model-00` and `model-1`
- Re-plotting of persisted artifacts under alignment constraints those reports did not impose

### Excluded

- **Any re-fitting.** This report reads persisted CSVs and RDS objects only. It does not
  touch the analytic parquet, does not call `glmnet`, and does not call `MASS::glm.nb`.
  Every number shown here traces to a file written by `model-00` or `model-1`.
- New model specifications, new predictors, new outcomes
- Bootstrap intervals — still data-blocked, see `model-1` decision 10

## Local Decisions

| # | Decision | Alternatives | Chosen | Rationale | Reversal |
| --- | --- | --- | --- | --- | --- |
| 1 | Row spine scope | Model 1 retentions only; union of all four models; every candidate level | Every candidate level | An exhaustive spine is what makes an empty right-hand cell meaningful: a blank row is a variable the primary model declined, not a variable omitted from the display. | `row_spine` in `g1-data-prep` |
| 2 | Reference rows | None; every variable; multi-level factors only | Multi-level factors only | A binary `No / Yes` variable already carries its reference in the row label, and adding 31 redundant rows would inflate the graph without adding information. A four-level factor has no readable geometry without its anchor at 1. | `reference_row_rule` in `declare-globals` |
| 3 | Middle panel geometry | Tall tile; vertical bracket; midpoint dot | Vertical bracket | The bracket spans exactly the level-rows the variable owns, so the reader can see at a glance that `household_size` occupies four rows and `cc_arthritis` occupies one. A tile would do the same but reads as a heat map and competes with the estimate panels for attention. | `g1-data-prep` bracket geometry |
| 4 | Panel assembly | `facet_grid` with free scales; `cowplot::plot_grid` | `cowplot::plot_grid` | The three panels need different x scales *and* different x types (continuous log rate ratio, discrete model label). One `facet_grid` cannot carry both. | `g1` chunk |
| 5 | Selection states | Two (kept / dropped); four (forced / retained / eliminated / not offered) | Four | `cchs_cycle_f` was exempt from the penalty and `dhhgl12` and the three perceived-health measures were never offered. Collapsing these into "dropped" would state something false. | `selection_states` in `declare-globals` |
| 6 | Fold-level detail in g03 | Draw the five individual fold curves; draw the stored standard error | The stored standard error | `model-1`'s `fit_lasso()` calls `cv.glmnet()` without `keep = TRUE`, so per-fold prediction matrices and the fold assignment were never stored. Drawing five curves would require re-running the cross-validation, which this report's scope forbids. The stored `cvsd` is the same quantity summarised. | Add `keep = TRUE` to `fit_lasso()` in `model-1.R` and re-run |
| 7 | g11 label placement | Left edge only; both outer edges | Both outer edges, right block left-aligned | At 20 inches wide and 119 rows tall, a single label block on the left forces the eye to travel the full width to identify a row in the Model 4 panel. Mirroring the block puts an anchor within a few centimetres of any point in the graph. | `show_labels` argument in `build_estimate_panel()` |
| 8 | g11 facet padding | Scale expansion; band geometry; both | Band geometry alone, expansion set to zero | The banding rectangles already extend half a row past each domain's outermost rows. Adding a scale expansion on top widened each facet's range past the neighbouring domain's outermost break, and `ggplot2` then drew that neighbour's label a second time at the foot of the block. Range is pinned by `g11_extent` so it does not depend on which variables happen to be banded. | `g11_y_expand` and `g11_extent` in `g11-data-prep` |

## Known Constraints

- **Per-fold curves are unavailable.** See local decision 6. If fold-level spaghetti is
  wanted, `model-1`'s `fit_lasso()` needs `keep = TRUE` and a re-run; eda-81 could then
  read `fit.preval` and `foldid` from the enlarged object without changing its own scope.
- **The two sources use different samples.** `model-00` series S1 is per-predictor
  complete case (up to n = 63,843); `model-1` uses the shared complete-case sample
  (n = 48,967). The left and right panels of g1 are therefore not estimated on identical
  rows. `model-00` series S2 exists precisely to quantify that gap and is referenced in
  the g1 caption rather than silently substituted.
- **The right panel's intervals ignore selection.** They are Wald intervals conditional
  on a term list chosen from the same data, so they are optimistic. `model-1` states this;
  eda-81 repeats it beside the graph rather than letting the panel imply otherwise.
