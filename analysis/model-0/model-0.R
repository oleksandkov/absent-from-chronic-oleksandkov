# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# MODEL-0: LASSO variable-selection rehearsal on predisposing variables.
# Scope: Section 5.4 of stats_instructions_v3.md, demonstrated on one Andersen domain.
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
requireNamespace("Matrix", quietly = TRUE)
requireNamespace("knitr", quietly = TRUE)

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R")
base::source("./scripts/graphing/graph-presets.R")

# ---- declare-globals ---------------------------------------------------------
local_root <- "./analysis/model-0/"
local_data <- paste0(local_root, "data-local/")
prints_folder <- paste0(local_root, "prints/")
path_parquet <- "./data-private/derived/cchs-2-tables/cchs_analytic.parquet"

outcome_var <- "days_absent_chronic"
weight_col <- "wts_m_pooled"
cycle_var <- "cchs_cycle_f"
lasso_seed <- 42
lasso_folds <- 5

if (!fs::dir_exists(local_data)) { fs::dir_create(local_data) }
if (!fs::dir_exists(prints_folder)) { fs::dir_create(prints_folder) }

# Predisposing domain per stats_instructions_v3.md Section 2.2.
# `dhhgage` is deliberately excluded: it is the same construct as `age_group_3`
# at finer resolution, and the proposal specifies the 3-category recode.
#
# `dhhgl12` is also excluded, ratified 2026-08-01. It is the logical OR of
# `dhhgle5` and `dhhg611` in all 63,843 rows, so all three together span the same
# column space as `dhhgle5 * dhhg611`. This report exists to demonstrate how the
# penalty behaves, and a deterministically redundant column would demonstrate the
# wrong thing: the penalty would split one shared coefficient arbitrarily between
# the three. It is retained for descriptive and bivariate reporting in model-00.
# See `bivariate_only_vars` in scripts/modeling/candidate-registry.R.
#
# `home_ownership` was admitted 2026-08-01 after QC established that `DHH_OWN` is
# present in both cycles with 99.74% coverage; it satisfies the Section 2.2
# "homeownership" requirement that was previously believed to have no PUMF
# equivalent.
predisposing_specs <- tibble::tribble(
  ~variable, ~variable_label,
  "age_group_3", "Age group",
  "sex", "Sex",
  "marital_status", "Marital status",
  "household_size", "Household size",
  "dhhgle5", "Child aged 0-5 in household",
  "dhhg611", "Child aged 6-11 in household",
  "education", "Education",
  "immigration_status", "Immigration status",
  "visible_minority", "Visible minority",
  "home_ownership", "Home ownership",
  "living_arrangements", "Living arrangements"
)

predisposing_vars <- predisposing_specs$variable

# `cchs_cycle_f` is forced into every model (penalty.factor = 0) because the
# pooled design requires a cycle indicator regardless of selection outcome.
forced_vars <- cycle_var

lambda_colours <- c(
  "lambda.1se" = abcol[["magenta"]],
  "lambda.min" = abcol[["blue"]]
)

# Used by the stage-two forest plot to separate terms whose Wald interval clears
# the null from those whose does not. Not a significance test: see the caveat in
# the "Stage Two" section about what these intervals ignore.
interval_colours <- c(
  "Interval excludes 1" = abcol[["blue"]],
  "Interval includes 1" = "grey65"
)

# ---- declare-functions -------------------------------------------------------
# Render a data frame as styled HTML for Quarto, or plainly for console use.
print_table <- function(data, caption, align = NULL) {
  html <- data %>%
    knitr::kable(
      format = "html",
      caption = caption,
      escape = FALSE,
      align = align,
      row.names = FALSE
    ) %>%
    kableExtra::kable_styling(
      bootstrap_options = c("striped", "hover", "condensed"),
      full_width = FALSE
    ) %>%
    kableExtra::scroll_box(width = "100%") %>%
    as.character()
  cat(html)
  invisible(data)
}

# Convert 0/1 numeric indicators into labelled factors so that model.matrix
# produces one interpretable dummy column per indicator.
to_yes_no <- function(x) {
  factor(ifelse(x == 1, "Yes", "No"), levels = c("No", "Yes"))
}

# Map every design-matrix column back to the source variable that generated it.
# This is what makes the "how many variables did LASSO keep?" question answerable.
map_columns_to_variables <- function(model_frame, model_formula) {
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
    )
  )
}

# Strip the variable-name prefix from a design-matrix column to recover the
# level label. Vectorized, because `sub()` uses only the first pattern element.
strip_variable_prefix <- function(column, variable) {
  purrr::map2_chr(column, variable, ~ sub(paste0("^", .y), "", .x))
}

# Extract a tidy coefficient vector from a cv.glmnet fit at a named lambda.
extract_coefficients <- function(cv_fit, lambda_label) {
  coefficient_matrix <- stats::coef(cv_fit, s = lambda_label)
  tibble::tibble(
    column = rownames(coefficient_matrix),
    estimate = as.numeric(coefficient_matrix)
  ) %>%
    filter(column != "(Intercept)")
}

# ---- load-data ---------------------------------------------------------------
ds0 <- arrow::read_parquet(path_parquet)

# ---- tweak-data-0 ------------------------------------------------------------
# Build the model frame. Three transformations matter for LASSO:
#   1. Ordered factors become unordered, so model.matrix emits readable dummy
#      columns instead of polynomial contrasts (.L, .Q, .C).
#   2. Binary numeric indicators become No/Yes factors.
#   3. Complete-case restriction, because glmnet cannot accept a design matrix
#      with missing cells.
ds1 <- ds0 %>%
  select(
    all_of(c(outcome_var, weight_col, cycle_var, predisposing_vars))
  ) %>%
  mutate(across(where(is.ordered), ~ factor(., ordered = FALSE))) %>%
  mutate(across(any_of(c("dhhgle5", "dhhg611", "dhhgl12")), to_yes_no)) %>%
  mutate(across(where(is.character), factor))

n_before_complete_case <- nrow(ds1)

ds1 <- ds1 %>%
  tidyr::drop_na() %>%
  mutate(
    .respondent_id = dplyr::row_number(),
    weight_scaled = .data[[weight_col]] / mean(.data[[weight_col]])
  )

n_after_complete_case <- nrow(ds1)

model_formula <- stats::reformulate(c(forced_vars, predisposing_vars))
design <- map_columns_to_variables(ds1, model_formula)
x_matrix <- design$x
y_outcome <- ds1[[outcome_var]]
weight_vector <- ds1$weight_scaled
penalty_vector <- as.numeric(!design$map$variable %in% forced_vars)

variable_labels <- c(
  stats::setNames(predisposing_specs$variable_label, predisposing_specs$variable),
  stats::setNames("CCHS cycle", cycle_var)
)

# ---- inspect-data-0 ----------------------------------------------------------
cat("Rows before complete-case restriction: ", n_before_complete_case, "\n")
cat("Rows after complete-case restriction:  ", n_after_complete_case, "\n")
cat("Rows dropped: ", n_before_complete_case - n_after_complete_case,
    sprintf(" (%.2f%%)\n",
            100 * (n_before_complete_case - n_after_complete_case) / n_before_complete_case))
cat("Design matrix dimensions: ", nrow(x_matrix), " x ", ncol(x_matrix), "\n")

# ---- data-context-tables -----------------------------------------------------
# Single source table: the Ellis analytic parquet, one row per respondent.
# Variables drawn from it fall into four roles.
tibble::tibble(
  role = c("Outcome", "Survey weight", "Forced covariate", "Candidate predictors"),
  columns = c(
    outcome_var,
    weight_col,
    cycle_var,
    paste(predisposing_vars, collapse = ", ")
  ),
  rationale = c(
    "Sensitivity outcome of Section 4.1: workdays lost to chronic conditions",
    "Pooled master weight; rescaled to mean 1 for numerical stability",
    "Pooled design requires a cycle indicator in every specification",
    "Predisposing domain of the Andersen model, Section 2.2"
  )
) %>%
  print_table(
    caption = "Source table `cchs_analytic.parquet` and the role of each column",
    align = c("l", "l", "l")
  )

# ---- data-context-person -----------------------------------------------------
# One respondent who reported chronic absence days, shown across every column
# that enters the model.
set.seed(lasso_seed)
example_row <- ds1 %>%
  filter(.data[[outcome_var]] > 0) %>%
  slice_sample(n = 1)

example_row %>%
  select(-.respondent_id) %>%
  tidyr::pivot_longer(
    cols = everything(),
    names_to = "column",
    values_transform = as.character,
    values_to = "value"
  ) %>%
  print_table(
    caption = "Every modelled column for one respondent reporting chronic absence days",
    align = c("l", "l")
  )

# ---- data-context-distributions ----------------------------------------------
# Level counts for each candidate predictor, plus the dummy columns each yields.
design$map %>%
  count(variable, name = "design_columns") %>%
  left_join(
    ds1 %>%
      select(all_of(c(forced_vars, predisposing_vars))) %>%
      summarise(across(everything(), ~ length(levels(factor(.))))) %>%
      tidyr::pivot_longer(everything(), names_to = "variable", values_to = "levels"),
    by = "variable"
  ) %>%
  mutate(
    variable_label = variable_labels[variable],
    reference_level = purrr::map_chr(variable, ~ levels(factor(ds1[[.x]]))[1])
  ) %>%
  select(variable, variable_label, levels, design_columns, reference_level) %>%
  arrange(variable) %>%
  print_table(
    caption = "Candidate predictors: observed levels, dummy columns, and reference level",
    align = c("l", "l", "r", "r", "l")
  )

# ---- out1 --------------------------------------------------------------------
# Grain proof: one row per respondent, no duplicate identifiers.
cat("Unit of analysis: one row per CCHS respondent\n")
cat("Rows: ", nrow(ds1), "\n")
cat("Distinct respondent ids: ", dplyr::n_distinct(ds1$.respondent_id), "\n")
cat("Duplicate rows: ", sum(duplicated(ds1$.respondent_id)), "\n")

# ---- SECTION: The Problem LASSO Is Asked To Solve ----------------------------
# Before penalization, two facts frame the exercise: the outcome is severely
# zero-inflated and overdispersed, and the 12 candidate variables expand into a
# design matrix considerably wider than the variable count suggests.

# ---- out2 --------------------------------------------------------------------
outcome_values <- ds1[[outcome_var]]
outcome_mean <- stats::weighted.mean(outcome_values, weight_vector)
outcome_var_weighted <- sum(weight_vector * (outcome_values - outcome_mean)^2) /
  (sum(weight_vector) - 1)

cat("Outcome: ", outcome_var, "\n")
cat("Weighted mean:      ", sprintf("%.4f", outcome_mean), "\n")
cat("Weighted variance:  ", sprintf("%.4f", outcome_var_weighted), "\n")
cat("Variance / mean:    ", sprintf("%.2f", outcome_var_weighted / outcome_mean),
    "  (Poisson assumes 1.0)\n")
cat("Proportion of zeros:", sprintf("%.2f%%", 100 * mean(outcome_values == 0)), "\n")
cat("Maximum observed:   ", max(outcome_values), "\n")

# ---- t1 ----------------------------------------------------------------------
# The variable-to-column expansion. This table is the empirical answer to the
# ambiguity in Section 5.4: "16 variables" may mean 16 factors or 16 columns.
design$map %>%
  mutate(variable_label = variable_labels[variable]) %>%
  group_by(variable, variable_label) %>%
  summarise(
    design_columns = n(),
    columns = paste(strip_variable_prefix(column, variable), collapse = "; "),
    .groups = "drop"
  ) %>%
  arrange(desc(design_columns), variable) %>%
  select(Variable = variable_label, `Design columns` = design_columns,
         `Non-reference levels` = columns) %>%
  bind_rows(
    tibble::tibble(
      Variable = "TOTAL",
      `Design columns` = ncol(x_matrix),
      `Non-reference levels` = ""
    )
  ) %>%
  print_table(
    caption = paste0(
      "Table t1: Twelve candidate variables expand into ", ncol(x_matrix),
      " design-matrix columns"
    ),
    align = c("l", "r", "l")
  )

# ---- SECTION: LASSO Fitting and Lambda Selection -----------------------------
# Stage 1 of Section 5.4: an L1-penalized Poisson regression, with lambda chosen
# by 5-fold cross-validation.

# ---- g1-data-prep ------------------------------------------------------------
set.seed(lasso_seed)
lasso_path <- glmnet::glmnet(
  x = x_matrix,
  y = y_outcome,
  family = "poisson",
  alpha = 1,
  weights = weight_vector,
  penalty.factor = penalty_vector
)

set.seed(lasso_seed)
cv_fit <- glmnet::cv.glmnet(
  x = x_matrix,
  y = y_outcome,
  family = "poisson",
  alpha = 1,
  nfolds = lasso_folds,
  weights = weight_vector,
  penalty.factor = penalty_vector
)

lambda_1se <- cv_fit$lambda.1se
lambda_min <- cv_fit$lambda.min

path_long <- as.matrix(lasso_path$beta) %>%
  as.data.frame() %>%
  tibble::rownames_to_column("column") %>%
  tidyr::pivot_longer(-column, names_to = "step", values_to = "estimate") %>%
  mutate(lambda = lasso_path$lambda[as.integer(sub("^s", "", step)) + 1]) %>%
  left_join(design$map, by = "column") %>%
  mutate(variable_label = variable_labels[variable])

saveRDS(cv_fit, paste0(local_data, "cv_fit.rds"))

# ---- g1 ----------------------------------------------------------------------
g1_coefficient_path <- path_long %>%
  ggplot(aes(x = lambda, y = estimate, group = column, colour = variable_label)) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_vline(xintercept = lambda_1se, colour = lambda_colours[["lambda.1se"]],
             linetype = "dashed", linewidth = 0.5) +
  geom_vline(xintercept = lambda_min, colour = lambda_colours[["lambda.min"]],
             linetype = "dashed", linewidth = 0.5) +
  geom_line(linewidth = 0.5, alpha = 0.85) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.0001)) +
  annotation_logticks(sides = "b", outside = FALSE, colour = "grey70") +
  scale_colour_viridis_d(option = "turbo", end = 0.92) +
  labs(
    title = "Graph g1: How the Penalty Erases Coefficients",
    subtitle = paste0(
      "Reading right to left, the penalty relaxes and coefficients depart from zero.\n",
      "Dashed lines mark lambda.1se (magenta) and lambda.min (blue)."
    ),
    x = "Lambda (log scale, larger = heavier penalty)",
    y = "Penalized Poisson coefficient (log rate ratio)",
    colour = "Source variable",
    caption = "Cycle indicator is unpenalized and never shrinks to zero."
  ) +
  theme(legend.position = "right", legend.key.size = unit(0.4, "cm"))

print(g1_coefficient_path)
ggsave(
  paste0(prints_folder, "g1_coefficient_path.png"),
  g1_coefficient_path, width = 8.5, height = 5.5, dpi = 300
)

# ---- g2 ----------------------------------------------------------------------
g2_data <- tibble::tibble(
  lambda = cv_fit$lambda,
  cv_mean = cv_fit$cvm,
  cv_low = cv_fit$cvlo,
  cv_high = cv_fit$cvup,
  n_nonzero = cv_fit$nzero
)

g2_nonzero_at <- function(lambda_value) {
  g2_data$n_nonzero[which.min(abs(g2_data$lambda - lambda_value))]
}

label_columns_kept <- function(count) {
  sprintf("%d column%s kept", count, ifelse(count == 1, "", "s"))
}

g2_cv_curve <- g2_data %>%
  ggplot(aes(x = lambda, y = cv_mean)) +
  geom_ribbon(aes(ymin = cv_low, ymax = cv_high), fill = abcol[["grey"]], alpha = 0.25) +
  geom_line(colour = abcol[["grey"]], linewidth = 0.7) +
  geom_vline(xintercept = lambda_1se, colour = lambda_colours[["lambda.1se"]],
             linetype = "dashed", linewidth = 0.6) +
  geom_vline(xintercept = lambda_min, colour = lambda_colours[["lambda.min"]],
             linetype = "dashed", linewidth = 0.6) +
  annotate(
    "text", x = lambda_1se, y = max(g2_data$cv_high), hjust = 1.05, vjust = 1,
    label = sprintf("lambda.1se = %.5f\n%s", lambda_1se,
                    label_columns_kept(g2_nonzero_at(lambda_1se))),
    colour = lambda_colours[["lambda.1se"]], size = 3
  ) +
  annotate(
    "text", x = lambda_min, y = min(g2_data$cv_low), hjust = 1.05, vjust = 0,
    label = sprintf("lambda.min = %.5f\n%s", lambda_min,
                    label_columns_kept(g2_nonzero_at(lambda_min))),
    colour = lambda_colours[["lambda.min"]], size = 3
  ) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.0001)) +
  labs(
    title = "Graph g2: Cross-Validated Deviance Selects the Penalty",
    subtitle = paste0(
      lasso_folds, "-fold cross-validation. lambda.min minimizes deviance;\n",
      "lambda.1se is the largest penalty still within one standard error of it."
    ),
    x = "Lambda (log scale, larger = heavier penalty)",
    y = "Poisson deviance (mean +/- 1 SE across folds)"
  )

print(g2_cv_curve)
ggsave(
  paste0(prints_folder, "g2_cv_curve.png"),
  g2_cv_curve, width = 8.5, height = 5.5, dpi = 300
)

# ---- SECTION: What Each Lambda Retains ---------------------------------------
# The two penalties define the Model 1 / Model 3 contrast of Section 5.4,
# restricted here to the predisposing domain.

# ---- t2 ----------------------------------------------------------------------
selection_table <- extract_coefficients(cv_fit, "lambda.1se") %>%
  rename(estimate_1se = estimate) %>%
  left_join(
    extract_coefficients(cv_fit, "lambda.min") %>% rename(estimate_min = estimate),
    by = "column"
  ) %>%
  left_join(design$map, by = "column") %>%
  mutate(
    variable_label = variable_labels[variable],
    level = strip_variable_prefix(column, variable),
    kept_1se = estimate_1se != 0,
    kept_min = estimate_min != 0
  )

selection_summary <- selection_table %>%
  group_by(Variable = variable_label) %>%
  summarise(
    `Columns` = n(),
    `Kept at lambda.1se` = sum(kept_1se),
    `Kept at lambda.min` = sum(kept_min),
    .groups = "drop"
  ) %>%
  arrange(desc(`Kept at lambda.min`), Variable)

n_col_1se <- sum(selection_table$kept_1se)
n_col_min <- sum(selection_table$kept_min)
n_var_1se <- dplyr::n_distinct(selection_table$variable[selection_table$kept_1se])
n_var_min <- dplyr::n_distinct(selection_table$variable[selection_table$kept_min])

selection_summary %>%
  bind_rows(
    tibble::tibble(
      Variable = "TOTAL (columns)",
      Columns = nrow(selection_table),
      `Kept at lambda.1se` = n_col_1se,
      `Kept at lambda.min` = n_col_min
    )
  ) %>%
  print_table(
    caption = paste0(
      "Table t2: Retention by variable. At lambda.1se, ", n_col_1se, " of ",
      nrow(selection_table), " columns survive (", n_var_1se,
      " source variables). At lambda.min, ", n_col_min, " columns survive (",
      n_var_min, " source variables)."
    ),
    align = c("l", "r", "r", "r")
  )

# ---- g3 ----------------------------------------------------------------------
g3_data <- selection_table %>%
  filter(kept_min) %>%
  mutate(
    term_label = paste0(variable_label, ": ", level),
    rate_ratio_1se = exp(estimate_1se),
    rate_ratio_min = exp(estimate_min)
  ) %>%
  select(term_label, variable_label, rate_ratio_1se, rate_ratio_min) %>%
  tidyr::pivot_longer(
    c(rate_ratio_1se, rate_ratio_min),
    names_to = "penalty", values_to = "rate_ratio"
  ) %>%
  mutate(
    penalty = recode(penalty,
                     rate_ratio_1se = "lambda.1se",
                     rate_ratio_min = "lambda.min"),
    term_label = forcats::fct_reorder(term_label, rate_ratio, .fun = max)
  )

g3_shrinkage <- g3_data %>%
  ggplot(aes(x = rate_ratio, y = term_label, colour = penalty)) +
  geom_vline(xintercept = 1, colour = "grey60", linewidth = 0.4) +
  geom_line(aes(group = term_label), colour = "grey75", linewidth = 0.4) +
  geom_point(size = 2.2, alpha = 0.9) +
  scale_colour_manual(values = lambda_colours) +
  labs(
    title = "Graph g3: Shrinkage Made Visible",
    subtitle = paste0(
      "Every column retained at lambda.min, shown as a rate ratio under both penalties.\n",
      "Points collapsed onto 1.0 were eliminated by the heavier penalty."
    ),
    x = "Rate ratio, exp(penalized coefficient)",
    y = NULL,
    colour = "Penalty"
  ) +
  theme(legend.position = "top")

print(g3_shrinkage)
ggsave(
  paste0(prints_folder, "g3_shrinkage.png"),
  g3_shrinkage, width = 8.5, height = 7.5, dpi = 300
)

# ---- SECTION: Stage Two, Handing Selection To Negative Binomial --------------
# Section 5.4 selects with Poisson and estimates with negative binomial. A
# variable is carried forward if ANY of its dummy columns survived the penalty.
# Because lambda.1se retained no predisposing variable at all, the handoff is
# demonstrated on the lambda.min set, which is the Model 3 analogue.
#
# CONDITIONALITY WARNING, applying to everything below.
# The penalty does not measure whether a variable is associated with the
# outcome. It measures whether a variable earns its place AGAINST THE
# COMPETITORS IT WAS SHOWN. Every competitor here is drawn from the
# predisposing domain alone: chronic conditions, perceived health, activity
# limitations, income, occupation and work schedule were all withheld. Those
# withheld variables are, on substantive grounds, nearer causes of work absence
# than marital status or household composition. Part of what the surviving
# terms below are measuring is therefore borrowed - they proxy for omitted
# causes with which they are correlated. Offer the omitted causes, as Model 1
# does, and these terms can be expected to weaken or drop out entirely.
# Read this section as a statement about what predisposing characteristics do
# IN THE ABSENCE OF ANYTHING BETTER, not as an estimate of their effect.

# ---- t3 ----------------------------------------------------------------------
retained_variables_1se <- selection_table %>%
  filter(kept_1se) %>%
  pull(variable) %>%
  unique()

retained_variables_min <- selection_table %>%
  filter(kept_min) %>%
  pull(variable) %>%
  unique()

nb_variables <- union(forced_vars, setdiff(retained_variables_min, forced_vars))
nb_formula <- stats::reformulate(nb_variables, response = outcome_var)

nb_fit <- suppressWarnings(
  MASS::glm.nb(nb_formula, data = ds1, weights = weight_scaled)
)

nb_summary <- summary(nb_fit)$coefficients %>%
  as.data.frame() %>%
  tibble::rownames_to_column("column") %>%
  rename(estimate = Estimate, std_error = `Std. Error`, p_value = `Pr(>|z|)`) %>%
  filter(column != "(Intercept)") %>%
  left_join(design$map, by = "column") %>%
  left_join(selection_table %>% select(column, estimate_min, kept_min), by = "column") %>%
  mutate(
    variable_label = variable_labels[variable],
    level = strip_variable_prefix(column, variable),
    penalised_rr = exp(estimate_min),
    rate_ratio = exp(estimate),
    ci_low = exp(estimate - 1.96 * std_error),
    ci_high = exp(estimate + 1.96 * std_error),
    interval_excludes_one = ci_low > 1 | ci_high < 1
  )

# Levels that the penalty zeroed but that re-enter stage two anyway, because
# their parent variable had at least one surviving level (decision: carry the
# whole variable, not the surviving columns).
n_readmitted <- sum(!nb_summary$kept_min)

nb_summary %>%
  transmute(
    Variable = variable_label,
    Level = level,
    `Penalised RR` = ifelse(kept_min, sprintf("%.3f", penalised_rr),
                            sprintf("%.3f \u2020", penalised_rr)),
    `Refit RR` = sprintf("%.3f", rate_ratio),
    `95% CI` = sprintf("%.3f - %.3f", ci_low, ci_high),
    `p-value` = ifelse(p_value < 0.001, "<0.001", sprintf("%.3f", p_value))
  ) %>%
  print_table(
    caption = paste0(
      "Table t3: The two stages side by side, on the ", length(nb_variables),
      " variables retained at lambda.min. 'Penalised RR' is the shrunken LASSO ",
      "estimate; 'Refit RR' is the unpenalised negative binomial estimate. ",
      "A dagger marks the ", n_readmitted, " levels the penalty had zeroed that ",
      "re-enter because a sibling level survived. Wald intervals only, not ",
      "bootstrap, and they ignore the selection step entirely."
    ),
    align = c("l", "l", "r", "r", "r", "r")
  )

# ---- g4 ----------------------------------------------------------------------
# The interpretable face of the solution: what the retained set actually says
# about absenteeism, with uncertainty attached. Subject to the conditionality
# warning at the head of this section.
g4_data <- nb_summary %>%
  mutate(
    term = paste0(variable_label, ": ", level),
    term = forcats::fct_reorder(term, rate_ratio),
    evidence = ifelse(interval_excludes_one,
                      "Interval excludes 1", "Interval includes 1")
  )

g4_forest <- g4_data %>%
  ggplot(aes(x = rate_ratio, y = term, colour = evidence)) +
  geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.4) +
  geom_linerange(aes(xmin = ci_low, xmax = ci_high), linewidth = 0.5) +
  geom_point(size = 2.1) +
  scale_colour_manual(values = interval_colours) +
  scale_x_log10() +
  labs(
    title = "Graph g4: What the Retained Set Says, With Uncertainty Attached",
    subtitle = paste0(
      "Unpenalised negative binomial rate ratios for every term carried into stage two.\n",
      "Valid only within this predictor universe: the predisposing domain alone. ",
      "Chronic\nconditions, perceived health and activity limitations were withheld, ",
      "and these terms\npartly proxy for them. Wald intervals, and they ignore the ",
      "selection step that\nproduced the term list."
    ),
    x = "Rate ratio (log scale)", y = NULL, colour = NULL
  ) +
  theme(legend.position = "top")

print(g4_forest)
ggsave(
  paste0(prints_folder, "g4_forest.png"),
  g4_forest, width = 8.5, height = 8, dpi = 300
)

# ---- out3 --------------------------------------------------------------------
# Why the second stage is needed at all: the Poisson variance assumption fails
# badly, and the negative binomial dispersion parameter measures by how much.
poisson_fit <- stats::glm(
  nb_formula, data = ds1, family = stats::poisson(), weights = weight_scaled
)

cat("Predisposing variables retained at lambda.1se: ",
    length(setdiff(retained_variables_1se, forced_vars)), "\n")
cat("Predisposing variables retained at lambda.min: ",
    length(setdiff(retained_variables_min, forced_vars)), "\n")
cat("Variables carried into stage 2: ", length(nb_variables), "\n")
cat("  ", paste(nb_variables, collapse = ", "), "\n\n")
cat("Poisson residual deviance / df: ",
    sprintf("%.2f", poisson_fit$deviance / poisson_fit$df.residual),
    "  (1.0 indicates no overdispersion)\n")
cat("Negative binomial theta:        ", sprintf("%.4f", nb_fit$theta),
    " (SE ", sprintf("%.4f", nb_fit$SE.theta), ")\n")
cat("Implied variance at the mean:   ",
    sprintf("%.3f", mean(stats::fitted(nb_fit)) *
              (1 + mean(stats::fitted(nb_fit)) / nb_fit$theta)),
    " vs Poisson ", sprintf("%.3f", mean(stats::fitted(nb_fit))), "\n\n")
cat("AIC, Poisson:           ", sprintf("%.0f", stats::AIC(poisson_fit)), "\n")
cat("AIC, negative binomial: ", sprintf("%.0f", stats::AIC(nb_fit)), "\n")

# ---- out4 --------------------------------------------------------------------
# Is the lambda.1se collapse a property of the data or an artifact of the survey
# weights? Survey weights range across three orders of magnitude, which inflates
# the cross-validation standard error and therefore pushes lambda.1se upward.
# Re-running the identical cross-validation unweighted isolates that effect.
set.seed(lasso_seed)
cv_unweighted <- glmnet::cv.glmnet(
  x = x_matrix,
  y = y_outcome,
  family = "poisson",
  alpha = 1,
  nfolds = lasso_folds,
  penalty.factor = penalty_vector
)

count_nonzero <- function(fit, lambda_label) {
  sum(as.numeric(stats::coef(fit, s = lambda_label))[-1] != 0)
}

cat("Survey weight range: ", sprintf("%.2f to %.2f", min(ds1[[weight_col]]),
                                     max(ds1[[weight_col]])), "\n")
cat("Weight coefficient of variation: ",
    sprintf("%.2f", stats::sd(weight_vector) / mean(weight_vector)), "\n")
cat("Kish effective sample size: ",
    sprintf("%.0f of %d",
            sum(weight_vector)^2 / sum(weight_vector^2), nrow(ds1)), "\n\n")
cat("Columns retained, weighted CV:   lambda.1se = ",
    count_nonzero(cv_fit, "lambda.1se"), ", lambda.min = ",
    count_nonzero(cv_fit, "lambda.min"), "\n")
cat("Columns retained, unweighted CV: lambda.1se = ",
    count_nonzero(cv_unweighted, "lambda.1se"), ", lambda.min = ",
    count_nonzero(cv_unweighted, "lambda.min"), "\n")

# nolint end
