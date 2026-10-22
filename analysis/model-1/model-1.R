# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# MODEL-1: Full implementation of Section 5.4 variable selection via LASSO.
# Four model specifications, two-stage Poisson-to-negative-binomial procedure.
# Every analytical decision is registered; every fitted object is persisted.
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
requireNamespace("survival", quietly = TRUE) # concordance() for the Section 5.6 C-statistic

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R")
base::source("./scripts/graphing/graph-presets.R")

# ---- declare-globals ---------------------------------------------------------
local_root <- "./analysis/model-1/"
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

# Section 5.6 performance cross-validation. Deliberately named apart from
# `lasso_folds`: that one tunes the penalty inside glmnet on a Poisson deviance,
# this one estimates out-of-sample prediction error for the negative binomial
# refits. They are both five-fold because Sections 5.4 and 5.6 both say five,
# but they are not the same folds and they answer different questions.
perf_folds <- 5
perf_seed <- 42

# Step 9 refits every specification on every fold twice over - once holding the
# selected term set fixed, once re-running the whole LASSO inside each training
# fold - so the block is cached. Set TRUE to rebuild.
force_refit_cv <- FALSE
cv_cache_path <- paste0(fits_folder, "cv-performance.rds")

for (folder in c(local_data, fits_folder, prints_folder)) {
  if (!fs::dir_exists(folder)) { fs::dir_create(folder, recurse = TRUE) }
}

# The canonical candidate registry lives in scripts/modeling/candidate-registry.R
# and is shared with model-0 and model-00. Sourcing it, rather than restating it
# here, is what stops the three model reports from drifting apart.
#
# It provides:
#   candidate_registry        52 rows; `status` records the inclusion decision and
#                             `exclusion_reason` records why, empty when included
#   included_vars             49; everything in the study (descriptives, bivariate)
#   bivariate_only_vars        1; in the study but withheld from the penalty
#   lasso_vars                48; the predictor set offered to cv.glmnet
#   perceived_health_vars      3; the measures Section 5.4 toggles
#   vars_excluding_perceived / vars_including_perceived   derived from lasso_vars
#
# The second eligibility axis exists because `dhhgl12` is a deterministic
# function of `dhhgle5` and `dhhg611`. A penalty splits a shared coefficient
# arbitrarily among redundant columns, so `dhhgl12` is reported bivariately in
# model-00 and withheld here.
base::source("./scripts/modeling/candidate-registry.R")

# The four specifications of Section 5.4. Note that Models 1 and 3 share a
# single cross-validated fit, as do Models 2 and 4: the predictor set defines
# the fit, the penalty defines the model drawn from it.
model_specs <- tibble::tribble(
  ~spec_id,  ~model_label, ~perceived_health, ~lambda_rule,  ~fit_id,    ~target_n, ~role,
  "model_1", "Model 1",    "excluded",        "lambda.1se",  "exclude",  16L,       "Primary",
  "model_2", "Model 2",    "included",        "lambda.1se",  "include",   9L,       "Secondary",
  "model_3", "Model 3",    "excluded",        "lambda.min",  "exclude",  32L,       "Sensitivity",
  "model_4", "Model 4",    "included",        "lambda.min",  "include",  33L,       "Sensitivity"
)

# Every analytical decision, with the alternatives that were available and the
# reason the chosen option won. `reversal` names the object to edit to undo it.
decision_registry <- tibble::tribble(
  ~id, ~decision, ~alternatives, ~chosen, ~rationale, ~reversal,
  1L, "Outcome variable",
  "days_absent_total; days_absent_chronic",
  "days_absent_total",
  "Section 5.5 designates it primary, and the 16/9/32/33 reproduction targets derive from it.",
  "`outcome_var` in declare-globals",

  2L, "COPD indicator",
  "Include; exclude; recode as No / Yes / Not asked",
  "Exclude",
  "Asked only of respondents aged 35+, so 100% missing below 35 and 30.9% missing in the 25-54 band. A 'not asked' level would be a deterministic function of age, which is already in the model.",
  "`candidate_registry` status for cc_copd",

  3L, "Family doctor indicator",
  "Include; exclude",
  "Exclude",
  "Optional content in 2010-2011, selected only by Ontario: 100% missing in every other province that cycle. Retaining it would make the variable a near-perfect alias for cycle crossed with province.",
  "`candidate_registry` status for has_family_doctor",

  4L, "Age resolution",
  "age_group_3; dhhgage; both",
  "age_group_3",
  "The two encode the same construct and would compete arbitrarily under the penalty. Section 2.2 specifies the three-category recode.",
  "`candidate_registry` status for dhhgage",

  5L, "Missing data handling",
  "Complete case; explicit Missing level; multiple imputation",
  "Complete case",
  "After decisions 2 and 3 the loss falls from 63.7% to roughly 24%. Section 5.1 permits a separate category only below 5%, which several variables exceed; multiple imputation is deferred rather than dismissed.",
  "`tweak-data-0` chunk",

  6L, "Perceived health definition",
  "The 3 self-perceived measures; the whole Needs domain",
  "The 3 self-perceived measures",
  "Ratified 2026-07-29. ADL items measure functional limitation, not perception, and injury status is a distinct construct.",
  "`perceived_health_vars` in declare-globals",

  7L, "Dummy coding scheme",
  "Reference (treatment) contrasts; full one-hot",
  "Reference contrasts",
  "Matches the stage-two negative binomial parameterisation. The snippet in Section 5.4 mixes both schemes and is internally inconsistent.",
  "`build_design()` in declare-functions",

  8L, "Cycle indicator",
  "Penalised; unpenalised",
  "Unpenalised (penalty.factor = 0)",
  "The pooled design requires a cycle term whether or not it survives selection.",
  "`forced_vars` in declare-globals",

  9L, "Carry-forward rule to stage 2",
  "Any surviving column promotes the whole factor; retained levels only",
  "Any surviving column promotes the whole factor",
  "Preserves standard factor contrasts in the negative binomial refit. Level-wise carry-forward would produce non-standard contrasts that are hard to interpret.",
  "`retained_variables()` in declare-functions",

  10L, "Variance estimation",
  "500 bootstrap replicate weights; Wald standard errors",
  "Wald standard errors",
  "DATA-BLOCKED. Bootstrap replicate weights are absent from the 2010 and 2014 PUMF files; Statistics Canada began releasing them with the 2015 cycle. Documented in CACHE-manifest.md and confirmed with Marc-Andre Blanchette on 2026-05-15.",
  "Not reversible without a Research Data Centre file",

  11L, "Penalty selection",
  "5-fold CV; 10-fold CV; fixed lambda grid",
  "5-fold CV, seed 42",
  "Specified in Section 5.4.",
  "`lasso_folds` and `lasso_seed` in declare-globals",

  12L, "Weights in cross-validation",
  "Weighted likelihood; unweighted",
  "Weighted likelihood",
  "Section 5.4 passes survey weights to cv.glmnet. Note that folds are still drawn as though observations were independent; model-0 out4 quantified the consequence.",
  "`weight_vector` in tweak-data-0",

  13L, "Child-presence flag dhhgl12",
  "Include in the penalty; exclude from the study; keep for descriptives and bivariate models only",
  "Keep for descriptives and bivariate models only",
  "dhhgl12 is the logical OR of dhhgle5 and dhhg611 in all 63,843 rows, so a design matrix carrying all three spans the same column space as their interaction. A penalty distributes a shared coefficient arbitrarily among redundant columns, which would make the selection result unstable and uninterpretable. Its marginal rate ratio is still a legitimate quantity, so it remains in model-00.",
  "`bivariate_only_vars` in scripts/modeling/candidate-registry.R",

  14L, "Homeownership",
  "Omit; proxy by living_arrangements; include DHH_OWN directly",
  "Include DHH_OWN directly as home_ownership",
  "Section 2.2 requests homeownership. Earlier revisions recorded it as unavailable in the PUMF and used living_arrangements as a proxy; QC on 2026-08-01 showed DHH_OWN is present in both cycles with identical integer coding and 99.74% coverage. living_arrangements is retained on its own merits rather than as a substitute.",
  "`home_ownership` row in scripts/modeling/candidate-registry.R",

  15L, "Interval reporting for Table 3",
  "Wald only; Wald plus a Huber-White sandwich; Wald plus Kish inflation; all three",
  "All three, side by side",
  "Decision 10 blocks the bootstrap the proposal asks for, so the honest response is to bracket the understatement rather than hide it. The sandwich captures the unequal-weighting component of the design effect; Kish inflation applies sqrt(deff) uniformly. Both are LOWER bounds, because strata and PSU identifiers are suppressed and neither instrument can see clustering. model-00 uses the same two instruments on Table 2, so Tables 2 and 3 are now on the same footing.",
  "`tidy_nb()` and `kish_deff` in declare-globals",

  16L, "Basis for the Section 5.6 cross-validation",
  "Hold the LASSO-selected term set fixed across folds; re-run selection inside each training fold; both",
  "Both, reported side by side",
  "Section 5.6 says 'repeat model fitting 5 times', which reads as a fixed term set. That is the compliant number, and it is optimistic, because the penalty already saw every held-out fold. Re-running selection inside each training fold is the honest generalisation estimate and also measures how stable the selection itself is. Reporting only the first would overstate performance; reporting only the second would not answer the proposal.",
  "`cv_performance` in the t63 chunk",

  17L, "C-statistic for a count outcome",
  "Omit; Harrell's C on predicted mean vs observed count; dichotomise the outcome and use AUC",
  "Harrell's C on predicted mean vs observed count",
  "Section 5.6 asks for 'Harrell's C adapted for count data'. Dichotomising would answer a different question (any absence vs none) and discard the count. Pairs tied on the outcome are not comparable and are excluded from the denominator; with 70.5% of respondents at zero days that is most pairs, so the comparable share is reported beside every C.",
  "`harrell_c()` in declare-functions",

  18L, "Information criteria under survey weighting",
  "Report AIC/BIC as-is; report with a pseudo-likelihood caveat; omit",
  "Report with a pseudo-likelihood caveat",
  "glm.nb maximises a weighted pseudo-likelihood, so logLik is not a likelihood and AIC's 2k penalty is not calibrated to it. BIC is worse still: log(n) uses the unweighted row count against a weighted likelihood. Section 5.6 asks for both, so both are reported, but they rank models rather than measure them.",
  "`t61` chunk",

  19L, "Scale of the error metrics",
  "Unweighted RMSE/MAE; weighted RMSE/MAE",
  "Weighted",
  "The models are estimated on a weighted likelihood and the target population is the weighted one, so an unweighted error metric scores a population the analysis is not about. Applies to the in-sample metrics in t61 and the cross-validated ones in t63 and t64 alike, so the two are comparable.",
  "`model_fit_comparison` in the t61 chunk"
)

domain_colours <- c(
  "Exposure"     = abcol[["magenta"]],
  "Predisposing" = abcol[["blue"]],
  "Facilitating" = abcol[["green"]],
  "Needs"        = abcol[["brown"]],
  "Survey design" = abcol[["grey"]]
)

model_colours <- c(
  "Model 1" = abcol[["magenta"]],
  "Model 2" = abcol[["blue"]],
  "Model 3" = abcol[["green"]],
  "Model 4" = abcol[["brown"]]
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

# Build a design matrix and the column-to-variable map that makes selection
# results interpretable. Reference contrasts; intercept dropped.
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
# from the penalty, plus the full coefficient path for plotting.
fit_lasso <- function(design, outcome, weights, seed) {
  penalty_vector <- as.numeric(!design$map$variable %in% forced_vars)

  set.seed(seed)
  path <- glmnet::glmnet(
    x = design$x, y = outcome, family = "poisson", alpha = 1,
    weights = weights, penalty.factor = penalty_vector
  )
  set.seed(seed)
  cv <- glmnet::cv.glmnet(
    x = design$x, y = outcome, family = "poisson", alpha = 1,
    nfolds = lasso_folds, weights = weights, penalty.factor = penalty_vector
  )
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

# Decision 9: a variable is promoted to stage 2 if ANY of its columns survived.
retained_variables <- function(coefficient_table) {
  coefficient_table %>%
    filter(retained) %>%
    pull(variable) %>%
    unique()
}

# Stage 2. Unpenalised negative binomial on the retained variable set.
fit_nb <- function(model_frame, term_vars, outcome) {
  terms_used <- if (length(term_vars) > 0) term_vars else "1"
  model_formula <- stats::reformulate(terms_used, response = outcome)
  environment(model_formula) <- environment()
  suppressWarnings(
    MASS::glm.nb(
      model_formula, data = model_frame, weights = weight_scaled,
      control = stats::glm.control(maxit = 50)
    )
  )
}

# Huber-White sandwich covariance for a weighted negative binomial fit, with
# theta held at its estimate. This is the unequal-weighting component of the
# design effect and nothing more: strata and PSUs are suppressed in the PUMF, so
# the clustering component is not recoverable. Decision 15.
# The definition is shared verbatim with model-00's declare-functions chunk.
# If one changes, the other must change with it, or Tables 2 and 3 stop being
# comparable.
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
# sampling. A lower bound. Shared verbatim with model-00.
kish_design_effect <- function(w) {
  length(w) * sum(w^2) / (sum(w)^2)
}

# Wald summary on the rate-ratio scale, carrying three interval variants:
#   - Wald        model-based, understates uncertainty (decision 10)
#   - robust      Huber-White sandwich, sees unequal weighting only
#   - Kish        Wald inflated by sqrt(design effect), applied uniformly
# NOT bootstrap: the replicate weights the proposal assumes do not exist in the
# 2010 or 2014 PUMF. Decisions 10 and 15.
tidy_nb <- function(nb_fit, column_map, deff = 1) {
  robust_se <- sqrt(diag(robust_vcov(nb_fit)))

  summary(nb_fit)$coefficients %>%
    as.data.frame() %>%
    tibble::rownames_to_column("column") %>%
    rename(estimate = Estimate, std_error = `Std. Error`, p_value = `Pr(>|z|)`) %>%
    filter(column != "(Intercept)") %>%
    left_join(column_map, by = "column") %>%
    mutate(
      se_robust = unname(robust_se[column]),
      se_kish = std_error * sqrt(deff),
      p_robust = 2 * stats::pnorm(-abs(estimate / se_robust)),
      rate_ratio = exp(estimate),
      ci_low = exp(estimate - 1.96 * std_error),
      ci_high = exp(estimate + 1.96 * std_error),
      ci_low_robust = exp(estimate - 1.96 * se_robust),
      ci_high_robust = exp(estimate + 1.96 * se_robust),
      ci_low_kish = exp(estimate - 1.96 * se_kish),
      ci_high_kish = exp(estimate + 1.96 * se_kish)
    )
}

# Section 5.6's C-statistic, adapted to a count outcome (decision 17). Pairs
# tied on the outcome carry no information about discrimination and are excluded
# from the denominator, so the comparable share travels with the statistic: a C
# of 0.62 computed on 30% of pairs is a weaker claim than the same number
# computed on 90%.
harrell_c <- function(observed, predicted, weights) {
  fit <- survival::concordance(observed ~ predicted, weights = weights)
  counts <- fit$count
  comparable <- sum(counts[c("concordant", "discordant", "tied.x")])
  total <- comparable + sum(counts[c("tied.y", "tied.xy")])
  tibble::tibble(
    c_statistic = as.numeric(fit$concordance),
    c_se = sqrt(as.numeric(fit$var)),
    comparable_share = comparable / total
  )
}

# Negative binomial log-likelihood on held-out rows, using the coefficients and
# the theta estimated on the training rows. Weighted, per decision 19.
nb_loglik <- function(observed, predicted, theta, weights) {
  sum(weights * stats::dnbinom(observed, size = theta, mu = predicted, log = TRUE))
}

# Deterministic fold assignment. Every specification and both CV variants score
# the same partition, so differences between them are differences in model, not
# in luck of the draw.
assign_folds <- function(n, k, seed) {
  set.seed(seed)
  sample(rep_len(seq_len(k), n))
}

# One training/testing pass for a GIVEN term set. Both CV variants of Step 9
# call this; they differ only in where `term_vars` comes from.
#
# A factor level that appears in the test fold but not the training fold cannot
# be scored by a model that never saw it. Those rows are dropped and counted
# rather than allowed to propagate NA through the metrics.
evaluate_fold <- function(frame, train_rows, test_rows, term_vars, outcome) {
  train <- droplevels(frame[train_rows, , drop = FALSE])
  test <- frame[test_rows, , drop = FALSE]

  factor_terms <- term_vars[purrr::map_lgl(term_vars, ~ is.factor(train[[.x]]))]
  scorable <- rep(TRUE, nrow(test))
  for (this_var in factor_terms) {
    scorable <- scorable & as.character(test[[this_var]]) %in% levels(train[[this_var]])
  }
  n_dropped <- sum(!scorable)
  test <- test[scorable, , drop = FALSE]
  for (this_var in factor_terms) {
    test[[this_var]] <- factor(as.character(test[[this_var]]),
                               levels = levels(train[[this_var]]))
  }

  fit <- fit_nb(train, term_vars, outcome)
  fit_null <- fit_nb(train, character(0), outcome)

  predicted <- stats::predict(fit, newdata = test, type = "response")
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
      converged = fit$converged,
      rmse = sqrt(stats::weighted.mean((observed - predicted)^2, w)),
      mae = stats::weighted.mean(abs(observed - predicted), w),
      loglik = loglik_test,
      mcfadden_r2 = 1 - loglik_test / loglik_test_null
    ),
    harrell_c(observed, predicted, w)
  )
}

# ---- load-data ---------------------------------------------------------------
ds0 <- arrow::read_parquet(path_parquet)

# ---- tweak-data-0 ------------------------------------------------------------
# Decision 5: complete-case on the candidate set actually offered to the
# penalty. Excluding cc_copd and has_family_doctor first (decisions 2 and 3) is
# what makes a complete-case analysis tenable at all.
#
# Note `lasso_vars`, not `included_vars`: decision 9 keeps `dhhgl12` in the
# study but withholds it here, so it must not drive the complete-case filter
# either.
ds_model_raw <- ds0 %>%
  select(all_of(c(outcome_var, weight_col, cycle_var, lasso_vars))) %>%
  mutate(across(where(is.ordered), ~ factor(., ordered = FALSE))) %>%
  mutate(across(where(is.logical), to_yes_no)) %>%
  mutate(across(any_of(c("dhhgle5", "dhhg611", "dhhgl12")), to_yes_no)) %>%
  mutate(across(where(is.character), factor))

n_source <- nrow(ds_model_raw)
complete_flag <- stats::complete.cases(ds_model_raw)

ds1 <- ds_model_raw %>%
  filter(complete_flag) %>%
  mutate(
    .respondent_id = dplyr::row_number(),
    weight_scaled = .data[[weight_col]] / mean(.data[[weight_col]])
  )

n_analytic <- nrow(ds1)

design_exclude <- build_design(ds1, c(forced_vars, vars_excluding_perceived))
design_include <- build_design(ds1, c(forced_vars, vars_including_perceived))
designs <- list(exclude = design_exclude, include = design_include)

y_outcome <- ds1[[outcome_var]]
weight_vector <- ds1$weight_scaled

# Decision 15. Computed on the analytic sample rather than on the source file,
# because it is the analytic sample the intervals in Step 8 describe. model-00
# reports the universe value (3.595 on 63,843 rows); the two are not the same
# quantity and should not be quoted interchangeably.
kish_deff <- kish_design_effect(ds1[[weight_col]])
kish_effective_n <- n_analytic / kish_deff

variable_labels <- c(
  stats::setNames(candidate_registry$variable_label, candidate_registry$variable),
  stats::setNames("CCHS cycle", cycle_var)
)
variable_domains <- c(
  stats::setNames(candidate_registry$domain, candidate_registry$variable),
  stats::setNames("Survey design", cycle_var)
)

# ---- inspect-data-0 ----------------------------------------------------------
ds0 %>% dplyr::glimpse(width = 100)

# ---- data-context-tables -----------------------------------------------------
# A single Ellis output feeds this report. No joins are performed, so there is
# no risk of row multiplication between the parquet file and the model frame.
cat("Source table: ", path_parquet, "\n", sep = "")
cat("  grain:      one row per respondent, two pooled CCHS cycles\n")
cat("  rows:       ", format(nrow(ds0), big.mark = ","), "\n", sep = "")
cat("  columns:    ", ncol(ds0), "\n\n", sep = "")

cat("Columns this report draws on:\n")
cat("  outcome:    ", outcome_var, "\n", sep = "")
cat("  weight:     ", weight_col, " (master weight halved for pooling)\n", sep = "")
cat("  forced in:  ", forced_vars, "\n", sep = "")
cat("  candidates: ", length(lasso_vars), " of ", nrow(candidate_registry),
    " registered (see Table t1)\n", sep = "")
cat("              ", length(included_vars), " are in the study; ",
    length(bivariate_only_vars), " of those (",
    paste(bivariate_only_vars, collapse = ", "),
    ") is reported bivariately only\n\n", sep = "")

ds0 %>%
  count(!!rlang::sym(cycle_var), name = "respondents") %>%
  mutate(share = scales::percent(respondents / sum(respondents), accuracy = 0.1)) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

# ---- data-context-person -----------------------------------------------------
# Grain proof, then one respondent shown in full so a reader can see exactly
# what a single row of the model frame contains.
cat("Grain proof\n")
cat("  rows in source:        ", format(nrow(ds0), big.mark = ","), "\n", sep = "")
cat("  distinct complete rows:", format(nrow(dplyr::distinct(ds0)), big.mark = ","), "\n", sep = "")
cat("  rows in model frame:   ", format(nrow(ds1), big.mark = ","), "\n", sep = "")
cat("  duplicated ids:        ", sum(duplicated(ds1$.respondent_id)), "\n\n", sep = "")

set.seed(lasso_seed)
example_row <- ds1 %>% slice_sample(n = 1)

cat("One respondent, every column used in estimation:\n\n")
example_row %>%
  select(-.respondent_id) %>%
  tidyr::pivot_longer(everything(), names_to = "variable",
                      values_to = "value", values_transform = list(value = as.character)) %>%
  left_join(
    candidate_registry %>% select(variable, domain, variable_label),
    by = "variable"
  ) %>%
  mutate(
    domain = tidyr::replace_na(domain, "Outcome / design"),
    variable_label = dplyr::coalesce(variable_label, variable)
  ) %>%
  arrange(match(domain, c("Outcome / design", "Exposure", "Predisposing",
                          "Facilitating", "Needs"))) %>%
  select(Domain = domain, Variable = variable_label, Value = value) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

# ---- data-context-distributions ----------------------------------------------
# The outcome first, because every modelling decision downstream answers to its
# shape, then the marginal spread of the design as the penalty will see it.
cat("Outcome: ", outcome_var, " (days, capped at 90 in Ellis)\n", sep = "")
outcome_summary <- tibble::tibble(
  statistic = c("mean (unweighted)", "mean (weighted)", "variance (weighted)",
                "variance / mean", "share of zeros", "median", "90th percentile",
                "maximum"),
  value = c(
    mean(y_outcome),
    stats::weighted.mean(y_outcome, weight_vector),
    sum(weight_vector * (y_outcome - stats::weighted.mean(y_outcome, weight_vector))^2) /
      sum(weight_vector),
    NA_real_,
    mean(y_outcome == 0),
    stats::median(y_outcome),
    stats::quantile(y_outcome, 0.90),
    max(y_outcome)
  )
)
outcome_summary$value[4] <- outcome_summary$value[3] / outcome_summary$value[2]
outcome_summary %>%
  mutate(value = round(value, 4)) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nEquidispersion would put variance / mean at 1. It is not close, which is\n")
cat("why stage two is negative binomial rather than Poisson.\n\n")

cat("Design columns entering the penalised fits:\n")
tibble::tibble(
  fit = c("perceived health excluded", "perceived health included"),
  variables = c(length(c(forced_vars, vars_excluding_perceived)),
                length(c(forced_vars, vars_including_perceived))),
  columns = c(ncol(design_exclude$x), ncol(design_include$x))
) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nPrevalence of the exposure domain, the variables Section 5.4 exists to sift:\n")
ds1 %>%
  select(any_of(candidate_registry$variable[candidate_registry$domain == "Exposure"])) %>%
  tidyr::pivot_longer(everything(), names_to = "variable", values_to = "value") %>%
  filter(value == "Yes") %>%
  count(variable, name = "n_yes") %>%
  mutate(
    label = variable_labels[variable],
    percent = scales::percent(n_yes / nrow(ds1), accuracy = 0.01)
  ) %>%
  arrange(desc(n_yes)) %>%
  select(Condition = label, n = n_yes, `%` = percent) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

# ---- SECTION: Step 1 - The Candidate Registry --------------------------------
# One source of truth for which variables are eligible, replacing the vectors
# that had drifted apart across eda-62 and eda-65.

# ---- t1 ----------------------------------------------------------------------
candidate_registry %>%
  transmute(
    Domain = domain,
    Variable = variable,
    Label = variable_label,
    Status = dplyr::case_when(
      status != "include"              ~ "EXCLUDED",
      variable %in% bivariate_only_vars ~ "bivariate only",
      TRUE                              ~ "included"
    ),
    `Reason for exclusion` = dplyr::if_else(
      variable %in% bivariate_only_vars,
      "Deterministic function of dhhgle5 and dhhg611; kept for descriptives and bivariate models, withheld from the penalty",
      exclusion_reason
    )
  ) %>%
  print_table(
    caption = paste0(
      "Table t1: Candidate registry. ", length(lasso_vars),
      " of ", nrow(candidate_registry),
      " variables enter the selection procedure; the three exclusions are justified in Table t3, and ",
      paste(bivariate_only_vars, collapse = ", "),
      " is held back from the penalty alone."
    ),
    align = c("l", "l", "l", "l", "l")
  )

# ---- t11 ---------------------------------------------------------------------
candidate_registry %>%
  count(domain, status) %>%
  tidyr::pivot_wider(names_from = status, values_from = n, values_fill = 0L) %>%
  mutate(
    total = include + exclude,
    `In perceived-health toggle` = purrr::map_int(
      domain,
      ~ sum(candidate_registry$domain == .x &
              candidate_registry$variable %in% perceived_health_vars)
    )
  ) %>%
  select(Domain = domain, Included = include, Excluded = exclude,
         Total = total, `Toggled by Sec 5.4` = `In perceived-health toggle`) %>%
  print_table(
    caption = "Table t11: Candidate counts by Andersen domain",
    align = c("l", "r", "r", "r", "r")
  )

# ---- SECTION: Step 2 - Missing Data -------------------------------------------
# The two exclusions in Table t1 are not stylistic. Complete-case analysis on
# the full candidate list would discard nearly two thirds of the sample.

# ---- g1-data-prep ------------------------------------------------------------
missingness_by_cycle <- ds0 %>%
  select(all_of(c(cycle_var, candidate_registry$variable))) %>%
  tidyr::pivot_longer(
    -all_of(cycle_var), names_to = "variable", values_transform = as.character,
    values_to = "value"
  ) %>%
  group_by(cycle = .data[[cycle_var]], variable) %>%
  summarise(pct_missing = 100 * mean(is.na(value)), .groups = "drop") %>%
  left_join(
    candidate_registry %>% select(variable, domain, variable_label, status),
    by = "variable"
  ) %>%
  mutate(
    variable_label = forcats::fct_reorder(variable_label, pct_missing, .fun = max)
  )

complete_case_cascade <- tibble::tribble(
  ~scenario, ~variables_used,
  paste0("All ", nrow(candidate_registry), " candidates"), candidate_registry$variable,
  "Drop cc_copd", setdiff(candidate_registry$variable, "cc_copd"),
  "Drop has_family_doctor", setdiff(candidate_registry$variable, "has_family_doctor"),
  "Drop both (chosen)", setdiff(candidate_registry$variable,
                                c("cc_copd", "has_family_doctor")),
  "Chosen set, minus dhhgage", included_vars,
  "LASSO set (minus dhhgl12)", lasso_vars
) %>%
  mutate(
    n_variables = lengths(variables_used),
    n_complete = purrr::map_int(variables_used,
                                ~ sum(stats::complete.cases(ds0[, .x]))),
    pct_retained = 100 * n_complete / nrow(ds0)
  )

readr::write_csv(
  missingness_by_cycle %>% mutate(variable_label = as.character(variable_label)),
  paste0(local_data, "missingness-by-cycle.csv")
)

# ---- g1 ----------------------------------------------------------------------
g1_missingness <- missingness_by_cycle %>%
  filter(pct_missing > 0.5) %>%
  ggplot(aes(x = pct_missing, y = variable_label, colour = cycle,
             shape = status)) +
  geom_vline(xintercept = 5, colour = "grey60", linetype = "dotted") +
  geom_point(size = 2.4, alpha = 0.9) +
  scale_colour_manual(values = c("2010-2011" = abcol[["magenta"]],
                                 "2013-2014" = abcol[["blue"]])) +
  scale_shape_manual(values = c("include" = 16, "exclude" = 4)) +
  scale_x_continuous(labels = scales::label_percent(scale = 1)) +
  labs(
    title = "Graph g1: Missingness Is Structural, Not Random",
    subtitle = paste0(
      "Candidate variables with more than 0.5% missing, split by cycle.\n",
      "Crosses mark the two variables excluded in Table t1. Dotted line is the 5% Section 5.1 threshold."
    ),
    x = "Missing (%)", y = NULL, colour = "Cycle", shape = "Status"
  ) +
  theme(legend.position = "right")

print(g1_missingness)
ggsave(paste0(prints_folder, "g1_missingness.png"),
       g1_missingness, width = 8.5, height = 6.5, dpi = 300)

# ---- t2 ----------------------------------------------------------------------
complete_case_cascade %>%
  transmute(
    Scenario = scenario,
    `Variables` = n_variables,
    `Complete cases` = scales::comma(n_complete),
    `Retained (%)` = sprintf("%.1f%%", pct_retained)
  ) %>%
  print_table(
    caption = paste0(
      "Table t2: Complete-case cascade. Excluding two structurally missing ",
      "variables raises retention from 36.3% to ",
      sprintf("%.1f%%",
              complete_case_cascade$pct_retained[
                complete_case_cascade$scenario == "Chosen set, minus dhhgage"]),
      "."
    ),
    align = c("l", "r", "r", "r")
  )

# ---- out1 --------------------------------------------------------------------
# Evidence that the two exclusions are questionnaire skip patterns rather than
# item non-response. Both patterns are deterministic, which is why no imputation
# model could recover the missing values.
cat("Output out1: Skip-pattern and optional-content evidence\n\n")
cat("cc_copd: missing (%) by age group\n")
ds0 %>%
  group_by(age_group_3) %>%
  summarise(n = n(), pct_missing = round(100 * mean(is.na(cc_copd)), 1),
            .groups = "drop") %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nInterpretation: the COPD question is administered only to respondents\n")
cat("aged 35 and over, so absence below that age is by design.\n")

cat("\nhas_family_doctor: missing (%) by cycle and province\n")
ds0 %>%
  group_by(cchs_cycle_f, province) %>%
  summarise(pct_missing = round(100 * mean(is.na(has_family_doctor)), 1),
            .groups = "drop") %>%
  tidyr::pivot_wider(names_from = cchs_cycle_f, values_from = pct_missing) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nInterpretation: optional content in 2010-2011, selected only by Ontario.\n")
cat("Retaining it would encode cycle crossed with province, not health access.\n")

# ---- SECTION: Step 3 - The Analytic Sample ------------------------------------
# Complete-case restriction discards respondents non-randomly. This step
# quantifies how far the retained sample drifts from the source sample.

# ---- out2 --------------------------------------------------------------------
cat("Output out2: Sample construction arithmetic\n\n")
cat("Source rows (Ellis analytic table):        ", scales::comma(n_source), "\n")
cat("Complete cases on included candidates:     ", scales::comma(n_analytic), "\n")
cat("Dropped:                                   ",
    scales::comma(n_source - n_analytic),
    sprintf(" (%.2f%%)\n", 100 * (n_source - n_analytic) / n_source))
cat("\nUnit of analysis: one row per CCHS respondent\n")
cat("Distinct respondent ids:                   ",
    scales::comma(dplyr::n_distinct(ds1$.respondent_id)), "\n")
cat("Duplicate ids:                             ", sum(duplicated(ds1$.respondent_id)), "\n")
cat("\nDesign matrix, perceived health EXCLUDED:  ",
    nrow(design_exclude$x), " x ", ncol(design_exclude$x), "\n")
cat("Design matrix, perceived health INCLUDED:  ",
    nrow(design_include$x), " x ", ncol(design_include$x), "\n")

# ---- t21 ---------------------------------------------------------------------
# Selection-bias check: does the complete-case sample resemble the source?
selection_check <- bind_rows(
  ds_model_raw %>% mutate(sample = "Source (63,843)"),
  ds_model_raw %>% filter(complete_flag) %>% mutate(sample = "Analytic (complete case)")
) %>%
  group_by(sample) %>%
  summarise(
    `Mean days absent` = sprintf("%.3f", mean(.data[[outcome_var]])),
    `Zero days (%)` = sprintf("%.1f%%", 100 * mean(.data[[outcome_var]] == 0)),
    `Female (%)` = sprintf("%.1f%%", 100 * mean(sex == "Female", na.rm = TRUE)),
    `Age 15-24 (%)` = sprintf("%.1f%%", 100 * mean(age_group_3 == "15-24", na.rm = TRUE)),
    `Age 55-75 (%)` = sprintf("%.1f%%", 100 * mean(age_group_3 == "55-75", na.rm = TRUE)),
    `Cycle 2013-2014 (%)` = sprintf("%.1f%%", 100 * mean(.data[[cycle_var]] == "2013-2014")),
    .groups = "drop"
  ) %>%
  arrange(desc(sample))

selection_check %>%
  rename(Sample = sample) %>%
  print_table(
    caption = paste0(
      "Table t21: Selection-bias check. The complete-case restriction removes ",
      sprintf("%.1f%%", 100 * (n_source - n_analytic) / n_source),
      " of respondents; these margins show how far that moves the sample."
    ),
    align = c("l", "r", "r", "r", "r", "r", "r")
  )

# ---- SECTION: Step 4 - The Decision Registry ----------------------------------
# Nineteen decisions stand between the Ellis table and the fitted models. Each is
# recorded with the alternatives available and the object to edit to reverse it.

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
    caption = "Table t3: Decision registry. Every choice made between the Ellis table and the fitted models.",
    align = c("r", "l", "l", "l", "l", "l")
  )

# ---- SECTION: Step 5 - The Four Specifications --------------------------------
# Section 5.4 asks for four models, but they arise from only two fits: the
# predictor set determines the fit, the penalty selects a model from it.

# ---- t4 ----------------------------------------------------------------------
model_specs %>%
  left_join(
    tibble::tibble(
      fit_id = c("exclude", "include"),
      n_variables = c(length(vars_excluding_perceived) + 1L,
                      length(vars_including_perceived) + 1L),
      n_columns = c(ncol(design_exclude$x), ncol(design_include$x))
    ),
    by = "fit_id"
  ) %>%
  transmute(
    Model = model_label,
    Role = role,
    `Perceived health` = perceived_health,
    Penalty = lambda_rule,
    `Shared CV fit` = fit_id,
    `Candidate variables` = n_variables,
    `Design columns` = n_columns,
    `Target (Sec 5.5)` = target_n
  ) %>%
  print_table(
    caption = paste0(
      "Table t4: The four specifications of Section 5.4. Models 1 and 3 draw on ",
      "one cross-validated fit; Models 2 and 4 draw on the other."
    ),
    align = c("l", "l", "l", "l", "l", "r", "r", "r")
  )

# ---- SECTION: Step 6 - Stage One, Penalised Poisson Fitting -------------------
# Two weighted L1-penalised Poisson fits with 5-fold cross-validation.

# ---- g2-data-prep ------------------------------------------------------------
lasso_fits <- list(
  exclude = fit_lasso(design_exclude, y_outcome, weight_vector, lasso_seed),
  include = fit_lasso(design_include, y_outcome, weight_vector, lasso_seed)
)

for (fit_name in names(lasso_fits)) {
  saveRDS(lasso_fits[[fit_name]]$cv,
          paste0(fits_folder, "cv_", fit_name, "_perceived.rds"))
  saveRDS(designs[[fit_name]]$map,
          paste0(fits_folder, "map_", fit_name, "_perceived.rds"))
}

cv_curve_data <- purrr::imap_dfr(lasso_fits, function(fit, fit_name) {
  tibble::tibble(
    fit_id = fit_name,
    lambda = fit$cv$lambda,
    cv_mean = fit$cv$cvm,
    cv_low = fit$cv$cvlo,
    cv_high = fit$cv$cvup,
    n_nonzero = fit$cv$nzero
  )
}) %>%
  mutate(fit_label = ifelse(fit_id == "exclude",
                            "Perceived health excluded (Models 1 and 3)",
                            "Perceived health included (Models 2 and 4)"))

lambda_marks <- purrr::imap_dfr(lasso_fits, function(fit, fit_name) {
  tibble::tibble(
    fit_id = fit_name,
    lambda_rule = c("lambda.1se", "lambda.min"),
    lambda = c(fit$cv$lambda.1se, fit$cv$lambda.min)
  )
}) %>%
  mutate(fit_label = ifelse(fit_id == "exclude",
                            "Perceived health excluded (Models 1 and 3)",
                            "Perceived health included (Models 2 and 4)"))

path_data <- purrr::imap_dfr(lasso_fits, function(fit, fit_name) {
  as.matrix(fit$path$beta) %>%
    as.data.frame() %>%
    tibble::rownames_to_column("column") %>%
    tidyr::pivot_longer(-column, names_to = "step", values_to = "estimate") %>%
    mutate(
      lambda = fit$path$lambda[as.integer(sub("^s", "", step)) + 1],
      fit_id = fit_name
    ) %>%
    left_join(designs[[fit_name]]$map, by = "column")
}) %>%
  mutate(
    domain = variable_domains[variable],
    fit_label = ifelse(fit_id == "exclude",
                       "Perceived health excluded (Models 1 and 3)",
                       "Perceived health included (Models 2 and 4)")
  )

# ---- g2 ----------------------------------------------------------------------
g2_cv_curves <- cv_curve_data %>%
  ggplot(aes(x = lambda, y = cv_mean)) +
  geom_ribbon(aes(ymin = cv_low, ymax = cv_high), fill = abcol[["grey"]], alpha = 0.25) +
  geom_line(colour = abcol[["grey"]], linewidth = 0.7) +
  geom_vline(data = lambda_marks,
             aes(xintercept = lambda, colour = lambda_rule),
             linetype = "dashed", linewidth = 0.6) +
  facet_wrap(~ fit_label, ncol = 2) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.0001)) +
  scale_colour_manual(values = c("lambda.1se" = abcol[["magenta"]],
                                 "lambda.min" = abcol[["blue"]])) +
  labs(
    title = "Graph g2: Cross-Validated Deviance for Both Predictor Sets",
    subtitle = paste0(
      lasso_folds, "-fold cross-validated Poisson deviance with the one-standard-error band.\n",
      "Each panel yields two models, one per penalty rule."
    ),
    x = "Lambda (log scale)", y = "Poisson deviance", colour = "Penalty"
  ) +
  theme(legend.position = "top")

print(g2_cv_curves)
ggsave(paste0(prints_folder, "g2_cv_curves.png"),
       g2_cv_curves, width = 11.69, height = 5.5, dpi = 300)

# ---- g3 ----------------------------------------------------------------------
g3_paths <- path_data %>%
  ggplot(aes(x = lambda, y = estimate, group = column, colour = domain)) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_vline(data = lambda_marks,
             aes(xintercept = lambda), colour = "grey40",
             linetype = "dashed", linewidth = 0.4) +
  geom_line(linewidth = 0.4, alpha = 0.8) +
  facet_wrap(~ fit_label, ncol = 2) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.0001)) +
  scale_colour_manual(values = domain_colours) +
  labs(
    title = "Graph g3: Coefficient Paths by Andersen Domain",
    subtitle = paste0(
      "Each line is one design column. Dashed lines mark lambda.1se (right) and lambda.min (left).\n",
      "The two panels are fit to the same 48,967 respondents and differ only in what was offered."
    ),
    x = "Lambda (log scale)", y = "Penalised Poisson coefficient", colour = "Domain"
  ) +
  theme(legend.position = "top")

print(g3_paths)
ggsave(paste0(prints_folder, "g3_paths.png"),
       g3_paths, width = 11.69, height = 5.5, dpi = 300)

# ---- SECTION: Step 7 - Selection Results --------------------------------------
# What each of the four penalised fits retained, and how that compares with the
# counts the previous analysis reported.

# ---- t5 ----------------------------------------------------------------------
selection_long <- purrr::pmap_dfr(
  model_specs,
  function(spec_id, model_label, perceived_health, lambda_rule, fit_id, target_n, role) {
    coefficients_at(lasso_fits[[fit_id]], designs[[fit_id]], lambda_rule) %>%
      mutate(spec_id = spec_id, model_label = model_label, lambda_rule = lambda_rule)
  }
) %>%
  mutate(domain = variable_domains[variable])

readr::write_csv(selection_long, paste0(local_data, "selection-long.csv"))

selection_counts <- selection_long %>%
  group_by(spec_id, model_label) %>%
  summarise(
    columns_offered = n(),
    columns_retained = sum(retained),
    variables_retained = dplyr::n_distinct(variable[retained]),
    .groups = "drop"
  ) %>%
  left_join(model_specs %>% select(spec_id, role, perceived_health, lambda_rule, target_n),
            by = "spec_id") %>%
  mutate(gap_vs_target = variables_retained - target_n)

selection_counts %>%
  transmute(
    Model = model_label,
    Role = role,
    `Perceived health` = perceived_health,
    Penalty = lambda_rule,
    `Columns offered` = columns_offered,
    `Columns retained` = columns_retained,
    `Variables retained` = variables_retained,
    `Target (Sec 5.5)` = target_n,
    `Gap` = sprintf("%+d", gap_vs_target)
  ) %>%
  print_table(
    caption = paste0(
      "Table t5: Selection counts against the reproduction targets of Section 5.5. ",
      "The 'variables' count promotes a factor whenever any of its columns survived."
    ),
    align = c("l", "l", "l", "l", "r", "r", "r", "r", "r")
  )

# ---- t51 ---------------------------------------------------------------------
selection_matrix <- selection_long %>%
  group_by(domain, variable, model_label) %>%
  summarise(kept = any(retained), .groups = "drop") %>%
  mutate(mark = ifelse(kept, "kept", "")) %>%
  select(-kept) %>%
  tidyr::pivot_wider(names_from = model_label, values_from = mark, values_fill = "") %>%
  mutate(variable_label = variable_labels[variable]) %>%
  arrange(factor(domain, levels = names(domain_colours)), variable_label)

readr::write_csv(selection_matrix, paste0(local_data, "selection-matrix.csv"))

selection_matrix %>%
  select(Domain = domain, Variable = variable_label,
         `Model 1`, `Model 2`, `Model 3`, `Model 4`) %>%
  print_table(
    caption = "Table t51: Which variables each specification retained",
    align = c("l", "l", "c", "c", "c", "c")
  )

# ---- g4 ----------------------------------------------------------------------
g4_selection_grid <- selection_long %>%
  group_by(domain, variable, model_label) %>%
  summarise(kept = any(retained), .groups = "drop") %>%
  # Models 1 and 3 were never shown the perceived-health variables. Completing
  # the grid turns that absence into a stated third state rather than a blank.
  tidyr::complete(model_label, tidyr::nesting(domain, variable)) %>%
  mutate(
    outcome = dplyr::case_when(
      is.na(kept) ~ "not offered",
      kept        ~ "retained",
      TRUE        ~ "eliminated"
    ),
    outcome = factor(outcome, levels = c("retained", "eliminated", "not offered")),
    variable_label = variable_labels[variable],
    domain = factor(domain, levels = names(domain_colours))
  ) %>%
  ggplot(aes(x = model_label, y = variable_label, fill = outcome)) +
  geom_tile(colour = "white", linewidth = 0.6) +
  facet_grid(domain ~ ., scales = "free_y", space = "free_y") +
  scale_fill_manual(
    values = c(
      "retained"    = abcol[["green"]],
      "eliminated"  = "grey90",
      "not offered" = "grey60"
    ),
    drop = FALSE
  ) +
  labs(
    title = "Graph g4: Selection Grid Across the Four Specifications",
    subtitle = paste0(
      "A variable counts as retained when at least one of its design columns survived the penalty.\n",
      "'Not offered' marks the three perceived-health variables withheld from Models 1 and 3."
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
       g4_selection_grid, width = 8.5, height = 11, dpi = 300)

# ---- SECTION: Step 8 - Stage Two, Negative Binomial Estimation ----------------
# Each retained set is re-estimated without penalty under a negative binomial
# likelihood. This is where the estimates for publication are produced, and it
# is the step that answers Section 5.5 and yields deliverable Table 3.
# Intervals are Wald, sandwich, and Kish-inflated - not bootstrap: decisions
# 10 and 15.

# ---- t6-data-prep ------------------------------------------------------------
nb_fits <- purrr::map(
  stats::setNames(model_specs$spec_id, model_specs$spec_id),
  function(this_spec) {
    spec_row <- model_specs %>% filter(spec_id == this_spec)
    kept <- selection_long %>%
      filter(spec_id == this_spec) %>%
      retained_variables()
    term_vars <- union(forced_vars, setdiff(kept, forced_vars))
    fit_nb(ds1, term_vars, outcome_var)
  }
)

nb_null <- fit_nb(ds1, character(0), outcome_var)

for (this_spec in names(nb_fits)) {
  saveRDS(nb_fits[[this_spec]], paste0(fits_folder, "nb_", this_spec, ".rds"))
}
saveRDS(nb_null, paste0(fits_folder, "nb_null.rds"))

nb_coefficients <- purrr::imap_dfr(nb_fits, function(fit, this_spec) {
  fit_id <- model_specs$fit_id[model_specs$spec_id == this_spec]
  tidy_nb(fit, designs[[fit_id]]$map, deff = kish_deff) %>%
    mutate(spec_id = this_spec,
           model_label = model_specs$model_label[model_specs$spec_id == this_spec])
}) %>%
  mutate(domain = variable_domains[variable],
         variable_label = variable_labels[variable])

readr::write_csv(nb_coefficients, paste0(local_data, "nb-coefficients.csv"))

# ---- out5 --------------------------------------------------------------------
cat("Output out5: Variance-estimation instruments for Section 5.5\n\n")
cat("The proposal asks for 500 bootstrap replicate weights. They do not exist in\n")
cat("the 2010 or 2014 PUMF (decision 10), and strata and PSU identifiers are\n")
cat("suppressed, so no fully design-based variance estimator can be built. What\n")
cat("follows are two LOWER bounds on how much the model-based intervals\n")
cat("understate uncertainty. Neither instrument can see clustering, so the true\n")
cat("inflation is larger than both.\n\n")

cat("  analytic n:             ", scales::comma(n_analytic), "\n")
cat("  Kish design effect:     ", sprintf("%.3f", kish_deff), "\n")
cat("  Kish effective n:       ", scales::comma(round(kish_effective_n)),
    " of ", scales::comma(n_analytic), "\n", sep = "")
cat("  implied SE multiplier:  ", sprintf("%.3f", sqrt(kish_deff)),
    "  (square root of the design effect)\n")

sandwich_multipliers <- purrr::imap_dfr(nb_fits, function(fit, this_spec) {
  tibble::tibble(
    spec_id = this_spec,
    ratio = sqrt(diag(robust_vcov(fit))) / sqrt(diag(stats::vcov(fit)))
  )
})

cat("  sandwich SE multiplier: ",
    sprintf("%.3f", stats::median(sandwich_multipliers$ratio)),
    "  (median over every term in all four models)\n")
cat("  sandwich range:         ",
    sprintf("%.3f", min(sandwich_multipliers$ratio)), " to ",
    sprintf("%.3f", max(sandwich_multipliers$ratio)), "\n\n", sep = "")

cat("Table t62 reports all three interval variants side by side. A term whose\n")
cat("Wald interval excludes 1 but whose Kish-inflated interval does not should\n")
cat("be read as unresolved rather than as a finding.\n")

# ---- t6 ----------------------------------------------------------------------
nb_coefficients %>%
  mutate(
    term = paste0(variable_label, ifelse(level == "", "", paste0(": ", level))),
    cell = sprintf("%.3f (%.3f-%.3f)%s", rate_ratio, ci_low, ci_high,
                   ifelse(p_value < 0.05, "*", ""))
  ) %>%
  select(domain, term, model_label, cell) %>%
  tidyr::pivot_wider(names_from = model_label, values_from = cell, values_fill = "") %>%
  arrange(factor(domain, levels = names(domain_colours)), term) %>%
  select(Domain = domain, Term = term,
         any_of(c("Model 1", "Model 2", "Model 3", "Model 4"))) %>%
  print_table(
    caption = paste0(
      "Table t6 (deliverable Table 3): Adjusted prevalence rate ratios with 95% ",
      "Wald intervals across the four Section 5.4 specifications. An asterisk ",
      "marks Wald p &lt; 0.05. These are NOT bootstrap intervals (decision 10), ",
      "and they ignore the selection step that produced the term list. ",
      "Table t62 carries the log-scale coefficients, standard errors, exact ",
      "p-values, and two wider interval variants."
    ),
    align = c("l", "l", "r", "r", "r", "r")
  )

# ---- t62 ---------------------------------------------------------------------
# The Section 5.5 compliance artifact: every quantity the proposal asks to be
# reported, one row per estimated term per model.
nb_coefficients %>%
  mutate(
    term = paste0(variable_label, ifelse(level == "", "", paste0(": ", level)))
  ) %>%
  arrange(model_label, factor(domain, levels = names(domain_colours)), term) %>%
  transmute(
    Model = model_label,
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
    `p (robust)` = ifelse(p_robust < 0.0001, "&lt;0.0001", sprintf("%.4f", p_robust))
  ) %>%
  print_table(
    caption = paste0(
      "Table t62 (deliverable Table 3, full ledger): Everything Section 5.5 ",
      "asks to be reported - log-scale coefficient, standard error, prevalence ",
      "rate ratio, 95% interval and Wald p-value - for every term in all four ",
      "models. The sandwich and Kish columns bracket the understatement caused ",
      "by the absent bootstrap weights (decisions 10 and 15); both are lower ",
      "bounds. All intervals remain conditional on a selection step that used ",
      "the same data."
    ),
    align = c("l", "l", "l", rep("r", 9)),
    scroll_height = "700px"
  )

# ---- g5 ----------------------------------------------------------------------
primary_spec <- "model_1"
primary_terms <- nb_coefficients %>%
  filter(spec_id == primary_spec) %>%
  pull(column)

g5_data <- nb_coefficients %>%
  filter(column %in% primary_terms) %>%
  mutate(
    term = paste0(variable_label, ifelse(level == "", "", paste0(": ", level))),
    term = forcats::fct_reorder(term, rate_ratio, .fun = stats::median)
  )

g5_forest <- g5_data %>%
  ggplot(aes(x = rate_ratio, y = term, colour = model_label)) +
  geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.4) +
  geom_linerange(aes(xmin = ci_low, xmax = ci_high),
                 position = position_dodge(width = 0.6), linewidth = 0.5) +
  geom_point(size = 1.9, position = position_dodge(width = 0.6)) +
  scale_colour_manual(values = model_colours) +
  scale_x_log10() +
  labs(
    title = "Graph g5: Rate Ratios for the Primary Model's Terms",
    subtitle = paste0(
      "Terms retained by Model 1, shown across every specification that also retained them.\n",
      "Wald intervals; see decision 10 for why these are not the intervals Section 5.5 requests."
    ),
    x = "Rate ratio (log scale)", y = NULL, colour = NULL
  ) +
  theme(legend.position = "top")

print(g5_forest)
ggsave(paste0(prints_folder, "g5_forest.png"),
       g5_forest, width = 8.5, height = 9, dpi = 300)

# ---- t61 ---------------------------------------------------------------------
null_loglik <- as.numeric(stats::logLik(nb_null))
weighted_N <- sum(ds1[[weight_col]])

model_fit_comparison <- purrr::imap_dfr(nb_fits, function(fit, this_spec) {
  fitted_values <- stats::fitted(fit)
  residuals_raw <- ds1[[outcome_var]] - fitted_values
  concordance_row <- harrell_c(ds1[[outcome_var]], fitted_values, weight_vector)
  tibble::tibble(
    spec_id = this_spec,
    n_analytic = n_analytic,
    weighted_N = weighted_N,
    n_terms = length(stats::coef(fit)) - 1L,
    aic = stats::AIC(fit),
    bic = stats::BIC(fit),
    log_likelihood = as.numeric(stats::logLik(fit)),
    mcfadden_r2 = 1 - as.numeric(stats::logLik(fit)) / null_loglik,
    theta = fit$theta,
    # Decision 19: weighted, because the models are estimated on a weighted
    # likelihood and the target population is the weighted one.
    rmse = sqrt(stats::weighted.mean(residuals_raw^2, weight_vector)),
    mae = stats::weighted.mean(abs(residuals_raw), weight_vector),
    c_statistic = concordance_row$c_statistic,
    c_comparable_share = concordance_row$comparable_share,
    converged = fit$converged
  )
}) %>%
  left_join(model_specs %>% select(spec_id, model_label, role), by = "spec_id")

readr::write_csv(model_fit_comparison, paste0(local_data, "model-comparison.csv"))

model_fit_comparison %>%
  transmute(
    Model = model_label,
    Role = role,
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
    Converged = ifelse(converged, "yes", "NO")
  ) %>%
  print_table(
    caption = paste0(
      "Table t61: Section 5.6 metrics computed IN SAMPLE. RMSE and MAE are ",
      "weighted (decision 19). AIC and BIC come from a weighted pseudo-",
      "likelihood and rank models rather than measure them (decision 18); BIC ",
      "in particular sets log(n) on the unweighted row count against a weighted ",
      "likelihood. The C-statistic excludes pairs tied on the outcome, which ",
      "here is most pairs - see out6. The held-out versions of these numbers, ",
      "which are the ones Section 5.6 actually asks for, are in Tables t63 and t64."
    ),
    align = c("l", "l", "r", "r", "r", "r", "r", "r", "r", "r", "r", "r", "l")
  )

# ---- out3 --------------------------------------------------------------------
cat("Output out3: Convergence, dispersion, and the null-model comparison\n\n")
cat("Stage 1 - penalised Poisson fits\n\n")
for (fit_name in names(lasso_fits)) {
  cv <- lasso_fits[[fit_name]]$cv
  label <- ifelse(fit_name == "exclude",
                  "Perceived health EXCLUDED", "Perceived health INCLUDED")
  cat(label, "\n")
  cat("  columns offered:  ", ncol(designs[[fit_name]]$x), "\n")
  cat("  lambda.min:       ", sprintf("%.6f", cv$lambda.min),
      "  -> ", cv$nzero[which(cv$lambda == cv$lambda.min)], " columns\n")
  cat("  lambda.1se:       ", sprintf("%.6f", cv$lambda.1se),
      "  -> ", cv$nzero[which(cv$lambda == cv$lambda.1se)], " columns\n")
  cat("  CV deviance at min:", sprintf("%.4f", min(cv$cvm)),
      "  SE band width:", sprintf("%.4f", cv$cvsd[which.min(cv$cvm)]), "\n\n")
}

cat("Stage 2 - negative binomial refits\n\n")
for (this_spec in names(nb_fits)) {
  fit <- nb_fits[[this_spec]]
  cat(model_specs$model_label[model_specs$spec_id == this_spec], "\n")
  cat("  converged:        ", fit$converged, " in ", fit$iter, " iterations\n")
  cat("  theta:            ", sprintf("%.4f", fit$theta),
      " (SE ", sprintf("%.4f", fit$SE.theta), ")\n")
  cat("  terms estimated:  ", length(stats::coef(fit)) - 1L, "\n\n")
}

# ---- SECTION: Step 9 - Section 5.6, Held-Out Performance ---------------------
# Section 5.6 asks for AIC, BIC, McFadden's pseudo-R-squared, a C-statistic, and
# RMSE and MAE "computed on the withheld test fold", averaged over five folds.
# Table t61 gave the in-sample versions. This step gives the held-out ones.
#
# Two variants are computed, per decision 16:
#   t63  term set held FIXED across folds - the literal reading of Section 5.6,
#        and optimistic, because the penalty already saw every held-out fold
#   t64  selection RE-RUN inside each training fold - the honest generalisation
#        estimate, and a measure of how stable the selection itself is
# The gap between them is the price of doing selection and evaluation on the
# same data, and it is a quantity worth having.

# ---- t63-data-prep -----------------------------------------------------------
if (!force_refit_cv && file.exists(cv_cache_path)) {
  cv_performance <- readRDS(cv_cache_path)
  cat("Loaded cached cross-validation results from ", cv_cache_path, "\n", sep = "")
} else {
  cat("Refitting the Section 5.6 cross-validation. This is the slow block.\n")
  cv_start_time <- Sys.time()

  fold_id <- assign_folds(n_analytic, perf_folds, perf_seed)
  spec_terms_fixed <- purrr::map(
    stats::setNames(model_specs$spec_id, model_specs$spec_id),
    function(this_spec) {
      kept <- selection_long %>% filter(spec_id == this_spec) %>% retained_variables()
      union(forced_vars, setdiff(kept, forced_vars))
    }
  )

  # Variant A - fixed term set.
  cv_fixed <- purrr::map_dfr(seq_len(perf_folds), function(this_fold) {
    test_rows <- which(fold_id == this_fold)
    train_rows <- which(fold_id != this_fold)
    cat("  fixed  | fold ", this_fold, " of ", perf_folds, "\n", sep = "")
    purrr::imap_dfr(spec_terms_fixed, function(term_vars, this_spec) {
      evaluate_fold(ds1, train_rows, test_rows, term_vars, outcome_var) %>%
        mutate(spec_id = this_spec, fold = this_fold, variant = "fixed term set")
    })
  })

  # Variant B - selection re-run inside each training fold.
  cv_reselected <- purrr::map_dfr(seq_len(perf_folds), function(this_fold) {
    test_rows <- which(fold_id == this_fold)
    train_rows <- which(fold_id != this_fold)
    cat("  reselect | fold ", this_fold, " of ", perf_folds, "\n", sep = "")

    train_frame <- droplevels(ds1[train_rows, , drop = FALSE])
    fold_designs <- list(
      exclude = build_design(train_frame, c(forced_vars, vars_excluding_perceived)),
      include = build_design(train_frame, c(forced_vars, vars_including_perceived))
    )
    fold_lassos <- purrr::map(
      fold_designs,
      ~ fit_lasso(.x, train_frame[[outcome_var]], train_frame$weight_scaled, lasso_seed)
    )

    purrr::pmap_dfr(
      model_specs %>% select(spec_id, fit_id, lambda_rule),
      function(spec_id, fit_id, lambda_rule) {
        kept <- coefficients_at(fold_lassos[[fit_id]], fold_designs[[fit_id]],
                                lambda_rule) %>%
          retained_variables()
        term_vars <- union(forced_vars, setdiff(kept, forced_vars))
        evaluate_fold(ds1, train_rows, test_rows, term_vars, outcome_var) %>%
          mutate(spec_id = spec_id, fold = this_fold,
                 variant = "selection re-run", n_vars_selected = length(term_vars))
      }
    )
  })

  cv_performance <- bind_rows(cv_fixed, cv_reselected) %>%
    left_join(model_specs %>% select(spec_id, model_label, role), by = "spec_id")

  attr(cv_performance, "elapsed_minutes") <-
    as.numeric(difftime(Sys.time(), cv_start_time, units = "mins"))
  attr(cv_performance, "fold_id") <- fold_id
  saveRDS(cv_performance, cv_cache_path)
}

readr::write_csv(cv_performance, paste0(local_data, "cv-performance-folds.csv"))

cv_summary <- cv_performance %>%
  group_by(variant, spec_id, model_label, role) %>%
  summarise(
    n_terms_mean = mean(n_terms),
    n_terms_range = paste0(min(n_terms), "-", max(n_terms)),
    rmse_mean = mean(rmse), rmse_sd = stats::sd(rmse),
    mae_mean = mean(mae), mae_sd = stats::sd(mae),
    mcfadden_mean = mean(mcfadden_r2), mcfadden_sd = stats::sd(mcfadden_r2),
    c_mean = mean(c_statistic), c_sd = stats::sd(c_statistic),
    comparable_share = mean(comparable_share),
    unscorable = sum(n_unscorable),
    all_converged = all(converged),
    .groups = "drop"
  ) %>%
  arrange(variant, spec_id)

readr::write_csv(cv_summary, paste0(local_data, "cv-performance-summary.csv"))

# ---- t63 ---------------------------------------------------------------------
cv_summary %>%
  filter(variant == "fixed term set") %>%
  transmute(
    Model = model_label,
    Role = role,
    Terms = round(n_terms_mean),
    `CV RMSE` = sprintf("%.3f (%.3f)", rmse_mean, rmse_sd),
    `CV MAE` = sprintf("%.3f (%.3f)", mae_mean, mae_sd),
    `CV McFadden R2` = sprintf("%.4f (%.4f)", mcfadden_mean, mcfadden_sd),
    `CV C-statistic` = sprintf("%.4f (%.4f)", c_mean, c_sd),
    `Comparable pairs` = scales::percent(comparable_share, accuracy = 0.1),
    Converged = ifelse(all_converged, "all folds", "SOME FAILED")
  ) %>%
  print_table(
    caption = paste0(
      "Table t63: Section 5.6 five-fold cross-validated performance, term set ",
      "held FIXED across folds. Each cell is the mean over five folds with the ",
      "between-fold standard deviation in parentheses. Metrics are computed on ",
      "the withheld fold only, weighted (decision 19). These numbers are ",
      "optimistic: the LASSO that chose the term set saw every fold ",
      "(decision 16). Table t64 removes that advantage."
    ),
    align = c("l", "l", "r", "r", "r", "r", "r", "r", "l")
  )

# ---- t64 ---------------------------------------------------------------------
cv_summary %>%
  filter(variant == "selection re-run") %>%
  transmute(
    Model = model_label,
    Role = role,
    `Terms (mean)` = round(n_terms_mean),
    `Terms (range)` = n_terms_range,
    `CV RMSE` = sprintf("%.3f (%.3f)", rmse_mean, rmse_sd),
    `CV MAE` = sprintf("%.3f (%.3f)", mae_mean, mae_sd),
    `CV McFadden R2` = sprintf("%.4f (%.4f)", mcfadden_mean, mcfadden_sd),
    `CV C-statistic` = sprintf("%.4f (%.4f)", c_mean, c_sd),
    Converged = ifelse(all_converged, "all folds", "SOME FAILED")
  ) %>%
  print_table(
    caption = paste0(
      "Table t64: The same five folds, with the entire LASSO re-run inside each ",
      "training fold so that no held-out respondent contributed to selection. ",
      "The term range shows how much the selected set moves when a fifth of the ",
      "sample is withheld - a direct measure of selection stability that the ",
      "single full-sample fit cannot provide."
    ),
    align = c("l", "l", "r", "r", "r", "r", "r", "r", "l")
  )

# ---- g6 ----------------------------------------------------------------------
g6_data <- cv_performance %>%
  select(model_label, variant, fold, rmse, mae, mcfadden_r2, c_statistic) %>%
  tidyr::pivot_longer(c(rmse, mae, mcfadden_r2, c_statistic),
                      names_to = "metric", values_to = "value") %>%
  mutate(
    metric = factor(
      metric,
      levels = c("rmse", "mae", "mcfadden_r2", "c_statistic"),
      labels = c("RMSE (held-out)", "MAE (held-out)",
                 "McFadden R2 (held-out)", "C-statistic (held-out)")
    ),
    model_label = factor(model_label, levels = rev(model_specs$model_label))
  )

g6_cv_spread <- g6_data %>%
  ggplot(aes(x = value, y = model_label, colour = variant, shape = variant)) +
  geom_point(size = 2, alpha = 0.55,
             position = position_dodge(width = 0.55)) +
  stat_summary(fun = mean, geom = "point", size = 4, alpha = 0.95,
               position = position_dodge(width = 0.55)) +
  facet_wrap(~ metric, scales = "free_x", nrow = 2) +
  scale_colour_manual(values = c("fixed term set" = abcol[["magenta"]],
                                 "selection re-run" = abcol[["blue"]])) +
  labs(
    title = "Graph g6: Held-Out Performance by Fold",
    subtitle = paste0(
      "Small points are the five individual folds; the large point is their mean.\n",
      "Where the two series separate, the gap is the optimism introduced by ",
      "selecting on the full sample."
    ),
    x = NULL, y = NULL, colour = NULL, shape = NULL
  ) +
  theme(legend.position = "top")

print(g6_cv_spread)
ggsave(paste0(prints_folder, "g6_cv_spread.png"),
       g6_cv_spread, width = 10, height = 8, dpi = 300)

# ---- out6 --------------------------------------------------------------------
cat("Output out6: How to read the C-statistic on a count outcome\n\n")

zero_share <- mean(ds1[[outcome_var]] == 0)
cat("  share of respondents at zero days: ", scales::percent(zero_share, accuracy = 0.1), "\n", sep = "")
cat("  comparable pair share (fixed):     ",
    scales::percent(mean(cv_summary$comparable_share[cv_summary$variant == "fixed term set"]),
                    accuracy = 0.1), "\n", sep = "")
cat("\nHarrell's C counts a pair only when the two respondents differ on the\n")
cat("outcome. Because most respondents share the value zero, most pairs are not\n")
cat("comparable and never enter the denominator. The statistic therefore\n")
cat("measures how well the model orders respondents who differ in days absent,\n")
cat("and says nothing about how well it separates any-absence from none. That\n")
cat("second question is a different one and is not what Section 5.6 asked for.\n\n")

optimism <- cv_summary %>%
  select(variant, model_label, rmse_mean, mcfadden_mean, c_mean) %>%
  tidyr::pivot_wider(names_from = variant,
                     values_from = c(rmse_mean, mcfadden_mean, c_mean))

cat("Selection optimism (fixed minus re-run), per model:\n\n")
optimism %>%
  transmute(
    Model = model_label,
    `d RMSE` = sprintf("%+.4f", `rmse_mean_fixed term set` - `rmse_mean_selection re-run`),
    `d McFadden` = sprintf("%+.4f", `mcfadden_mean_fixed term set` - `mcfadden_mean_selection re-run`),
    `d C` = sprintf("%+.4f", `c_mean_fixed term set` - `c_mean_selection re-run`)
  ) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nA positive d McFadden or d C is the amount by which evaluating a model on\n")
cat("data that helped select it flatters that model.\n")

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
      "reloads it. These files are the versioned evidentiary record for Sections ",
      "5.4 through 5.6; downstream reports should read them rather than re-estimate."
    ),
    align = c("l", "l", "r", "l")
  )

# ---- out4 --------------------------------------------------------------------
cat("Output out4: Reproducibility parameters and residual scope\n\n")
cat("  seed:                  ", lasso_seed, "\n")
cat("  penalty CV folds:      ", lasso_folds, "\n")
cat("  performance CV folds:  ", perf_folds, " (seed ", perf_seed, ")\n", sep = "")
cat("  outcome:               ", outcome_var, "\n")
cat("  weight:                ", weight_col, " (rescaled to mean 1)\n")
cat("  forced-in terms:       ", paste(forced_vars, collapse = ", "), "\n")
cat("  source parquet:        ", path_parquet, "\n")
cat("  analytic n:            ", scales::comma(n_analytic), "\n")
cat("  weighted N:            ", scales::comma(round(weighted_N)), "\n\n")

cat("Proposal sections model-1 closes:\n")
cat("  - Section 5.4 variable selection, all four specifications\n")
cat("  - Section 5.5 primary multivariable models (Table 3 = t6 / t62)\n")
cat("  - Section 5.6 model performance evaluation (t61 in-sample, t63 / t64 held out)\n\n")

cat("Requirements NOT met, and why:\n")
cat("  - Bootstrap variance estimation (decision 10: replicate weights absent from\n")
cat("    the PUMF). Sandwich and Kish-inflated intervals stand in as lower bounds.\n")
cat("  - Section 5.7 condition-specific models (19 subgroups)\n")
cat("  - Section 5.9 sex-stratified models\n")
cat("  - Section 5.1 Little's MCAR test and multiple imputation\n\n")

cat("Downstream reports should read the artifacts in Table t7 rather than\n")
cat("re-estimate. The fits, coefficients, and fold-level metrics persisted here\n")
cat("are the versioned evidentiary record for Sections 5.4 through 5.6.\n\n")
utils::sessionInfo()

# nolint end
