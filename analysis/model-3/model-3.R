# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# MODEL-3: Full implementation of Sections 5.9 and 5.10 - sex-stratified
# multivariable models. One negative binomial model per sex, estimated inside
# the stratum of female and of male respondents, with variable selection
# following the Section 5.4 LASSO procedure.
#
# Deliberately built as a structural rhyme of analysis/model-2/model-2.R, which
# is itself a rhyme of model-1: the same ten steps, the same artifact roles
# (t6 is the deliverable table, t62 the full ledger, t61 the in-sample metrics,
# t63 / t64 the held-out ones, t7 the manifest), and the same helper names. A
# reader who has read either predecessor should be able to read this without
# relearning anything.
#
# One thing genuinely differs, and it is the reason model-3 exists: Section 5.9
# asks not only for two models but for the DIFFERENCE between them. Artifacts
# t65, g5 and g51 answer that, and they are built on a union model rather than
# on the two selected models, so that a term is never absent from one side of
# the comparison merely because a penalty declined to select it there.
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
requireNamespace("survival", quietly = TRUE) # concordance() for the Section 5.10 C-statistic

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R")
base::source("./scripts/graphing/graph-presets.R")

# ---- declare-globals ---------------------------------------------------------
local_root <- "./analysis/model-3/"
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

# The stratification variable of Section 5.9. The PUMF carries DHH_SEX, a binary
# item; there is no gender-identity question in either the 2010 or the 2014
# cycle. Decision 31.
stratum_var <- "sex"

# Section 5.9 names the female model first, so it is reported first, even though
# the Ellis factor orders Male before Female.
strata_levels <- c("Female", "Male")

# Section 5.10 performance cross-validation. Named apart from `lasso_folds` for
# the same reason as in model-1 and model-2: that one tunes the penalty inside
# glmnet on a Poisson deviance, this one estimates out-of-sample prediction
# error for the negative binomial refits. Both are five-fold because Sections
# 5.4 and 5.10 both say five; they are not the same folds.
perf_folds <- 5
perf_seed <- 42

# A term whose standard error exceeds this on the log scale has an interval
# spanning more than four orders of magnitude on the rate-ratio scale. It is
# reported and marked rather than removed. Decision 40.
unstable_se <- 2

# Step 9 refits every specification on every fold twice over, for both strata,
# so the block is cached. Set TRUE to rebuild.
force_refit_cv <- FALSE
cv_cache_path <- paste0(fits_folder, "cv-performance.rds")

for (folder in c(local_data, fits_folder, prints_folder)) {
  if (!fs::dir_exists(folder)) { fs::dir_create(folder, recurse = TRUE) }
}

# The canonical candidate registry, shared with model-0, model-00, model-1 and
# model-2. See scripts/modeling/candidate-registry.R for the full contract.
# What model-3 uses from it:
#   candidate_registry        52 rows, with domain, label and exclusion reason
#   lasso_vars                48; also used to define the complete-case frame
#   vars_excluding_perceived  45; the Section 5.5 primary predictor set
#   vars_including_perceived  48; the Section 5.5 secondary predictor set
base::source("./scripts/modeling/candidate-registry.R")

# The four specifications of Section 5.4, carried in full into each stratum.
# model-2 carried only two, because a condition subgroup of a few hundred
# respondents cannot support the four-way comparison. A sex stratum is roughly
# half the Section 5.5 analytic sample, so that constraint does not apply and
# model-3 answers "the same LASSO procedure described in Section 5.4" literally.
# Decision 34.
#
# Models 1 and 3 share a single cross-validated fit within a stratum, as do
# Models 2 and 4: the predictor set defines the fit, the penalty selects a model
# from it. Two predictor sets x two strata = four cv.glmnet fits in total.
model_specs <- tibble::tribble(
  ~spec_id,  ~model_label, ~perceived_health, ~lambda_rule,  ~fit_id,   ~role,
  "model_1", "Model 1",    "excluded",        "lambda.1se",  "exclude", "Primary",
  "model_2", "Model 2",    "included",        "lambda.1se",  "include", "Secondary",
  "model_3", "Model 3",    "excluded",        "lambda.min",  "exclude", "Sensitivity",
  "model_4", "Model 4",    "included",        "lambda.min",  "include", "Sensitivity"
)

# Section 5.5 designates the 1SE rule without perceived health as primary, and
# Section 5.9 refers selection back to Section 5.4 without amending that
# designation. model-3 therefore keeps model-1's ordering, and does NOT adopt
# model-2's decision 25, which reversed it for small subgroups only.
primary_spec <- "model_1"

fit_ids <- unique(model_specs$fit_id)
candidate_sets <- list(
  exclude = vars_excluding_perceived,
  include = vars_including_perceived
)

# Decisions 1 through 19 are made in model-1 and inherited here unchanged. They
# are listed by title so that model-3 is readable on its own; the alternatives,
# rationale and reversal instructions live in model-1 Table t3 and are not
# restated, because two copies of a decision drift.
#
# Decisions 20 through 30 belong to model-2 and are specific to condition
# subgroups. model-3 does not inherit them. Where one of them describes a device
# model-3 also needs - the unstable-term flag, the within-stratum design effect,
# the two cross-validation variants - model-3 re-makes the decision on its own
# account below, so that changing model-2 cannot silently change model-3.
inherited_decisions <- tibble::tribble(
  ~id, ~decision,                                  ~chosen,
  1L,  "Outcome variable",                         "days_absent_total",
  2L,  "COPD indicator",                           "Exclude",
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

# The decisions model-3 makes on its own account. Numbering continues from
# model-2 so that a decision id is unambiguous across the whole project.
decision_registry <- tibble::tribble(
  ~id, ~decision, ~alternatives, ~chosen, ~rationale, ~reversal,

  31L, "The stratification variable",
  "sex as recorded in DHH_SEX; a gender variable; sex crossed with age or cycle",
  "sex (DHH_SEX), two levels",
  "Section 5.9 says 'female respondents' and 'male respondents'. The PUMF carries DHH_SEX, a binary item, in both cycles, and neither cycle carries a gender-identity question. The report therefore says sex and not gender throughout, and the two-level structure is a property of the instrument rather than a modelling choice. No respondent is excluded by the stratification: DHH_SEX has no missing values in the analytic frame.",
  "`stratum_var` and `strata_levels` in declare-globals",

  32L, "Stratum base sample",
  "Re-derive complete cases inside each stratum; filter the model-1 complete-case frame",
  "Filter the model-1 frame",
  "Re-deriving would give each stratum its own denominator and its own candidate set, so the female and male models would not be comparable with each other and neither would be comparable with Table 3. Filtering makes each stratum a strict subset of the Section 5.5 analytic sample, and makes the two strata a partition of it.",
  "`ds1` in tweak-data-0",

  33L, "Candidate set inside a stratum",
  "Keep sex in the candidate set; remove it; remove it and add its interactions",
  "Remove sex; keep everything else that is informative",
  "Sex is constant inside its own stratum by construction and carries no information there. Nothing else is removed a priori: a variable is dropped only if it loses all but one level inside the stratum, and every such drop is recorded in Table t2. Interactions are not introduced, because stratification IS the interaction Section 5.9 asks for - fitting the model separately by sex allows every coefficient to differ, which a single sex-by-term interaction set would only do for the terms chosen to carry it.",
  "`stratum_candidates()` in declare-functions",

  34L, "How many Section 5.4 specifications are carried",
  "One (the Section 5.5 primary); two (one predictor set at both penalties, as model-2 does); all four",
  "All four",
  "Section 5.9 refers selection back to Section 5.4, which describes four specifications on two axes. model-2 carried only the primary predictor set because a condition subgroup of a few hundred respondents cannot support a four-way comparison. A sex stratum is roughly half the Section 5.5 sample, so that constraint does not apply, and carrying all four makes Table 5 comparable with Table 3 specification by specification. Models 1 and 3 share one cross-validated fit and Models 2 and 4 share another, so four specifications cost two fits per stratum, not four.",
  "`model_specs` and `candidate_sets` in declare-globals",

  35L, "Penalty rule designated primary",
  "lambda.1se as Section 5.5 designates; lambda.min as model-2 designates for small subgroups",
  "lambda.1se, without perceived health (Model 1)",
  "model-2 reversed this ordering with decision 25, but the argument there was scale: a parsimonious penalty applied to a subgroup of a few hundred respondents frequently returns nothing at all. In model-1 the 1SE rule retained 10 variables at n = 48,932, and a sex stratum is about half of that, so the rule has something to say. Section 5.5's designation therefore stands unamended. Table t5 reports what each rule retained in each stratum so the choice remains checkable.",
  "`primary_spec` in declare-globals",

  36L, "Design effect basis",
  "Reuse model-1's full-sample Kish design effect; compute one within each stratum",
  "Within each stratum",
  "A design effect describes the weight distribution of the sample whose intervals it widens. Weights inside a sex stratum are not distributed as they are in the pooled sample, and Output out5 shows the realised value differing between the two. This repeats model-2's decision 29 rather than inheriting it, so that the two reports can diverge without either breaking silently.",
  "`build_stratum()` in declare-functions",

  37L, "Weight rescaling",
  "Carry model-1's weight into the stratum unchanged; rescale to mean 1 within each stratum",
  "Rescale within each stratum",
  "glm.nb treats prior weights as frequencies when estimating dispersion, so a stratum whose carried-forward weights average far from 1 would return a theta on a different scale from the other. Rescaling inside the stratum makes theta comparable between the female and male models. Point estimates are unaffected; only the scale of the weights changes.",
  "`build_stratum()` in declare-functions",

  38L, "Section 5.10 resampling method",
  "5-fold cross-validation; leave-one-out; a single train / test split",
  "5-fold, in both variants of inherited decision 16",
  "Section 5.10 names five folds and, unlike Section 5.8, does not offer leave-one-out - which is consistent, because both strata are large. The term set is scored twice over: once held fixed at what the whole stratum selected (Table t63, the literal reading), and once with the entire two-stage procedure re-run inside each training fold (Table t64, the honest estimate). Folds that fail to converge are counted, not silently dropped.",
  "`perf_folds` in declare-globals",

  39L, "Basis for the female-male comparison",
  "Compare the two selected models term by term; compare only terms selected in both; refit both strata on the union of the two selected sets",
  "Refit on the union set",
  "Section 5.9 asks the stratified models to 'highlight potential differences in the determinants of absenteeism between men and women'. Comparing the two SELECTED models cannot do that cleanly: a term missing from the male model may be absent because the association is absent, or because a penalty declined to select it, and the two are not distinguishable from the output. Refitting both strata, without penalty, on the union of the terms either stratum retained under the primary specification gives every term an estimate on both sides. Selection asymmetry is then reported separately, as a fact about the procedure, in the 'Retained in' column of Table t65.",
  "`union_terms` and `nb_union` in the t65 block",

  40L, "Rare levels and unstable terms",
  "Collapse rare levels; drop variables that have a rare level; retain and flag",
  "Retain and flag at SE > 2 on the log scale",
  "The same device model-2 adopted with decision 27, re-made here rather than inherited. It matters much less at stratum scale than at subgroup scale - both strata carry more than twenty thousand respondents - but a factor level that is rare in the population is rare in both strata, and a flagged term is cheaper than a silently uninformative interval.",
  "`unstable_se` in declare-globals"
)

domain_colours <- c(
  "Exposure"      = abcol[["magenta"]],
  "Predisposing"  = abcol[["blue"]],
  "Facilitating"  = abcol[["green"]],
  "Needs"         = abcol[["brown"]],
  "Survey design" = abcol[["grey"]]
)

stratum_colours <- c(
  "Female" = abcol[["magenta"]],
  "Male"   = abcol[["blue"]]
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
# stratum cannot be dummy-coded, and a constant numeric contributes nothing.
is_informative <- function(x) {
  if (is.factor(x)) return(nlevels(droplevels(x)) > 1L)
  length(unique(x[!is.na(x)])) > 1L
}

# Apply the model-1 recoding contract to the source columns. model-3 builds one
# frame, not two: unlike model-2 it has no age-restricted item to accommodate.
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
# with model-1 and model-2.
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
# with model-1 and model-2.
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
# in tryCatch so that a failure is reported rather than fatal, exactly as in
# model-2 - both strata are large, but the fold refits of Step 9 are not.
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
# Shared verbatim with model-00, model-1 and model-2. If one changes, all must
# change, or Tables 2, 3, 4 and 5 stop being comparable.
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
# sampling. A lower bound. Computed per stratum, per decision 36.
kish_design_effect <- function(w) {
  length(w) * sum(w^2) / (sum(w)^2)
}

# Wald summary on the rate-ratio scale, carrying three interval variants:
#   - Wald        model-based, understates uncertainty (inherited decision 10)
#   - robust      Huber-White sandwich, sees unequal weighting only
#   - Kish        Wald inflated by sqrt(design effect), applied uniformly
# NOT bootstrap: the replicate weights Section 5.9 assumes do not exist in the
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

# Section 5.10's C-statistic, adapted to a count outcome (inherited decision 17).
# Pairs tied on the outcome carry no information about discrimination and are
# excluded from the denominator, so the comparable share travels with the
# statistic.
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

# Deterministic fold assignment. Every specification and CV variant scores the
# same partition of its own stratum, so differences between them are differences
# in model rather than luck of the draw.
assign_folds <- function(n, k, seed) {
  set.seed(seed)
  sample(rep_len(seq_len(k), n))
}

# One training/testing pass for a GIVEN term set. Both CV variants of Step 9
# call this; they differ only in where `term_vars` comes from. Shared verbatim
# with model-2, including its three guards: terms that go constant in the
# training fold are dropped, test rows carrying an unseen factor level are
# dropped and counted, and a fold whose fit fails returns `converged = FALSE`
# rather than aborting the stratum.
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

# Cut one sex stratum out of the analytic frame and re-scale its weights to
# mean 1 (decision 37). Unused factor levels are dropped here, once, so that
# every downstream step sees the same stratum.
build_stratum <- function(frame, level) {
  frame %>%
    filter(.data[[stratum_var]] == level) %>%
    droplevels() %>%
    mutate(weight_scaled = .data[[weight_col]] / mean(.data[[weight_col]]))
}

# The candidate set offered to the penalty inside one stratum (decision 33):
# the requested Section 5.4 predictor set, minus the stratification variable,
# minus anything that has gone constant.
stratum_candidates <- function(stratum, candidates) {
  offered <- setdiff(candidates, stratum_var)
  offered[purrr::map_lgl(offered, ~ is_informative(stratum[[.x]]))]
}

# The whole stage-one pipeline for one stratum and one predictor set, from
# frame to cross-validated penalised fit. Returns everything the later steps
# need, including what it had to drop, so Table t2 can report the cost of the
# stratum restriction.
fit_stratum_spec <- function(level, this_fit_id) {
  stratum <- strata[[level]]
  candidates <- candidate_sets[[this_fit_id]]

  offered <- stratum_candidates(stratum, candidates)
  dropped <- setdiff(setdiff(candidates, stratum_var), offered)
  forced_here <- forced_vars[purrr::map_lgl(forced_vars, ~ is_informative(stratum[[.x]]))]

  design <- build_design(stratum, c(forced_here, offered))
  lasso <- tryCatch(
    fit_lasso(design, stratum[[outcome_var]], stratum$weight_scaled, lasso_seed),
    error = function(e) NULL
  )

  list(
    stratum = level,
    fit_id = this_fit_id,
    offered = offered,
    dropped = dropped,
    forced = forced_here,
    design = design,
    lasso = lasso
  )
}

# ---- load-data ---------------------------------------------------------------
ds0 <- arrow::read_parquet(path_parquet)

# ---- tweak-data-0 ------------------------------------------------------------
# One frame, recoded exactly as model-1 recodes it (decision 32).
#
#   ds1   the model-1 complete-case frame: complete on the 48 LASSO candidates.
#         Both sex strata are cut from it, so together they partition the
#         Section 5.5 analytic sample exactly and Table 5 describes the same
#         respondents as Table 3.
ds_model_raw <- prepare_frame()

n_source <- nrow(ds_model_raw)
complete_flag <- stats::complete.cases(ds_model_raw)

ds1 <- ds_model_raw %>%
  filter(complete_flag) %>%
  mutate(.respondent_id = dplyr::row_number())

n_analytic <- nrow(ds1)

strata <- purrr::map(
  stats::setNames(strata_levels, strata_levels),
  ~ build_stratum(ds1, .x)
)

# The stratification must be a partition: no respondent lost, none duplicated.
stopifnot(
  !anyNA(ds1[[stratum_var]]),
  sum(purrr::map_int(strata, nrow)) == n_analytic,
  setequal(levels(droplevels(ds1[[stratum_var]])), strata_levels)
)

variable_labels <- c(
  stats::setNames(candidate_registry$variable_label, candidate_registry$variable),
  stats::setNames("CCHS cycle", cycle_var)
)
variable_domains <- c(
  stats::setNames(candidate_registry$domain, candidate_registry$variable),
  stats::setNames("Survey design", cycle_var)
)

exposure_vars <- candidate_registry %>%
  filter(domain == "Exposure", status == "include") %>%
  pull(variable)

# ---- inspect-data-0 ----------------------------------------------------------
ds0 %>% dplyr::glimpse(width = 100)

# ---- data-context-tables -----------------------------------------------------
# A single Ellis output feeds this report, as it feeds model-1 and model-2. No
# joins are performed, so there is no risk of row multiplication anywhere in
# model-3. What model-3 adds is a partition of one frame, not a second source.
cat("Source table: ", path_parquet, "\n", sep = "")
cat("  grain:      one row per respondent, two pooled CCHS cycles\n")
cat("  rows:       ", format(nrow(ds0), big.mark = ","), "\n", sep = "")
cat("  columns:    ", ncol(ds0), "\n\n", sep = "")

cat("Columns this report draws on:\n")
cat("  outcome:      ", outcome_var, "\n", sep = "")
cat("  weight:       ", weight_col, " (master weight halved for pooling, rescaled within each stratum)\n", sep = "")
cat("  forced in:    ", forced_vars, "\n", sep = "")
cat("  stratifying:  ", stratum_var, " (", paste(strata_levels, collapse = ", "), ")\n", sep = "")
cat("  candidates:   ", length(vars_excluding_perceived) - 1L, " or ",
    length(vars_including_perceived) - 1L,
    " offered inside each stratum, depending on the perceived-health toggle\n\n", sep = "")

cat("The analytic frame and its partition:\n")
tibble::tibble(
  frame = c("analytic frame (ds1)", "Female stratum", "Male stratum"),
  definition = c("complete on the 48 LASSO candidates",
                 "ds1 where sex == 'Female'",
                 "ds1 where sex == 'Male'"),
  rows = c(n_analytic, nrow(strata[["Female"]]), nrow(strata[["Male"]]))
) %>%
  mutate(
    share = scales::percent(rows / n_analytic, accuracy = 0.1),
    rows = scales::comma(rows)
  ) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

# ---- data-context-person -----------------------------------------------------
# Grain proof, then one respondent from the female stratum shown in full, so a
# reader can see exactly what a single row of a Section 5.9 model frame contains
# and confirm that the stratifying variable really is constant within it.
cat("Grain proof\n")
cat("  rows in source:         ", format(nrow(ds0), big.mark = ","), "\n", sep = "")
cat("  rows in analytic frame: ", format(n_analytic, big.mark = ","), "\n", sep = "")
cat("  Female + Male:          ",
    format(nrow(strata[["Female"]]) + nrow(strata[["Male"]]), big.mark = ","),
    " (the two strata partition the frame)\n", sep = "")
cat("  duplicated ids:         ", sum(duplicated(ds1$.respondent_id)), "\n\n", sep = "")

cat("One respondent from the Female stratum (n = ",
    scales::comma(nrow(strata[["Female"]])), "):\n\n", sep = "")

set.seed(lasso_seed)
strata[["Female"]] %>%
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
    variable_label = ifelse(variable == stratum_var,
                            paste0(variable_label, "  <- stratifying variable"),
                            variable_label)
  ) %>%
  arrange(match(domain, c("Outcome / design", "Exposure", "Predisposing",
                          "Facilitating", "Needs"))) %>%
  select(Domain = domain, Variable = variable_label, Value = value) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nSex reads 'Female' by construction, which is precisely why it is removed\n")
cat("from the candidate set inside its own stratum (decision 33).\n")

# ---- data-context-distributions ----------------------------------------------
# The outcome inside strata rather than in the pooled sample, because that is
# what the Section 5.9 models are fitted to and the three are not the same shape.
cat("Outcome: ", outcome_var, " (days, capped at 90 in Ellis)\n\n", sep = "")

stratum_outcome_shape <- purrr::map_dfr(strata_levels, function(this_stratum) {
  sub <- strata[[this_stratum]]
  y <- sub[[outcome_var]]
  w <- sub$weight_scaled
  mean_w <- stats::weighted.mean(y, w)
  tibble::tibble(
    stratum = this_stratum,
    n = nrow(sub),
    mean_weighted = mean_w,
    variance_weighted = sum(w * (y - mean_w)^2) / sum(w),
    zero_share = mean(y == 0),
    max_days = max(y)
  )
}) %>%
  mutate(var_over_mean = variance_weighted / mean_weighted)

pooled_shape <- local({
  y <- ds1[[outcome_var]]
  w <- ds1[[weight_col]] / mean(ds1[[weight_col]])
  mean_w <- stats::weighted.mean(y, w)
  tibble::tibble(
    stratum = "Pooled (Table 3 sample)",
    n = nrow(ds1),
    mean_weighted = mean_w,
    variance_weighted = sum(w * (y - mean_w)^2) / sum(w),
    zero_share = mean(y == 0),
    max_days = max(y)
  ) %>%
    mutate(var_over_mean = variance_weighted / mean_weighted)
})

bind_rows(stratum_outcome_shape, pooled_shape) %>%
  transmute(
    Stratum = stratum,
    n = scales::comma(n),
    `Mean days (wtd)` = sprintf("%.3f", mean_weighted),
    `Variance (wtd)` = sprintf("%.2f", variance_weighted),
    `Var / mean` = sprintf("%.2f", var_over_mean),
    `Zero days` = scales::percent(zero_share, accuracy = 0.1),
    Max = max_days
  ) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nEquidispersion would put variance / mean at 1. Neither stratum is close, so\n")
cat("stage two is negative binomial in both, exactly as in model-1 and model-2.\n")
cat("The pooled row is there for one purpose: to show that stratifying does not\n")
cat("change the shape of the outcome, only its level. Whatever differs between\n")
cat("the two models will be a difference in association, not in likelihood.\n")

# ---- SECTION: Step 1 - The Stratification Variable ----------------------------
# Section 5.9 asks for two models, one per sex. Establishing what "sex" is in
# these files, and what it is not, is the first substantive act of the report.

# ---- t1 ----------------------------------------------------------------------
stratification_roster <- tibble::tribble(
  ~requested, ~pumf_item, ~carried, ~note,
  "Female respondents", "DHH_SEX = 2", "yes",
  "Coded to sex == 'Female' in Ellis. Reported first, as Section 5.9 names it first.",
  "Male respondents", "DHH_SEX = 1", "yes",
  "Coded to sex == 'Male' in Ellis. The Ellis factor orders Male first; the reporting order here is Section 5.9's.",
  "Gender identity", "&mdash;", "no",
  "Neither the 2010-2011 nor the 2013-2014 PUMF carries a gender item. This report says sex throughout and does not use the two words interchangeably.",
  "A third or unstated category", "&mdash;", "no",
  "DHH_SEX is binary and has no 'not stated' code in the analytic frame. No respondent is lost to the stratification.",
  "Sex as a predictor", "DHH_SEX", "removed",
  "Constant inside its own stratum, so it carries no information there and is removed from the candidate set (decision 33). Its pooled main effect is a model-1 quantity and lives in Table 3."
)

stratification_roster %>%
  transmute(
    `Section 5.9 asks for` = requested,
    `PUMF item` = pumf_item,
    `Carried` = carried,
    Note = note
  ) %>%
  print_table(
    caption = paste0(
      "Table t1: The stratification variable. What Section 5.9 asks to stratify ",
      "on, and what the 2010 and 2014 Public Use Microdata Files actually ",
      "carry. Unlike model-2's condition roster, nothing is lost in the ",
      "mapping - two requested models resolve to two fitted models - but the ",
      "vocabulary matters and decision 31 records it."
    ),
    align = c("l", "l", "l", "l")
  )

# ---- t11 ---------------------------------------------------------------------
stratum_inventory <- purrr::map_dfr(strata_levels, function(this_stratum) {
  sub <- strata[[this_stratum]]
  y <- sub[[outcome_var]]
  tibble::tibble(
    stratum = this_stratum,
    n = nrow(sub),
    weighted_N = sum(sub[[weight_col]]),
    share_of_frame = nrow(sub) / n_analytic,
    n_nonzero = sum(y > 0),
    nonzero_share = mean(y > 0),
    mean_days = stats::weighted.mean(y, sub$weight_scaled),
    total_days = sum(sub[[weight_col]] * y),
    kish_deff = kish_design_effect(sub[[weight_col]])
  )
})

readr::write_csv(stratum_inventory, paste0(local_data, "stratum-inventory.csv"))

stratum_inventory %>%
  transmute(
    Stratum = stratum,
    n = scales::comma(n),
    `Weighted N` = scales::comma(round(weighted_N)),
    `Share of frame` = scales::percent(share_of_frame, accuracy = 0.1),
    `n with >= 1 day` = scales::comma(n_nonzero),
    `% with >= 1 day` = scales::percent(nonzero_share, accuracy = 0.1),
    `Mean days (wtd)` = sprintf("%.3f", mean_days),
    `Weighted days lost` = scales::comma(round(total_days)),
    `Kish deff` = sprintf("%.3f", kish_deff)
  ) %>%
  print_table(
    caption = paste0(
      "Table t11: Sex stratum inventory. Both sample sizes Section 5.9 asks ",
      "for - unweighted n and weighted N - plus the count that actually limits ",
      "a count model, the number of respondents reporting at least one day ",
      "absent. The design effect is computed within each stratum (decision 36). ",
      "'Weighted days lost' is the population total the two models are ",
      "ultimately about."
    ),
    align = c("l", "r", "r", "r", "r", "r", "r", "r", "r")
  )

# ---- SECTION: Step 2 - Stratum Feasibility and Composition --------------------
# Neither stratum is small, so feasibility is not in doubt. The question that
# replaces it is composition: the female and male strata are different
# populations, and a difference in what the penalty selects may be a difference
# in who is in the stratum rather than in how absence is produced.

# ---- g1-data-prep ------------------------------------------------------------
feasibility <- tidyr::expand_grid(
  stratum = strata_levels,
  fit_id = fit_ids
) %>%
  purrr::pmap_dfr(function(stratum, fit_id) {
    sub <- strata[[stratum]]
    candidates <- candidate_sets[[fit_id]]
    offered <- stratum_candidates(sub, candidates)
    dropped <- setdiff(setdiff(candidates, stratum_var), offered)
    forced_here <- forced_vars[purrr::map_lgl(forced_vars, ~ is_informative(sub[[.x]]))]
    n_columns <- ncol(build_design(sub, c(forced_here, offered))$x)
    tibble::tibble(
      stratum = stratum,
      fit_id = fit_id,
      predictor_set = ifelse(fit_id == "include",
                             "including perceived health",
                             "excluding perceived health"),
      n = nrow(sub),
      n_nonzero = sum(sub[[outcome_var]] > 0),
      n_offered = length(offered),
      n_dropped = length(dropped),
      dropped_vars = paste(variable_labels[dropped], collapse = "; "),
      n_columns = n_columns
    )
  }) %>%
  mutate(
    per_column = n / pmax(n_columns, 1L),
    nonzero_per_column = n_nonzero / pmax(n_columns, 1L)
  )

readr::write_csv(feasibility, paste0(local_data, "stratum-feasibility.csv"))

# Standardised differences between the two strata, over every design column the
# Section 5.4 candidate set would produce. A dummy column's standardised
# difference is a difference in prevalence scaled by its own spread, so the same
# statistic covers factors and numerics without special-casing either.
composition_design <- build_design(ds1, setdiff(vars_including_perceived, stratum_var))

composition_balance <- local({
  x <- composition_design$x
  is_female <- ds1[[stratum_var]] == "Female"
  wf <- ds1[[weight_col]][is_female]
  wm <- ds1[[weight_col]][!is_female]
  wf <- wf / mean(wf)
  wm <- wm / mean(wm)

  weighted_moments <- function(mat, w) {
    m <- as.numeric(crossprod(mat, w) / sum(w))
    centred <- sweep(mat, 2, m, "-")
    v <- as.numeric(crossprod(centred^2, w) / sum(w))
    list(mean = m, var = v)
  }

  f <- weighted_moments(x[is_female, , drop = FALSE], wf)
  m <- weighted_moments(x[!is_female, , drop = FALSE], wm)
  pooled_sd <- sqrt((f$var + m$var) / 2)

  composition_design$map %>%
    mutate(
      mean_female = f$mean,
      mean_male = m$mean,
      difference = f$mean - m$mean,
      smd = ifelse(pooled_sd > 0, difference / pooled_sd, NA_real_),
      domain = variable_domains[variable],
      variable_label = variable_labels[variable],
      term = paste0(variable_label, ifelse(level == "", "", paste0(": ", level)))
    )
})

readr::write_csv(composition_balance, paste0(local_data, "composition-balance.csv"))

# ---- g1 ----------------------------------------------------------------------
g1_composition <- composition_balance %>%
  filter(!is.na(smd)) %>%
  slice_max(abs(smd), n = 30) %>%
  mutate(
    term = forcats::fct_reorder(term, smd),
    domain = factor(domain, levels = names(domain_colours))
  ) %>%
  ggplot(aes(x = smd, y = term, colour = domain)) +
  geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.4) +
  geom_vline(xintercept = c(-0.1, 0.1), colour = "grey75", linetype = "dotted") +
  geom_segment(aes(x = 0, xend = smd, yend = term), linewidth = 0.5) +
  geom_point(size = 2.6) +
  scale_colour_manual(values = domain_colours, drop = FALSE) +
  labs(
    title = "Graph g1: How the Two Strata Differ Before Any Model Is Fitted",
    subtitle = paste0(
      "The 30 design columns with the largest standardised difference between the female and male strata, weighted.\n",
      "Positive means more common among women. The dotted lines mark +/- 0.1, the conventional threshold for a negligible imbalance.\n",
      "A predictor selected in one stratum and not the other may differ in prevalence rather than in association; this is where to check."
    ),
    x = "Standardised difference (Female minus Male)", y = NULL, colour = NULL
  ) +
  theme(legend.position = "top")

print(g1_composition)
ggsave(paste0(prints_folder, "g1_composition.png"),
       g1_composition, width = 8.5, height = 8.5, dpi = 300)

# ---- t2 ----------------------------------------------------------------------
feasibility %>%
  transmute(
    Stratum = stratum,
    `Predictor set` = predictor_set,
    n = scales::comma(n),
    `n with >= 1 day` = scales::comma(n_nonzero),
    `Candidates offered` = n_offered,
    `Dropped as constant` = n_dropped,
    `Design columns` = n_columns,
    `Respondents per column` = sprintf("%.0f", per_column),
    `Non-zero per column` = sprintf("%.0f", nonzero_per_column)
  ) %>%
  print_table(
    caption = paste0(
      "Table t2: Stratum feasibility ledger, one row per stratum per predictor ",
      "set. 'Dropped as constant' counts candidate variables that lose all but ",
      "one level inside the stratum and so cannot be dummy-coded (decision 33); ",
      "the stratifying variable is removed separately and is not counted here. ",
      "Both strata carry hundreds of respondents per design column, which is ",
      "why model-2's small-subgroup machinery - the n &lt; 500 flag, the ",
      "minimum-fit threshold, the reversed penalty designation - is absent from ",
      "model-3."
    ),
    align = c("l", "l", "r", "r", "r", "r", "r", "r", "r")
  )

# ---- out1 --------------------------------------------------------------------
cat("Output out1: What stratification does to the candidate set\n\n")

cat("Section 5.9 asks for ", length(strata_levels), " models. The PUMF supports ",
    length(strata_levels), ".\n", sep = "")
cat("Section 5.4 describes ", nrow(model_specs),
    " specifications, all of which are carried (decision 34),\n", sep = "")
cat("so model-3 estimates ", length(strata_levels) * nrow(model_specs),
    " negative binomial models from ", length(strata_levels) * length(fit_ids),
    " cross-validated penalised fits.\n\n", sep = "")

cat("Sex leaves the candidate set and becomes the stratification:\n\n")
# model-1 is a sibling report, not a dependency: if its artifacts are absent the
# comparison is skipped rather than allowed to abort model-3.
model_1_row <- tryCatch(
  readr::read_csv(
    "./analysis/model-1/data-local/selection-long.csv", show_col_types = FALSE
  ) %>%
    filter(variable == stratum_var, retained) %>%
    distinct(spec_id, column),
  error = function(e) tibble::tibble()
)

if (nrow(model_1_row) > 0) {
  cat("  In model-1 (pooled), sex survived the penalty in these specifications:\n")
  model_1_row %>%
    count(spec_id, name = "columns retained") %>%
    as.data.frame() %>%
    print(row.names = FALSE)
  cat("\n  That coefficient is a single multiplicative shift applied to every\n")
  cat("  respondent. Stratification replaces it with two complete models, in\n")
  cat("  which every coefficient is free to differ. The two are answers to\n")
  cat("  different questions and neither supersedes the other.\n\n")
} else {
  cat("  model-1 selection artifacts were not found or sex was not retained;\n")
  cat("  see analysis/model-1 for the pooled treatment of sex.\n\n")
}

cat("Candidate counts offered inside a stratum:\n\n")
tibble::tibble(
  `Predictor set` = c("excluding perceived health", "including perceived health"),
  `Section 5.4 count` = c(length(vars_excluding_perceived), length(vars_including_perceived)),
  `Offered in a stratum` = c(length(vars_excluding_perceived) - 1L,
                             length(vars_including_perceived) - 1L),
  `Removed` = stratum_var
) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nNo other candidate is dropped a priori. Table t2 records any variable that\n")
cat("lost all but one level inside a stratum; at this sample size there should\n")
cat("be none, and a non-zero count there is worth investigating.\n")

# ---- SECTION: Step 3 - The Stratum Samples ------------------------------------
# Two strata cut from one frame. Unlike model-2's seventeen subgroups these are
# disjoint and exhaustive, which removes the comorbidity problem entirely and
# replaces it with a different one: the two populations are not alike.

# ---- out2 --------------------------------------------------------------------
cat("Output out2: Sample construction arithmetic\n\n")
cat("Source rows (Ellis analytic table):     ", scales::comma(n_source), "\n")
cat("Analytic frame, complete on 48:         ", scales::comma(n_analytic),
    sprintf(" (%.2f%%)\n", 100 * n_analytic / n_source))
cat("  Female stratum:                       ", scales::comma(nrow(strata[["Female"]])),
    sprintf(" (%.2f%% of the frame)\n", 100 * nrow(strata[["Female"]]) / n_analytic))
cat("  Male stratum:                         ", scales::comma(nrow(strata[["Male"]])),
    sprintf(" (%.2f%% of the frame)\n", 100 * nrow(strata[["Male"]]) / n_analytic))
cat("  Female + Male:                        ",
    scales::comma(nrow(strata[["Female"]]) + nrow(strata[["Male"]])), "\n")
cat("\nThe analytic frame is the model-1 sample, unchanged (decision 32). The two\n")
cat("strata partition it: every respondent appears in exactly one, and the sum\n")
cat("of the two is the whole. This is the structural difference from model-2,\n")
cat("whose seventeen subgroups overlapped heavily and summed to far more than\n")
cat("the frame. Nothing here needs a comorbidity correction.\n\n")

cat("What replaces it is imbalance. Design columns exceeding the conventional\n")
cat("negligible-difference threshold of 0.1 in absolute standardised difference:\n\n")
composition_balance %>%
  filter(!is.na(smd)) %>%
  summarise(
    `design columns compared` = n(),
    `|SMD| > 0.10` = sum(abs(smd) > 0.10),
    `|SMD| > 0.25` = sum(abs(smd) > 0.25),
    `largest |SMD|` = sprintf("%.3f", max(abs(smd)))
  ) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

# ---- t21 ---------------------------------------------------------------------
# Chronic-condition prevalence by sex. The study's exposure is chronic disease,
# and the conditions are not equally distributed between the strata. Any
# difference in the selected models has to be read against this table.
condition_by_sex <- purrr::map_dfr(exposure_vars, function(this_condition) {
  if (!this_condition %in% names(ds1)) return(tibble::tibble())
  purrr::map_dfr(strata_levels, function(this_stratum) {
    sub <- strata[[this_stratum]]
    yes <- sub[[this_condition]] == "Yes"
    tibble::tibble(
      condition = this_condition,
      stratum = this_stratum,
      n_yes = sum(yes),
      prevalence = stats::weighted.mean(yes, sub$weight_scaled)
    )
  })
}) %>%
  mutate(condition_label = variable_labels[condition])

readr::write_csv(condition_by_sex, paste0(local_data, "condition-prevalence-by-sex.csv"))

condition_by_sex %>%
  select(condition_label, stratum, n_yes, prevalence) %>%
  tidyr::pivot_wider(names_from = stratum, values_from = c(n_yes, prevalence)) %>%
  mutate(
    difference = prevalence_Female - prevalence_Male,
    ratio = prevalence_Female / prevalence_Male
  ) %>%
  arrange(desc(abs(difference))) %>%
  transmute(
    Condition = condition_label,
    `n (F)` = scales::comma(n_yes_Female),
    `Prevalence (F)` = scales::percent(prevalence_Female, accuracy = 0.01),
    `n (M)` = scales::comma(n_yes_Male),
    `Prevalence (M)` = scales::percent(prevalence_Male, accuracy = 0.01),
    `Difference (pp)` = sprintf("%+.2f", 100 * difference),
    `Ratio F / M` = sprintf("%.2f", ratio)
  ) %>%
  print_table(
    caption = paste0(
      "Table t21: Weighted prevalence of each chronic condition within each sex ",
      "stratum, ordered by the size of the gap. The exposures the study is ",
      "about are themselves unequally distributed between the strata. A ",
      "condition retained in the female model and not the male one may be more ",
      "prevalent, more strongly associated with absence, or simply better ",
      "powered among women; this table settles the first of those three and ",
      "the other two remain open."
    ),
    align = c("l", "r", "r", "r", "r", "r", "r")
  )

# ---- SECTION: Step 4 - The Decision Registry ----------------------------------
# Model-3 inherits nineteen decisions from model-1 and makes ten of its own. It
# does NOT inherit model-2's decisions 20 to 30, which are specific to condition
# subgroups; where it needs the same device it re-makes the decision.

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
      "Table t3: Decision registry for model-3, decisions ",
      min(decision_registry$id), " through ", max(decision_registry$id),
      ". Numbering continues from model-2 so that a decision id is unambiguous ",
      "across the project."
    ),
    align = c("r", "l", "l", "l", "l", "l")
  )

# ---- t31 ---------------------------------------------------------------------
inherited_decisions %>%
  transmute(`#` = id, Decision = decision, `Chosen in model-1` = chosen) %>%
  print_table(
    caption = paste0(
      "Table t31: The nineteen decisions model-3 inherits from model-1 ",
      "unchanged. Alternatives, rationale and reversal instructions are in ",
      "model-1 Table t3 and are deliberately not restated here, because two ",
      "copies of a decision drift apart. Model-2's decisions 20 through 30 are ",
      "NOT inherited: they concern condition subgroups. Decisions 35, 36, 38 ",
      "and 40 re-make the four of them that describe devices model-3 also needs."
    ),
    align = c("r", "l", "l"),
    scroll_height = "420px"
  )

# ---- SECTION: Step 5 - The Four Specifications --------------------------------
# Section 5.9 refers selection back to Section 5.4, which offers four
# specifications. Unlike model-2, model-3 carries all four.

# ---- t4 ----------------------------------------------------------------------
model_specs %>%
  left_join(
    feasibility %>%
      filter(stratum == "Female") %>%
      select(fit_id, n_offered),
    by = "fit_id"
  ) %>%
  transmute(
    Specification = model_label,
    Role = role,
    Penalty = lambda_rule,
    `Perceived health` = perceived_health,
    `Candidates offered` = paste0(n_offered, " (sex removed)"),
    `Shares a fit with` = ifelse(
      fit_id == "exclude", "Models 1 and 3", "Models 2 and 4"
    ),
    `Section 5.5 counterpart` = paste0("Table 3 ", model_label)
  ) %>%
  print_table(
    caption = paste0(
      "Table t4: The four Section 5.4 specifications, carried in full into each ",
      "stratum (decision 34). The predictor set defines the cross-validated ",
      "fit; the penalty selects a model from it, so two fits per stratum yield ",
      "four models. Model 1 is primary, following Section 5.5 and unlike ",
      "model-2, which reversed the designation for small subgroups only ",
      "(decision 35). Every row has a direct counterpart in model-1's Table 3, ",
      "which is what makes Table 5 readable against Table 3."
    ),
    align = c("l", "l", "l", "l", "l", "l", "l")
  )

# ---- SECTION: Step 6 - Stage One, Per-Stratum Penalised Poisson ---------------
# Four weighted L1-penalised Poisson fits: two strata by two predictor sets,
# each with its own 5-fold cross-validated penalty path.

# ---- g2-data-prep ------------------------------------------------------------
fit_keys <- tidyr::expand_grid(stratum = strata_levels, fit_id = fit_ids) %>%
  mutate(key = paste0(stratum, "__", fit_id))

stratum_fits <- purrr::set_names(
  purrr::map2(fit_keys$stratum, fit_keys$fit_id, fit_stratum_spec),
  fit_keys$key
)

for (this_key in names(stratum_fits)) {
  sf <- stratum_fits[[this_key]]
  if (!is.null(sf$lasso)) {
    saveRDS(sf$lasso$cv, paste0(fits_folder, "cv_", this_key, ".rds"))
    saveRDS(sf$design$map, paste0(fits_folder, "map_", this_key, ".rds"))
  }
}

fitted_ok <- names(stratum_fits)[purrr::map_lgl(stratum_fits, ~ !is.null(.x$lasso))]
stopifnot(length(fitted_ok) == nrow(fit_keys))

fit_panel_label <- function(key) {
  parts <- strsplit(key, "__", fixed = TRUE)[[1]]
  paste0(parts[1], " - perceived health ",
         ifelse(parts[2] == "include", "included", "excluded"))
}
panel_levels <- purrr::map_chr(fit_keys$key, fit_panel_label)

cv_curve_data <- purrr::map_dfr(fitted_ok, function(this_key) {
  cv <- stratum_fits[[this_key]]$lasso$cv
  tibble::tibble(
    key = this_key,
    lambda = cv$lambda,
    cv_mean = cv$cvm,
    cv_low = cv$cvlo,
    cv_high = cv$cvup,
    n_nonzero = cv$nzero
  )
}) %>%
  mutate(panel = factor(purrr::map_chr(key, fit_panel_label), levels = panel_levels))

lambda_marks <- purrr::map_dfr(fitted_ok, function(this_key) {
  cv <- stratum_fits[[this_key]]$lasso$cv
  tibble::tibble(
    key = this_key,
    lambda_rule = c("lambda.1se", "lambda.min"),
    lambda = c(cv$lambda.1se, cv$lambda.min)
  )
}) %>%
  mutate(panel = factor(purrr::map_chr(key, fit_panel_label), levels = panel_levels))

path_data <- purrr::map_dfr(fitted_ok, function(this_key) {
  sf <- stratum_fits[[this_key]]
  as.matrix(sf$lasso$path$beta) %>%
    as.data.frame() %>%
    tibble::rownames_to_column("column") %>%
    tidyr::pivot_longer(-column, names_to = "step", values_to = "estimate") %>%
    mutate(
      lambda = sf$lasso$path$lambda[as.integer(sub("^s", "", step)) + 1],
      key = this_key
    ) %>%
    left_join(sf$design$map, by = "column")
}) %>%
  mutate(
    domain = variable_domains[variable],
    panel = factor(purrr::map_chr(key, fit_panel_label), levels = panel_levels)
  )

# ---- g2 ----------------------------------------------------------------------
g2_cv_curves <- cv_curve_data %>%
  ggplot(aes(x = lambda, y = cv_mean)) +
  geom_ribbon(aes(ymin = cv_low, ymax = cv_high), fill = abcol[["grey"]], alpha = 0.25) +
  geom_line(colour = abcol[["grey"]], linewidth = 0.6) +
  geom_vline(data = lambda_marks,
             aes(xintercept = lambda, colour = lambda_rule),
             linetype = "dashed", linewidth = 0.5) +
  facet_wrap(~ panel, ncol = 2, scales = "free") +
  scale_x_log10(labels = scales::label_number(accuracy = 0.001)) +
  scale_colour_manual(values = c("lambda.1se" = abcol[["magenta"]],
                                 "lambda.min" = abcol[["blue"]])) +
  labs(
    title = "Graph g2: Cross-Validated Deviance Inside Each Stratum",
    subtitle = paste0(
      lasso_folds, "-fold cross-validated Poisson deviance with the one-standard-error band, one panel per fit.\n",
      "The distance between the two dashed lines is how much room the penalty has: where the curve is flat, the two rules disagree a great deal."
    ),
    x = "Lambda (log scale)", y = "Poisson deviance", colour = "Penalty"
  ) +
  theme(legend.position = "top")

print(g2_cv_curves)
ggsave(paste0(prints_folder, "g2_cv_curves.png"),
       g2_cv_curves, width = 10, height = 8, dpi = 300)

# ---- g3 ----------------------------------------------------------------------
g3_paths <- path_data %>%
  ggplot(aes(x = lambda, y = estimate, group = column, colour = domain)) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_vline(data = lambda_marks,
             aes(xintercept = lambda), colour = "grey40",
             linetype = "dashed", linewidth = 0.35) +
  geom_line(linewidth = 0.4, alpha = 0.8) +
  facet_wrap(~ panel, ncol = 2, scales = "free") +
  scale_x_log10(labels = scales::label_number(accuracy = 0.001)) +
  scale_colour_manual(values = domain_colours) +
  labs(
    title = "Graph g3: Coefficient Paths by Andersen Domain, One Panel per Fit",
    subtitle = paste0(
      "Each line is one design column. Dashed lines mark lambda.1se (right) and lambda.min (left).\n",
      "Reading right to left, the order in which coefficients leave zero is the order in which each stratum insists on them.\n",
      "Comparing the female and male panels of the same predictor set is the first look at whether the two sexes insist on the same things."
    ),
    x = "Lambda (log scale)", y = "Penalised Poisson coefficient", colour = "Domain"
  ) +
  theme(legend.position = "top")

print(g3_paths)
ggsave(paste0(prints_folder, "g3_paths.png"),
       g3_paths, width = 10, height = 8, dpi = 300)

# ---- SECTION: Step 7 - Selection Results --------------------------------------
# What each stratum retained under each of the four specifications, and where
# the two strata disagree.

# ---- t5 ----------------------------------------------------------------------
selection_long <- purrr::pmap_dfr(
  model_specs %>% select(spec_id, model_label, lambda_rule, fit_id),
  function(spec_id, model_label, lambda_rule, fit_id) {
    purrr::map_dfr(strata_levels, function(this_stratum) {
      sf <- stratum_fits[[paste0(this_stratum, "__", fit_id)]]
      coefficients_at(sf$lasso, sf$design, lambda_rule) %>%
        mutate(stratum = this_stratum, spec_id = spec_id,
               model_label = model_label, lambda_rule = lambda_rule,
               fit_id = fit_id)
    })
  }
) %>%
  mutate(
    domain = variable_domains[variable],
    variable_label = variable_labels[variable]
  )

readr::write_csv(selection_long, paste0(local_data, "selection-long.csv"))

selection_counts <- selection_long %>%
  group_by(stratum, spec_id, model_label) %>%
  summarise(
    columns_offered = n(),
    columns_retained = sum(retained),
    variables_retained = dplyr::n_distinct(variable[retained]),
    exposure_retained = dplyr::n_distinct(variable[retained & domain == "Exposure"]),
    .groups = "drop"
  ) %>%
  left_join(stratum_inventory %>% select(stratum, n, n_nonzero), by = "stratum") %>%
  mutate(empty_selection = variables_retained <= length(forced_vars))

readr::write_csv(selection_counts, paste0(local_data, "selection-counts.csv"))

selection_counts %>%
  arrange(spec_id, match(stratum, strata_levels)) %>%
  transmute(
    Specification = model_label,
    Stratum = stratum,
    n = scales::comma(n),
    `n with >= 1 day` = scales::comma(n_nonzero),
    `Columns offered` = columns_offered,
    `Columns retained` = columns_retained,
    `Variables retained` = variables_retained,
    `Of which exposure` = exposure_retained
  ) %>%
  print_table(
    caption = paste0(
      "Table t5: What each stratum retained under each of the four Section 5.4 ",
      "specifications. The cycle indicator is exempt from the penalty ",
      "(inherited decision 8), so a count of 1 variable would mean nothing but ",
      "cycle survived. Reading the two rows of a specification against each ",
      "other is the first quantitative answer to Section 5.9: if the female and ",
      "male models retain different numbers of variables, the determinants of ",
      "absence are not equally identifiable in the two populations."
    ),
    align = c("l", "l", "r", "r", "r", "r", "r", "r")
  )

# ---- t51 ---------------------------------------------------------------------
# Every variable that was offered anywhere, so the table shows what was offered
# and eliminated, not only what survived. A left join rather than complete():
# a variable retained in neither stratum has no row to expand from.
all_offered_vars <- selection_long %>%
  distinct(domain, variable, variable_label)

selection_kept <- selection_long %>%
  mutate(model_number = sub("^model_", "", spec_id)) %>%
  group_by(domain, variable, variable_label, stratum, model_number) %>%
  summarise(kept = any(retained), .groups = "drop") %>%
  filter(kept) %>%
  group_by(domain, variable, variable_label, stratum) %>%
  summarise(models = paste(sort(model_number), collapse = ", "), .groups = "drop") %>%
  tidyr::pivot_wider(names_from = stratum, values_from = models)

selection_matrix <- all_offered_vars %>%
  left_join(selection_kept, by = c("domain", "variable", "variable_label"))

# A stratum that retained nothing at all would leave its column out of the pivot.
for (this_stratum in strata_levels) {
  if (!this_stratum %in% names(selection_matrix)) {
    selection_matrix[[this_stratum]] <- NA_character_
  }
  selection_matrix[[this_stratum]] <- tidyr::replace_na(
    selection_matrix[[this_stratum]], ""
  )
}

selection_matrix <- selection_matrix %>%
  mutate(
    agreement = dplyr::case_when(
      Female != "" & Male != "" ~ "both",
      Female != ""              ~ "female only",
      Male != ""                ~ "male only",
      TRUE                      ~ "neither"
    )
  ) %>%
  arrange(factor(domain, levels = names(domain_colours)),
          factor(agreement, levels = c("both", "female only", "male only", "neither")),
          variable_label)

readr::write_csv(selection_matrix, paste0(local_data, "selection-matrix.csv"))

selection_matrix %>%
  transmute(
    Domain = domain,
    Variable = variable_label,
    `Female (models)` = Female,
    `Male (models)` = Male,
    Agreement = agreement
  ) %>%
  print_table(
    caption = paste0(
      "Table t51: Which variables each stratum retained, and under which of the ",
      "four specifications. A cell reading '1, 3' means the variable survived ",
      "in Models 1 and 3 of that stratum; an empty cell means it was offered ",
      "and eliminated in all four. The 'Agreement' column is the Section 5.9 ",
      "summary: 'female only' and 'male only' are the candidate sex-specific ",
      "predictors, and they are candidates rather than findings until Table ",
      "t65 shows what the other stratum's estimate would have been."
    ),
    align = c("l", "l", "l", "l", "l"),
    scroll_height = "700px"
  )

# ---- g4 ----------------------------------------------------------------------
g4_selection_grid <- selection_long %>%
  group_by(domain, variable, stratum, spec_id, model_label) %>%
  summarise(kept = any(retained), .groups = "drop") %>%
  tidyr::complete(
    tidyr::nesting(spec_id, model_label),
    stratum = strata_levels,
    tidyr::nesting(domain, variable),
    fill = list(kept = NA)
  ) %>%
  mutate(
    outcome = dplyr::case_when(
      is.na(kept) ~ "not offered",
      kept        ~ "retained",
      TRUE        ~ "eliminated"
    ),
    outcome = factor(outcome, levels = c("retained", "eliminated", "not offered")),
    variable_label = variable_labels[variable],
    stratum = factor(stratum, levels = strata_levels),
    domain = factor(domain, levels = names(domain_colours))
  ) %>%
  ggplot(aes(x = stratum, y = variable_label, fill = outcome)) +
  geom_tile(colour = "white", linewidth = 0.5) +
  facet_grid(domain ~ model_label, scales = "free_y", space = "free_y") +
  scale_fill_manual(
    values = c("retained" = abcol[["magenta"]],
               "eliminated" = "grey90",
               "not offered" = "grey60"),
    drop = FALSE
  ) +
  labs(
    title = "Graph g4: Selection Grid, Female Against Male in Every Specification",
    subtitle = paste0(
      "A variable counts as retained when at least one of its design columns survived the penalty.\n",
      "A row coloured in both columns of a panel is a predictor both sexes insist on; a row coloured in one is where Section 5.9 has something to say.\n",
      "'Not offered' marks the perceived-health measures in the two specifications that exclude them."
    ),
    x = NULL, y = NULL, fill = NULL
  ) +
  theme(
    legend.position = "top",
    strip.text.y = element_text(angle = 0),
    panel.grid = element_blank()
  )

print(g4_selection_grid)
ggsave(paste0(prints_folder, "g4_selection_grid.png"),
       g4_selection_grid, width = 11, height = 13, dpi = 300)

# ---- SECTION: Step 8 - Stage Two, Negative Binomial Estimation ----------------
# Each retained set is re-estimated without penalty under a negative binomial
# likelihood, inside its own stratum. This step answers Section 5.9 and yields
# deliverable Table 5. Intervals are Wald, sandwich, and Kish-inflated - not
# bootstrap: inherited decisions 10 and 15.

# ---- t6-data-prep ------------------------------------------------------------
nb_keys <- tidyr::expand_grid(
  stratum = strata_levels,
  spec_id = model_specs$spec_id
) %>%
  mutate(key = paste0(stratum, "__", spec_id))

spec_terms <- purrr::set_names(
  purrr::map2(nb_keys$stratum, nb_keys$spec_id, function(this_stratum, this_spec) {
    this_fit_id <- model_specs$fit_id[model_specs$spec_id == this_spec]
    sf <- stratum_fits[[paste0(this_stratum, "__", this_fit_id)]]
    kept <- selection_long %>%
      filter(stratum == this_stratum, spec_id == this_spec) %>%
      retained_variables()
    union(sf$forced, setdiff(kept, sf$forced))
  }),
  nb_keys$key
)

nb_fits <- purrr::imap(spec_terms, function(term_vars, this_key) {
  this_stratum <- sub("__.*$", "", this_key)
  fit_nb(strata[[this_stratum]], term_vars, outcome_var)
})

nb_nulls <- purrr::map(
  stats::setNames(strata_levels, strata_levels),
  ~ fit_nb(strata[[.x]], character(0), outcome_var)
)

for (this_key in names(nb_fits)) {
  if (!is.null(nb_fits[[this_key]])) {
    saveRDS(nb_fits[[this_key]], paste0(fits_folder, "nb_", this_key, ".rds"))
  }
}
saveRDS(nb_nulls, paste0(fits_folder, "nb_nulls.rds"))

stratum_deff <- stats::setNames(stratum_inventory$kish_deff, stratum_inventory$stratum)

nb_coefficients <- purrr::imap_dfr(nb_fits, function(fit, this_key) {
  if (is.null(fit)) return(tibble::tibble())
  this_stratum <- sub("__.*$", "", this_key)
  this_spec <- sub("^.*__", "", this_key)
  this_fit_id <- model_specs$fit_id[model_specs$spec_id == this_spec]
  column_map <- stratum_fits[[paste0(this_stratum, "__", this_fit_id)]]$design$map
  tidy_nb(fit, column_map, deff = stratum_deff[[this_stratum]]) %>%
    mutate(stratum = this_stratum, spec_id = this_spec)
}) %>%
  left_join(model_specs %>% select(spec_id, model_label, role), by = "spec_id") %>%
  mutate(
    domain = variable_domains[variable],
    variable_label = variable_labels[variable],
    term = paste0(variable_label, ifelse(level == "", "", paste0(": ", level)))
  )

readr::write_csv(nb_coefficients, paste0(local_data, "nb-coefficients.csv"))

# ---- out5 --------------------------------------------------------------------
cat("Output out5: Variance-estimation instruments for Section 5.9\n\n")
cat("Section 5.9 asks for 500 bootstrap replicate weights, the same instrument\n")
cat("Sections 5.3, 5.5 and 5.7 ask for. They do not exist in the 2010 or 2014\n")
cat("PUMF (inherited decision 10), and strata and PSU identifiers are\n")
cat("suppressed, so no fully design-based variance estimator can be built for\n")
cat("either stratum. What follows are two LOWER bounds on how far the\n")
cat("model-based intervals understate uncertainty. Neither sees clustering.\n\n")

cat("Kish design effect, computed WITHIN each stratum (decision 36):\n\n")
stratum_inventory %>%
  mutate(effective_n = round(n / kish_deff)) %>%
  transmute(
    Stratum = stratum,
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
  tibble::tibble(key = this_key, stratum = sub("__.*$", "", this_key), ratio = ratio)
}) %>%
  filter(!is.na(ratio))

cat("\nHuber-White sandwich SE multiplier, over every term in every fitted model:\n\n")
sandwich_multipliers %>%
  group_by(Stratum = stratum) %>%
  summarise(
    Terms = scales::comma(n()),
    Median = sprintf("%.3f", stats::median(ratio)),
    Minimum = sprintf("%.3f", min(ratio)),
    Maximum = sprintf("%.3f", max(ratio)),
    .groups = "drop"
  ) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nBoth instruments are close to their model-1 values, which is what a\n")
cat("stratification of a large sample should produce: halving a sample does not\n")
cat("change how unequal its weights are. Table t62 reports all three interval\n")
cat("variants side by side and marks terms whose standard error exceeds ",
    unstable_se, "\non the log scale (decision 40).\n", sep = "")

# ---- t6 ----------------------------------------------------------------------
# Deliverable Table 5. One row per estimated term per stratum, with the four
# specifications side by side so a reader can see which associations survive
# the parsimonious penalty and which survive the addition of perceived health.
table_5 <- nb_coefficients %>%
  mutate(
    cell = sprintf("%.2f (%.2f-%.2f)%s%s",
                   rate_ratio, ci_low, ci_high,
                   ifelse(!is.na(p_value) & p_value < 0.05, "*", ""),
                   ifelse(unstable, " !", ""))
  ) %>%
  select(stratum, domain, term, model_label, cell) %>%
  tidyr::pivot_wider(names_from = model_label, values_from = cell, values_fill = "") %>%
  left_join(stratum_inventory %>% select(stratum, n, weighted_N), by = "stratum") %>%
  arrange(match(stratum, strata_levels),
          factor(domain, levels = names(domain_colours)), term)

# A specification that retained nothing would leave its column absent from the
# pivot. Guarantee all four, so the deliverable table always has the same shape.
for (this_label in model_specs$model_label) {
  if (!this_label %in% names(table_5)) table_5[[this_label]] <- ""
}

readr::write_csv(table_5, paste0(local_data, "table-5-sex-stratified-models.csv"))

table_5 %>%
  transmute(
    Stratum = stratum,
    n = scales::comma(n),
    `Weighted N` = scales::comma(round(weighted_N)),
    Domain = domain,
    Term = term,
    `Model 1` = `Model 1`,
    `Model 2` = `Model 2`,
    `Model 3` = `Model 3`,
    `Model 4` = `Model 4`
  ) %>%
  print_table(
    caption = paste0(
      "Table t6 (deliverable Table 5): Adjusted prevalence rate ratios with 95% ",
      "Wald intervals for every term retained inside each sex stratum, under ",
      "all four Section 5.4 specifications. An asterisk marks Wald p &lt; 0.05; ",
      "an exclamation mark flags a term whose standard error exceeds ",
      unstable_se, " on the log scale (decision 40). A blank cell means the ",
      "term was not retained by that specification. These are NOT bootstrap ",
      "intervals (inherited decision 10), and they ignore the selection step ",
      "that produced the term list. Table t62 carries the log-scale ",
      "coefficients, standard errors, exact p-values and two wider interval ",
      "variants; Table t65 carries the female-male comparison, which this ",
      "table deliberately does not support."
    ),
    align = c("l", "r", "r", "l", "l", "r", "r", "r", "r"),
    scroll_height = "700px"
  )

# ---- t62 ---------------------------------------------------------------------
# The Section 5.9 compliance artifact: every quantity the section asks to be
# reported, one row per estimated term per stratum per specification.
nb_coefficients %>%
  left_join(stratum_inventory %>% select(stratum, n, weighted_N), by = "stratum") %>%
  arrange(match(stratum, strata_levels), model_label,
          factor(domain, levels = names(domain_colours)), term) %>%
  transmute(
    Stratum = stratum,
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
      "Table t62 (deliverable Table 5, full ledger): Everything Section 5.9 ",
      "asks to be reported - unweighted n, weighted N, log-scale coefficient, ",
      "standard error, prevalence rate ratio, 95% interval and Wald p-value - ",
      "for every term in every sex-stratified model. The sandwich and Kish ",
      "columns bracket the understatement caused by the absent bootstrap ",
      "weights (inherited decisions 10 and 15); both are lower bounds. All ",
      "intervals remain conditional on a selection step that used the same ",
      "stratum."
    ),
    align = c("l", "r", "r", "l", "l", "l", rep("r", 9), "l"),
    scroll_height = "700px"
  )

# ---- t65 ---------------------------------------------------------------------
# The Section 5.9 comparison. Both strata are refitted, without penalty, on the
# UNION of the terms either retained under the primary specification, so that
# every term has an estimate on both sides and a missing coefficient can never
# be mistaken for a null one (decision 39).
union_terms <- union(
  spec_terms[[paste0("Female__", primary_spec)]],
  spec_terms[[paste0("Male__", primary_spec)]]
)

nb_union <- purrr::map(
  stats::setNames(strata_levels, strata_levels),
  ~ fit_nb(strata[[.x]], union_terms, outcome_var)
)
saveRDS(nb_union, paste0(fits_folder, "nb_union.rds"))

union_coefficients <- purrr::imap_dfr(nb_union, function(fit, this_stratum) {
  if (is.null(fit)) return(tibble::tibble())
  this_fit_id <- model_specs$fit_id[model_specs$spec_id == primary_spec]
  column_map <- stratum_fits[[paste0(this_stratum, "__", this_fit_id)]]$design$map
  tidy_nb(fit, column_map, deff = stratum_deff[[this_stratum]]) %>%
    mutate(stratum = this_stratum)
}) %>%
  mutate(
    domain = variable_domains[variable],
    variable_label = variable_labels[variable],
    term = paste0(variable_label, ifelse(level == "", "", paste0(": ", level)))
  )

readr::write_csv(union_coefficients, paste0(local_data, "union-coefficients.csv"))

selected_where <- selection_long %>%
  filter(spec_id == primary_spec, retained) %>%
  distinct(stratum, variable) %>%
  mutate(present = TRUE) %>%
  tidyr::pivot_wider(names_from = stratum, values_from = present, values_fill = FALSE)

for (this_stratum in strata_levels) {
  if (!this_stratum %in% names(selected_where)) selected_where[[this_stratum]] <- FALSE
}

selected_where <- selected_where %>%
  mutate(
    retained_in = dplyr::case_when(
      Female & Male ~ "both",
      Female        ~ "female only",
      Male          ~ "male only",
      TRUE          ~ "neither"
    )
  ) %>%
  select(variable, retained_in)

heterogeneity <- union_coefficients %>%
  select(column, term, domain, variable, stratum,
         estimate, std_error, se_kish, rate_ratio, ci_low, ci_high, unstable) %>%
  tidyr::pivot_wider(
    names_from = stratum,
    values_from = c(estimate, std_error, se_kish, rate_ratio, ci_low, ci_high, unstable)
  ) %>%
  filter(!is.na(estimate_Female), !is.na(estimate_Male)) %>%
  mutate(
    log_diff = estimate_Female - estimate_Male,
    se_diff = sqrt(std_error_Female^2 + std_error_Male^2),
    se_diff_kish = sqrt(se_kish_Female^2 + se_kish_Male^2),
    ratio_of_ratios = exp(log_diff),
    ror_low = exp(log_diff - 1.96 * se_diff),
    ror_high = exp(log_diff + 1.96 * se_diff),
    z_diff = log_diff / se_diff,
    p_diff = 2 * stats::pnorm(-abs(z_diff)),
    p_diff_kish = 2 * stats::pnorm(-abs(log_diff / se_diff_kish)),
    unstable_either = unstable_Female | unstable_Male
  ) %>%
  left_join(selected_where, by = "variable") %>%
  mutate(retained_in = tidyr::replace_na(retained_in, "neither")) %>%
  arrange(p_diff)

readr::write_csv(heterogeneity, paste0(local_data, "sex-heterogeneity.csv"))

heterogeneity %>%
  transmute(
    Domain = domain,
    Term = term,
    `Retained in` = retained_in,
    `PR female` = sprintf("%.3f (%.3f-%.3f)", rate_ratio_Female, ci_low_Female, ci_high_Female),
    `PR male` = sprintf("%.3f (%.3f-%.3f)", rate_ratio_Male, ci_low_Male, ci_high_Male),
    `Ratio F / M` = sprintf("%.3f (%.3f-%.3f)", ratio_of_ratios, ror_low, ror_high),
    `z` = sprintf("%+.2f", z_diff),
    `p (difference)` = ifelse(p_diff < 0.0001, "&lt;0.0001", sprintf("%.4f", p_diff)),
    `p (Kish-inflated)` = ifelse(p_diff_kish < 0.0001, "&lt;0.0001", sprintf("%.4f", p_diff_kish)),
    Flag = ifelse(unstable_either, "UNSTABLE", "")
  ) %>%
  print_table(
    caption = paste0(
      "Table t65: The female-male comparison Section 5.9 asks for. Both strata ",
      "are refitted without penalty on the union of the terms either retained ",
      "under the primary specification (decision 39), so every term has an ",
      "estimate on both sides and 'not selected' is never mistaken for 'null'. ",
      "'Retained in' records what the penalty did; the estimates record what ",
      "the data say. The ratio of rate ratios is the multiplicative difference ",
      "between the female and male associations, and its interval and z-test ",
      "use se = sqrt(se_F^2 + se_M^2), which is valid because the two strata ",
      "are disjoint samples. Rows are ordered by p; the table is a screen for ",
      "heterogeneity, NOT a set of confirmatory tests - it carries ",
      nrow(heterogeneity), " comparisons with no multiplicity control, and all ",
      "of them inherit the selection step that produced the union set."
    ),
    align = c("l", "l", "l", "r", "r", "r", "r", "r", "r", "l"),
    scroll_height = "700px"
  )

# ---- g5 ----------------------------------------------------------------------
g5_data <- union_coefficients %>%
  filter(!unstable) %>%
  left_join(heterogeneity %>% select(column, log_diff, p_diff), by = "column") %>%
  filter(!is.na(log_diff)) %>%
  mutate(
    stratum = factor(stratum, levels = strata_levels),
    domain = factor(domain, levels = names(domain_colours)),
    term = forcats::fct_reorder(term, log_diff)
  )

g5_paired_forest <- g5_data %>%
  ggplot(aes(x = rate_ratio, y = term, colour = stratum)) +
  geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.4) +
  geom_linerange(aes(xmin = ci_low, xmax = ci_high),
                 position = position_dodge(width = 0.6), linewidth = 0.5) +
  geom_point(size = 2, position = position_dodge(width = 0.6)) +
  facet_grid(domain ~ ., scales = "free_y", space = "free_y") +
  scale_x_log10() +
  scale_colour_manual(values = stratum_colours) +
  labs(
    title = "Graph g5: The Same Terms Estimated in Both Strata",
    subtitle = paste0(
      "Union model: both strata refitted without penalty on the union of the terms either retained under the primary specification.\n",
      "Terms are ordered by the size of the female-male gap, so the top and bottom of each panel is where Section 5.9 has something to say.\n",
      "Wald intervals; see inherited decision 10 for why these are not the intervals Section 5.9 requests. Unstable terms are omitted."
    ),
    x = "Prevalence rate ratio (log scale)", y = NULL, colour = NULL
  ) +
  theme(legend.position = "top", strip.text.y = element_text(angle = 0))

print(g5_paired_forest)
ggsave(paste0(prints_folder, "g5_paired_forest.png"),
       g5_paired_forest, width = 10, height = 13, dpi = 300)

# ---- g51 ---------------------------------------------------------------------
g51_data <- heterogeneity %>%
  filter(!unstable_either) %>%
  mutate(
    domain = factor(domain, levels = names(domain_colours)),
    term = forcats::fct_reorder(term, log_diff),
    notable = p_diff < 0.05
  )

g51_difference <- g51_data %>%
  ggplot(aes(x = ratio_of_ratios, y = term, colour = domain)) +
  geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.4) +
  geom_linerange(aes(xmin = ror_low, xmax = ror_high), linewidth = 0.5) +
  geom_point(aes(shape = notable), size = 2.4, fill = "white") +
  facet_grid(domain ~ ., scales = "free_y", space = "free_y") +
  scale_x_log10() +
  scale_colour_manual(values = domain_colours, drop = FALSE, guide = "none") +
  scale_shape_manual(values = c(`FALSE` = 21, `TRUE` = 19),
                     labels = c(`FALSE` = "interval covers 1", `TRUE` = "interval excludes 1")) +
  labs(
    title = "Graph g51: How Far Each Association Differs Between the Sexes",
    subtitle = paste0(
      "Ratio of the female rate ratio to the male one, with a 95% interval built from the two independent stratum standard errors.\n",
      "A point at 1 means the association is the same in both strata. Filled points mark intervals excluding 1 - a screen, not a test:\n",
      "there are ", nrow(g51_data), " comparisons here and no multiplicity control (see Table t65)."
    ),
    x = "Ratio of rate ratios, female / male (log scale)", y = NULL, shape = NULL
  ) +
  theme(legend.position = "top", strip.text.y = element_text(angle = 0))

print(g51_difference)
ggsave(paste0(prints_folder, "g51_difference.png"),
       g51_difference, width = 10, height = 13, dpi = 300)

# ---- t61 ---------------------------------------------------------------------
model_fit_comparison <- purrr::imap_dfr(nb_fits, function(fit, this_key) {
  this_stratum <- sub("__.*$", "", this_key)
  this_spec <- sub("^.*__", "", this_key)
  sub <- strata[[this_stratum]]
  null_fit <- nb_nulls[[this_stratum]]

  if (is.null(fit) || is.null(null_fit)) {
    return(tibble::tibble(
      stratum = this_stratum, spec_id = this_spec,
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
    stratum = this_stratum,
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
  left_join(model_specs %>% select(spec_id, model_label, role), by = "spec_id") %>%
  arrange(match(stratum, strata_levels), spec_id)

readr::write_csv(model_fit_comparison, paste0(local_data, "model-comparison.csv"))

model_fit_comparison %>%
  transmute(
    Stratum = stratum,
    Specification = model_label,
    Role = role,
    n = scales::comma(n_analytic),
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
      "Table t61: Section 5.10 metrics computed IN SAMPLE, for all eight ",
      "sex-stratified models. RMSE and MAE are weighted (inherited decision ",
      "19). AIC and BIC come from a weighted pseudo-likelihood and rank models ",
      "rather than measure them (inherited decision 18); ACROSS strata they are ",
      "not comparable at all, because each is computed on a different sample. ",
      "Read them down a stratum, never across. The held-out versions, which are ",
      "the ones Section 5.10 actually asks for, are in Tables t63 and t64."
    ),
    align = c("l", "l", "l", "r", "r", "r", "r", "r", "r", "r", "r", "r", "r", "l")
  )

# ---- out3 --------------------------------------------------------------------
cat("Output out3: Convergence, dispersion, and empty selections\n\n")

convergence_summary <- model_fit_comparison %>%
  group_by(Stratum = stratum) %>%
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
    transmute(Stratum = stratum, Specification = model_label, n = n_analytic) %>%
    as.data.frame() %>%
    print(row.names = FALSE)
} else {
  cat("\nNo sex-stratified model failed to converge.\n")
}

empty_selections <- selection_counts %>% filter(empty_selection)
if (nrow(empty_selections) > 0) {
  cat("\nSelections that retained nothing beyond the forced cycle indicator:\n\n")
  empty_selections %>%
    transmute(Stratum = stratum, Specification = model_label,
              n = scales::comma(n), `Variables retained` = variables_retained) %>%
    as.data.frame() %>%
    print(row.names = FALSE)
} else {
  cat("\nNo specification returned an empty selection in either stratum. This is\n")
  cat("the contrast with model-2 that justifies decision 35: at stratum scale\n")
  cat("the parsimonious rule still has something to say, so Section 5.5's\n")
  cat("designation of it as primary needs no amendment.\n")
}

cat("\nDispersion (theta; smaller means more overdispersed):\n\n")
model_fit_comparison %>%
  filter(!is.na(theta)) %>%
  transmute(Stratum = stratum, Specification = model_label,
            Theta = sprintf("%.4f", theta)) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nTheta is comparable between the strata because the weights are rescaled to\n")
cat("mean 1 inside each of them (decision 37). A lower theta in one stratum\n")
cat("means the count is more overdispersed there once the model has had its say.\n")

# ---- SECTION: Step 9 - Section 5.10, Held-Out Performance ---------------------
# Section 5.10 asks for AIC, BIC, McFadden's pseudo-R-squared, a C-statistic,
# and RMSE and MAE "computed on the withheld test fold", averaged over five
# folds, for each sex-stratified model. Table t61 gave the in-sample versions.
# This step gives the held-out ones.
#
# Two variants, mirroring model-1 and model-2 (inherited decision 16):
#   t63  term set held FIXED across folds - the literal reading, and optimistic
#   t64  selection RE-RUN inside each training fold - the honest estimate, and a
#        measure of how stable the selection itself is
#
# Unlike Section 5.8, Section 5.10 does not offer leave-one-out, which is
# consistent: both strata are large. Decision 38.

# ---- t63-data-prep -----------------------------------------------------------
if (!force_refit_cv && file.exists(cv_cache_path)) {
  cv_performance <- readRDS(cv_cache_path)
  cat("Loaded cached cross-validation results from ", cv_cache_path, "\n", sep = "")
} else {
  cat("Refitting the Section 5.10 cross-validation. This is the slow block.\n")
  cv_start_time <- Sys.time()

  cv_performance <- purrr::map_dfr(strata_levels, function(this_stratum) {
    sub <- strata[[this_stratum]]
    fold_id <- assign_folds(nrow(sub), perf_folds, perf_seed)
    cat("  ", this_stratum, " (n = ", nrow(sub), ")\n", sep = "")

    purrr::map_dfr(seq_len(perf_folds), function(this_fold) {
      cat("    fold ", this_fold, " of ", perf_folds, "\n", sep = "")
      test_rows <- which(fold_id == this_fold)
      train_rows <- which(fold_id != this_fold)

      # Variant A - term set fixed at what the whole stratum selected.
      fixed <- purrr::map_dfr(model_specs$spec_id, function(this_spec) {
        term_vars <- spec_terms[[paste0(this_stratum, "__", this_spec)]]
        evaluate_fold(sub, train_rows, test_rows, term_vars, outcome_var) %>%
          mutate(stratum = this_stratum, spec_id = this_spec,
                 fold = this_fold, variant = "fixed term set")
      })

      # Variant B - the whole two-stage procedure re-run inside the training
      # fold, so no held-out respondent contributed to selection. One penalised
      # fit per predictor set, shared by the two penalties that read it.
      train_frame <- droplevels(sub[train_rows, , drop = FALSE])
      fold_forced <- forced_vars[
        purrr::map_lgl(forced_vars, ~ is_informative(train_frame[[.x]]))
      ]
      fold_lassos <- purrr::map(
        stats::setNames(fit_ids, fit_ids),
        function(this_fit_id) {
          offered <- stratum_candidates(train_frame, candidate_sets[[this_fit_id]])
          design <- build_design(train_frame, c(fold_forced, offered))
          list(
            design = design,
            lasso = tryCatch(
              fit_lasso(design, train_frame[[outcome_var]],
                        train_frame$weight_scaled, lasso_seed),
              error = function(e) NULL
            )
          )
        }
      )

      reselected <- purrr::pmap_dfr(
        model_specs %>% select(spec_id, lambda_rule, fit_id),
        function(spec_id, lambda_rule, fit_id) {
          fl <- fold_lassos[[fit_id]]
          term_vars <- if (is.null(fl$lasso)) {
            fold_forced
          } else {
            kept <- coefficients_at(fl$lasso, fl$design, lambda_rule) %>%
              retained_variables()
            union(fold_forced, setdiff(kept, fold_forced))
          }
          evaluate_fold(sub, train_rows, test_rows, term_vars, outcome_var) %>%
            mutate(stratum = this_stratum, spec_id = spec_id,
                   fold = this_fold, variant = "selection re-run",
                   n_vars_selected = length(term_vars))
        }
      )

      bind_rows(fixed, reselected)
    })
  }) %>%
    left_join(model_specs %>% select(spec_id, model_label, role), by = "spec_id")

  attr(cv_performance, "elapsed_minutes") <-
    as.numeric(difftime(Sys.time(), cv_start_time, units = "mins"))
  saveRDS(cv_performance, cv_cache_path)
}

readr::write_csv(cv_performance, paste0(local_data, "cv-performance-folds.csv"))

cv_summary <- cv_performance %>%
  group_by(variant, stratum, spec_id, model_label) %>%
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
  left_join(stratum_inventory %>% select(stratum, n), by = "stratum") %>%
  arrange(variant, match(stratum, strata_levels), spec_id)

readr::write_csv(cv_summary, paste0(local_data, "cv-performance-summary.csv"))

# ---- t63 ---------------------------------------------------------------------
cv_summary %>%
  filter(variant == "fixed term set") %>%
  transmute(
    Stratum = stratum,
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
      "Table t63: Section 5.10 five-fold cross-validated performance, term set ",
      "held FIXED across folds. Each cell is the mean over five folds of that ",
      "stratum, with the between-fold standard deviation in parentheses. ",
      "Metrics are computed on the withheld fold only, weighted (inherited ",
      "decision 19). These numbers are optimistic: the LASSO that chose the ",
      "term set saw every fold (inherited decision 16). Table t64 removes that ",
      "advantage."
    ),
    align = c("l", "l", "r", "r", "r", "r", "r", "r", "r", "l")
  )

# ---- t64 ---------------------------------------------------------------------
cv_summary %>%
  filter(variant == "selection re-run") %>%
  transmute(
    Stratum = stratum,
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
      "it says how far a stratum's selected set moves when a fifth of it is ",
      "withheld. model-1 found that range wide even at n = 48,932; a stratum is ",
      "about half that, so a wider range here is expected and a narrow one ",
      "would be the surprise."
    ),
    align = c("l", "l", "r", "r", "r", "r", "r", "r", "l")
  )

# ---- g6 ----------------------------------------------------------------------
g6_data <- cv_performance %>%
  filter(spec_id == primary_spec) %>%
  select(stratum, variant, fold, rmse, mcfadden_r2, c_statistic) %>%
  tidyr::pivot_longer(c(rmse, mcfadden_r2, c_statistic),
                      names_to = "metric", values_to = "value") %>%
  filter(!is.na(value)) %>%
  mutate(
    metric = factor(
      metric,
      levels = c("rmse", "mcfadden_r2", "c_statistic"),
      labels = c("RMSE (held-out)", "McFadden R2 (held-out)", "C-statistic (held-out)")
    ),
    stratum = factor(stratum, levels = rev(strata_levels))
  )

g6_cv_spread <- g6_data %>%
  ggplot(aes(x = value, y = stratum, colour = variant, shape = variant)) +
  geom_point(size = 2, alpha = 0.55, position = position_dodge(width = 0.6)) +
  stat_summary(fun = mean, geom = "point", size = 4, alpha = 0.95,
               position = position_dodge(width = 0.6)) +
  facet_wrap(~ metric, scales = "free_x", nrow = 1) +
  scale_colour_manual(values = c("fixed term set" = abcol[["magenta"]],
                                 "selection re-run" = abcol[["blue"]])) +
  labs(
    title = "Graph g6: Held-Out Performance by Fold, Female Against Male",
    subtitle = paste0(
      "Primary specification (Model 1) only. Small points are the five individual folds; the large point is their mean.\n",
      "Where the fold points scatter more widely than the gap between the two strata, the difference in performance is not a difference."
    ),
    x = NULL, y = NULL, colour = NULL, shape = NULL
  ) +
  theme(legend.position = "top")

print(g6_cv_spread)
ggsave(paste0(prints_folder, "g6_cv_spread.png"),
       g6_cv_spread, width = 11, height = 5.5, dpi = 300)

# ---- out6 --------------------------------------------------------------------
cat("Output out6: Reading the C-statistic, and the size of the selection optimism\n\n")

cat("Share of respondents at zero days, by stratum:\n\n")
stratum_outcome_shape %>%
  transmute(Stratum = stratum,
            `Zero days` = scales::percent(zero_share, accuracy = 0.1)) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nHarrell's C counts a pair only when the two respondents differ on the\n")
cat("outcome. Most respondents in both strata report zero days, so most pairs\n")
cat("are incomparable and never enter the denominator. Table t63 reports the\n")
cat("comparable share beside every C for exactly this reason, and the female\n")
cat("and male C-statistics should be compared only alongside those shares.\n\n")

optimism <- cv_summary %>%
  filter(spec_id == primary_spec) %>%
  select(variant, stratum, n, rmse_mean, mcfadden_mean, c_mean) %>%
  tidyr::pivot_wider(names_from = variant,
                     values_from = c(rmse_mean, mcfadden_mean, c_mean))

cat("Selection optimism (fixed minus re-run), primary specification:\n\n")
optimism %>%
  transmute(
    Stratum = stratum,
    n = scales::comma(n),
    `d RMSE` = sprintf("%+.4f", `rmse_mean_fixed term set` - `rmse_mean_selection re-run`),
    `d McFadden` = sprintf("%+.4f", `mcfadden_mean_fixed term set` - `mcfadden_mean_selection re-run`),
    `d C` = sprintf("%+.4f", `c_mean_fixed term set` - `c_mean_selection re-run`)
  ) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nA positive d McFadden or d C is the amount by which evaluating a model on\n")
cat("data that helped select it flatters that model. model-1 found this quantity\n")
cat("to be essentially zero at n = 48,932; a stratum is about half that, so the\n")
cat("same reassurance should be earned rather than assumed.\n")

cat("\nTerm-set instability under refitting, all four specifications:\n\n")
cat("Both columns count DESIGN COLUMNS, not variables, so that the full-stratum\n")
cat("fit and the fold refits are measured on the same scale.\n\n")
cv_summary %>%
  filter(variant == "selection re-run") %>%
  transmute(
    Stratum = stratum,
    Specification = model_label,
    `Full-stratum columns` = purrr::map2_int(
      stratum, spec_id,
      ~ {
        fit <- nb_fits[[paste0(.x, "__", .y)]]
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
      "Sections 5.9 and 5.10; downstream reports should read them rather than ",
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
cat("  weight:                  ", weight_col, " (rescaled to mean 1 within each stratum)\n")
cat("  forced-in terms:         ", paste(forced_vars, collapse = ", "), "\n")
cat("  stratifying variable:    ", stratum_var, "\n")
cat("  source parquet:          ", path_parquet, "\n")
cat("  analytic frame n:        ", scales::comma(n_analytic), "\n")
cat("  Female stratum n:        ", scales::comma(nrow(strata[["Female"]])), "\n")
cat("  Male stratum n:          ", scales::comma(nrow(strata[["Male"]])), "\n")
cat("  penalised fits:          ", length(fitted_ok), "\n")
cat("  models estimated:        ", sum(!purrr::map_lgl(nb_fits, is.null)),
    " of ", length(nb_fits), "\n", sep = "")
cat("  union models:            ", sum(!purrr::map_lgl(nb_union, is.null)),
    " of ", length(nb_union), " (", length(union_terms), " terms)\n", sep = "")
cat("  heterogeneity rows:      ", nrow(heterogeneity), "\n\n")

cat("Proposal sections model-3 closes:\n")
cat("  - Section 5.9 sex-stratified multivariable models (Table 5 = t6 / t62)\n")
cat("  - Section 5.10 model performance evaluation (t61 in-sample, t63 / t64 held out)\n\n")

cat("Requirements NOT met, and why:\n")
cat("  - Bootstrap variance estimation (inherited decision 10: replicate weights\n")
cat("    absent from the PUMF). Sandwich and Kish-inflated intervals stand in as\n")
cat("    lower bounds, exactly as in model-00, model-1 and model-2.\n")
cat("  - Section 5.1 Little's MCAR test and multiple imputation are not performed.\n")
cat("  - The female-male comparison of Table t65 is a screen, not a confirmatory\n")
cat("    test: no multiplicity control, and every row inherits the selection step\n")
cat("    that produced the union term set (decision 39).\n\n")

cat("With model-3, every modelling section of the proposal has an estimation of\n")
cat("record: 5.3 in model-00, 5.4 to 5.6 in model-1, 5.7 to 5.8 in model-2, and\n")
cat("5.9 to 5.10 here. Downstream reports should read the artifacts in Table t7\n")
cat("rather than re-estimate.\n\n")
utils::sessionInfo()

# nolint end
