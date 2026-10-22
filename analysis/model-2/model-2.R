# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# MODEL-2: Full implementation of Sections 5.7 and 5.8 - condition-specific
# multivariable models. One negative binomial model per chronic condition,
# estimated inside the subgroup of respondents who report that condition, with
# variable selection following the Section 5.4 LASSO procedure.
#
# Deliberately built as a structural rhyme of analysis/model-1/model-1.R: the
# same ten steps, the same artifact roles (t6 is the deliverable table, t62 the
# full ledger, t61 the in-sample metrics, t63 / t64 the held-out ones, t7 the
# manifest), and the same helper names. A reader who has read model-1 should be
# able to read this without relearning anything.
rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014") # Clear the console
cat("Working directory: ", getwd()) # Must be set to Project Directory

# ---- load-packages -----------------------------------------------------------
library(magrittr)
library(ggplot2)
library(dplyr)
library(tidyr)
library(forcats)
library(purrr)
library(tibble)
library(scales)
library(fs)
library(kableExtra)
requireNamespace("arrow", quietly = TRUE)
requireNamespace("glmnet", quietly = TRUE)
requireNamespace("MASS", quietly = TRUE)
requireNamespace("readr", quietly = TRUE)
requireNamespace("knitr", quietly = TRUE)
requireNamespace("survival", quietly = TRUE) # concordance() for the Section 5.8 C-statistic

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R")
base::source("./scripts/graphing/graph-presets.R")

# ---- declare-globals ---------------------------------------------------------
local_root <- "./analysis/model-2/"
local_data <- paste0(local_root, "data-local/")
fits_folder <- paste0(local_data, "fits/")
prints_folder <- paste0(local_root, "prints/")
path_parquet <- "./data-private/derived/cchs-2-tables/cchs_analytic.parquet"

outcome_var <- "days_absent_total"
weight_col <- "wts_m_pooled"
cycle_var <- "cchs_cycle_f"
forced_vars <- cycle_var
lasso_seed <- 42
lasso_folds <- 5

# The COPD item is administered only to respondents aged 35 and over, so it
# cannot sit on the primary complete-case frame (model-1 decision 2). It gets a
# supplementary frame of its own here, because Section 5.7 conditions ON the
# disease and everyone who reports COPD was asked the question by construction.
# Decision 21.
copd_var <- "cc_copd"

# Section 5.8 performance cross-validation. Named apart from `lasso_folds` for
# the same reason as in model-1: that one tunes the penalty inside glmnet on a
# Poisson deviance, this one estimates out-of-sample prediction error for the
# negative binomial refits. Both are five-fold because Sections 5.4 and 5.8 both
# say five; they are not the same folds and they answer different questions.
perf_folds <- 5
perf_seed <- 42

# Subgroup feasibility thresholds. Section 5.7 names 500 unweighted as the flag
# threshold; `min_fit_n` is the point below which a model is not attempted at
# all. Decision 26.
small_subgroup_n <- 500L
min_fit_n <- 100L

# A term whose standard error exceeds this on the log scale has an interval
# spanning more than four orders of magnitude on the rate-ratio scale. It is
# reported and marked rather than removed. Decision 27.
unstable_se <- 2

# Step 9 refits every specification on every fold twice over, for every
# condition, so the block is cached. Set TRUE to rebuild.
force_refit_cv <- FALSE
cv_cache_path <- paste0(fits_folder, "cv-performance.rds")

for (folder in c(local_data, fits_folder, prints_folder)) {
  if (!fs::dir_exists(folder)) { fs::dir_create(folder, recurse = TRUE) }
}

# The canonical candidate registry, shared with model-0, model-00 and model-1.
# See scripts/modeling/candidate-registry.R for the full contract. What model-2
# uses from it:
#   candidate_registry        52 rows, with domain, label and exclusion reason
#   vars_excluding_perceived  45; the primary predictor set of Section 5.5
#   lasso_vars                48; used only to define the complete-case frame
base::source("./scripts/modeling/candidate-registry.R")

# The 19 chronic conditions Section 2.2 names, mapped onto the items the CCC
# module of the 2010 and 2014 PUMF actually carries. Two of the nineteen are not
# separately available: "mental illness (depression / bipolar)" is the same CCC
# question as "mood disorder", and "digestive diseases" has no item distinct
# from bowel disorder. Nineteen requested constructs therefore resolve to
# SEVENTEEN fitted models. Decision 20.
condition_roster <- tibble::tribble(
  ~proposal_id, ~proposal_condition,                     ~variable,             ~frame,  ~status,       ~note,
  1L,  "Arthritis",                            "cc_arthritis",        "main",  "fitted",      "",
  2L,  "Asthma",                               "cc_asthma",           "main",  "fitted",      "",
  3L,  "Cardiovascular disease",               "cc_heart_disease",    "main",  "fitted",      "Section 2.2 pairs this with stroke; the CCC module carries them as two items and they are modelled separately.",
  4L,  "Stroke",                               "cc_stroke",           "main",  "fitted",      "See row 3. The rarest condition in the roster; read its model against the n in Table t2.",
  5L,  "Hypertension",                         "cc_hypertension",     "main",  "fitted",      "",
  6L,  "Fibromyalgia",                         "cc_fibromyalgia",     "main",  "fitted",      "",
  7L,  "Diabetes",                             "cc_diabetes",         "main",  "fitted",      "",
  8L,  "Migraine",                             "cc_migraine",         "main",  "fitted",      "",
  9L,  "Back problems",                        "cc_back_problems",    "main",  "fitted",      "",
  10L, "Cancer",                               "cc_cancer",           "main",  "fitted",      "",
  11L, "COPD",                                 "cc_copd",             "age35", "fitted",      "Administered only to respondents aged 35 and over, so it is fitted on the supplementary frame. Decision 21.",
  12L, "Mental illness (depression, bipolar)", "cc_mood_disorder",    "main",  "duplicate",   "The CCC module asks a single mood-disorder question covering depression, bipolar disorder, mania and dysthymia. Identical to row 17; modelled once.",
  13L, "Bowel disorders",                      "cc_bowel_disorder",   "main",  "fitted",      "",
  14L, "Digestive diseases",                   NA_character_,         "none",  "unavailable", "No CCC item distinct from bowel disorder exists in either cycle's PUMF.",
  15L, "Chronic fatigue syndrome",             "cc_fatigue_syndrome", "main",  "fitted",      "Named in Section 5.7 as a subgroup expected to be small.",
  16L, "Multiple chemical sensitivities",      "cc_chem_sensitivity", "main",  "fitted",      "Named in Section 5.7 as a subgroup expected to be small.",
  17L, "Mood disorder",                        "cc_mood_disorder",    "main",  "fitted",      "The item that also answers row 12.",
  18L, "Anxiety disorder",                     "cc_anxiety",          "main",  "fitted",      "",
  19L, "Stomach or intestinal ulcer",          "cc_ulcer",            "main",  "fitted",      ""
)

fitted_conditions <- condition_roster %>%
  filter(status == "fitted") %>%
  select(variable, frame, proposal_condition)

# Guard against silent divergence between the roster and the registry.
stopifnot(
  nrow(condition_roster) == 19L,
  nrow(fitted_conditions) == 17L,
  !any(duplicated(fitted_conditions$variable)),
  all(fitted_conditions$variable %in% candidate_registry$variable),
  all(fitted_conditions$frame %in% c("main", "age35"))
)

# Section 5.7 asks for one model per condition and refers selection back to
# Section 5.4, which offers four specifications. model-2 carries the PRIMARY
# predictor set of Section 5.5 (perceived health excluded) and reads it at both
# penalties, so a single cross-validated fit per condition yields both rows.
# lambda.min is designated primary at subgroup scale. Decision 25.
condition_specs <- tibble::tribble(
  ~spec_id,    ~model_label,             ~lambda_rule,  ~role,
  "spec_min",  "Permissive (min)",       "lambda.min",  "Primary",
  "spec_1se",  "Parsimonious (1SE)",     "lambda.1se",  "Sensitivity"
)

primary_spec <- "spec_min"

# Decisions 1 through 19 are made in model-1 and inherited here unchanged. They
# are listed by title so that model-2 is readable on its own; the alternatives,
# rationale and reversal instructions live in model-1 Table t3 and are not
# restated, because two copies of a decision drift.
inherited_decisions <- tibble::tribble(
  ~id, ~decision,                                  ~chosen,
  1L,  "Outcome variable",                         "days_absent_total",
  2L,  "COPD indicator",                           "Exclude from the primary frame (extended by decision 21)",
  3L,  "Family doctor indicator",                  "Exclude",
  4L,  "Age resolution",                           "age_group_3",
  5L,  "Missing data handling",                    "Complete case",
  6L,  "Perceived health definition",              "The 3 self-perceived measures",
  7L,  "Dummy coding scheme",                      "Reference contrasts",
  8L,  "Cycle indicator",                          "Unpenalised (penalty.factor = 0)",
  9L,  "Carry-forward rule to stage 2",            "Any surviving column promotes the whole factor",
  10L, "Variance estimation",                      "Wald standard errors (bootstrap weights absent from the PUMF)",
  11L, "Penalty selection",                        "5-fold CV, seed 42",
  12L, "Weights in cross-validation",              "Weighted likelihood",
  13L, "Child-presence flag dhhgl12",              "Descriptives and bivariate models only",
  14L, "Homeownership",                            "Include DHH_OWN directly as home_ownership",
  15L, "Interval reporting",                       "Wald, sandwich and Kish-inflated, side by side",
  16L, "Basis for the held-out cross-validation",  "Both fixed term set and selection re-run",
  17L, "C-statistic for a count outcome",          "Harrell's C on predicted mean vs observed count",
  18L, "Information criteria under weighting",     "Report with a pseudo-likelihood caveat",
  19L, "Scale of the error metrics",               "Weighted"
)

# The decisions model-2 makes on its own account. Numbering continues from
# model-1 so that a decision id is unambiguous across the whole project.
decision_registry <- tibble::tribble(
  ~id, ~decision, ~alternatives, ~chosen, ~rationale, ~reversal,

  20L, "Which chronic conditions are modelled",
  "All 19 constructs named in Section 2.2; the 17 distinct CCC items the PUMF carries; the 16 items available on the primary analytic frame",
  "17 CCC items - 16 on the primary frame plus COPD on a supplementary frame",
  "Section 2.2 names 19 constructs, but the CCC module of the 2010 and 2014 PUMF carries 17 distinct items. 'Mental illness (depression, bipolar)' is the same question as 'mood disorder', and 'digestive diseases' has no item separate from bowel disorder. Table t1 maps every requested construct to the item that answers it, so the shortfall is visible rather than silent.",
  "`condition_roster` in declare-globals",

  21L, "COPD subgroup",
  "Omit COPD as model-1 does; fit it on the primary frame; fit it on a supplementary complete-case frame carrying cc_copd",
  "Supplementary frame",
  "model-1 excluded cc_copd because it is asked only of respondents aged 35 and over, and carrying it would have cost the pooled analysis a third of its sample. Section 5.7 conditions ON the disease, so the age restriction is a property of the subgroup rather than a loss: every respondent who reports COPD was asked the question by construction. The frame is reported separately because its denominator differs from the other sixteen. Within it the '25-54' age band contains only respondents aged 35-54.",
  "`copd_var` and `frames` in tweak-data-0",

  22L, "Subgroup base sample",
  "Re-derive complete cases inside each condition subgroup; filter the model-1 complete-case frame",
  "Filter the model-1 frame",
  "Re-deriving would give each condition its own denominator and its own candidate set, so no two condition models would be comparable with each other and none would be comparable with Table 3. Filtering keeps every subgroup a strict subset of the Section 5.5 analytic sample.",
  "`ds1` in tweak-data-0",

  23L, "Candidate set inside a subgroup",
  "All 48 LASSO candidates; the 45 excluding perceived health; a reduced set scaled to subgroup size",
  "45 excluding perceived health, minus the index condition, minus anything constant in the subgroup",
  "The index condition is constant inside its own subgroup and carries no information there. The perceived-health toggle belongs to the four-way comparison of Section 5.4; Section 5.7 asks for one model per condition, and the primary specification of Section 5.5 is the one that excludes perceived health. A variable that loses all but one level inside a subgroup cannot be dummy-coded and is dropped, with every drop recorded in Table t2.",
  "`subgroup_candidates()` in declare-functions",

  24L, "Comorbidity",
  "Drop the other 16 conditions from the candidate set; retain them",
  "Retain them",
  "Chronic conditions co-occur heavily; Table t21 quantifies how heavily. A model of absenteeism among respondents with arthritis that ignored whether they also have a mood disorder would attribute to arthritis an association belonging to the pair. The subgroups are not disjoint and these estimates are conditional, not causal, which is exactly why t21 sits upstream of the models.",
  "`subgroup_candidates()` in declare-functions",

  25L, "Penalty rule designated primary for subgroups",
  "lambda.1se, matching the primary model of Section 5.5; lambda.min; both",
  "Both reported; lambda.min designated primary",
  "These subgroups are one to two orders of magnitude smaller than the Section 5.5 sample. model-0 showed lambda.1se retaining nothing at all at n = 63,843 on a single domain; at subgroup scale an empty selection is the expected outcome, and a specification that names no predictors cannot answer 'the main predictors of absenteeism within that subgroup'. Table t5 reports how often each rule returned an empty set, so the choice is checkable rather than asserted.",
  "`primary_spec` and `condition_specs` in declare-globals",

  26L, "Small-subgroup threshold",
  "No flag; the proposal's n < 500; a rule based on the number of non-zero outcomes",
  "Flag n < 500 as Section 5.7 directs, and report non-zero respondents beside it",
  "Section 5.7 names 500 unweighted. That count is not the binding constraint for a count model: what limits estimation is the number of respondents with at least one day absent, which is well under a third of any subgroup. Both are reported. A subgroup that clears 500 but carries ninety informative respondents should be read as small.",
  "`small_subgroup_n` and `min_fit_n` in declare-globals",

  27L, "Rare levels and unstable terms",
  "Collapse rare levels; drop variables that have a rare level; retain and flag",
  "Retain and flag",
  "Collapsing changes what a coefficient means, and would have to be done differently in each subgroup, which breaks comparability. Dropping would remove province and occupation from every small subgroup. Instead, a term whose standard error exceeds 2 on the log scale is marked unstable in Table t62: its interval is uninformative and its point estimate should not be quoted.",
  "`unstable_se` in declare-globals",

  28L, "Section 5.8 resampling method",
  "5-fold cross-validation; leave-one-out for small subgroups; a mixture by subgroup size",
  "5-fold for every subgroup",
  "Section 5.8 permits leave-one-out at the analyst's discretion. It is declined for a technical reason rather than a convenience one: Harrell's C is computed over PAIRS of held-out respondents, and a leave-one-out fold contains a single respondent, so the C-statistic Section 5.8 requests would be undefined and the between-fold spread that makes a cross-validated number readable would not exist. Five folds also keep model-2 on the same footing as model-1's Tables t63 and t64. Folds that fail to converge are counted, not silently dropped.",
  "`perf_folds` in declare-globals",

  29L, "Design effect basis",
  "Reuse model-1's full-sample Kish design effect; compute one within each subgroup",
  "Within each subgroup",
  "A design effect describes the weight distribution of the sample whose intervals it widens. Weights inside a condition subgroup are not distributed as they are in the pooled sample, and Output out5 shows the realised value varying across conditions. Using a single number for all seventeen would understate some intervals and overstate others.",
  "`build_subgroup()` in declare-functions",

  30L, "Weight rescaling",
  "Carry model-1's rescaled weight into the subgroup; rescale to mean 1 within each subgroup",
  "Rescale within each subgroup",
  "glm.nb treats prior weights as frequencies when estimating dispersion, so a subgroup whose carried-forward weights average far from 1 would return a theta on a different scale from its neighbours. Rescaling inside the subgroup makes theta comparable across conditions. Point estimates are unaffected; only the scale of the weights changes."
  , "`build_subgroup()` in declare-functions"
)

domain_colours <- c(
  "Exposure"      = abcol[["magenta"]],
  "Predisposing"  = abcol[["blue"]],
  "Facilitating"  = abcol[["green"]],
  "Needs"         = abcol[["brown"]],
  "Survey design" = abcol[["grey"]]
)

spec_colours <- c(
  "Permissive (min)"   = abcol[["blue"]],
  "Parsimonious (1SE)" = abcol[["magenta"]]
)

verdict_colours <- c(
  "fitted"              = abcol[["green"]],
  "fitted, flagged small" = abcol[["yellow"]],
  "not fitted"          = abcol[["grey"]]
)

# ---- declare-functions -------------------------------------------------------
# Render a data frame as styled HTML for Quarto, or plainly for console use.
# Tall tables get a fixed-height scroll box so the report stays navigable.
print_table <- function(data, caption, align = NULL, scroll_height = NULL) {
  if (is.null(scroll_height) && nrow(data) > 25) scroll_height <- "600px"
  boxed <- data %>%
    knitr::kable(
      format = "html", caption = caption, escape = FALSE,
      align = align, row.names = FALSE
    ) %>%
    kableExtra::kable_styling(
      bootstrap_options = c("striped", "hover", "condensed"), full_width = FALSE
    )
  boxed <- if (is.null(scroll_height)) {
    kableExtra::scroll_box(boxed, width = "100%")
  } else {
    kableExtra::scroll_box(boxed, width = "100%", height = scroll_height)
  }
  cat(as.character(boxed))
  invisible(data)
}

to_yes_no <- function(x) {
  factor(ifelse(x %in% c(1, TRUE), "Yes", "No"), levels = c("No", "Yes"))
}

# Strip the variable-name prefix from a design column to recover the level
# label. Vectorised, because sub() uses only the first element of `pattern`.
strip_variable_prefix <- function(column, variable) {
  purrr::map2_chr(column, variable, ~ sub(paste0("^", .y), "", .x))
}

# Does this column carry any information? A factor reduced to one level inside a
# subgroup cannot be dummy-coded, and a constant numeric contributes nothing.
is_informative <- function(x) {
  if (is.factor(x)) return(nlevels(droplevels(x)) > 1L)
  length(unique(x[!is.na(x)])) > 1L
}

# Apply the model-1 recoding contract to a selection of source columns. Factored
# out here because model-2 builds two frames rather than one (decision 21) and
# they must be recoded identically or the COPD model stops being comparable.
prepare_frame <- function(extra_vars = character(0)) {
  ds0 %>%
    select(all_of(unique(c(outcome_var, weight_col, cycle_var, lasso_vars, extra_vars)))) %>%
    mutate(across(where(is.ordered), ~ factor(., ordered = FALSE))) %>%
    mutate(across(where(is.logical), to_yes_no)) %>%
    mutate(across(any_of(c("dhhgle5", "dhhg611", "dhhgl12")), to_yes_no)) %>%
    mutate(across(where(is.character), factor))
}

# Build a design matrix and the column-to-variable map that makes selection
# results interpretable. Reference contrasts; intercept dropped. Shared verbatim
# with model-1.
build_design <- function(model_frame, term_vars) {
  model_formula <- stats::reformulate(term_vars)
  mm <- stats::model.matrix(model_formula, data = model_frame)
  assign_index <- attr(mm, "assign")
  term_labels <- attr(stats::terms(model_formula, data = model_frame), "term.labels")
  source_variable <- c("(Intercept)", term_labels)[assign_index + 1]
  keep <- colnames(mm) != "(Intercept)"

  list(
    x = mm[, keep, drop = FALSE],
    map = tibble::tibble(
      column = colnames(mm)[keep],
      variable = source_variable[keep]
    ) %>%
      mutate(level = strip_variable_prefix(column, variable))
  )
}

# Stage 1. A weighted, L1-penalised Poisson fit with the cycle indicator exempt
# from the penalty, plus the full coefficient path for plotting. Shared verbatim
# with model-1.
fit_lasso <- function(design, outcome, weights, seed) {
  penalty_vector <- as.numeric(!design$map$variable %in% forced_vars)

  set.seed(seed)
  path <- glmnet::glmnet(
    x = design$x, y = outcome, family = "poisson", alpha = 1,
    weights = weights, penalty.factor = penalty_vector
  )
  set.seed(seed)
  cv <- suppressWarnings(glmnet::cv.glmnet(
    x = design$x, y = outcome, family = "poisson", alpha = 1,
    nfolds = lasso_folds, weights = weights, penalty.factor = penalty_vector
  ))
  list(path = path, cv = cv, penalty = penalty_vector)
}

# Extract the coefficient vector at a named lambda, joined to the column map.
coefficients_at <- function(lasso, design, lambda_rule) {
  coefficient_matrix <- stats::coef(lasso$cv, s = lambda_rule)
  tibble::tibble(
    column = rownames(coefficient_matrix),
    estimate = as.numeric(coefficient_matrix)
  ) %>%
    filter(column != "(Intercept)") %>%
    left_join(design$map, by = "column") %>%
    mutate(retained = estimate != 0)
}

# Decision 9 (inherited): a variable is promoted to stage 2 if ANY of its
# columns survived the penalty.
retained_variables <- function(coefficient_table) {
  coefficient_table %>%
    filter(retained) %>%
    pull(variable) %>%
    unique()
}

# Stage 2. Unpenalised negative binomial on the retained variable set. Wrapped
# in tryCatch because Section 5.7 anticipates non-convergence in small
# subgroups and asks for it to be reported rather than hidden.
fit_nb <- function(model_frame, term_vars, outcome) {
  usable <- term_vars[purrr::map_lgl(term_vars, ~ is_informative(model_frame[[.x]]))]
  terms_used <- if (length(usable) > 0) usable else "1"
  model_formula <- stats::reformulate(terms_used, response = outcome)
  environment(model_formula) <- environment()
  tryCatch(
    suppressWarnings(
      MASS::glm.nb(
        model_formula, data = model_frame, weights = weight_scaled,
        control = stats::glm.control(maxit = 100)
      )
    ),
    error = function(e) NULL
  )
}

# Huber-White sandwich covariance for a weighted negative binomial fit, with
# theta held at its estimate. The unequal-weighting component of the design
# effect and nothing more: strata and PSUs are suppressed in the PUMF, so the
# clustering component is not recoverable. Inherited decision 15.
# Shared verbatim with model-00 and model-1. If one changes, all must change, or
# Tables 2, 3 and 4 stop being comparable.
robust_vcov <- function(nb_fit) {
  design <- stats::model.matrix(nb_fit)
  mu <- stats::fitted(nb_fit)
  y <- nb_fit$y
  w <- nb_fit$prior.weights
  score <- w * (y - mu) / (1 + mu / nb_fit$theta)
  bread <- stats::vcov(nb_fit)
  meat <- crossprod(design * score)
  bread %*% meat %*% bread
}

# Kish's approximate design effect from unequal weighting alone. Its square root
# is the factor by which a design-based standard error would exceed the
# model-based one if weighting were the only departure from simple random
# sampling. A lower bound. Computed per subgroup here, per decision 29.
kish_design_effect <- function(w) {
  length(w) * sum(w^2) / (sum(w)^2)
}

# Wald summary on the rate-ratio scale, carrying three interval variants:
#   - Wald        model-based, understates uncertainty (inherited decision 10)
#   - robust      Huber-White sandwich, sees unequal weighting only
#   - Kish        Wald inflated by sqrt(design effect), applied uniformly
# NOT bootstrap: the replicate weights Section 5.7 assumes do not exist in the
# 2010 or 2014 PUMF. Inherited decisions 10 and 15.
tidy_nb <- function(nb_fit, column_map, deff = 1) {
  robust_se <- tryCatch(sqrt(diag(robust_vcov(nb_fit))), error = function(e) NULL)

  out <- summary(nb_fit)$coefficients %>%
    as.data.frame() %>%
    tibble::rownames_to_column("column") %>%
    rename(estimate = Estimate, std_error = `Std. Error`, p_value = `Pr(>|z|)`) %>%
    filter(column != "(Intercept)") %>%
    left_join(column_map, by = "column")

  out %>%
    mutate(
      se_robust = if (is.null(robust_se)) NA_real_ else unname(robust_se[column]),
      se_kish = std_error * sqrt(deff),
      p_robust = 2 * stats::pnorm(-abs(estimate / se_robust)),
      rate_ratio = exp(estimate),
      ci_low = exp(estimate - 1.96 * std_error),
      ci_high = exp(estimate + 1.96 * std_error),
      ci_low_robust = exp(estimate - 1.96 * se_robust),
      ci_high_robust = exp(estimate + 1.96 * se_robust),
      ci_low_kish = exp(estimate - 1.96 * se_kish),
      ci_high_kish = exp(estimate + 1.96 * se_kish),
      unstable = std_error > unstable_se
    )
}

# Section 5.8's C-statistic, adapted to a count outcome (inherited decision 17).
# Pairs tied on the outcome carry no information about discrimination and are
# excluded from the denominator, so the comparable share travels with the
# statistic. Returns NA rather than failing when a subgroup is too thin or too
# uniform for concordance to be defined.
harrell_c <- function(observed, predicted, weights) {
  empty <- tibble::tibble(c_statistic = NA_real_, c_se = NA_real_,
                          comparable_share = NA_real_)
  if (length(unique(observed)) < 2L || length(observed) < 3L) return(empty)
  tryCatch({
    fit <- survival::concordance(observed ~ predicted, weights = weights)
    counts <- fit$count
    comparable <- sum(counts[c("concordant", "discordant", "tied.x")])
    total <- comparable + sum(counts[c("tied.y", "tied.xy")])
    tibble::tibble(
      c_statistic = as.numeric(fit$concordance),
      c_se = sqrt(as.numeric(fit$var)),
      comparable_share = comparable / total
    )
  }, error = function(e) empty)
}

# Negative binomial log-likelihood on held-out rows, using the coefficients and
# the theta estimated on the training rows. Weighted, per inherited decision 19.
nb_loglik <- function(observed, predicted, theta, weights) {
  sum(weights * stats::dnbinom(observed, size = theta, mu = predicted, log = TRUE))
}

# Deterministic fold assignment. Every condition, specification and CV variant
# scores the same partition of its own subgroup, so differences between them are
# differences in model rather than luck of the draw.
assign_folds <- function(n, k, seed) {
  set.seed(seed)
  sample(rep_len(seq_len(k), n))
}

# One training/testing pass for a GIVEN term set. Both CV variants of Step 9
# call this; they differ only in where `term_vars` comes from.
#
# This is model-1's `evaluate_fold()` with three subgroup guards added, because
# a fifth of a two-thousand-respondent subgroup is a much thinner object than a
# fifth of the Section 5.5 sample:
#   1. terms that go constant in the training fold are dropped and counted
#   2. test rows carrying a factor level the training fold never saw are dropped
#      and counted, rather than allowed to propagate NA through the metrics
#   3. a fold whose fit fails returns a row marked `converged = FALSE` rather
#      than aborting the condition, as Section 5.7 requires
evaluate_fold <- function(frame, train_rows, test_rows, term_vars, outcome) {
  failed <- tibble::tibble(
    n_train = length(train_rows), n_test = length(test_rows), n_unscorable = NA_integer_,
    n_terms = NA_integer_, theta = NA_real_, converged = FALSE,
    rmse = NA_real_, mae = NA_real_, loglik = NA_real_, mcfadden_r2 = NA_real_,
    c_statistic = NA_real_, c_se = NA_real_, comparable_share = NA_real_
  )

  train <- droplevels(frame[train_rows, , drop = FALSE])
  test <- frame[test_rows, , drop = FALSE]

  term_vars <- term_vars[purrr::map_lgl(term_vars, ~ is_informative(train[[.x]]))]

  factor_terms <- term_vars[purrr::map_lgl(term_vars, ~ is.factor(train[[.x]]))]
  scorable <- rep(TRUE, nrow(test))
  for (this_var in factor_terms) {
    scorable <- scorable & as.character(test[[this_var]]) %in% levels(train[[this_var]])
  }
  n_dropped <- sum(!scorable)
  test <- test[scorable, , drop = FALSE]
  if (nrow(test) < 3L) return(failed)
  for (this_var in factor_terms) {
    test[[this_var]] <- factor(as.character(test[[this_var]]),
                               levels = levels(train[[this_var]]))
  }

  fit <- fit_nb(train, term_vars, outcome)
  fit_null <- fit_nb(train, character(0), outcome)
  if (is.null(fit) || is.null(fit_null)) return(failed)

  predicted <- tryCatch(stats::predict(fit, newdata = test, type = "response"),
                        error = function(e) NULL)
  if (is.null(predicted) || anyNA(predicted)) return(failed)
  predicted_null <- stats::predict(fit_null, newdata = test, type = "response")
  observed <- test[[outcome]]
  w <- test$weight_scaled

  loglik_test <- nb_loglik(observed, predicted, fit$theta, w)
  loglik_test_null <- nb_loglik(observed, predicted_null, fit_null$theta, w)

  dplyr::bind_cols(
    tibble::tibble(
      n_train = nrow(train),
      n_test = nrow(test),
      n_unscorable = n_dropped,
      n_terms = length(stats::coef(fit)) - 1L,
      theta = fit$theta,
      converged = isTRUE(fit$converged),
      rmse = sqrt(stats::weighted.mean((observed - predicted)^2, w)),
      mae = stats::weighted.mean(abs(observed - predicted), w),
      loglik = loglik_test,
      mcfadden_r2 = 1 - loglik_test / loglik_test_null
    ),
    harrell_c(observed, predicted, w)
  )
}

# Cut a condition subgroup out of its frame and re-scale its weights to mean 1
# (decision 30). Unused factor levels are dropped here, once, so that every
# downstream step sees the same subgroup.
build_subgroup <- function(frame, condition_var) {
  frame %>%
    filter(.data[[condition_var]] == "Yes") %>%
    droplevels() %>%
    mutate(weight_scaled = .data[[weight_col]] / mean(.data[[weight_col]]))
}

# The candidate set offered to the penalty inside one subgroup (decisions 23
# and 24): the primary Section 5.5 predictor set, minus the index condition,
# minus anything that has gone constant. The other sixteen conditions stay.
subgroup_candidates <- function(subgroup, condition_var, candidates) {
  offered <- setdiff(candidates, condition_var)
  offered[purrr::map_lgl(offered, ~ is_informative(subgroup[[.x]]))]
}

# The whole stage-one pipeline for one condition, from frame to cross-validated
# penalised fit. Returns everything the later steps need, including what it had
# to drop, so that Table t2 can report the cost of the subgroup restriction.
fit_condition <- function(condition_var) {
  frame_id <- fitted_conditions$frame[fitted_conditions$variable == condition_var]
  subgroup <- build_subgroup(frames[[frame_id]], condition_var)

  offered <- subgroup_candidates(subgroup, condition_var, vars_excluding_perceived)
  dropped <- setdiff(setdiff(vars_excluding_perceived, condition_var), offered)
  forced_here <- forced_vars[purrr::map_lgl(forced_vars, ~ is_informative(subgroup[[.x]]))]

  feasible <- nrow(subgroup) >= min_fit_n && length(offered) > 0
  design <- if (feasible) build_design(subgroup, c(forced_here, offered)) else NULL
  lasso <- if (feasible) {
    tryCatch(
      fit_lasso(design, subgroup[[outcome_var]], subgroup$weight_scaled, lasso_seed),
      error = function(e) NULL
    )
  } else {
    NULL
  }

  list(
    condition = condition_var,
    frame_id = frame_id,
    subgroup = subgroup,
    offered = offered,
    dropped = dropped,
    forced = forced_here,
    design = design,
    lasso = lasso,
    kish_deff = kish_design_effect(subgroup[[weight_col]])
  )
}

# ---- load-data ---------------------------------------------------------------
ds0 <- arrow::read_parquet(path_parquet)

# ---- tweak-data-0 ------------------------------------------------------------
# Two frames, recoded identically (decisions 21 and 22).
#
#   ds1   the model-1 complete-case frame: complete on the 48 LASSO candidates.
#         Sixteen of the seventeen condition subgroups are cut from it, so every
#         one of them is a strict subset of the Section 5.5 analytic sample.
#
#   ds2   the same, additionally complete on cc_copd. Because the COPD question
#         is administered only from age 35, requiring it is what restricts the
#         frame; no explicit age filter is applied or needed. This frame exists
#         only to host the COPD subgroup.
ds_model_raw <- prepare_frame()

n_source <- nrow(ds_model_raw)
complete_flag <- stats::complete.cases(ds_model_raw)

ds1 <- ds_model_raw %>%
  filter(complete_flag) %>%
  mutate(.respondent_id = dplyr::row_number())

ds_copd_raw <- prepare_frame(copd_var)
ds2 <- ds_copd_raw %>%
  filter(stats::complete.cases(.)) %>%
  mutate(.respondent_id = dplyr::row_number())

frames <- list(main = ds1, age35 = ds2)

n_analytic <- nrow(ds1)
n_analytic_copd <- nrow(ds2)

variable_labels <- c(
  stats::setNames(candidate_registry$variable_label, candidate_registry$variable),
  stats::setNames("CCHS cycle", cycle_var)
)
variable_domains <- c(
  stats::setNames(candidate_registry$domain, candidate_registry$variable),
  stats::setNames("Survey design", cycle_var)
)
condition_labels <- stats::setNames(
  variable_labels[fitted_conditions$variable], fitted_conditions$variable
)

# ---- inspect-data-0 ----------------------------------------------------------
ds0 %>% dplyr::glimpse(width = 100)

# ---- data-context-tables -----------------------------------------------------
# A single Ellis output feeds this report, as it feeds model-1. No joins are
# performed, so there is no risk of row multiplication anywhere in model-2. What
# model-2 adds is a second complete-case frame, not a second source.
cat("Source table: ", path_parquet, "\n", sep = "")
cat("  grain:      one row per respondent, two pooled CCHS cycles\n")
cat("  rows:       ", format(nrow(ds0), big.mark = ","), "\n", sep = "")
cat("  columns:    ", ncol(ds0), "\n\n", sep = "")

cat("Columns this report draws on:\n")
cat("  outcome:      ", outcome_var, "\n", sep = "")
cat("  weight:       ", weight_col, " (master weight halved for pooling, rescaled within each subgroup)\n", sep = "")
cat("  forced in:    ", forced_vars, "\n", sep = "")
cat("  subgrouping:  ", nrow(fitted_conditions), " chronic-condition indicators\n", sep = "")
cat("  candidates:   ", length(vars_excluding_perceived),
    " offered inside each subgroup, less the index condition\n\n", sep = "")

cat("The two analytic frames:\n")
tibble::tibble(
  frame = c("main (ds1)", "age 35+ (ds2)"),
  definition = c("complete on the 48 LASSO candidates",
                 "the same, plus complete on cc_copd"),
  rows = c(n_analytic, n_analytic_copd),
  hosts = c("16 condition subgroups", "the COPD subgroup only")
) %>%
  mutate(rows = scales::comma(rows)) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

# ---- data-context-person -----------------------------------------------------
# Grain proof, then one respondent from a condition subgroup shown in full, so a
# reader can see exactly what a single row of a Section 5.7 model frame contains
# and confirm that the index condition really is constant within it.
cat("Grain proof\n")
cat("  rows in source:         ", format(nrow(ds0), big.mark = ","), "\n", sep = "")
cat("  rows in main frame:     ", format(n_analytic, big.mark = ","), "\n", sep = "")
cat("  rows in age 35+ frame:  ", format(n_analytic_copd, big.mark = ","), "\n", sep = "")
cat("  duplicated ids (main):  ", sum(duplicated(ds1$.respondent_id)), "\n\n", sep = "")

example_condition <- "cc_arthritis"
example_subgroup <- build_subgroup(ds1, example_condition)

cat("One respondent from the ", variable_labels[[example_condition]],
    " subgroup (n = ", scales::comma(nrow(example_subgroup)), "):\n\n", sep = "")

set.seed(lasso_seed)
example_subgroup %>%
  slice_sample(n = 1) %>%
  select(-.respondent_id, -weight_scaled) %>%
  tidyr::pivot_longer(everything(), names_to = "variable",
                      values_to = "value", values_transform = list(value = as.character)) %>%
  left_join(
    candidate_registry %>% select(variable, domain, variable_label),
    by = "variable"
  ) %>%
  mutate(
    domain = tidyr::replace_na(domain, "Outcome / design"),
    variable_label = dplyr::coalesce(variable_label, variable),
    variable_label = ifelse(variable == example_condition,
                            paste0(variable_label, "  <- index condition"),
                            variable_label)
  ) %>%
  arrange(match(domain, c("Outcome / design", "Exposure", "Predisposing",
                          "Facilitating", "Needs"))) %>%
  select(Domain = domain, Variable = variable_label, Value = value) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nThe index condition reads 'Yes' by construction, which is precisely why it\n")
cat("is removed from the candidate set inside its own subgroup (decision 23).\n")

# ---- data-context-distributions ----------------------------------------------
# The outcome inside subgroups rather than in the pooled sample, because that is
# what the Section 5.7 models are fitted to and the two are not the same shape.
cat("Outcome: ", outcome_var, " (days, capped at 90 in Ellis)\n\n", sep = "")

subgroup_outcome_shape <- purrr::map_dfr(fitted_conditions$variable, function(this_condition) {
  frame_id <- fitted_conditions$frame[fitted_conditions$variable == this_condition]
  sub <- build_subgroup(frames[[frame_id]], this_condition)
  y <- sub[[outcome_var]]
  w <- sub$weight_scaled
  mean_w <- stats::weighted.mean(y, w)
  tibble::tibble(
    condition = this_condition,
    n = nrow(sub),
    mean_weighted = mean_w,
    variance_weighted = sum(w * (y - mean_w)^2) / sum(w),
    zero_share = mean(y == 0),
    max_days = max(y)
  )
}) %>%
  mutate(var_over_mean = variance_weighted / mean_weighted)

subgroup_outcome_shape %>%
  arrange(desc(n)) %>%
  transmute(
    Condition = variable_labels[condition],
    n = scales::comma(n),
    `Mean days (wtd)` = sprintf("%.3f", mean_weighted),
    `Variance (wtd)` = sprintf("%.2f", variance_weighted),
    `Var / mean` = sprintf("%.2f", var_over_mean),
    `Zero days` = scales::percent(zero_share, accuracy = 0.1),
    Max = max_days
  ) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nEquidispersion would put variance / mean at 1. No subgroup is close, so\n")
cat("stage two is negative binomial in every one of them, exactly as in model-1.\n")
cat("Note also that the zero share stays high inside every subgroup: conditioning\n")
cat("on a chronic condition does not turn this into a dense count outcome.\n")

# ---- SECTION: Step 1 - The Condition Roster -----------------------------------
# Section 5.7 asks for 19 models. Establishing which 19 - and discovering that
# the PUMF supports 17 - is the first substantive act of the report.

# ---- t1 ----------------------------------------------------------------------
condition_roster %>%
  transmute(
    `#` = proposal_id,
    `Condition (Section 2.2)` = proposal_condition,
    `CCHS variable` = dplyr::coalesce(variable, "&mdash;"),
    Frame = dplyr::recode(frame, main = "main", age35 = "age 35+", none = "&mdash;"),
    Status = dplyr::recode(
      status,
      fitted = "fitted",
      duplicate = "SAME ITEM as row 17",
      unavailable = "NO PUMF ITEM"
    ),
    Note = note
  ) %>%
  print_table(
    caption = paste0(
      "Table t1: Condition roster. The ", nrow(condition_roster),
      " constructs Section 2.2 names, mapped onto the items the CCC module of ",
      "the 2010 and 2014 PUMF carries. Two of them are not separately ",
      "available, so Section 5.7's nineteen models resolve to ",
      nrow(fitted_conditions), " (decision 20)."
    ),
    align = c("r", "l", "l", "l", "l", "l")
  )

# ---- t11 ---------------------------------------------------------------------
condition_inventory <- purrr::map_dfr(fitted_conditions$variable, function(this_condition) {
  frame_id <- fitted_conditions$frame[fitted_conditions$variable == this_condition]
  frame <- frames[[frame_id]]
  sub <- build_subgroup(frame, this_condition)
  y <- sub[[outcome_var]]
  tibble::tibble(
    condition = this_condition,
    frame_id = frame_id,
    frame_n = nrow(frame),
    n = nrow(sub),
    weighted_N = sum(sub[[weight_col]]),
    prevalence = nrow(sub) / nrow(frame),
    n_nonzero = sum(y > 0),
    nonzero_share = mean(y > 0),
    mean_days = stats::weighted.mean(y, sub$weight_scaled),
    kish_deff = kish_design_effect(sub[[weight_col]])
  )
}) %>%
  mutate(
    condition_label = variable_labels[condition],
    flag_small = n < small_subgroup_n,
    verdict = dplyr::case_when(
      n < min_fit_n ~ "not fitted",
      n < small_subgroup_n ~ "fitted, flagged small",
      TRUE ~ "fitted"
    )
  ) %>%
  arrange(desc(n))

readr::write_csv(condition_inventory, paste0(local_data, "condition-inventory.csv"))

condition_inventory %>%
  transmute(
    Condition = condition_label,
    Frame = dplyr::recode(frame_id, main = "main", age35 = "age 35+"),
    n = scales::comma(n),
    `Weighted N` = scales::comma(round(weighted_N)),
    `Prevalence in frame` = scales::percent(prevalence, accuracy = 0.01),
    `n with >= 1 day` = scales::comma(n_nonzero),
    `% with >= 1 day` = scales::percent(nonzero_share, accuracy = 0.1),
    `Mean days (wtd)` = sprintf("%.2f", mean_days),
    `Kish deff` = sprintf("%.2f", kish_deff),
    `Sec 5.7 flag` = ifelse(flag_small, "n &lt; 500", "")
  ) %>%
  print_table(
    caption = paste0(
      "Table t11: Condition subgroup inventory. Both sample sizes Section 5.7 ",
      "asks for - unweighted n and weighted N - plus the count that actually ",
      "limits a count model, the number of respondents reporting at least one ",
      "day absent (decision 26). The design effect is computed within each ",
      "subgroup (decision 29)."
    ),
    align = c("l", "l", "r", "r", "r", "r", "r", "r", "r", "l")
  )

# ---- SECTION: Step 2 - Subgroup Feasibility -----------------------------------
# Section 5.7 asks for a flag where a subgroup falls below 500 unweighted. The
# more useful quantity is how many respondents there are per design column, and
# it is worse than the raw n suggests.

# ---- g1-data-prep ------------------------------------------------------------
feasibility <- purrr::map_dfr(fitted_conditions$variable, function(this_condition) {
  frame_id <- fitted_conditions$frame[fitted_conditions$variable == this_condition]
  sub <- build_subgroup(frames[[frame_id]], this_condition)
  offered <- subgroup_candidates(sub, this_condition, vars_excluding_perceived)
  dropped <- setdiff(setdiff(vars_excluding_perceived, this_condition), offered)
  forced_here <- forced_vars[purrr::map_lgl(forced_vars, ~ is_informative(sub[[.x]]))]
  n_columns <- if (length(offered) > 0) {
    ncol(build_design(sub, c(forced_here, offered))$x)
  } else {
    0L
  }
  tibble::tibble(
    condition = this_condition,
    n = nrow(sub),
    n_nonzero = sum(sub[[outcome_var]] > 0),
    n_offered = length(offered),
    n_dropped = length(dropped),
    dropped_vars = paste(variable_labels[dropped], collapse = "; "),
    n_columns = n_columns
  )
}) %>%
  mutate(
    condition_label = variable_labels[condition],
    per_column = n / pmax(n_columns, 1L),
    nonzero_per_column = n_nonzero / pmax(n_columns, 1L),
    verdict = dplyr::case_when(
      n < min_fit_n ~ "not fitted",
      n < small_subgroup_n ~ "fitted, flagged small",
      TRUE ~ "fitted"
    )
  ) %>%
  arrange(desc(n))

readr::write_csv(feasibility, paste0(local_data, "subgroup-feasibility.csv"))

# ---- g1 ----------------------------------------------------------------------
g1_subgroup_size <- feasibility %>%
  mutate(condition_label = forcats::fct_reorder(condition_label, n)) %>%
  ggplot(aes(x = n, y = condition_label, colour = verdict)) +
  geom_vline(xintercept = small_subgroup_n, colour = "grey55", linetype = "dotted") +
  geom_segment(aes(x = 0, xend = n, yend = condition_label), linewidth = 0.5) +
  geom_point(size = 2.6) +
  geom_point(aes(x = n_nonzero), shape = 21, fill = "white", size = 2.2) +
  scale_x_continuous(labels = scales::comma) +
  scale_colour_manual(values = verdict_colours) +
  labs(
    title = "Graph g1: Subgroup Size Against the Section 5.7 Threshold",
    subtitle = paste0(
      "Filled points are the unweighted subgroup n; hollow points are the respondents reporting at least one day absent.\n",
      "The dotted line is the ", small_subgroup_n,
      " threshold Section 5.7 names. The gap between the two points is what limits a count model."
    ),
    x = "Respondents", y = NULL, colour = NULL
  ) +
  theme(legend.position = "top")

print(g1_subgroup_size)
ggsave(paste0(prints_folder, "g1_subgroup_size.png"),
       g1_subgroup_size, width = 8.5, height = 6.5, dpi = 300)

# ---- t2 ----------------------------------------------------------------------
feasibility %>%
  transmute(
    Condition = condition_label,
    n = scales::comma(n),
    `n with >= 1 day` = scales::comma(n_nonzero),
    `Candidates offered` = n_offered,
    `Dropped as constant` = n_dropped,
    `Design columns` = n_columns,
    `Respondents per column` = sprintf("%.1f", per_column),
    `Non-zero per column` = sprintf("%.1f", nonzero_per_column),
    Verdict = verdict
  ) %>%
  print_table(
    caption = paste0(
      "Table t2: Subgroup feasibility ledger. 'Dropped as constant' counts ",
      "candidate variables that lose all but one level inside the subgroup and ",
      "so cannot be dummy-coded (decision 23); the index condition is removed ",
      "separately and is not counted here. The last column is the honest ",
      "measure of how much a subgroup can support: a penalty is what makes ",
      "estimation possible at all when it falls below one."
    ),
    align = c("l", "r", "r", "r", "r", "r", "r", "r", "l")
  )

# ---- out1 --------------------------------------------------------------------
cat("Output out1: Where the nineteen conditions went\n\n")

cat("Section 2.2 names ", nrow(condition_roster), " constructs.\n", sep = "")
cat("The CCC module of the 2010 and 2014 PUMF carries ",
    dplyr::n_distinct(stats::na.omit(condition_roster$variable)), " distinct items.\n", sep = "")
cat("model-2 fits ", nrow(fitted_conditions), " condition-specific models.\n\n", sep = "")

cat("The two that do not survive the mapping:\n\n")
condition_roster %>%
  filter(status != "fitted") %>%
  transmute(`#` = proposal_id, Condition = proposal_condition, Status = status, Reason = note) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nThe one that needs its own frame:\n\n")
copd_row <- condition_inventory %>% filter(condition == copd_var)
cat("  cc_copd is asked only of respondents aged 35 and over. Requiring it to be\n")
cat("  observed is therefore an age restriction in disguise, which is why model-1\n")
cat("  excluded it. Section 5.7 conditions on the disease, so that restriction\n")
cat("  costs the COPD model nothing it would otherwise have had.\n\n")
cat("    main frame rows:        ", scales::comma(n_analytic), "\n", sep = "")
cat("    age 35+ frame rows:     ", scales::comma(n_analytic_copd),
    sprintf(" (%.1f%% of the main frame)\n", 100 * n_analytic_copd / n_analytic), sep = "")
if (nrow(copd_row) == 1) {
  cat("    COPD subgroup:          ", scales::comma(copd_row$n), "\n", sep = "")
  cat("    COPD with >= 1 day:     ", scales::comma(copd_row$n_nonzero), "\n", sep = "")
}

cat("\n  Age composition of the age 35+ frame (the '25-54' band contains only\n")
cat("  respondents aged 35-54 here, because the question was not asked below 35):\n\n")
ds2 %>%
  count(age_group_3, name = "respondents") %>%
  mutate(share = scales::percent(respondents / sum(respondents), accuracy = 0.1)) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

# ---- SECTION: Step 3 - The Subgroup Samples -----------------------------------
# Seventeen subgroups cut from two frames. They are not disjoint, and the extent
# to which they overlap governs how every estimate in Table 4 may be read.

# ---- out2 --------------------------------------------------------------------
cat("Output out2: Sample construction arithmetic\n\n")
cat("Source rows (Ellis analytic table):          ", scales::comma(n_source), "\n")
cat("Main frame, complete on 48 candidates:       ", scales::comma(n_analytic),
    sprintf(" (%.2f%%)\n", 100 * n_analytic / n_source))
cat("Age 35+ frame, additionally complete on COPD:", scales::comma(n_analytic_copd),
    sprintf(" (%.2f%%)\n", 100 * n_analytic_copd / n_source))
cat("\nThe main frame is the model-1 analytic sample, unchanged. Every condition\n")
cat("subgroup except COPD is a strict subset of it (decision 22), so Table 4 and\n")
cat("Table 3 describe the same respondents.\n\n")

cat("Subgroup coverage of the main frame:\n")
main_conditions <- fitted_conditions$variable[fitted_conditions$frame == "main"]
any_condition <- ds1 %>%
  select(all_of(main_conditions)) %>%
  mutate(across(everything(), ~ . == "Yes")) %>%
  as.matrix() %>%
  rowSums()

cat("  respondents with at least one of the 16:  ",
    scales::comma(sum(any_condition > 0)),
    sprintf(" (%.1f%%)\n", 100 * mean(any_condition > 0)))
cat("  respondents with none of the 16:          ",
    scales::comma(sum(any_condition == 0)),
    sprintf(" (%.1f%%)\n", 100 * mean(any_condition == 0)))
cat("  sum of the 16 subgroup sizes:             ",
    scales::comma(sum(condition_inventory$n[condition_inventory$frame_id == "main"])), "\n")
cat("\nThe sum exceeds the count of distinct respondents because the subgroups\n")
cat("overlap. Table t21 measures by how much.\n")

# ---- t21 ---------------------------------------------------------------------
# The comorbidity check. Section 5.7's design - one model per condition, fitted
# inside that condition's subgroup - does not isolate the condition. It selects
# on it. Everyone in the arthritis subgroup carries whatever else they carry.
comorbidity <- purrr::map_dfr(main_conditions, function(this_condition) {
  sub <- build_subgroup(ds1, this_condition)
  others <- setdiff(main_conditions, this_condition)
  other_counts <- sub %>%
    select(all_of(others)) %>%
    mutate(across(everything(), ~ . == "Yes")) %>%
    as.matrix() %>%
    rowSums()
  most_common <- sub %>%
    select(all_of(others)) %>%
    tidyr::pivot_longer(everything(), names_to = "variable", values_to = "value") %>%
    filter(value == "Yes") %>%
    count(variable, sort = TRUE) %>%
    slice_head(n = 2)
  tibble::tibble(
    condition = this_condition,
    n = nrow(sub),
    mean_others = mean(other_counts),
    share_any_other = mean(other_counts > 0),
    share_three_plus = mean(other_counts >= 3),
    top_comorbidity = paste0(
      variable_labels[most_common$variable], " (",
      scales::percent(most_common$n / nrow(sub), accuracy = 0.1), ")",
      collapse = "; "
    )
  )
}) %>%
  mutate(condition_label = variable_labels[condition]) %>%
  arrange(desc(n))

readr::write_csv(comorbidity, paste0(local_data, "comorbidity-overlap.csv"))

comorbidity %>%
  transmute(
    Condition = condition_label,
    n = scales::comma(n),
    `Mean other conditions` = sprintf("%.2f", mean_others),
    `Has >= 1 other` = scales::percent(share_any_other, accuracy = 0.1),
    `Has >= 3 others` = scales::percent(share_three_plus, accuracy = 0.1),
    `Two most common companions` = top_comorbidity
  ) %>%
  print_table(
    caption = paste0(
      "Table t21: Comorbidity overlap among the 16 main-frame subgroups. These ",
      "subgroups are not disjoint and a Section 5.7 model does not isolate its ",
      "index condition - it conditions on it. The other conditions are ",
      "therefore left in the candidate set (decision 24), so that a coefficient ",
      "in Table 4 is adjusted for what else the respondent carries."
    ),
    align = c("l", "r", "r", "r", "r", "l")
  )

# ---- SECTION: Step 4 - The Decision Registry ----------------------------------
# Model-2 inherits nineteen decisions from model-1 and makes eleven of its own.
# The inherited ones are listed by title; their reasoning lives in model-1 t3.

# ---- t3 ----------------------------------------------------------------------
readr::write_csv(decision_registry, paste0(local_data, "decision-registry.csv"))

decision_registry %>%
  transmute(
    `#` = id,
    Decision = decision,
    `Alternatives considered` = alternatives,
    Chosen = chosen,
    Rationale = rationale,
    `Reverse by editing` = reversal
  ) %>%
  print_table(
    caption = paste0(
      "Table t3: Decision registry for model-2, decisions ",
      min(decision_registry$id), " through ", max(decision_registry$id),
      ". Numbering continues from model-1 so that a decision id is unambiguous ",
      "across the project."
    ),
    align = c("r", "l", "l", "l", "l", "l")
  )

# ---- t31 ---------------------------------------------------------------------
inherited_decisions %>%
  transmute(`#` = id, Decision = decision, `Chosen in model-1` = chosen) %>%
  print_table(
    caption = paste0(
      "Table t31: The nineteen decisions model-2 inherits from model-1 unchanged. ",
      "Alternatives, rationale and reversal instructions are in model-1 Table t3 ",
      "and are deliberately not restated here, because two copies of a decision ",
      "drift apart. Decision 2 is the one model-2 extends - see decision 21."
    ),
    align = c("r", "l", "l"),
    scroll_height = "420px"
  )

# ---- SECTION: Step 5 - The Two Specifications ---------------------------------
# Section 5.7 refers selection back to Section 5.4, which offers four
# specifications. Only one of the two axes survives the reference.

# ---- t4 ----------------------------------------------------------------------
condition_specs %>%
  transmute(
    Specification = model_label,
    Role = role,
    Penalty = lambda_rule,
    `Perceived health` = "excluded",
    `Candidates offered` = paste0("up to ", length(vars_excluding_perceived) - 1L,
                                  " (index condition removed)"),
    `Corresponds to` = ifelse(lambda_rule == "lambda.1se",
                              "Section 5.5 Model 1", "Section 5.5 Model 3")
  ) %>%
  print_table(
    caption = paste0(
      "Table t4: The two specifications carried into every condition subgroup. ",
      "As in model-1, one cross-validated fit per condition yields both rows: ",
      "the predictor set defines the fit, the penalty selects a model from it. ",
      "The perceived-health toggle is not carried, because it belongs to the ",
      "four-way comparison of Section 5.4 and Section 5.7 asks for one model ",
      "per condition (decision 23). lambda.min is designated primary at ",
      "subgroup scale (decision 25)."
    ),
    align = c("l", "l", "l", "l", "l", "l")
  )

# ---- SECTION: Step 6 - Stage One, Per-Condition Penalised Poisson -------------
# Seventeen weighted L1-penalised Poisson fits, one per condition subgroup, each
# with its own 5-fold cross-validated penalty path.

# ---- g2-data-prep ------------------------------------------------------------
condition_fits <- purrr::map(
  stats::setNames(fitted_conditions$variable, fitted_conditions$variable),
  fit_condition
)

for (this_condition in names(condition_fits)) {
  cf <- condition_fits[[this_condition]]
  if (!is.null(cf$lasso)) {
    saveRDS(cf$lasso$cv, paste0(fits_folder, "cv_", this_condition, ".rds"))
    saveRDS(cf$design$map, paste0(fits_folder, "map_", this_condition, ".rds"))
  }
}

fitted_ok <- names(condition_fits)[
  purrr::map_lgl(condition_fits, ~ !is.null(.x$lasso))
]

# Order every downstream facet and axis by subgroup size, largest first, so that
# a reader always knows roughly how much evidence sits behind a panel.
condition_order <- condition_inventory$condition[condition_inventory$condition %in% fitted_ok]
condition_factor_levels <- unname(variable_labels[condition_order])

cv_curve_data <- purrr::map_dfr(fitted_ok, function(this_condition) {
  cv <- condition_fits[[this_condition]]$lasso$cv
  tibble::tibble(
    condition = this_condition,
    lambda = cv$lambda,
    cv_mean = cv$cvm,
    cv_low = cv$cvlo,
    cv_high = cv$cvup,
    n_nonzero = cv$nzero
  )
}) %>%
  mutate(condition_label = factor(variable_labels[condition],
                                  levels = condition_factor_levels))

lambda_marks <- purrr::map_dfr(fitted_ok, function(this_condition) {
  cv <- condition_fits[[this_condition]]$lasso$cv
  tibble::tibble(
    condition = this_condition,
    lambda_rule = c("lambda.1se", "lambda.min"),
    lambda = c(cv$lambda.1se, cv$lambda.min)
  )
}) %>%
  mutate(condition_label = factor(variable_labels[condition],
                                  levels = condition_factor_levels))

path_data <- purrr::map_dfr(fitted_ok, function(this_condition) {
  cf <- condition_fits[[this_condition]]
  as.matrix(cf$lasso$path$beta) %>%
    as.data.frame() %>%
    tibble::rownames_to_column("column") %>%
    tidyr::pivot_longer(-column, names_to = "step", values_to = "estimate") %>%
    mutate(
      lambda = cf$lasso$path$lambda[as.integer(sub("^s", "", step)) + 1],
      condition = this_condition
    ) %>%
    left_join(cf$design$map, by = "column")
}) %>%
  mutate(
    domain = variable_domains[variable],
    condition_label = factor(variable_labels[condition],
                             levels = condition_factor_levels)
  )

# ---- g2 ----------------------------------------------------------------------
g2_cv_curves <- cv_curve_data %>%
  ggplot(aes(x = lambda, y = cv_mean)) +
  geom_ribbon(aes(ymin = cv_low, ymax = cv_high), fill = abcol[["grey"]], alpha = 0.25) +
  geom_line(colour = abcol[["grey"]], linewidth = 0.6) +
  geom_vline(data = lambda_marks,
             aes(xintercept = lambda, colour = lambda_rule),
             linetype = "dashed", linewidth = 0.5) +
  facet_wrap(~ condition_label, ncol = 4, scales = "free") +
  scale_x_log10(labels = scales::label_number(accuracy = 0.001)) +
  scale_colour_manual(values = c("lambda.1se" = abcol[["magenta"]],
                                 "lambda.min" = abcol[["blue"]])) +
  labs(
    title = "Graph g2: Cross-Validated Deviance Inside Each Condition Subgroup",
    subtitle = paste0(
      lasso_folds, "-fold cross-validated Poisson deviance with the one-standard-error band, one panel per condition.\n",
      "Panels are ordered by subgroup size. The wider the band, the less the cross-validation can distinguish penalties."
    ),
    x = "Lambda (log scale)", y = "Poisson deviance", colour = "Penalty"
  ) +
  theme(legend.position = "top", strip.text = element_text(size = 8))

print(g2_cv_curves)
ggsave(paste0(prints_folder, "g2_cv_curves.png"),
       g2_cv_curves, width = 12, height = 10, dpi = 300)

# ---- g3 ----------------------------------------------------------------------
g3_paths <- path_data %>%
  ggplot(aes(x = lambda, y = estimate, group = column, colour = domain)) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_vline(data = lambda_marks,
             aes(xintercept = lambda), colour = "grey40",
             linetype = "dashed", linewidth = 0.35) +
  geom_line(linewidth = 0.35, alpha = 0.8) +
  facet_wrap(~ condition_label, ncol = 4, scales = "free") +
  scale_x_log10(labels = scales::label_number(accuracy = 0.001)) +
  scale_colour_manual(values = domain_colours) +
  labs(
    title = "Graph g3: Coefficient Paths by Andersen Domain, One Panel per Condition",
    subtitle = paste0(
      "Each line is one design column. Dashed lines mark lambda.1se (right) and lambda.min (left).\n",
      "Reading right to left, the order in which coefficients leave zero is the order in which each subgroup insists on them."
    ),
    x = "Lambda (log scale)", y = "Penalised Poisson coefficient", colour = "Domain"
  ) +
  theme(legend.position = "top", strip.text = element_text(size = 8))

print(g3_paths)
ggsave(paste0(prints_folder, "g3_paths.png"),
       g3_paths, width = 12, height = 10, dpi = 300)

# ---- SECTION: Step 7 - Selection Results --------------------------------------
# What each subgroup retained under each penalty rule, and how often the
# parsimonious rule returned nothing at all.

# ---- t5 ----------------------------------------------------------------------
selection_long <- purrr::map_dfr(fitted_ok, function(this_condition) {
  cf <- condition_fits[[this_condition]]
  purrr::pmap_dfr(
    condition_specs %>% select(spec_id, model_label, lambda_rule),
    function(spec_id, model_label, lambda_rule) {
      coefficients_at(cf$lasso, cf$design, lambda_rule) %>%
        mutate(condition = this_condition, spec_id = spec_id,
               model_label = model_label, lambda_rule = lambda_rule)
    }
  )
}) %>%
  mutate(
    domain = variable_domains[variable],
    condition_label = variable_labels[condition],
    variable_label = variable_labels[variable]
  )

readr::write_csv(selection_long, paste0(local_data, "selection-long.csv"))

selection_counts <- selection_long %>%
  group_by(condition, condition_label, spec_id, model_label) %>%
  summarise(
    columns_offered = n(),
    columns_retained = sum(retained),
    variables_retained = dplyr::n_distinct(variable[retained]),
    exposure_retained = dplyr::n_distinct(variable[retained & domain == "Exposure"]),
    .groups = "drop"
  ) %>%
  left_join(condition_inventory %>% select(condition, n, n_nonzero), by = "condition") %>%
  mutate(empty_selection = variables_retained <= length(forced_vars))

readr::write_csv(selection_counts, paste0(local_data, "selection-counts.csv"))

selection_counts %>%
  select(condition, condition_label, n, n_nonzero, model_label,
         columns_offered, columns_retained, variables_retained) %>%
  tidyr::pivot_wider(
    names_from = model_label,
    values_from = c(columns_retained, variables_retained),
    names_sep = " | "
  ) %>%
  arrange(desc(n)) %>%
  transmute(
    Condition = condition_label,
    n = scales::comma(n),
    `n with >= 1 day` = scales::comma(n_nonzero),
    `Columns offered` = columns_offered,
    `Cols kept (min)` = `columns_retained | Permissive (min)`,
    `Vars kept (min)` = `variables_retained | Permissive (min)`,
    `Cols kept (1SE)` = `columns_retained | Parsimonious (1SE)`,
    `Vars kept (1SE)` = `variables_retained | Parsimonious (1SE)`
  ) %>%
  print_table(
    caption = paste0(
      "Table t5: What each subgroup retained under each penalty rule. The cycle ",
      "indicator is exempt from the penalty (inherited decision 8), so a count ",
      "of 1 variable means nothing but cycle survived. Compare the two 'Vars ",
      "kept' columns: the difference between them is the evidence behind ",
      "decision 25."
    ),
    align = c("l", "r", "r", "r", "r", "r", "r", "r")
  )

# ---- t51 ---------------------------------------------------------------------
selection_matrix <- selection_long %>%
  group_by(domain, variable, variable_label, condition_label, spec_id) %>%
  summarise(kept = any(retained), .groups = "drop") %>%
  tidyr::pivot_wider(names_from = spec_id, values_from = kept, values_fill = FALSE) %>%
  mutate(
    mark = dplyr::case_when(
      spec_min & spec_1se ~ "both",
      spec_min            ~ "min",
      spec_1se            ~ "1SE",
      TRUE                ~ ""
    )
  ) %>%
  select(domain, variable, variable_label, condition_label, mark) %>%
  tidyr::pivot_wider(names_from = condition_label, values_from = mark, values_fill = "") %>%
  arrange(factor(domain, levels = names(domain_colours)), variable_label)

readr::write_csv(selection_matrix, paste0(local_data, "selection-matrix.csv"))

selection_matrix %>%
  select(Domain = domain, Variable = variable_label,
         any_of(unname(variable_labels[condition_order]))) %>%
  print_table(
    caption = paste0(
      "Table t51: Which variables each condition retained. 'both' means the ",
      "variable survived at both penalties, 'min' only at lambda.min, '1SE' ",
      "only at lambda.1se, and blank means it was offered and eliminated. An ",
      "empty cell for a variable that was never offered - because it went ",
      "constant inside that subgroup - is indistinguishable here; Table t2 ",
      "carries the drop counts."
    ),
    align = c("l", "l", rep("c", length(condition_order))),
    scroll_height = "700px"
  )

# ---- g4 ----------------------------------------------------------------------
g4_selection_grid <- selection_long %>%
  group_by(domain, variable, condition, spec_id) %>%
  summarise(kept = any(retained), .groups = "drop") %>%
  tidyr::pivot_wider(names_from = spec_id, values_from = kept, values_fill = FALSE) %>%
  # Completing the grid turns "never offered inside this subgroup" into a stated
  # third state rather than a blank a reader has to interpret.
  tidyr::complete(
    condition = fitted_ok,
    tidyr::nesting(domain, variable),
    fill = list(spec_min = NA, spec_1se = NA)
  ) %>%
  mutate(
    outcome = dplyr::case_when(
      is.na(spec_min)      ~ "not offered",
      spec_min & spec_1se  ~ "retained at both penalties",
      spec_min | spec_1se  ~ "retained at one penalty",
      TRUE                 ~ "eliminated"
    ),
    outcome = factor(outcome, levels = c("retained at both penalties",
                                         "retained at one penalty",
                                         "eliminated", "not offered")),
    variable_label = variable_labels[variable],
    condition_label = factor(variable_labels[condition], levels = condition_factor_levels),
    domain = factor(domain, levels = names(domain_colours))
  ) %>%
  filter(!is.na(condition_label)) %>%
  ggplot(aes(x = condition_label, y = variable_label, fill = outcome)) +
  geom_tile(colour = "white", linewidth = 0.5) +
  facet_grid(domain ~ ., scales = "free_y", space = "free_y") +
  scale_fill_manual(
    values = c(
      "retained at both penalties" = abcol[["magenta"]],
      "retained at one penalty"    = abcol[["green"]],
      "eliminated"                 = "grey90",
      "not offered"                = "grey60"
    ),
    drop = FALSE
  ) +
  labs(
    title = "Graph g4: Selection Grid Across the Condition-Specific Models",
    subtitle = paste0(
      "A variable counts as retained when at least one of its design columns survived the penalty.\n",
      "Columns are conditions, ordered by subgroup size; rows are candidate variables grouped by Andersen domain.\n",
      "A row that is coloured across many columns is a predictor of absenteeism regardless of which condition a worker has."
    ),
    x = NULL, y = NULL, fill = NULL
  ) +
  theme(
    legend.position = "top",
    strip.text.y = element_text(angle = 0),
    panel.grid = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

print(g4_selection_grid)
ggsave(paste0(prints_folder, "g4_selection_grid.png"),
       g4_selection_grid, width = 11, height = 13, dpi = 300)

# ---- SECTION: Step 8 - Stage Two, Negative Binomial Estimation ----------------
# Each retained set is re-estimated without penalty under a negative binomial
# likelihood, inside its own subgroup. This step answers Section 5.7 and yields
# deliverable Table 4. Intervals are Wald, sandwich, and Kish-inflated - not
# bootstrap: inherited decisions 10 and 15.

# ---- t6-data-prep ------------------------------------------------------------
nb_keys <- tidyr::expand_grid(
  condition = fitted_ok,
  spec_id = condition_specs$spec_id
) %>%
  mutate(key = paste0(condition, "__", spec_id))

spec_terms <- purrr::set_names(
  purrr::map2(nb_keys$condition, nb_keys$spec_id, function(this_condition, this_spec) {
    kept <- selection_long %>%
      filter(condition == this_condition, spec_id == this_spec) %>%
      retained_variables()
    union(condition_fits[[this_condition]]$forced,
          setdiff(kept, condition_fits[[this_condition]]$forced))
  }),
  nb_keys$key
)

nb_fits <- purrr::imap(spec_terms, function(term_vars, this_key) {
  this_condition <- sub("__.*$", "", this_key)
  fit_nb(condition_fits[[this_condition]]$subgroup, term_vars, outcome_var)
})

nb_nulls <- purrr::map(
  stats::setNames(fitted_ok, fitted_ok),
  ~ fit_nb(condition_fits[[.x]]$subgroup, character(0), outcome_var)
)

for (this_key in names(nb_fits)) {
  if (!is.null(nb_fits[[this_key]])) {
    saveRDS(nb_fits[[this_key]], paste0(fits_folder, "nb_", this_key, ".rds"))
  }
}
saveRDS(nb_nulls, paste0(fits_folder, "nb_nulls.rds"))

nb_coefficients <- purrr::imap_dfr(nb_fits, function(fit, this_key) {
  if (is.null(fit)) return(tibble::tibble())
  this_condition <- sub("__.*$", "", this_key)
  this_spec <- sub("^.*__", "", this_key)
  tidy_nb(fit, condition_fits[[this_condition]]$design$map,
          deff = condition_fits[[this_condition]]$kish_deff) %>%
    mutate(condition = this_condition, spec_id = this_spec)
}) %>%
  left_join(condition_specs %>% select(spec_id, model_label, role), by = "spec_id") %>%
  mutate(
    domain = variable_domains[variable],
    variable_label = variable_labels[variable],
    condition_label = variable_labels[condition],
    term = paste0(variable_label, ifelse(level == "", "", paste0(": ", level)))
  )

readr::write_csv(nb_coefficients, paste0(local_data, "nb-coefficients.csv"))

# ---- out5 --------------------------------------------------------------------
cat("Output out5: Variance-estimation instruments for Section 5.7\n\n")
cat("Section 5.7 asks for 500 bootstrap replicate weights, the same instrument\n")
cat("Sections 5.3 and 5.5 ask for. They do not exist in the 2010 or 2014 PUMF\n")
cat("(inherited decision 10), and strata and PSU identifiers are suppressed, so\n")
cat("no fully design-based variance estimator can be built for any subgroup.\n")
cat("What follows are two LOWER bounds on how far the model-based intervals\n")
cat("understate uncertainty. Neither sees clustering.\n\n")

cat("Kish design effect, computed WITHIN each subgroup (decision 29):\n\n")
condition_inventory %>%
  # Compute the effective size BEFORE formatting, so the arithmetic never meets
  # a comma-separated character.
  mutate(effective_n = round(n / kish_deff)) %>%
  transmute(
    Condition = condition_label,
    n = scales::comma(n),
    `Kish deff` = sprintf("%.3f", kish_deff),
    `Effective n` = scales::comma(effective_n),
    `SE multiplier` = sprintf("%.3f", sqrt(kish_deff))
  ) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

sandwich_multipliers <- purrr::imap_dfr(nb_fits, function(fit, this_key) {
  if (is.null(fit)) return(tibble::tibble())
  ratio <- tryCatch(
    sqrt(diag(robust_vcov(fit))) / sqrt(diag(stats::vcov(fit))),
    error = function(e) NA_real_
  )
  tibble::tibble(key = this_key, ratio = ratio)
}) %>%
  filter(!is.na(ratio))

cat("\nHuber-White sandwich SE multiplier, over every term in every fitted model:\n")
cat("  median: ", sprintf("%.3f", stats::median(sandwich_multipliers$ratio)), "\n", sep = "")
cat("  range:  ", sprintf("%.3f", min(sandwich_multipliers$ratio)), " to ",
    sprintf("%.3f", max(sandwich_multipliers$ratio)), "\n", sep = "")
cat("  terms:  ", scales::comma(nrow(sandwich_multipliers)), "\n\n", sep = "")

cat("The spread is wider than model-1's because subgroup cells are thinner. A\n")
cat("multiplier below 1 is not a narrowing of the true interval; it is a thin\n")
cat("cell in which the sandwich estimator is itself unreliable. Table t62\n")
cat("reports all three interval variants side by side and marks terms whose\n")
cat("standard error exceeds ", unstable_se, " on the log scale (decision 27).\n", sep = "")

# ---- t6 ----------------------------------------------------------------------
# Deliverable Table 4. One row per estimated term per condition, with the two
# penalty rules side by side so that a reader can see at once which associations
# survive the parsimonious specification.
table_4 <- nb_coefficients %>%
  mutate(
    cell = sprintf("%.2f (%.2f-%.2f)%s%s",
                   rate_ratio, ci_low, ci_high,
                   ifelse(!is.na(p_value) & p_value < 0.05, "*", ""),
                   ifelse(unstable, " !", ""))
  ) %>%
  select(condition, condition_label, domain, term, model_label, cell) %>%
  tidyr::pivot_wider(names_from = model_label, values_from = cell, values_fill = "") %>%
  left_join(condition_inventory %>% select(condition, n, n_weighted = weighted_N),
            by = "condition") %>%
  arrange(desc(n), factor(domain, levels = names(domain_colours)), term)

# A specification that retained nothing anywhere would leave its column absent
# from the pivot. Guarantee both, so the deliverable table always has the same
# shape regardless of what the penalties did.
for (this_label in condition_specs$model_label) {
  if (!this_label %in% names(table_4)) table_4[[this_label]] <- ""
}

readr::write_csv(table_4, paste0(local_data, "table-4-condition-models.csv"))

table_4 %>%
  transmute(
    Condition = condition_label,
    n = scales::comma(n),
    `Weighted N` = scales::comma(round(n_weighted)),
    Domain = domain,
    Term = term,
    `PR (95% CI), lambda.min` = `Permissive (min)`,
    `PR (95% CI), lambda.1SE` = `Parsimonious (1SE)`
  ) %>%
  print_table(
    caption = paste0(
      "Table t6 (deliverable Table 4): Adjusted prevalence rate ratios with 95% ",
      "Wald intervals for every term retained inside every condition subgroup, ",
      "under both penalty rules. An asterisk marks Wald p &lt; 0.05; an ",
      "exclamation mark flags a term whose standard error exceeds ", unstable_se,
      " on the log scale and whose interval is therefore uninformative ",
      "(decision 27). A blank cell means the term was not retained under that ",
      "penalty. These are NOT bootstrap intervals (inherited decision 10), and ",
      "they ignore the selection step that produced the term list. Table t62 ",
      "carries the log-scale coefficients, standard errors, exact p-values and ",
      "two wider interval variants."
    ),
    align = c("l", "r", "r", "l", "l", "r", "r"),
    scroll_height = "700px"
  )

# ---- t62 ---------------------------------------------------------------------
# The Section 5.7 compliance artifact: every quantity the section asks to be
# reported, one row per estimated term per condition per specification.
nb_coefficients %>%
  left_join(condition_inventory %>% select(condition, n, weighted_N), by = "condition") %>%
  arrange(desc(n), model_label, factor(domain, levels = names(domain_colours)), term) %>%
  transmute(
    Condition = condition_label,
    n = scales::comma(n),
    `Weighted N` = scales::comma(round(weighted_N)),
    Specification = model_label,
    Domain = domain,
    Term = term,
    `Beta (log)` = sprintf("%.4f", estimate),
    SE = sprintf("%.4f", std_error),
    `SE robust` = sprintf("%.4f", se_robust),
    PR = sprintf("%.3f", rate_ratio),
    `95% CI (Wald)` = sprintf("%.3f-%.3f", ci_low, ci_high),
    `95% CI (sandwich)` = sprintf("%.3f-%.3f", ci_low_robust, ci_high_robust),
    `95% CI (Kish)` = sprintf("%.3f-%.3f", ci_low_kish, ci_high_kish),
    `p (Wald)` = ifelse(p_value < 0.0001, "&lt;0.0001", sprintf("%.4f", p_value)),
    `p (robust)` = ifelse(p_robust < 0.0001, "&lt;0.0001", sprintf("%.4f", p_robust)),
    Flag = ifelse(unstable, "UNSTABLE", "")
  ) %>%
  print_table(
    caption = paste0(
      "Table t62 (deliverable Table 4, full ledger): Everything Section 5.7 ",
      "asks to be reported - unweighted n, weighted N, log-scale coefficient, ",
      "standard error, prevalence rate ratio, 95% interval and Wald p-value - ",
      "for every term in every condition-specific model. The sandwich and Kish ",
      "columns bracket the understatement caused by the absent bootstrap ",
      "weights (inherited decisions 10 and 15); both are lower bounds. All ",
      "intervals remain conditional on a selection step that used the same ",
      "subgroup."
    ),
    align = c("l", "r", "r", "l", "l", "l", rep("r", 9), "l"),
    scroll_height = "700px"
  )

# ---- g5 ----------------------------------------------------------------------
# Which predictors recur across conditions. A term retained in one subgroup is a
# finding about that condition; a term retained in a dozen is a finding about
# absenteeism.
recurrence <- nb_coefficients %>%
  filter(spec_id == primary_spec, !unstable) %>%
  count(term, name = "n_conditions") %>%
  arrange(desc(n_conditions))

readr::write_csv(recurrence, paste0(local_data, "term-recurrence.csv"))

recurrent_terms <- recurrence %>%
  slice_head(n = 9) %>%
  pull(term)

g5_data <- nb_coefficients %>%
  filter(spec_id == primary_spec, term %in% recurrent_terms, !unstable) %>%
  left_join(condition_inventory %>% select(condition, n), by = "condition") %>%
  mutate(condition_label = forcats::fct_reorder(condition_label, n))

g5_forest <- g5_data %>%
  ggplot(aes(x = rate_ratio, y = condition_label)) +
  geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.4) +
  geom_linerange(aes(xmin = ci_low, xmax = ci_high),
                 colour = abcol[["blue"]], linewidth = 0.5) +
  geom_point(size = 1.9, colour = abcol[["blue"]]) +
  facet_wrap(~ term, ncol = 3, scales = "free_y") +
  scale_x_log10() +
  labs(
    title = "Graph g5: Predictors That Recur Across Condition-Specific Models",
    subtitle = paste0(
      "The nine terms retained in the greatest number of subgroups under the primary penalty rule, shown wherever they were retained.\n",
      "Conditions are ordered by subgroup size, largest at the top. Wald intervals; see inherited decision 10 for why these are not the intervals Section 5.7 requests."
    ),
    x = "Rate ratio (log scale)", y = NULL
  ) +
  theme(strip.text = element_text(size = 8))

print(g5_forest)
ggsave(paste0(prints_folder, "g5_forest.png"),
       g5_forest, width = 11, height = 9, dpi = 300)

# ---- t61 ---------------------------------------------------------------------
model_fit_comparison <- purrr::imap_dfr(nb_fits, function(fit, this_key) {
  this_condition <- sub("__.*$", "", this_key)
  this_spec <- sub("^.*__", "", this_key)
  sub <- condition_fits[[this_condition]]$subgroup
  null_fit <- nb_nulls[[this_condition]]

  if (is.null(fit) || is.null(null_fit)) {
    return(tibble::tibble(
      condition = this_condition, spec_id = this_spec,
      n_analytic = nrow(sub), weighted_N = sum(sub[[weight_col]]),
      n_terms = NA_integer_, aic = NA_real_, bic = NA_real_,
      log_likelihood = NA_real_, mcfadden_r2 = NA_real_, theta = NA_real_,
      rmse = NA_real_, mae = NA_real_, c_statistic = NA_real_,
      c_comparable_share = NA_real_, converged = FALSE
    ))
  }

  fitted_values <- stats::fitted(fit)
  residuals_raw <- sub[[outcome_var]] - fitted_values
  concordance_row <- harrell_c(sub[[outcome_var]], fitted_values, sub$weight_scaled)

  tibble::tibble(
    condition = this_condition,
    spec_id = this_spec,
    n_analytic = nrow(sub),
    weighted_N = sum(sub[[weight_col]]),
    n_terms = length(stats::coef(fit)) - 1L,
    aic = stats::AIC(fit),
    bic = stats::BIC(fit),
    log_likelihood = as.numeric(stats::logLik(fit)),
    mcfadden_r2 = 1 - as.numeric(stats::logLik(fit)) / as.numeric(stats::logLik(null_fit)),
    theta = fit$theta,
    # Inherited decision 19: weighted, because the models are estimated on a
    # weighted likelihood and the target population is the weighted one.
    rmse = sqrt(stats::weighted.mean(residuals_raw^2, sub$weight_scaled)),
    mae = stats::weighted.mean(abs(residuals_raw), sub$weight_scaled),
    c_statistic = concordance_row$c_statistic,
    c_comparable_share = concordance_row$comparable_share,
    converged = isTRUE(fit$converged)
  )
}) %>%
  left_join(condition_specs %>% select(spec_id, model_label, role), by = "spec_id") %>%
  mutate(condition_label = variable_labels[condition]) %>%
  arrange(desc(n_analytic), spec_id)

readr::write_csv(model_fit_comparison, paste0(local_data, "model-comparison.csv"))

model_fit_comparison %>%
  transmute(
    Condition = condition_label,
    Specification = model_label,
    n = scales::comma(n_analytic),
    `Weighted N` = scales::comma(round(weighted_N)),
    Terms = n_terms,
    AIC = scales::comma(round(aic)),
    BIC = scales::comma(round(bic)),
    `McFadden R2` = sprintf("%.4f", mcfadden_r2),
    Theta = sprintf("%.4f", theta),
    RMSE = sprintf("%.3f", rmse),
    MAE = sprintf("%.3f", mae),
    `C-statistic` = sprintf("%.4f", c_statistic),
    `Comparable pairs` = scales::percent(c_comparable_share, accuracy = 0.1),
    Converged = ifelse(converged, "yes", "NO")
  ) %>%
  print_table(
    caption = paste0(
      "Table t61: Section 5.8 metrics computed IN SAMPLE, for every ",
      "condition-specific model. RMSE and MAE are weighted (inherited decision ",
      "19). AIC and BIC come from a weighted pseudo-likelihood and rank models ",
      "rather than measure them (inherited decision 18); across conditions they ",
      "are not comparable at all, because each is computed on a different ",
      "subgroup. Read them down a condition, never across. The held-out ",
      "versions, which are the ones Section 5.8 actually asks for, are in ",
      "Tables t63 and t64."
    ),
    align = c("l", "l", "r", "r", "r", "r", "r", "r", "r", "r", "r", "r", "r", "l"),
    scroll_height = "700px"
  )

# ---- out3 --------------------------------------------------------------------
cat("Output out3: Convergence, dispersion, and the empty-selection count\n\n")

cat("Section 5.7 asks for conditions where the model fails to converge to be\n")
cat("flagged explicitly. The count:\n\n")

convergence_summary <- model_fit_comparison %>%
  group_by(model_label) %>%
  summarise(
    models = n(),
    converged = sum(converged),
    failed = sum(!converged),
    .groups = "drop"
  )
convergence_summary %>% as.data.frame() %>% print(row.names = FALSE)

failed_models <- model_fit_comparison %>% filter(!converged)
if (nrow(failed_models) > 0) {
  cat("\nModels that failed to converge:\n\n")
  failed_models %>%
    transmute(Condition = condition_label, Specification = model_label,
              n = n_analytic) %>%
    as.data.frame() %>%
    print(row.names = FALSE)
} else {
  cat("\nNo condition-specific model failed to converge.\n")
}

cat("\nSelections that retained nothing beyond the forced cycle indicator:\n\n")
selection_counts %>%
  filter(variables_retained <= 1L) %>%
  transmute(Condition = condition_label, Specification = model_label,
            n = scales::comma(n), `Variables retained` = variables_retained) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nDispersion across subgroups (theta; smaller means more overdispersed):\n\n")
model_fit_comparison %>%
  filter(spec_id == primary_spec, !is.na(theta)) %>%
  transmute(Condition = condition_label, n = scales::comma(n_analytic),
            Theta = sprintf("%.4f", theta)) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

# ---- SECTION: Step 9 - Section 5.8, Held-Out Performance ----------------------
# Section 5.8 asks for AIC, BIC, McFadden's pseudo-R-squared, a C-statistic, and
# RMSE and MAE "computed on the withheld test fold", averaged over five folds,
# for each condition-specific model. Table t61 gave the in-sample versions.
# This step gives the held-out ones.
#
# Two variants, mirroring model-1 exactly (inherited decision 16):
#   t63  term set held FIXED across folds - the literal reading, and optimistic
#   t64  selection RE-RUN inside each training fold - the honest estimate, and a
#        measure of how stable the selection itself is inside a small subgroup
#
# Leave-one-out is declined, per decision 28: Harrell's C is computed over pairs
# of held-out respondents and a leave-one-out fold contains one.

# ---- t63-data-prep -----------------------------------------------------------
if (!force_refit_cv && file.exists(cv_cache_path)) {
  cv_performance <- readRDS(cv_cache_path)
  cat("Loaded cached cross-validation results from ", cv_cache_path, "\n", sep = "")
} else {
  cat("Refitting the Section 5.8 cross-validation. This is the slow block.\n")
  cv_start_time <- Sys.time()

  cv_performance <- purrr::map_dfr(fitted_ok, function(this_condition) {
    cf <- condition_fits[[this_condition]]
    sub <- cf$subgroup
    fold_id <- assign_folds(nrow(sub), perf_folds, perf_seed)
    cat("  ", this_condition, " (n = ", nrow(sub), ")\n", sep = "")

    purrr::map_dfr(seq_len(perf_folds), function(this_fold) {
      test_rows <- which(fold_id == this_fold)
      train_rows <- which(fold_id != this_fold)

      # Variant A - term set fixed at what the full subgroup selected.
      fixed <- purrr::pmap_dfr(
        condition_specs %>% select(spec_id),
        function(spec_id) {
          term_vars <- spec_terms[[paste0(this_condition, "__", spec_id)]]
          evaluate_fold(sub, train_rows, test_rows, term_vars, outcome_var) %>%
            mutate(condition = this_condition, spec_id = spec_id,
                   fold = this_fold, variant = "fixed term set")
        }
      )

      # Variant B - the whole two-stage procedure re-run inside the training
      # fold, so no held-out respondent contributed to selection.
      train_frame <- droplevels(sub[train_rows, , drop = FALSE])
      fold_offered <- subgroup_candidates(train_frame, this_condition,
                                          vars_excluding_perceived)
      fold_forced <- forced_vars[
        purrr::map_lgl(forced_vars, ~ is_informative(train_frame[[.x]]))
      ]
      fold_design <- if (length(fold_offered) > 0) {
        build_design(train_frame, c(fold_forced, fold_offered))
      } else {
        NULL
      }
      fold_lasso <- if (!is.null(fold_design)) {
        tryCatch(
          fit_lasso(fold_design, train_frame[[outcome_var]],
                    train_frame$weight_scaled, lasso_seed),
          error = function(e) NULL
        )
      } else {
        NULL
      }

      reselected <- purrr::pmap_dfr(
        condition_specs %>% select(spec_id, lambda_rule),
        function(spec_id, lambda_rule) {
          term_vars <- if (is.null(fold_lasso)) {
            fold_forced
          } else {
            kept <- coefficients_at(fold_lasso, fold_design, lambda_rule) %>%
              retained_variables()
            union(fold_forced, setdiff(kept, fold_forced))
          }
          evaluate_fold(sub, train_rows, test_rows, term_vars, outcome_var) %>%
            mutate(condition = this_condition, spec_id = spec_id,
                   fold = this_fold, variant = "selection re-run",
                   n_vars_selected = length(term_vars))
        }
      )

      bind_rows(fixed, reselected)
    })
  }) %>%
    left_join(condition_specs %>% select(spec_id, model_label, role), by = "spec_id") %>%
    mutate(condition_label = variable_labels[condition])

  attr(cv_performance, "elapsed_minutes") <-
    as.numeric(difftime(Sys.time(), cv_start_time, units = "mins"))
  saveRDS(cv_performance, cv_cache_path)
}

readr::write_csv(cv_performance, paste0(local_data, "cv-performance-folds.csv"))

cv_summary <- cv_performance %>%
  group_by(variant, condition, condition_label, spec_id, model_label) %>%
  summarise(
    folds_converged = sum(converged),
    n_terms_mean = mean(n_terms, na.rm = TRUE),
    n_terms_range = if (all(is.na(n_terms))) {
      "n/a"
    } else {
      paste0(min(n_terms, na.rm = TRUE), "-", max(n_terms, na.rm = TRUE))
    },
    rmse_mean = mean(rmse, na.rm = TRUE), rmse_sd = stats::sd(rmse, na.rm = TRUE),
    mae_mean = mean(mae, na.rm = TRUE), mae_sd = stats::sd(mae, na.rm = TRUE),
    mcfadden_mean = mean(mcfadden_r2, na.rm = TRUE),
    mcfadden_sd = stats::sd(mcfadden_r2, na.rm = TRUE),
    c_mean = mean(c_statistic, na.rm = TRUE), c_sd = stats::sd(c_statistic, na.rm = TRUE),
    comparable_share = mean(comparable_share, na.rm = TRUE),
    unscorable = sum(n_unscorable, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(condition_inventory %>% select(condition, n), by = "condition") %>%
  arrange(variant, desc(n), spec_id)

readr::write_csv(cv_summary, paste0(local_data, "cv-performance-summary.csv"))

# ---- t63 ---------------------------------------------------------------------
cv_summary %>%
  filter(variant == "fixed term set") %>%
  transmute(
    Condition = condition_label,
    Specification = model_label,
    n = scales::comma(n),
    Terms = round(n_terms_mean),
    `CV RMSE` = sprintf("%.3f (%.3f)", rmse_mean, rmse_sd),
    `CV MAE` = sprintf("%.3f (%.3f)", mae_mean, mae_sd),
    `CV McFadden R2` = sprintf("%.4f (%.4f)", mcfadden_mean, mcfadden_sd),
    `CV C-statistic` = sprintf("%.4f (%.4f)", c_mean, c_sd),
    `Comparable pairs` = scales::percent(comparable_share, accuracy = 0.1),
    `Folds converged` = paste0(folds_converged, " / ", perf_folds)
  ) %>%
  print_table(
    caption = paste0(
      "Table t63: Section 5.8 five-fold cross-validated performance, term set ",
      "held FIXED across folds. Each cell is the mean over five folds of the ",
      "condition's own subgroup, with the between-fold standard deviation in ",
      "parentheses. Metrics are computed on the withheld fold only, weighted ",
      "(inherited decision 19). These numbers are optimistic: the LASSO that ",
      "chose the term set saw every fold (inherited decision 16). Table t64 ",
      "removes that advantage. Leave-one-out was declined - see decision 28."
    ),
    align = c("l", "l", "r", "r", "r", "r", "r", "r", "r", "l"),
    scroll_height = "700px"
  )

# ---- t64 ---------------------------------------------------------------------
cv_summary %>%
  filter(variant == "selection re-run") %>%
  transmute(
    Condition = condition_label,
    Specification = model_label,
    n = scales::comma(n),
    `Terms (mean)` = round(n_terms_mean),
    `Terms (range)` = n_terms_range,
    `CV RMSE` = sprintf("%.3f (%.3f)", rmse_mean, rmse_sd),
    `CV McFadden R2` = sprintf("%.4f (%.4f)", mcfadden_mean, mcfadden_sd),
    `CV C-statistic` = sprintf("%.4f (%.4f)", c_mean, c_sd),
    `Folds converged` = paste0(folds_converged, " / ", perf_folds)
  ) %>%
  print_table(
    caption = paste0(
      "Table t64: The same five folds, with the entire two-stage procedure ",
      "re-run inside each training fold so that no held-out respondent ",
      "contributed to selection. The term range is the artifact to read first: ",
      "it says how far a subgroup's selected set moves when a fifth of it is ",
      "withheld. In subgroups this size that range is the honest description of ",
      "what Section 5.7 can and cannot establish."
    ),
    align = c("l", "l", "r", "r", "r", "r", "r", "r", "l"),
    scroll_height = "700px"
  )

# ---- g6 ----------------------------------------------------------------------
g6_data <- cv_performance %>%
  filter(spec_id == primary_spec) %>%
  select(condition, condition_label, variant, fold, rmse, mcfadden_r2, c_statistic) %>%
  tidyr::pivot_longer(c(rmse, mcfadden_r2, c_statistic),
                      names_to = "metric", values_to = "value") %>%
  filter(!is.na(value)) %>%
  mutate(
    metric = factor(
      metric,
      levels = c("rmse", "mcfadden_r2", "c_statistic"),
      labels = c("RMSE (held-out)", "McFadden R2 (held-out)", "C-statistic (held-out)")
    ),
    condition_label = factor(condition_label, levels = rev(condition_factor_levels))
  )

g6_cv_spread <- g6_data %>%
  ggplot(aes(x = value, y = condition_label, colour = variant, shape = variant)) +
  geom_point(size = 1.7, alpha = 0.5, position = position_dodge(width = 0.6)) +
  stat_summary(fun = mean, geom = "point", size = 3.4, alpha = 0.95,
               position = position_dodge(width = 0.6)) +
  facet_wrap(~ metric, scales = "free_x", nrow = 1) +
  scale_colour_manual(values = c("fixed term set" = abcol[["magenta"]],
                                 "selection re-run" = abcol[["blue"]])) +
  labs(
    title = "Graph g6: Held-Out Performance by Fold, Condition by Condition",
    subtitle = paste0(
      "Primary specification (lambda.min) only. Small points are the five individual folds; the large point is their mean.\n",
      "Conditions are ordered by subgroup size, largest at the top. Where the fold points scatter widely, the mean is not a number to quote."
    ),
    x = NULL, y = NULL, colour = NULL, shape = NULL
  ) +
  theme(legend.position = "top")

print(g6_cv_spread)
ggsave(paste0(prints_folder, "g6_cv_spread.png"),
       g6_cv_spread, width = 12, height = 8, dpi = 300)

# ---- out6 --------------------------------------------------------------------
cat("Output out6: Reading the C-statistic, and the size of the selection optimism\n\n")

zero_shares <- subgroup_outcome_shape %>%
  transmute(Condition = variable_labels[condition],
            `Zero days` = scales::percent(zero_share, accuracy = 0.1))
cat("Share of respondents at zero days, by subgroup:\n\n")
zero_shares %>% as.data.frame() %>% print(row.names = FALSE)

cat("\nHarrell's C counts a pair only when the two respondents differ on the\n")
cat("outcome. Conditioning on a chronic condition raises the mean days absent\n")
cat("but leaves most respondents at zero, so most pairs are still incomparable\n")
cat("and never enter the denominator. Table t63 reports the comparable share\n")
cat("beside every C for exactly this reason.\n\n")

optimism <- cv_summary %>%
  filter(spec_id == primary_spec) %>%
  select(variant, condition_label, n, rmse_mean, mcfadden_mean, c_mean) %>%
  tidyr::pivot_wider(names_from = variant,
                     values_from = c(rmse_mean, mcfadden_mean, c_mean))

cat("Selection optimism (fixed minus re-run), primary specification:\n\n")
optimism %>%
  transmute(
    Condition = condition_label,
    n = scales::comma(n),
    `d RMSE` = sprintf("%+.4f", `rmse_mean_fixed term set` - `rmse_mean_selection re-run`),
    `d McFadden` = sprintf("%+.4f", `mcfadden_mean_fixed term set` - `mcfadden_mean_selection re-run`),
    `d C` = sprintf("%+.4f", `c_mean_fixed term set` - `c_mean_selection re-run`)
  ) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nA positive d McFadden or d C is the amount by which evaluating a model on\n")
cat("data that helped select it flatters that model. model-1 found this quantity\n")
cat("to be essentially zero at n = 48,932. Subgroups are smaller by one to two\n")
cat("orders of magnitude, so the same reassurance should not be assumed here;\n")
cat("the table above is where it is either earned or lost.\n")

cat("\nTerm-set instability under refitting, primary specification:\n\n")
cat("Both columns count DESIGN COLUMNS, not variables, so that the full-subgroup\n")
cat("fit and the fold refits are measured on the same scale.\n\n")
cv_summary %>%
  filter(variant == "selection re-run", spec_id == primary_spec) %>%
  transmute(
    Condition = condition_label,
    n = scales::comma(n),
    `Full-subgroup columns` = purrr::map_int(
      condition,
      ~ {
        fit <- nb_fits[[paste0(.x, "__", primary_spec)]]
        if (is.null(fit)) NA_integer_ else length(stats::coef(fit)) - 1L
      }
    ),
    `Across folds (mean)` = sprintf("%.1f", n_terms_mean),
    `Across folds (range)` = n_terms_range
  ) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

if (!is.null(attr(cv_performance, "elapsed_minutes"))) {
  cat("\n  cross-validation runtime: ",
      sprintf("%.1f", attr(cv_performance, "elapsed_minutes")), " minutes\n", sep = "")
}

# ---- SECTION: Step 10 - Reproducibility Ledger --------------------------------
# Every fitted object and every derived table is written to disk so that a
# reviewer can reload any single result without re-running the script, and so
# that downstream reports can cite these artifacts rather than recompute them.

# ---- t7 ----------------------------------------------------------------------
# Only .rds and .csv are listed. Run logs and helper scripts may also live under
# data-local/, but they are working residue, not evidence.
artifact_manifest <- fs::dir_info(local_data, recurse = TRUE) %>%
  filter(type == "file", grepl("\\.(rds|csv)$", path)) %>%
  mutate(
    path = fs::path_rel(path, local_root),
    kind = dplyr::case_when(
      grepl("\\.rds$", path) ~ "fitted object",
      grepl("\\.csv$", path) ~ "derived table",
      TRUE ~ "other"
    ),
    reload = ifelse(kind == "fitted object",
                    paste0("readRDS('", path, "')"),
                    paste0("readr::read_csv('", path, "')"))
  ) %>%
  select(path, kind, size, reload) %>%
  arrange(kind, path)

artifact_manifest %>%
  transmute(
    Artifact = path,
    Kind = kind,
    Size = as.character(size),
    `Reload with` = reload
  ) %>%
  print_table(
    caption = paste0(
      "Table t7: Artifact manifest. Every persisted object, with the call that ",
      "reloads it. These files are the versioned evidentiary record for ",
      "Sections 5.7 and 5.8; downstream reports should read them rather than ",
      "re-estimate."
    ),
    align = c("l", "l", "r", "l"),
    scroll_height = "600px"
  )

# ---- out4 --------------------------------------------------------------------
cat("Output out4: Reproducibility parameters and residual scope\n\n")
cat("  seed:                    ", lasso_seed, "\n")
cat("  penalty CV folds:        ", lasso_folds, "\n")
cat("  performance CV folds:    ", perf_folds, " (seed ", perf_seed, ")\n", sep = "")
cat("  outcome:                 ", outcome_var, "\n")
cat("  weight:                  ", weight_col, " (rescaled to mean 1 within each subgroup)\n")
cat("  forced-in terms:         ", paste(forced_vars, collapse = ", "), "\n")
cat("  source parquet:          ", path_parquet, "\n")
cat("  main frame n:            ", scales::comma(n_analytic), "\n")
cat("  age 35+ frame n:         ", scales::comma(n_analytic_copd), "\n")
cat("  conditions requested:    ", nrow(condition_roster), "\n")
cat("  conditions modelled:     ", nrow(fitted_conditions), "\n")
cat("  models estimated:        ", sum(!purrr::map_lgl(nb_fits, is.null)),
    " of ", length(nb_fits), "\n", sep = "")
cat("  subgroups below 500:     ", sum(condition_inventory$flag_small), "\n\n")

cat("Proposal sections model-2 closes:\n")
cat("  - Section 5.7 condition-specific multivariable models (Table 4 = t6 / t62)\n")
cat("  - Section 5.8 model performance evaluation (t61 in-sample, t63 / t64 held out)\n\n")

cat("Requirements NOT met, and why:\n")
cat("  - Bootstrap variance estimation (inherited decision 10: replicate weights\n")
cat("    absent from the PUMF). Sandwich and Kish-inflated intervals stand in as\n")
cat("    lower bounds, exactly as in model-00 and model-1.\n")
cat("  - Two of the nineteen requested conditions have no separate PUMF item\n")
cat("    (decision 20); see Table t1.\n")
cat("  - Section 5.9 sex-stratified models remain outstanding.\n")
cat("  - Section 5.1 Little's MCAR test and multiple imputation are not performed.\n\n")

cat("Downstream reports should read the artifacts in Table t7 rather than\n")
cat("re-estimate. The fits, coefficients, and fold-level metrics persisted here\n")
cat("are the versioned evidentiary record for Sections 5.7 and 5.8.\n\n")
utils::sessionInfo()

# nolint end
