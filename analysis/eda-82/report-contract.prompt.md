# Report Contract: eda-82

## Type

EDA

## Date

2026-08-03 | Last updated: 2026-08-03

## Status

complete — `.R` and `.qmd` both render clean; artifact audit passed (all 12 IDs unique
and synchronized across chunk name, chunk label, and rendered title); published to
`_frontend-1` as **Story 2**.

## Mission

Bring the results of `model-1` (pooled selection), `model-2` (condition-specific models),
and `model-3` (sex-stratified models) into a single reading and state what the three
frames, taken together, license us to say about the role chronic conditions play in
predicting days of missed work. Where `eda-81` explained *how* the primary model was
built, `eda-82` asks *what it means* — and where the evidence runs out.

## Data Sources

### Primary

All sources are artifacts persisted by upstream reports. **This report fits nothing.**

- `analysis/model-1/data-local/nb-coefficients.csv` — pooled negative binomial rate
  ratios for all four specifications
- `analysis/model-1/data-local/model-comparison.csv` — in-sample fit for Models 1–4
- `analysis/model-1/data-local/cv-performance-summary.csv` — held-out fold performance
- `analysis/model-1/data-local/selection-matrix.csv` — retained variables by specification
- `analysis/model-2/data-local/nb-coefficients.csv` — condition-specific rate ratios,
  17 subgroups × 2 penalty rules
- `analysis/model-2/data-local/condition-inventory.csv` — subgroup size, prevalence,
  non-zero share, mean days
- `analysis/model-2/data-local/comorbidity-overlap.csv` — how far the 17 subgroups overlap
- `analysis/model-2/data-local/selection-counts.csv` — selection yield per condition
- `analysis/model-2/data-local/term-recurrence.csv` — how many subgroups retained each term
- `analysis/model-3/data-local/union-coefficients.csv` — both strata refit on the union
  term list, the only place a female and a male estimate are directly comparable
- `analysis/model-3/data-local/sex-heterogeneity.csv` — ratio of rate ratios with intervals
- `analysis/model-3/data-local/stratum-inventory.csv` — stratum size, non-zero share, mean days
- `analysis/model-3/data-local/model-comparison.csv` — in-sample fit for both strata
- `analysis/model-3/data-local/selection-matrix.csv` — retained variables by stratum

### Supporting

- `scripts/modeling/candidate-registry.R` — the shared 52-row candidate registry,
  variable labels, Andersen domains
- `analysis/eda-81/` — the mechanics of the penalty and the four specifications
- `analysis/model-1/data-local/decision-registry.csv` — decisions 1–19
- `analysis/model-2/data-local/decision-registry.csv` — decisions 20–30
- `analysis/model-3/data-local/decision-registry.csv` — decisions 31–40
- `analysis/data-primer-1/` — canonical variable definitions

## Research Questions

1. What survives all three cuts of the data? Which predictors are retained in the pooled
   model, in both sex strata, and across many condition subgroups — and which appear in
   only one frame?
2. How much of the variation in days absent do these models actually explain, and what
   does the gap between a 10-term and an 81-term model tell us about the ceiling of this
   design?
3. Does the condition-specific view add anything the pooled view does not already carry,
   or does subgroup selection mostly track subgroup size?
4. Where do the sexes genuinely differ in the association between a condition and days
   absent, as opposed to differing only in which terms the penalty happened to retain?
5. What substantive claim about chronic conditions and work absence can this body of
   evidence currently support, stated at the strength the evidence permits and no higher?
6. What would the next round buy? Which methodological alternatives to L1 selection, and
   which substantive extensions, would settle a question this round left open?

## Target Graph Families

- **g1** — The convergent core. Which terms are retained in the pooled primary model, in
  each sex stratum, and in how many of the 17 condition subgroups, on one row axis.
  **g11** places the pooled, female, and male adjusted rate ratios for that core side by
  side on a shared log scale.
- **g2** — What the models explain. Cross-validated discrimination against model size,
  across all four pooled specifications and both strata, showing what the extra terms buy.
- **g3** — Subgroup scale against selection yield. Variables retained per condition
  plotted against the number of non-zero outcomes in the subgroup, separating what the
  penalty could see from what is there.
- **g4** — Where the sexes differ. Ratio of female to male rate ratios with intervals,
  from the union model, ordered by evidence for heterogeneity.

## Artifact Inventory

| ID | Type | Title | Purpose |
| --- | --- | --- | --- |
| t1 | Table | The Three Modelling Frames | State what each report asked, on what sample, with which primary rule |
| out1 | Output | Provenance Audit | Every file read, its row count, and its modification time |
| g1 | Graph | The Convergent Core | Retention across pooled, female, male, and the 17 condition subgroups |
| g11 | Graph | The Core Estimated Three Ways | Pooled, female, and male adjusted rate ratios on one log axis |
| t2 | Table | The Convergent Core Ledger | Every core term with its pooled estimate, stratum retention, and subgroup breadth |
| t3 | Table | The Explained-Variance Ledger | In-sample and cross-validated fit for all pooled specifications and both strata |
| g2 | Graph | What the Extra Terms Buy | Held-out discrimination against model size |
| t4 | Table | The Condition Ledger | Subgroup size, non-zero share, mean days, comorbidity load, selection yield |
| g3 | Graph | Subgroup Scale and Selection Yield | Variables retained against non-zero outcome count |
| t5 | Table | The Heterogeneity Ledger | Ratio of female to male rate ratios, with intervals and stratum retention |
| g4 | Graph | Where the Sexes Differ | Ratio-of-ratios forest from the union model |
| t6 | Table | Next Lines of Inquiry | Methodological and substantive extensions, each with what it would settle |

## Output Format

HTML

## Upstream Reports

- `analysis/model-1/` — pooled LASSO selection and negative binomial refit, Sections 5.4–5.6
- `analysis/model-2/` — condition-specific models, Sections 5.7–5.8
- `analysis/model-3/` — sex-stratified models and the union comparison, Sections 5.9–5.10
- `analysis/eda-81/` — how the penalty works and what each specification kept

## Scope Boundaries

### Included

- Cross-report synthesis of results already produced by `model-1`, `model-2`, and `model-3`
- Substantive interpretation written at the strength the current evidence supports
- A structured roadmap of methodological and substantive next steps

### Excluded

- **Any re-fitting.** This report reads persisted CSVs only. It does not touch the analytic
  parquet, does not call `glmnet`, and does not call `MASS::glm.nb`. Every number here
  traces to a file written by `model-1`, `model-2`, or `model-3`.
- New specifications, new predictors, new outcomes. The alternatives named in t6 are
  proposals, not results.
- Causal claims. Every estimate in this report is an adjusted association measured on
  cross-sectional data; nothing here identifies an effect.
- Bootstrap intervals — still data-blocked, see `model-1` decision 10.

## Local Decisions

| # | Decision | Alternatives | Chosen | Rationale | Reversal |
| --- | --- | --- | --- | --- | --- |
| 1 | Which specification represents each frame | Each report's primary; a common rule across all three | Each report's own primary | `model-2` reversed the penalty rule locally (its decision 25) because `lambda.1se` returns an empty selection in seven of seventeen subgroups. Forcing a common rule would either erase `model-2` entirely or inflate the pooled and stratified models past what their own authors designated primary. The reversal is stated wherever the frames are compared. | `frame_specs` in `declare-globals` |
| 2 | The join key across the three frames | Design column name; variable name; rendered term label | Rendered term label | `model-2` and `model-3` both persist a `term` column built as `variable_label: level`. Reconstructing the same string from `model-1`'s `variable_label` and `level` makes all three joinable without a lookup table that could drift. The audit in out1 confirms the reconstruction. | `make_term()` in `declare-functions` |
| 3 | Female–male comparison source | The stratified primary models; the union model | The union model | The stratified primaries retain different term lists, so a term absent from one is not an estimate of zero — it is an absence of an estimate. `model-3`'s union model refits both strata on the union of terms, which is the only arrangement in which a female and a male rate ratio for the same term are both present and comparable. | `path_m3_union` in `declare-globals` |
| 4 | Which interval to display | Wald; sandwich; Kish | Kish where available, Wald for the ratio of ratios | The Kish interval is the widest of the three lower bounds on the design effect, so quoting it is the least likely to overstate precision. `model-3` computed the ratio of ratios on the Wald standard error; recomputing it on the Kish standard error would be a new calculation, which this report's scope forbids. Both are labelled at the point of use. | `interval_variant` in `declare-globals` |
| 5 | Condition-subgroup breadth measure | Count of subgroups retaining the term; share of subgroups; weighted by subgroup size | Count, with unstable terms excluded | The count is what `model-2` itself persisted in `term-recurrence.csv`, so quoting it keeps the two reports in agreement. Weighting by subgroup size would blend the recurrence signal with the size signal that g3 exists to separate. | `path_m2_recurrence` in `declare-globals` |
| 6 | Roadmap content | Prose only; prose plus a structured table | Prose plus a structured table | The methodological alternatives differ along axes a reader will want to compare directly — what they change about selection, what they would settle, and what blocks them today. A table makes the comparison; the prose makes the argument. | `roadmap` in `t6` |

## Known Constraints

- **The three frames do not share a penalty rule.** `model-1` and `model-3` designate
  `lambda.1se` primary; `model-2` designates `lambda.min`. A term retained in 11 of 17
  subgroups under a permissive rule is not evidence of the same strength as a term
  retained in the pooled model under a parsimonious one. Every comparison in this report
  that crosses that boundary says so.
- **Subgroups overlap heavily.** The 17 condition subgroups are not a partition. Between
  63% and 93% of respondents in any one subgroup carry at least one other condition, and
  respondents with fibromyalgia carry 2.9 other conditions on average. Recurrence across
  subgroups is therefore partly recurrence across the same people.
- **Selection and estimation used the same rows.** Inherited from all three upstream
  reports. Every interval shown here is conditional on a term list chosen from the data it
  is estimated on, and is optimistic by an amount none of the four reports can quantify.
- **No bootstrap weights.** Neither the 2010–11 nor the 2014 PUMF ships them (`model-1`
  decision 10). The sandwich and Kish intervals bracket a lower bound on the true design
  effect; they do not reach it.
- **Cross-sectional data.** Condition status and days absent are reported in the same
  interview. Nothing in this body of work distinguishes a condition that causes absence
  from an absence that prompts a diagnosis.
