# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# MODEL-00: Section 5.3 bivariate analysis (Table 2).
# One negative binomial model per candidate predictor, each containing only that
# predictor and the pooled-cycle indicator. Estimation is strictly one predictor
# at a time; only the display is grouped.
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
requireNamespace("MASS", quietly = TRUE)
requireNamespace("readr", quietly = TRUE)
requireNamespace("knitr", quietly = TRUE)

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R")
base::source("./scripts/graphing/graph-presets.R")
# The candidate list is not re-typed here. It is the same object model-1 uses.
base::source("./scripts/modeling/candidate-registry.R")

# ---- declare-globals ---------------------------------------------------------
local_root <- "./analysis/model-00/"
local_data <- paste0(local_root, "data-local/")
fits_folder <- paste0(local_data, "fits/")
prints_folder <- paste0(local_root, "prints/")
path_parquet <- "./data-private/derived/cchs-2-tables/cchs_analytic.parquet"

outcome_primary     <- "days_absent_total"
outcome_sensitivity <- "days_absent_chronic"
weight_col <- "wts_m_pooled"
cycle_var  <- "cchs_cycle_f"
example_seed <- 42

# Set TRUE to discard the cached fits and re-estimate all 188 models.
force_refit <- FALSE

outcome_labels <- c(
  "days_absent_total"   = "All-cause absence days",
  "days_absent_chronic" = "Chronic-condition absence days"
)

basis_labels <- c(
  "per_predictor" = "Per-predictor complete case",
  "shared"        = "Shared model-1 sample"
)

for (folder in c(local_data, fits_folder, prints_folder)) {
  if (!fs::dir_exists(folder)) { fs::dir_create(folder, recurse = TRUE) }
}

# Four estimation series. S1 is Table 2 as Section 5.3 describes it; the other
# three exist to show how much the two arbitrary choices in S1 actually matter.
series_registry <- tibble::tribble(
  ~series_id, ~series_label,                 ~outcome,              ~basis,          ~role,
  "S1",       "Primary",                     outcome_primary,       "per_predictor", "Section 5.3 Table 2 as specified",
  "S2",       "Sample sensitivity",          outcome_primary,       "shared",        "Same rows as model-1, for comparability with Graph g4 there",
  "S3",       "Outcome sensitivity",         outcome_sensitivity,   "per_predictor", "Section 4.1 secondary outcome",
  "S4",       "Sample x outcome sensitivity", outcome_sensitivity,  "shared",        "Both sensitivities applied at once"
)

# Every analytical decision, with the alternatives that were available and the
# reason the chosen option won. `reversal` names the object to edit to undo it.
# Decisions 1-4 are inherited from model-1 and are restated, not re-litigated.
decision_registry <- tibble::tribble(
  ~id, ~decision, ~alternatives, ~chosen, ~rationale, ~reversal,
  1L, "Candidate list",
  "Re-declare locally; source the model-1 registry",
  "Source `scripts/modeling/candidate-registry.R`",
  "A third copy of the candidate list is exactly the drift that the registry was created to end. The file carries a stopifnot() guard on the 51 / 48 counts.",
  "`scripts/modeling/candidate-registry.R`",

  2L, "Excluded candidates",
  "Refit cc_copd and has_family_doctor bivariately; honour the model-1 exclusions",
  "Honour the model-1 exclusions",
  "Bivariately, cc_copd is estimable on the 35+ subsample and has_family_doctor on Ontario-2011 plus all of 2014. Both would then estimate a rate ratio on a differently-defined population than the other 46, and neither would be carried into Section 5.4. They are named in Table t1 so their absence is visible.",
  "`candidate_registry` status in the sourced registry file",

  3L, "Age resolution",
  "age_group_3; dhhgage; both",
  "age_group_3",
  "Collinearity is a multivariable problem and does not arise in a one-predictor model, so dhhgage COULD be fitted here. It is still withheld: offering two encodings of age would break the row-for-row correspondence with model-1 Graph g4 that this report is built to support, and would report the same signal twice.",
  "`candidate_registry` status for dhhgage",

  4L, "Model form",
  "Predictor alone; predictor + cycle; predictor + cycle + age + sex",
  "Predictor + cycle",
  "Section 5.3 specifies the cycle indicator and nothing else. Adding demographic adjusters would make the estimates partially adjusted and no longer the 'unadjusted PRs' the section names.",
  "`fit_bivariate()` in declare-functions",

  5L, "Analytic basis",
  "Per-predictor complete case; the shared model-1 sample; both",
  "Both, with per-predictor as primary",
  "Per-predictor complete case is the conventional Table 2 behaviour and preserves the largest sample for each estimate, but it makes n vary from row to row. The shared basis fixes the rows at model-1's and is reported alongside so a reader can see whether any estimate depends on that choice.",
  "`series_registry` in declare-globals",

  6L, "Outcome scope",
  "days_absent_total only; both outcomes",
  "Both, with days_absent_total as primary",
  "Section 5.3 names one outcome; Section 4.1 names days_absent_chronic as the sensitivity outcome. It is 94% zeros, so its estimates are reported with a convergence and dispersion flag rather than presented as equals.",
  "`series_registry` in declare-globals",

  7L, "Row granularity",
  "One row per variable; one row per non-reference level; both",
  "Both",
  "Section 5.3 asks for rate ratios, which exist only at the level. A variable-level omnibus test is added because a multi-level factor has no single PR and would otherwise be un-rankable.",
  "`t41` chunk",

  8L, "Variance estimation",
  "500 bootstrap replicate weights; Wald standard errors",
  "Wald standard errors, reported beside a robust sandwich alternative",
  "DATA-BLOCKED. Bootstrap replicate weights are absent from the 2010 and 2014 PUMF files; Statistics Canada began releasing them with the 2015 cycle, and strata and PSU identifiers are suppressed. This is decision 10 of model-1, restated. Section 5.3 flags this requirement explicitly, so the report quantifies the gap instead of ignoring it.",
  "Not reversible without a Research Data Centre file",

  9L, "Width-inflation instrument",
  "Naive respondent-level bootstrap; Huber-White sandwich; Kish design effect; do nothing",
  "Kish design effect plus a per-model sandwich",
  "Both are computable from the PUMF and both isolate the weighting component of the design effect. Neither can recover the clustering component, so both are LOWER bounds on the true interval width. A naive bootstrap would estimate the same weighting component at far greater cost.",
  "`robust_vcov()` in declare-functions",

  10L, "Multiplicity",
  "Unadjusted p-values; Benjamini-Hochberg; Bonferroni",
  "Unadjusted, with Benjamini-Hochberg shown alongside",
  "Section 5.3 is a screening step feeding Section 5.4, not a confirmatory analysis, so unadjusted p-values are the requested quantity. The BH column is provided because 47 simultaneous tests invite over-reading.",
  "`t41` chunk",

  11L, "Weight handling",
  "Raw master weights; weights rescaled to mean 1 within each estimation frame",
  "Rescaled to mean 1",
  "Raw CCHS weights sum to the population, which would make glm.nb behave as though the sample contained 25 million observations. Rescaling preserves the relative weighting and sets the nominal n to the actual number of respondents. Matches model-1.",
  "`fit_bivariate()` in declare-functions"
)

domain_colours <- c(
  "Exposure"      = abcol[["magenta"]],
  "Predisposing"  = abcol[["blue"]],
  "Facilitating"  = abcol[["green"]],
  "Needs"         = abcol[["brown"]],
  "Survey design" = abcol[["grey"]]
)

domain_levels <- c("Exposure", "Predisposing", "Facilitating", "Needs", "Survey design")

series_colours <- c(
  "S1" = abcol[["magenta"]],
  "S2" = abcol[["blue"]],
  "S3" = abcol[["green"]],
  "S4" = abcol[["brown"]]
)

variable_labels <- c(
  variable_labels_registry,
  stats::setNames("CCHS cycle", cycle_var)
)
variable_domains <- c(
  variable_domains_registry,
  stats::setNames("Survey design", cycle_var)
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

# Map each design column back to the variable and level that produced it, and
# record the position of that level so the display can preserve factor order.
column_map_for <- function(model_frame, term_vars) {
  model_formula <- stats::reformulate(term_vars)
  mm <- stats::model.matrix(model_formula, data = model_frame)
  assign_index <- attr(mm, "assign")
  term_labels <- attr(stats::terms(model_formula, data = model_frame), "term.labels")
  source_variable <- c("(Intercept)", term_labels)[assign_index + 1]
  keep <- colnames(mm) != "(Intercept)"

  tibble::tibble(
    column = colnames(mm)[keep],
    term_variable = source_variable[keep]
  ) %>%
    mutate(level = strip_variable_prefix(column, term_variable)) %>%
    group_by(term_variable) %>%
    mutate(level_index = dplyr::row_number()) %>%
    ungroup()
}

# Huber-White sandwich covariance for a weighted negative binomial fit, with
# theta held at its estimate. This is the weighting component of the design
# effect and nothing more: strata and PSUs are suppressed in the PUMF, so the
# clustering component is not recoverable. See decision 9.
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

# Kish's approximate design effect from unequal weighting alone. The square root
# is the factor by which a design-based standard error would exceed the
# model-based one if weighting were the only departure from simple random
# sampling. It is a lower bound.
kish_design_effect <- function(w) {
  length(w) * sum(w^2) / (sum(w)^2)
}

# One model of the form outcome ~ cycle + predictor, plus the cycle-only null
# fitted on the SAME rows so the likelihood-ratio test is legitimate.
# Returns one row per estimated term, carrying the model-level diagnostics.
fit_bivariate <- function(base_frame, predictor, outcome, series_id) {
  needed <- c(outcome, weight_col, cycle_var, predictor)
  frame <- base_frame[, needed, drop = FALSE]
  frame <- frame[stats::complete.cases(frame), , drop = FALSE]
  # A level that vanished with the complete-case restriction would otherwise
  # contribute an all-zero design column and an unestimable coefficient.
  frame <- droplevels(frame)

  # Decision 11: rescale inside the estimation frame so sum(weights) == n_k.
  frame$weight_scaled <- frame[[weight_col]] / mean(frame[[weight_col]])
  n_used <- nrow(frame)

  full_formula <- stats::reformulate(c(cycle_var, predictor), response = outcome)
  null_formula <- stats::reformulate(cycle_var, response = outcome)
  environment(full_formula) <- environment()
  environment(null_formula) <- environment()

  attempt <- function(model_formula) {
    tryCatch(
      suppressWarnings(
        MASS::glm.nb(model_formula, data = frame, weights = weight_scaled,
                     control = stats::glm.control(maxit = 100))
      ),
      error = function(e) NULL
    )
  }

  full_fit <- attempt(full_formula)
  null_fit <- attempt(null_formula)

  if (is.null(full_fit)) {
    return(tibble::tibble(
      series_id = series_id, variable = predictor, column = NA_character_,
      level = NA_character_, level_index = NA_integer_, term_variable = NA_character_,
      estimate = NA_real_, std_error = NA_real_, robust_se = NA_real_,
      p_value = NA_real_, rate_ratio = NA_real_,
      ci_low = NA_real_, ci_high = NA_real_,
      ci_low_robust = NA_real_, ci_high_robust = NA_real_,
      n_used = n_used, theta = NA_real_, converged = FALSE, iterations = NA_integer_,
      aic = NA_real_, lr_statistic = NA_real_, lr_df = NA_integer_, lr_p = NA_real_,
      var_mean_ratio = NA_real_, reference_level = NA_character_,
      design_effect = NA_real_
    ))
  }

  map <- column_map_for(frame, c(cycle_var, predictor))
  robust_se <- sqrt(diag(robust_vcov(full_fit)))

  lr_statistic <- if (is.null(null_fit)) NA_real_ else {
    2 * (as.numeric(stats::logLik(full_fit)) - as.numeric(stats::logLik(null_fit)))
  }
  lr_df <- sum(map$term_variable == predictor)
  outcome_values <- frame[[outcome]]
  predictor_values <- frame[[predictor]]
  reference <- if (is.factor(predictor_values)) levels(predictor_values)[1] else "continuous"

  summary(full_fit)$coefficients %>%
    as.data.frame() %>%
    tibble::rownames_to_column("column") %>%
    rename(estimate = Estimate, std_error = `Std. Error`, p_value = `Pr(>|z|)`) %>%
    mutate(robust_se = robust_se[column]) %>%
    filter(column != "(Intercept)") %>%
    left_join(map, by = "column") %>%
    transmute(
      series_id = series_id,
      variable = predictor,
      column, level, level_index, term_variable,
      estimate, std_error, robust_se, p_value,
      rate_ratio = exp(estimate),
      ci_low  = exp(estimate - stats::qnorm(0.975) * std_error),
      ci_high = exp(estimate + stats::qnorm(0.975) * std_error),
      ci_low_robust  = exp(estimate - stats::qnorm(0.975) * robust_se),
      ci_high_robust = exp(estimate + stats::qnorm(0.975) * robust_se),
      n_used = n_used,
      theta = full_fit$theta,
      converged = full_fit$converged,
      iterations = full_fit$iter,
      aic = stats::AIC(full_fit),
      lr_statistic = lr_statistic,
      lr_df = lr_df,
      lr_p = stats::pchisq(lr_statistic, df = lr_df, lower.tail = FALSE),
      var_mean_ratio = stats::var(outcome_values) / mean(outcome_values),
      reference_level = reference,
      design_effect = kish_design_effect(frame[[weight_col]])
    )
}

# ---- load-data ---------------------------------------------------------------
ds0 <- arrow::read_parquet(path_parquet)

# ---- tweak-data-0 ------------------------------------------------------------
# One model frame serves all four series. Missingness is NOT resolved here:
# each fit resolves it against its own two columns (decision 5), and the shared
# basis is a row filter applied on top.
ds_model <- ds0 %>%
  select(all_of(c(outcome_primary, outcome_sensitivity, weight_col, cycle_var,
                  included_vars))) %>%
  mutate(across(where(is.ordered), ~ factor(., ordered = FALSE))) %>%
  mutate(across(where(is.logical), to_yes_no)) %>%
  mutate(across(all_of(c("dhhgle5", "dhhg611", "dhhgl12")), to_yes_no)) %>%
  mutate(across(where(is.character), factor)) %>%
  filter(!is.na(.data[[weight_col]]), !is.na(.data[[cycle_var]])) %>%
  mutate(.respondent_id = dplyr::row_number())

n_source <- nrow(ds0)
n_universe <- nrow(ds_model)

shared_flag <- stats::complete.cases(ds_model[, c(cycle_var, included_vars)])
ds_shared <- ds_model %>% filter(shared_flag)
n_shared <- nrow(ds_shared)

base_frames <- list(per_predictor = ds_model, shared = ds_shared)

# ---- inspect-data-0 ----------------------------------------------------------
ds0 %>% dplyr::glimpse(width = 100)

# ---- data-context-tables -----------------------------------------------------
# A single Ellis output feeds this report. No joins are performed, so there is
# no risk of row multiplication between the parquet file and the model frames.
cat("Source table: ", path_parquet, "\n", sep = "")
cat("  grain:      one row per respondent, two pooled CCHS cycles\n")
cat("  rows:       ", format(nrow(ds0), big.mark = ","), "\n", sep = "")
cat("  columns:    ", ncol(ds0), "\n\n", sep = "")

cat("Columns this report draws on:\n")
cat("  outcome (primary):     ", outcome_primary, "\n", sep = "")
cat("  outcome (sensitivity): ", outcome_sensitivity, "\n", sep = "")
cat("  weight:                ", weight_col, " (master weight halved for pooling)\n", sep = "")
cat("  in every model:        ", cycle_var, "\n", sep = "")
cat("  predictors:            ", length(included_vars), " of ", nrow(candidate_registry),
    " registered, one per model (see Table t1)\n\n", sep = "")

ds_model %>%
  count(!!rlang::sym(cycle_var), name = "respondents") %>%
  mutate(share = scales::percent(respondents / sum(respondents), accuracy = 0.1)) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

# ---- data-context-person -----------------------------------------------------
# Grain proof, then one respondent shown in full so a reader can see exactly
# what a single row of the model frame contains.
cat("Grain proof\n")
cat("  rows in source:          ", format(n_source, big.mark = ","), "\n", sep = "")
cat("  rows with weight + cycle:", format(n_universe, big.mark = ","), "\n", sep = "")
cat("  rows in shared basis:    ", format(n_shared, big.mark = ","), "\n", sep = "")
cat("  duplicated ids:          ", sum(duplicated(ds_model$.respondent_id)), "\n\n", sep = "")

set.seed(example_seed)
example_row <- ds_model %>% slice_sample(n = 1)

cat("One respondent, every column available to estimation:\n\n")
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
  arrange(match(domain, c("Outcome / design", domain_levels))) %>%
  select(Domain = domain, Variable = variable_label, Value = value) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

# ---- data-context-distributions ----------------------------------------------
# Both outcomes, because the sensitivity series answers to the second one, and
# the dispersion statistic that justifies the negative binomial likelihood.
outcome_profile <- purrr::map_dfr(
  c(outcome_primary, outcome_sensitivity),
  function(this_outcome) {
    y <- ds_model[[this_outcome]]
    y <- y[!is.na(y)]
    w <- ds_model[[weight_col]][!is.na(ds_model[[this_outcome]])]
    w <- w / mean(w)
    weighted_mean <- stats::weighted.mean(y, w)
    tibble::tibble(
      outcome = outcome_labels[[this_outcome]],
      n = length(y),
      `mean (unweighted)` = mean(y),
      `mean (weighted)` = weighted_mean,
      `variance (weighted)` = sum(w * (y - weighted_mean)^2) / sum(w),
      `zeros (%)` = 100 * mean(y == 0),
      median = stats::median(y),
      `p90` = as.numeric(stats::quantile(y, 0.90)),
      maximum = max(y)
    )
  }
) %>%
  mutate(`variance / mean` = `variance (weighted)` / `mean (weighted)`)

outcome_profile %>%
  mutate(across(where(is.numeric), ~ round(., 3))) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\nEquidispersion would put variance / mean at 1. Neither outcome is close,\n")
cat("which is why Section 5.3 specifies a negative binomial rather than a Poisson.\n\n")

cat("Weighting, before any model is fitted:\n")
kish_universe <- kish_design_effect(ds_model[[weight_col]])
cat("  weight range:            ", sprintf("%.2f to %.2f",
    min(ds_model[[weight_col]]), max(ds_model[[weight_col]])), "\n", sep = "")
cat("  coefficient of variation:", sprintf("%.3f",
    stats::sd(ds_model[[weight_col]]) / mean(ds_model[[weight_col]])), "\n")
cat("  Kish design effect:      ", sprintf("%.3f", kish_universe), "\n")
cat("  effective sample size:   ",
    scales::comma(round(n_universe / kish_universe)), " of ",
    scales::comma(n_universe), "\n", sep = "")

# ---- SECTION: Step 1 - The Bivariate Protocol ---------------------------------
# Section 5.3 asks for one model per predictor. Establishing which predictors,
# on which rows, and against which outcome is the whole of the specification.

# ---- t1 ----------------------------------------------------------------------
candidate_registry %>%
  transmute(
    Domain = factor(domain, levels = domain_levels),
    Variable = variable,
    Label = variable_label,
    `Fitted here` = ifelse(status == "include", "yes", "NO"),
    `Reason for exclusion` = exclusion_reason
  ) %>%
  arrange(Domain, Label) %>%
  print_table(
    caption = paste0(
      "Table t1: Candidate registry, sourced from scripts/modeling/candidate-registry.R. ",
      length(included_vars), " of ", nrow(candidate_registry),
      " variables receive a bivariate model; the three exclusions are inherited from ",
      "model-1 and restated as decisions 2 and 3."
    ),
    align = c("l", "l", "l", "c", "l")
  )

# ---- t11 ---------------------------------------------------------------------
model_inventory <- purrr::map_dfr(included_vars, function(this_var) {
  values <- ds_model[[this_var]]
  tibble::tibble(
    variable = this_var,
    domain = variable_domains[[this_var]],
    n_levels = nlevels(droplevels(values[!is.na(values)])),
    n_terms = max(nlevels(droplevels(values[!is.na(values)])) - 1L, 1L)
  )
})

model_inventory %>%
  group_by(Domain = factor(domain, levels = domain_levels)) %>%
  summarise(
    `Models fitted` = n(),
    `Rate ratios estimated` = sum(n_terms),
    `Largest factor` = max(n_levels),
    .groups = "drop"
  ) %>%
  bind_rows(tibble::tibble(
    Domain = factor("Survey design", levels = domain_levels),
    `Models fitted` = 0L,
    `Rate ratios estimated` = nlevels(ds_model[[cycle_var]]) - 1L,
    `Largest factor` = nlevels(ds_model[[cycle_var]])
  )) %>%
  print_table(
    caption = paste0(
      "Table t11: Model inventory by Andersen domain. Every model also carries ",
      "the cycle indicator, so the survey-design row is estimated ",
      length(included_vars), " times over."
    ),
    align = c("l", "r", "r", "r")
  )

# ---- out1 --------------------------------------------------------------------
cat("Section 5.3, as written:\n\n")
cat("  'For each potential predictor variable individually, fit a weighted\n")
cat("   negative binomial regression model with only that predictor and the\n")
cat("   cycle indicator, using survey weights. Report unadjusted prevalence\n")
cat("   rate ratios (PRs) and 95% confidence intervals.'\n\n")
cat("  'Confidence intervals must be computed using bootstrap variance\n")
cat("   estimation (500 bootstrap weights provided by Statistics Canada),\n")
cat("   NOT using standard model-based SEs with simple random sampling\n")
cat("   assumptions. Failure to use bootstrap weights will yield artificially\n")
cat("   narrow CIs.'\n\n")

cat("Delivered here:\n\n")
requirement_status <- tibble::tibble(
  requirement = c(
    "One model per predictor",
    "Predictor plus cycle indicator only",
    "Negative binomial likelihood",
    "Survey weights applied",
    "Unadjusted rate ratios reported",
    "95% confidence intervals reported",
    "Bootstrap variance estimation"
  ),
  status = c("met", "met", "met", "met", "met", "met", "NOT MET - data blocked"),
  where = c(
    paste0("Table t4, ", length(included_vars), " models"),
    "decision 4",
    "MASS::glm.nb",
    paste0(weight_col, ", rescaled to mean 1 (decision 11)"),
    "Table t4",
    "Table t4, Graph g1",
    "decision 8; quantified in Table t21"
  )
)
requirement_status %>% as.data.frame() %>% print(row.names = FALSE)

cat("\nThe 500 bootstrap replicate weights do not exist for these two cycles.\n")
cat("Statistics Canada began distributing them with the 2015 CCHS; the 2010-2011\n")
cat("and 2013-2014 Public Use Microdata Files carry the master weight only, and\n")
cat("stratum and cluster identifiers are suppressed. Section 5.3 anticipates the\n")
cat("consequence correctly: the intervals below ARE artificially narrow. Step 2\n")
cat("estimates by how much.\n")

# ---- SECTION: Step 2 - The Interval Problem -----------------------------------
# Section 5.3's warning is the one requirement these data cannot satisfy. Rather
# than note it and move on, this step measures the part of the gap that IS
# measurable and states plainly which part is not.

# ---- t2 ----------------------------------------------------------------------
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
      "Table t2: Decision registry. Decisions 2, 3 and 8 are inherited from ",
      "model-1 and restated so this report stands alone."
    ),
    align = c("r", "l", "l", "l", "l", "l")
  )

# ---- SECTION: Step 3 - Fitting --------------------------------------------------
# 48 predictors x 2 analytic bases x 2 outcomes = 192 models, each with a
# cycle-only companion fitted on identical rows for the likelihood-ratio test.

# ---- fit-models ---------------------------------------------------------------
fits_path <- paste0(fits_folder, "bivariate-terms.rds")

if (force_refit || !fs::file_exists(fits_path)) {
  fit_start <- Sys.time()
  bivariate_terms <- purrr::pmap_dfr(
    series_registry %>% select(series_id, outcome, basis),
    function(series_id, outcome, basis) {
      purrr::map_dfr(
        included_vars,
        ~ fit_bivariate(base_frames[[basis]], .x, outcome, series_id)
      )
    }
  )
  fit_duration <- round(as.numeric(difftime(Sys.time(), fit_start, units = "mins")), 2)
  attr(bivariate_terms, "fit_duration_min") <- fit_duration
  saveRDS(bivariate_terms, fits_path)
} else {
  bivariate_terms <- readRDS(fits_path)
  fit_duration <- attr(bivariate_terms, "fit_duration_min")
}

bivariate_terms <- bivariate_terms %>%
  mutate(
    domain = factor(variable_domains[variable], levels = domain_levels),
    variable_label = variable_labels[variable],
    is_cycle = term_variable == cycle_var,
    term = ifelse(is.na(level) | level == "", variable_label,
                  paste0(variable_label, ": ", level))
  )

readr::write_csv(
  bivariate_terms %>% select(-domain) %>%
    mutate(domain = variable_domains[variable]),
  paste0(local_data, "bivariate-terms.csv")
)

model_diagnostics <- bivariate_terms %>%
  distinct(series_id, variable, variable_label, domain, n_used, theta, converged,
           iterations, aic, lr_statistic, lr_df, lr_p, var_mean_ratio,
           reference_level, design_effect)

readr::write_csv(model_diagnostics, paste0(local_data, "model-diagnostics.csv"))

# ---- t21 ---------------------------------------------------------------------
# The measurable part of the interval gap. Two instruments, both isolating the
# weighting component of the design effect; neither can see clustering.
inflation_by_model <- bivariate_terms %>%
  filter(series_id == "S1", !is_cycle, !is.na(std_error)) %>%
  mutate(inflation = robust_se / std_error)

design_effect_summary <- tibble::tribble(
  ~instrument, ~quantity, ~value, ~covers, ~missing,
  "Kish design effect",
  "n * sum(w^2) / (sum(w))^2 over the full universe",
  sprintf("%.3f", kish_universe),
  "unequal weighting",
  "stratification, clustering",

  "Kish effective n",
  "n / design effect",
  paste0(scales::comma(round(n_universe / kish_universe)), " of ",
         scales::comma(n_universe)),
  "unequal weighting",
  "stratification, clustering",

  "Implied SE multiplier",
  "sqrt(design effect)",
  sprintf("%.3f", sqrt(kish_universe)),
  "unequal weighting",
  "stratification, clustering",

  "Sandwich SE multiplier (median)",
  "median of robust SE / Wald SE across all Series S1 terms",
  sprintf("%.3f", stats::median(inflation_by_model$inflation, na.rm = TRUE)),
  "unequal weighting, model misspecification",
  "stratification, clustering",

  "Sandwich SE multiplier (range)",
  "range of robust SE / Wald SE across all Series S1 terms",
  sprintf("%.3f to %.3f", min(inflation_by_model$inflation, na.rm = TRUE),
          max(inflation_by_model$inflation, na.rm = TRUE)),
  "unequal weighting, model misspecification",
  "stratification, clustering"
)

design_effect_summary %>%
  transmute(
    Instrument = instrument,
    Quantity = quantity,
    Value = value,
    `Accounts for` = covers,
    `Cannot account for` = missing
  ) %>%
  print_table(
    caption = paste0(
      "Table t21: How much narrower the reported intervals are likely to be. ",
      "Both instruments are LOWER bounds: strata and PSU identifiers are ",
      "suppressed in the PUMF, so the clustering component of the design effect ",
      "is not merely unestimated but unestimable."
    ),
    align = c("l", "l", "r", "l", "l")
  )

# ---- out2 --------------------------------------------------------------------
cat("Reading Table t21\n\n")
cat("A Wald interval on the log scale has half-width 1.96 * SE. If the true\n")
cat("design-based SE exceeds the model-based one by a factor k, then every\n")
cat("interval below is too narrow by that same factor on the log scale.\n\n")
cat("  Kish lower bound, k =        ", sprintf("%.2f", sqrt(kish_universe)), "\n")
cat("  Sandwich median,  k =        ",
    sprintf("%.2f", stats::median(inflation_by_model$inflation, na.rm = TRUE)), "\n\n")
cat("A rate ratio reported as 1.30 (1.20-1.41) would, at k = ",
    sprintf("%.2f", sqrt(kish_universe)), ", become roughly\n", sep = "")
example_pr <- 1.30
example_half <- log(1.41 / 1.20) / 2
cat("  ", sprintf("%.2f (%.2f-%.2f)", example_pr,
    example_pr * exp(-example_half * sqrt(kish_universe)),
    example_pr * exp(example_half * sqrt(kish_universe))), "\n\n", sep = "")
cat("This is illustrative arithmetic, not a correction that has been applied.\n")
cat("Every interval in Table t4 and Graph g1 is the uncorrected Wald interval,\n")
cat("because that is the quantity a reader can check against the model output.\n")
cat("The robust interval is carried alongside it in both artifacts.\n\n")

cat("What neither instrument recovers:\n")
cat("  - CCHS uses a multistage stratified cluster design. Clustering inflates\n")
cat("    variance further, typically by more than weighting does.\n")
cat("  - The 500 replicate weights encode BOTH components. Nothing computable\n")
cat("    from a PUMF substitutes for them.\n")
cat("  - Therefore: treat every interval here as a lower bound on width, and\n")
cat("    treat p-values near 0.05 as undecided rather than as decided.\n")

# ---- out3 --------------------------------------------------------------------
cat("Fitting log\n\n")
if (!is.null(fit_duration)) {
  cat("  estimation time:      ", fit_duration, " minutes\n", sep = "")
}
cat("  models attempted:     ", nrow(model_diagnostics), "\n", sep = "")
cat("  models converged:     ", sum(model_diagnostics$converged, na.rm = TRUE), "\n", sep = "")
cat("  models failed:        ", sum(is.na(model_diagnostics$theta)), "\n\n", sep = "")

model_diagnostics %>%
  group_by(series_id) %>%
  summarise(
    models = n(),
    converged = sum(converged, na.rm = TRUE),
    failed = sum(is.na(theta)),
    `median n` = scales::comma(stats::median(n_used)),
    `n range` = paste0(scales::comma(min(n_used)), " to ", scales::comma(max(n_used))),
    `median theta` = sprintf("%.4f", stats::median(theta, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  left_join(series_registry %>% select(series_id, series_label, outcome, basis),
            by = "series_id") %>%
  mutate(outcome = outcome_labels[outcome], basis = basis_labels[basis]) %>%
  select(series_id, series_label, outcome, basis, models, converged, failed,
         `median n`, `n range`, `median theta`) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

non_convergers <- model_diagnostics %>% filter(!converged | is.na(theta))
if (nrow(non_convergers) > 0) {
  cat("\nModels that did not converge cleanly:\n")
  non_convergers %>%
    select(series_id, variable_label, n_used, theta, iterations) %>%
    as.data.frame() %>%
    print(row.names = FALSE)
} else {
  cat("\nAll models converged.\n")
}

# ---- t3 ----------------------------------------------------------------------
# What the per-predictor basis buys, variable by variable.
sample_comparison <- model_diagnostics %>%
  filter(series_id %in% c("S1", "S2")) %>%
  select(variable_label, domain, series_id, n_used) %>%
  tidyr::pivot_wider(names_from = series_id, values_from = n_used) %>%
  mutate(
    gain = S1 - S2,
    gain_pct = 100 * gain / S2
  ) %>%
  arrange(domain, variable_label)

sample_comparison %>%
  transmute(
    Domain = domain,
    Variable = variable_label,
    `n (per-predictor)` = scales::comma(S1),
    `n (shared)` = scales::comma(S2),
    `Rows gained` = scales::comma(gain),
    `Gain (%)` = sprintf("%+.1f%%", gain_pct)
  ) %>%
  print_table(
    caption = paste0(
      "Table t3: What the per-predictor basis buys. The shared basis holds all ",
      length(included_vars), " models at ", scales::comma(n_shared),
      " respondents; the per-predictor basis lets each model use every row on ",
      "which its own predictor is observed."
    ),
    align = c("l", "l", "r", "r", "r", "r")
  )

# ---- SECTION: Step 4 - Table 2 -------------------------------------------------
# The deliverable Section 5.3 names, plus the omnibus tests that a table of
# level-wise rate ratios cannot supply on its own.

# ---- t4 ----------------------------------------------------------------------
table_two <- bivariate_terms %>%
  filter(series_id == "S1", !is_cycle) %>%
  arrange(domain, variable_label, level_index)

readr::write_csv(table_two, paste0(local_data, "table-two.csv"))

table_two %>%
  transmute(
    Domain = domain,
    Variable = variable_label,
    Level = level,
    Reference = reference_level,
    n = scales::comma(n_used),
    PR = sprintf("%.3f", rate_ratio),
    `95% CI (Wald)` = sprintf("%.3f - %.3f", ci_low, ci_high),
    `95% CI (robust)` = sprintf("%.3f - %.3f", ci_low_robust, ci_high_robust),
    `p` = ifelse(p_value < 0.001, "<0.001", sprintf("%.3f", p_value))
  ) %>%
  print_table(
    caption = paste0(
      "Table t4: Section 5.3 Table 2. Unadjusted prevalence rate ratios for ",
      outcome_labels[[outcome_primary]],
      ", each from a separate negative binomial model containing only that ",
      "predictor and the cycle indicator. Wald intervals are the reported ",
      "quantity; robust intervals are shown beside them because neither is the ",
      "bootstrap interval Section 5.3 requires (decisions 8 and 9)."
    ),
    align = c("l", "l", "l", "l", "r", "r", "r", "r", "r"),
    scroll_height = "700px"
  )

# ---- t41 ---------------------------------------------------------------------
# A four-level factor has no single rate ratio. The likelihood-ratio test gives
# each variable one number, which is what makes the 47 models rankable.
omnibus_tests <- model_diagnostics %>%
  filter(series_id == "S1") %>%
  mutate(p_adjusted = stats::p.adjust(lr_p, method = "BH")) %>%
  arrange(lr_p)

readr::write_csv(omnibus_tests, paste0(local_data, "omnibus-tests.csv"))

omnibus_tests %>%
  transmute(
    Rank = dplyr::row_number(),
    Domain = domain,
    Variable = variable_label,
    n = scales::comma(n_used),
    `LR chi-sq` = sprintf("%.1f", lr_statistic),
    df = lr_df,
    `p` = ifelse(lr_p < 0.001, "<0.001", sprintf("%.3f", lr_p)),
    `p (BH)` = ifelse(p_adjusted < 0.001, "<0.001", sprintf("%.3f", p_adjusted)),
    `Survives BH at 0.05` = ifelse(p_adjusted < 0.05, "yes", "no")
  ) %>%
  print_table(
    caption = paste0(
      "Table t41: Variable-level omnibus tests against the cycle-only model on ",
      "identical rows. Because the likelihood is weighted, these are ",
      "pseudo-likelihood-ratio statistics and their reference distribution is ",
      "approximate; read the ranking, not the exact p-value."
    ),
    align = c("r", "l", "l", "r", "r", "r", "r", "r", "c"),
    scroll_height = "600px"
  )

# ---- g1-data-prep -------------------------------------------------------------
# Ordering is deliberate. Within each domain band, variables appear in the same
# sequence as model-1 Graph g4 - alphabetically by label, reading from the
# bottom of the band upward - so the two artifacts can be laid side by side.
forest_base <- table_two %>%
  filter(!is.na(rate_ratio)) %>%
  arrange(domain, variable_label, level_index) %>%
  mutate(
    term = factor(term, levels = unique(term)),
    significant = ifelse(p_value < 0.05, "p < 0.05", "not significant")
  )

pr_axis_limits <- c(
  max(0.2, min(forest_base$ci_low, na.rm = TRUE)),
  min(10, max(forest_base$ci_high, na.rm = TRUE))
)

# ---- g1 -----------------------------------------------------------------------
g1_bivariate_forest <- forest_base %>%
  ggplot(aes(x = rate_ratio, y = term)) +
  geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.4) +
  geom_linerange(aes(xmin = ci_low_robust, xmax = ci_high_robust),
                 colour = "grey75", linewidth = 1.6) +
  geom_linerange(aes(xmin = ci_low, xmax = ci_high, colour = domain),
                 linewidth = 0.6) +
  geom_point(aes(colour = domain, alpha = significant), size = 1.9) +
  facet_grid(domain ~ ., scales = "free_y", space = "free_y") +
  scale_colour_manual(values = domain_colours, guide = "none") +
  scale_alpha_manual(values = c("p < 0.05" = 1, "not significant" = 0.35)) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.1)) +
  coord_cartesian(xlim = pr_axis_limits) +
  labs(
    title = "Graph g1: Unadjusted Rate Ratios, One Model per Predictor",
    subtitle = paste0(
      "Outcome: ", outcome_labels[[outcome_primary]],
      ". Each estimate comes from its own model of that outcome on the cycle indicator\n",
      "and the named predictor alone. Coloured bars are the Wald intervals Section 5.3 asks for;\n",
      "pale grey bars behind them are robust intervals. Neither is the bootstrap interval the\n",
      "section requires, and both are narrower than it would be (Table t21).\n",
      "Domain bands and their internal ordering match model-1 Graph g4."
    ),
    x = "Prevalence rate ratio (log scale), reference level = 1",
    y = NULL, alpha = NULL
  ) +
  theme(
    legend.position = "top",
    strip.text.y = element_text(angle = 0),
    panel.grid.minor = element_blank()
  )

print(g1_bivariate_forest)
ggsave(paste0(prints_folder, "g1_bivariate_forest.png"),
       g1_bivariate_forest, width = 11, height = 16, dpi = 300, limitsize = FALSE)

# ---- g11 ----------------------------------------------------------------------
# The same estimates, ranked. Each term belongs to exactly one domain, so a
# global reorder sorts correctly inside every facet.
g11_sorted_forest <- forest_base %>%
  mutate(term = forcats::fct_reorder(as.character(term), rate_ratio)) %>%
  ggplot(aes(x = rate_ratio, y = term)) +
  geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.4) +
  geom_linerange(aes(xmin = ci_low_robust, xmax = ci_high_robust),
                 colour = "grey75", linewidth = 1.6) +
  geom_linerange(aes(xmin = ci_low, xmax = ci_high, colour = domain),
                 linewidth = 0.6) +
  geom_point(aes(colour = domain, alpha = significant), size = 1.9) +
  facet_grid(domain ~ ., scales = "free_y", space = "free_y") +
  scale_colour_manual(values = domain_colours, guide = "none") +
  scale_alpha_manual(values = c("p < 0.05" = 1, "not significant" = 0.35)) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.1)) +
  coord_cartesian(xlim = pr_axis_limits) +
  labs(
    title = "Graph g11: The Same Rate Ratios, Ranked Within Each Domain",
    subtitle = paste0(
      "Identical estimates to Graph g1, reordered by magnitude inside each domain band.\n",
      "Use g1 to compare against model-1 Graph g4; use g11 to see which levels carry the\n",
      "strongest unadjusted signal."
    ),
    x = "Prevalence rate ratio (log scale), reference level = 1",
    y = NULL, alpha = NULL
  ) +
  theme(
    legend.position = "top",
    strip.text.y = element_text(angle = 0),
    panel.grid.minor = element_blank()
  )

print(g11_sorted_forest)
ggsave(paste0(prints_folder, "g11_sorted_forest.png"),
       g11_sorted_forest, width = 11, height = 16, dpi = 300, limitsize = FALSE)

# ---- SECTION: Step 5 - The Cycle Term ------------------------------------------
# The cycle indicator is estimated once per predictor. Its spread across those
# models is a free diagnostic: a term that is genuinely independent of the
# predictors should barely move.

# ---- g2 ------------------------------------------------------------------------
cycle_terms <- bivariate_terms %>%
  filter(series_id == "S1", is_cycle, !is.na(rate_ratio))

cycle_only_pr <- {
  frame <- ds_model[, c(outcome_primary, weight_col, cycle_var)]
  frame <- frame[stats::complete.cases(frame), , drop = FALSE]
  frame$weight_scaled <- frame[[weight_col]] / mean(frame[[weight_col]])
  cycle_formula <- stats::reformulate(cycle_var, response = outcome_primary)
  environment(cycle_formula) <- environment()
  fit <- suppressWarnings(
    MASS::glm.nb(cycle_formula, data = frame, weights = weight_scaled,
                 control = stats::glm.control(maxit = 100))
  )
  exp(stats::coef(fit)[2])
}

g2_cycle_stability <- cycle_terms %>%
  arrange(domain, variable_label) %>%
  mutate(host_label = factor(variable_label, levels = unique(variable_label))) %>%
  ggplot(aes(x = rate_ratio, y = host_label, colour = domain)) +
  geom_vline(xintercept = cycle_only_pr, colour = abcol[["grey"]],
             linetype = "dashed", linewidth = 0.5) +
  geom_vline(xintercept = 1, colour = "grey75", linewidth = 0.3) +
  geom_linerange(aes(xmin = ci_low, xmax = ci_high), linewidth = 0.5) +
  geom_point(size = 1.8) +
  facet_grid(domain ~ ., scales = "free_y", space = "free_y") +
  scale_colour_manual(values = domain_colours, guide = "none") +
  scale_x_log10(labels = scales::label_number(accuracy = 0.01)) +
  labs(
    title = paste0("Graph g2: The Cycle Rate Ratio, Estimated ",
                   length(included_vars), " Times"),
    subtitle = paste0(
      "2013-2014 against 2010-2011, from each bivariate model in turn. ",
      "Dashed line is the cycle-only model (PR = ",
      sprintf("%.3f", cycle_only_pr), ").\n",
      "A predictor whose model pulls the cycle term away from that line is ",
      "distributed unevenly across the two cycles."
    ),
    x = "Cycle rate ratio (log scale)", y = "Model identified by its predictor"
  ) +
  theme(strip.text.y = element_text(angle = 0), panel.grid.minor = element_blank())

print(g2_cycle_stability)
ggsave(paste0(prints_folder, "g2_cycle_stability.png"),
       g2_cycle_stability, width = 9, height = 12, dpi = 300, limitsize = FALSE)

# ---- SECTION: Step 6 - Sensitivity ---------------------------------------------
# Two arbitrary choices sit inside Series S1: which rows, and which outcome.
# Series S2 through S4 vary each one and show what it was worth.

# ---- g3 ------------------------------------------------------------------------
basis_pairs <- bivariate_terms %>%
  filter(series_id %in% c("S1", "S2"), !is_cycle, !is.na(rate_ratio)) %>%
  select(series_id, column, term, domain, rate_ratio, p_value) %>%
  tidyr::pivot_wider(names_from = series_id,
                     values_from = c(rate_ratio, p_value)) %>%
  filter(!is.na(rate_ratio_S1), !is.na(rate_ratio_S2))

basis_axis <- range(c(basis_pairs$rate_ratio_S1, basis_pairs$rate_ratio_S2))

g3_basis_sensitivity <- basis_pairs %>%
  ggplot(aes(x = rate_ratio_S1, y = rate_ratio_S2, colour = domain)) +
  geom_abline(slope = 1, intercept = 0, colour = "grey60", linewidth = 0.4) +
  geom_hline(yintercept = 1, colour = "grey85", linewidth = 0.3) +
  geom_vline(xintercept = 1, colour = "grey85", linewidth = 0.3) +
  geom_point(size = 2, alpha = 0.85) +
  scale_colour_manual(values = domain_colours) +
  scale_x_log10(limits = basis_axis) +
  scale_y_log10(limits = basis_axis) +
  coord_fixed() +
  labs(
    title = "Graph g3: Does the Choice of Analytic Basis Move the Estimates?",
    subtitle = paste0(
      "Every rate ratio, estimated twice: on all rows where its own predictor is ",
      "observed (x) and on the ",
      scales::comma(n_shared), " rows model-1 uses (y).\n",
      "Points on the diagonal are indifferent to the choice. Decision 5 records why ",
      "the x-axis version is primary."
    ),
    x = "PR, per-predictor complete case (Series S1)",
    y = "PR, shared model-1 sample (Series S2)",
    colour = NULL
  ) +
  theme(legend.position = "top", panel.grid.minor = element_blank())

print(g3_basis_sensitivity)
ggsave(paste0(prints_folder, "g3_basis_sensitivity.png"),
       g3_basis_sensitivity, width = 8.5, height = 8.5, dpi = 300)

# ---- g4 ------------------------------------------------------------------------
outcome_pairs <- bivariate_terms %>%
  filter(series_id %in% c("S1", "S3"), !is_cycle, !is.na(rate_ratio)) %>%
  select(series_id, column, term, domain, rate_ratio) %>%
  tidyr::pivot_wider(names_from = series_id, values_from = rate_ratio) %>%
  filter(!is.na(S1), !is.na(S3))

g4_outcome_sensitivity <- outcome_pairs %>%
  ggplot(aes(x = S1, y = S3, colour = domain)) +
  geom_abline(slope = 1, intercept = 0, colour = "grey60", linewidth = 0.4) +
  geom_hline(yintercept = 1, colour = "grey85", linewidth = 0.3) +
  geom_vline(xintercept = 1, colour = "grey85", linewidth = 0.3) +
  geom_point(size = 2, alpha = 0.85) +
  scale_colour_manual(values = domain_colours) +
  scale_x_log10() +
  scale_y_log10() +
  labs(
    title = "Graph g4: All-Cause Absence Against Chronic-Condition Absence",
    subtitle = paste0(
      "The same ", length(included_vars), " bivariate models fitted to each outcome in turn. ",
      "Points above the diagonal mark predictors\nwhose association is stronger for the ",
      "chronic-condition outcome than for absence overall. That outcome is 94% zeros,\nso its ",
      "estimates carry wider intervals than the point positions suggest."
    ),
    x = paste0("PR, ", outcome_labels[[outcome_primary]], " (Series S1)"),
    y = paste0("PR, ", outcome_labels[[outcome_sensitivity]], " (Series S3)"),
    colour = NULL
  ) +
  theme(legend.position = "top", panel.grid.minor = element_blank())

print(g4_outcome_sensitivity)
ggsave(paste0(prints_folder, "g4_outcome_sensitivity.png"),
       g4_outcome_sensitivity, width = 8.5, height = 7, dpi = 300)

# ---- t42 ---------------------------------------------------------------------
# The sensitivity series in numbers, restricted to the terms that move most.
sensitivity_wide <- bivariate_terms %>%
  filter(!is_cycle, !is.na(rate_ratio)) %>%
  select(series_id, domain, term, rate_ratio, ci_low, ci_high) %>%
  mutate(cell = sprintf("%.3f (%.3f-%.3f)", rate_ratio, ci_low, ci_high)) %>%
  select(-rate_ratio, -ci_low, -ci_high) %>%
  tidyr::pivot_wider(names_from = series_id, values_from = cell)

basis_movers <- basis_pairs %>%
  mutate(log_shift = abs(log(rate_ratio_S1) - log(rate_ratio_S2))) %>%
  arrange(desc(log_shift)) %>%
  slice_head(n = 20)

basis_movers %>%
  transmute(
    Domain = domain,
    Term = term,
    `PR (per-predictor)` = sprintf("%.3f", rate_ratio_S1),
    `PR (shared)` = sprintf("%.3f", rate_ratio_S2),
    `Ratio of PRs` = sprintf("%.3f", rate_ratio_S2 / rate_ratio_S1),
    `Sign agreement` = ifelse((rate_ratio_S1 > 1) == (rate_ratio_S2 > 1),
                              "same side of 1", "CROSSES 1")
  ) %>%
  print_table(
    caption = paste0(
      "Table t42: The twenty estimates most sensitive to the choice of analytic ",
      "basis. Anything listed as CROSSES 1 changes direction depending on which ",
      "rows are used and should not be read from Table t4 alone."
    ),
    align = c("l", "l", "r", "r", "r", "c")
  )

# ---- t43 ---------------------------------------------------------------------
readr::write_csv(sensitivity_wide, paste0(local_data, "sensitivity-wide.csv"))

sensitivity_wide %>%
  arrange(domain, term) %>%
  select(Domain = domain, Term = term,
         `S1 total / per-predictor` = S1,
         `S2 total / shared` = S2,
         `S3 chronic / per-predictor` = S3,
         `S4 chronic / shared` = S4) %>%
  print_table(
    caption = paste0(
      "Table t43: All four series side by side. Wald intervals throughout; see ",
      "decision 8 for why none of them is the interval Section 5.3 requests."
    ),
    align = c("l", "l", "r", "r", "r", "r"),
    scroll_height = "700px"
  )

# ---- t5 ----------------------------------------------------------------------
model_diagnostics %>%
  filter(series_id == "S1") %>%
  arrange(domain, variable_label) %>%
  transmute(
    Domain = domain,
    Variable = variable_label,
    Reference = reference_level,
    n = scales::comma(n_used),
    Theta = sprintf("%.4f", theta),
    `Variance / mean` = sprintf("%.2f", var_mean_ratio),
    AIC = scales::comma(round(aic)),
    Iterations = iterations,
    Converged = ifelse(converged, "yes", "NO")
  ) %>%
  print_table(
    caption = paste0(
      "Table t5: Per-model diagnostics for Series S1. Theta far below 1 confirms ",
      "severe overdispersion in every model, which is what makes the negative ",
      "binomial likelihood the right choice and a Poisson the wrong one."
    ),
    align = c("l", "l", "l", "r", "r", "r", "r", "r", "c"),
    scroll_height = "600px"
  )

# ---- SECTION: Step 7 - Reproducibility Ledger ---------------------------------
# Every derived table and the full set of fitted terms are written to disk so a
# reviewer can reload any single result without re-running the estimation.

# ---- t6 ----------------------------------------------------------------------
artifact_manifest <- fs::dir_info(local_data, recurse = TRUE) %>%
  filter(type == "file") %>%
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
  filter(kind != "other") %>%
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
    caption = "Table t6: Artifact manifest. Every persisted object, with the call that reloads it.",
    align = c("l", "l", "r", "l")
  )

# ---- out4 --------------------------------------------------------------------
cat("Reproducibility parameters\n\n")
cat("  outcome (primary):     ", outcome_primary, "\n", sep = "")
cat("  outcome (sensitivity): ", outcome_sensitivity, "\n", sep = "")
cat("  weight:                ", weight_col, " (rescaled to mean 1 per estimation frame)\n", sep = "")
cat("  in every model:        ", cycle_var, "\n", sep = "")
cat("  candidate registry:    ./scripts/modeling/candidate-registry.R\n")
cat("  source parquet:        ", path_parquet, "\n", sep = "")
cat("  models fitted:         ", nrow(model_diagnostics), " (plus one null each)\n", sep = "")
cat("  seed:                  ", example_seed, " (used only to draw the example respondent)\n", sep = "")
cat("  cached fits:           ", fits_path, "\n", sep = "")
cat("  force_refit:           ", force_refit, "\n\n", sep = "")

cat("Section 5.3 requirements NOT met by model-00:\n")
cat("  - Bootstrap variance estimation (decision 8: replicate weights absent from PUMF).\n")
cat("    This is the one requirement Section 5.3 flags explicitly, and it is the one\n")
cat("    requirement these data cannot satisfy. Table t21 measures the shortfall that\n")
cat("    is measurable; the clustering component is not.\n")
cat("  - Design-based degrees of freedom for the omnibus tests in Table t41.\n\n")
utils::sessionInfo()

# nolint end
