# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# EDA-81: Interpretation layer for model-00 and model-1.
# This script FITS NOTHING. It reads artifacts those two reports persisted and
# re-presents them under alignment constraints they did not impose.
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
requireNamespace("readr", quietly = TRUE)
requireNamespace("knitr", quietly = TRUE)
requireNamespace("cowplot", quietly = TRUE)

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R")
base::source("./scripts/graphing/graph-presets.R")

# The same registry model-00 and model-1 source. Sourcing it, rather than
# restating the labels here, is what keeps this report from drifting away from
# the two it interprets.
base::source("./scripts/modeling/candidate-registry.R")

# ---- declare-globals ---------------------------------------------------------
local_root    <- "./analysis/eda-81/"
local_data    <- paste0(local_root, "data-local/")
prints_folder <- paste0(local_root, "prints/")

# Upstream artifacts. Every one of these is a file another report wrote.
path_table_two      <- "./analysis/model-00/data-local/table-two.csv"
path_selection_long <- "./analysis/model-1/data-local/selection-long.csv"
path_nb_coef        <- "./analysis/model-1/data-local/nb-coefficients.csv"
path_cv_exclude     <- "./analysis/model-1/data-local/fits/cv_exclude_perceived.rds"
path_cv_include     <- "./analysis/model-1/data-local/fits/cv_include_perceived.rds"

for (folder in c(local_data, prints_folder)) {
  if (!fs::dir_exists(folder)) { fs::dir_create(folder, recurse = TRUE) }
}

cycle_var   <- "cchs_cycle_f"
forced_vars <- cycle_var

# The specification whose adjusted estimates the right panel of g1 carries.
# Named once so the graph title, the table caption, and the prose cannot drift.
primary_spec        <- "model_1"
primary_spec_label  <- "Model 1"
primary_spec_desc   <- "perceived health excluded, lambda.1se"

# Local decision 2. Set to "all" to give every variable a reference row, or
# "none" to suppress them entirely.
reference_row_rule <- "multilevel_only"

# Local decision 5. Four states, because collapsing them would state something
# false about three of the four.
selection_states <- c("forced (unpenalised)", "retained", "eliminated", "not offered")

selection_colours <- c(
  "forced (unpenalised)" = abcol[["blue"]],
  "retained"             = abcol[["green"]],
  "eliminated"           = "grey88",
  "not offered"          = "grey62"
)

domain_levels <- c("Exposure", "Predisposing", "Facilitating", "Needs", "Survey design")

domain_colours <- c(
  "Exposure"      = abcol[["magenta"]],
  "Predisposing"  = abcol[["blue"]],
  "Facilitating"  = abcol[["green"]],
  "Needs"         = abcol[["brown"]],
  "Survey design" = abcol[["grey"]]
)

variable_labels <- c(
  variable_labels_registry,
  stats::setNames("CCHS cycle", cycle_var)
)
variable_domains <- c(
  variable_domains_registry,
  stats::setNames("Survey design", cycle_var)
)

model_labels_all <- c("Model 1", "Model 2", "Model 3", "Model 4")

# Restated from model-1, not re-derived. Used for t1 and for the g0 captions.
spec_grid <- tibble::tribble(
  ~model_label, ~perceived_health, ~lambda_rule, ~fit_id,   ~role,
  "Model 1",    "excluded",        "lambda.1se", "exclude", "Primary",
  "Model 2",    "included",        "lambda.1se", "include", "Secondary",
  "Model 3",    "excluded",        "lambda.min", "exclude", "Sensitivity",
  "Model 4",    "included",        "lambda.min", "include", "Sensitivity"
)

fit_labels <- c(
  "exclude" = "Perceived health excluded (Models 1 and 3)",
  "include" = "Perceived health included (Models 2 and 4)"
)

# Relative widths of the three g1 panels. The left panel carries the row labels,
# so it is given room for them; the middle panel is deliberately starved.
g1_panel_widths <- c(left = 1.00, middle = 0.20, right = 0.52)

# ---- declare-functions -------------------------------------------------------
# Render a data frame as styled HTML for Quarto, or plainly for console use.
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

# Pull the cross-validation curve out of a saved cv.glmnet object. `cvsd` is the
# across-fold standard error of the mean; `cvup` and `cvlo` are cvm +/- cvsd.
cv_curve <- function(cv_object, fit_id) {
  tibble::tibble(
    fit_id  = fit_id,
    lambda  = cv_object$lambda,
    cv_mean = cv_object$cvm,
    cv_se   = cv_object$cvsd,
    cv_low  = cv_object$cvlo,
    cv_high = cv_object$cvup,
    n_nonzero = as.integer(cv_object$nzero)
  ) %>%
    mutate(fit_label = unname(fit_labels[fit_id]))
}

# The two lambda marks, plus the horizontal threshold that defines the 1-SE rule:
# deviance at the minimum, raised by one standard error.
cv_marks <- function(cv_object, fit_id) {
  index_min <- which.min(cv_object$cvm)
  threshold <- cv_object$cvm[index_min] + cv_object$cvsd[index_min]
  index_1se <- which(cv_object$lambda == cv_object$lambda.1se)[1]

  tibble::tibble(
    fit_id      = fit_id,
    lambda_rule = c("lambda.min", "lambda.1se"),
    lambda      = c(cv_object$lambda.min, cv_object$lambda.1se),
    cv_mean     = cv_object$cvm[c(index_min, index_1se)],
    cv_se       = cv_object$cvsd[c(index_min, index_1se)],
    n_nonzero   = as.integer(cv_object$nzero[c(index_min, index_1se)]),
    threshold   = threshold
  ) %>%
    mutate(fit_label = unname(fit_labels[fit_id]))
}

# The unit deviance of a single Poisson observation. This is the quantity the
# cross-validation curve averages. Defined here as mathematics, not fitted.
poisson_unit_deviance <- function(y, mu) {
  ifelse(y == 0, 2 * mu, 2 * (y * log(y / pmax(mu, 1e-8)) - (y - mu)))
}

# cowplot changed its legend accessor across versions. Try the current name,
# fall back to the retired one, and return NULL rather than fail.
extract_legend <- function(plot) {
  out <- tryCatch(cowplot::get_plot_component(plot, "guide-box-bottom"),
                  error = function(e) NULL)
  if (is.null(out)) {
    out <- tryCatch(cowplot::get_legend(plot), error = function(e) NULL)
  }
  out
}

# ---- load-data ---------------------------------------------------------------
table_two      <- readr::read_csv(path_table_two, show_col_types = FALSE)
selection_long <- readr::read_csv(path_selection_long, show_col_types = FALSE)
nb_coefficients <- readr::read_csv(path_nb_coef, show_col_types = FALSE)

cv_fits <- list(
  exclude = readRDS(path_cv_exclude),
  include = readRDS(path_cv_include)
)

# ---- tweak-data-0 ------------------------------------------------------------
# Nothing is recomputed. The only work here is type coercion and the addition of
# labels and domains from the shared registry.
table_two <- table_two %>%
  mutate(
    level_index = as.integer(level_index),
    domain = factor(unname(variable_domains[variable]), levels = domain_levels)
  )

selection_long <- selection_long %>%
  mutate(
    model_label = factor(model_label, levels = model_labels_all),
    domain = factor(unname(variable_domains[variable]), levels = domain_levels)
  )

nb_coefficients <- nb_coefficients %>%
  mutate(
    model_label = factor(model_label, levels = model_labels_all),
    domain = factor(unname(variable_domains[variable]), levels = domain_levels)
  )

cv_curves <- purrr::imap_dfr(cv_fits, ~ cv_curve(.x, .y))
cv_lambda_marks <- purrr::imap_dfr(cv_fits, ~ cv_marks(.x, .y))

# The fit that Models 1 and 3 are drawn from. The g0 family works on this one
# only; showing both panels is model-1's Graph g2, which this family unpacks.
cv_primary_curve <- cv_curves %>% filter(fit_id == "exclude")
cv_primary_marks <- cv_lambda_marks %>% filter(fit_id == "exclude")
cv_primary_threshold <- cv_primary_marks$threshold[1]

# ---- inspect-data-0 ----------------------------------------------------------
cat("Upstream artifacts read by eda-81 (nothing was re-fitted):\n\n")
tibble::tibble(
  artifact = c("table-two.csv", "selection-long.csv", "nb-coefficients.csv",
               "cv_exclude_perceived.rds", "cv_include_perceived.rds"),
  rows = c(nrow(table_two), nrow(selection_long), nrow(nb_coefficients),
           length(cv_fits$exclude$lambda), length(cv_fits$include$lambda)),
  written_by = c("model-00", "model-1", "model-1", "model-1", "model-1")
) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

# ---- data-context-tables -----------------------------------------------------
tibble::tribble(
  ~Artifact, ~Grain, ~`Written by`, ~`Used for`,
  "table-two.csv", "One row per non-reference level of one predictor", "model-00 chunk t4",
  "Left panel of g1, and the bivariate column of t3 and t4",
  "selection-long.csv", "One row per design column per specification", "model-1 chunk t5",
  "Middle panel of g1, and t2",
  "nb-coefficients.csv", "One row per model term per specification", "model-1 chunk t6",
  "Right panel of g1, and t3",
  "cv_*_perceived.rds", "One cv.glmnet object per predictor set", "model-1 chunk g2-data-prep",
  "The whole g0 family, and t2"
) %>%
  print_table(
    caption = paste0(
      "Data context: the five upstream artifacts eda-81 reads. No analytic ",
      "parquet is opened and no model is estimated in this report."
    ),
    align = c("l", "l", "l", "l")
  )

# ---- data-context-person -----------------------------------------------------
# The unit of analysis in this report is not a respondent but a model term. One
# worked term, shown across all three of its appearances.
example_variable <- "cc_arthritis"

dplyr::bind_rows(
  table_two %>%
    filter(variable == example_variable) %>%
    transmute(source = "model-00 bivariate (S1)", level,
              estimate = sprintf("RR %.3f (%.3f - %.3f)", rate_ratio, ci_low, ci_high)),
  selection_long %>%
    filter(variable == example_variable) %>%
    transmute(source = paste0("model-1 penalised, ", model_label), level,
              estimate = sprintf("beta %.4f, %s", estimate,
                                 ifelse(retained, "retained", "eliminated"))),
  nb_coefficients %>%
    filter(variable == example_variable, spec_id == primary_spec) %>%
    transmute(source = paste0("model-1 negative binomial, ", model_label), level,
              estimate = sprintf("RR %.3f (%.3f - %.3f)", rate_ratio, ci_low, ci_high))
) %>%
  print_table(
    caption = paste0(
      "Data context: one worked term, ", variable_labels[[example_variable]],
      ", traced through every artifact eda-81 joins. The three panels of Graph ",
      "g1 show the first, the middle group, and the last of these rows."
    ),
    align = c("l", "l", "l")
  )

# ---- data-context-distributions ----------------------------------------------
tibble::tibble(
  quantity = c(
    "Variables with a bivariate estimate (model-00 S1)",
    "Non-reference levels with a bivariate estimate",
    "Variables offered to the penalty in Models 1 and 3",
    "Variables offered to the penalty in Models 2 and 4",
    "Variables withheld from the penalty but reported bivariately",
    "Variables retained by the primary model"
  ),
  n = c(
    dplyr::n_distinct(table_two$variable),
    nrow(table_two),
    dplyr::n_distinct(selection_long$variable[selection_long$model_label == "Model 1"]),
    dplyr::n_distinct(selection_long$variable[selection_long$model_label == "Model 2"]),
    length(bivariate_only_vars),
    dplyr::n_distinct(nb_coefficients$variable[nb_coefficients$spec_id == primary_spec])
  )
) %>%
  print_table(
    caption = paste0(
      "Data context: the counts that determine the height of Graph g1 and the ",
      "number of filled cells in its right panel."
    ),
    align = c("l", "r")
  )


# ---- SECTION: Step 1 - The Two Axes ------------------------------------------
# Section 5.4 asks for four models. They are not four independent analyses; they
# are two binary choices crossed.

# ---- t1 ----------------------------------------------------------------------
spec_grid %>%
  transmute(
    Model = model_label,
    Role = role,
    `Predictor set` = ifelse(
      perceived_health == "excluded",
      "45 candidates: the 3 self-perceived measures withheld",
      "48 candidates: the 3 self-perceived measures offered"
    ),
    `Penalty rule` = lambda_rule,
    `What the rule does` = ifelse(
      lambda_rule == "lambda.1se",
      "Takes the smallest model whose error is statistically indistinguishable from the best",
      "Takes the model with the lowest cross-validated error, whatever its size"
    ),
    `Cross-validated fit used` = unname(fit_labels[fit_id])
  ) %>%
  print_table(
    caption = paste0(
      "Table t1: The four specifications are one 2 x 2. The rows differ in two ",
      "binary choices and nothing else. Note the last column: Models 1 and 3 are ",
      "two readings of a single cross-validated fit, as are Models 2 and 4. The ",
      "predictor set determines the fit; the penalty rule determines which model ",
      "is drawn from it."
    ),
    align = c("l", "l", "l", "l", "l", "l"),
    scroll_height = NULL
  )

# ---- t2 ----------------------------------------------------------------------
retained_by_model <- selection_long %>%
  group_by(model_label) %>%
  summarise(
    columns_offered  = dplyr::n(),
    columns_retained = sum(retained),
    variables_retained = dplyr::n_distinct(variable[retained]),
    .groups = "drop"
  )

rule_ledger <- cv_lambda_marks %>%
  left_join(spec_grid, by = c("fit_id", "lambda_rule")) %>%
  left_join(retained_by_model, by = "model_label") %>%
  mutate(
    deviance_penalty = cv_mean - min(cv_mean[lambda_rule == "lambda.min"]),
    .by = fit_id
  )

readr::write_csv(rule_ledger, paste0(local_data, "rule-ledger.csv"))

rule_ledger %>%
  arrange(model_label) %>%
  transmute(
    Model = model_label,
    `Predictor set` = ifelse(perceived_health == "excluded", "without perceived health",
                             "with perceived health"),
    Rule = lambda_rule,
    Lambda = sprintf("%.5f", lambda),
    `CV deviance` = sprintf("%.4f", cv_mean),
    `One SE` = sprintf("%.4f", cv_se),
    `Deviance above the minimum` = sprintf("%+.4f", deviance_penalty),
    `Design columns kept` = columns_retained,
    `Variables kept` = variables_retained
  ) %>%
  print_table(
    caption = paste0(
      "Table t2: what each rule cost and what it bought. Read the last two ",
      "columns against the second-to-last. Within a predictor set, lambda.1se ",
      "accepts a measurably worse cross-validated deviance - but by construction ",
      "no worse than one standard error - and is paid for that concession in ",
      "variables it does not have to carry."
    ),
    align = c("l", "l", "l", "r", "r", "r", "r", "r", "r"),
    scroll_height = NULL
  )


# ---- SECTION: Step 2 - The g0 Family, Reading the Penalty ---------------------
# What the cross-validation curve is, what its band means, and how the two rules
# read a lambda off it. All four graphs use the saved cv.glmnet object for the
# predictor set without perceived health, which is the fit Models 1 and 3 share.

# ---- g0 ----------------------------------------------------------------------
g0_cv_annotated <- cv_primary_curve %>%
  ggplot(aes(x = lambda, y = cv_mean)) +
  geom_hline(yintercept = cv_primary_threshold,
             colour = abcol[["magenta"]], linetype = "dotted", linewidth = 0.5) +
  geom_ribbon(aes(ymin = cv_low, ymax = cv_high),
              fill = abcol[["grey"]], alpha = 0.20) +
  geom_line(colour = abcol[["grey"]], linewidth = 0.8) +
  geom_vline(data = cv_primary_marks,
             aes(xintercept = lambda, colour = lambda_rule),
             linetype = "dashed", linewidth = 0.6) +
  geom_point(data = cv_primary_marks,
             aes(x = lambda, y = cv_mean, colour = lambda_rule), size = 2.6) +
  geom_segment(
    data = cv_primary_marks %>%
      tidyr::pivot_wider(id_cols = fit_id, names_from = lambda_rule,
                         values_from = lambda),
    aes(x = lambda.min, xend = lambda.1se,
        y = cv_primary_threshold, yend = cv_primary_threshold),
    inherit.aes = FALSE,
    colour = abcol[["magenta"]], linewidth = 0.7,
    arrow = grid::arrow(length = grid::unit(0.16, "cm"), ends = "both")
  ) +
  annotate(
    "label", x = cv_primary_marks$lambda[cv_primary_marks$lambda_rule == "lambda.min"],
    y = cv_primary_threshold, hjust = -0.06, vjust = -0.5, size = 3, label.size = 0,
    fill = "white",
    label = "the 1-SE rule is read horizontally, right along this line"
  ) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.0001)) +
  scale_colour_manual(values = c("lambda.min" = abcol[["blue"]],
                                 "lambda.1se" = abcol[["magenta"]])) +
  labs(
    title = "Graph g0: Reading the Cross-Validation Curve",
    subtitle = paste0(
      "Predictor set without perceived health, the fit Models 1 and 3 are drawn from.\n",
      "Grey band: the mean plus and minus one standard error across the 5 folds.\n",
      "Dotted line: the deviance at the minimum, raised by one standard error. ",
      "lambda.1se is the LARGEST\npenalty whose curve still sits at or below that line - ",
      "the furthest right one can walk without\nleaving the band of the best model."
    ),
    x = "Lambda, the penalty (log scale). Larger means more shrinkage.",
    y = "5-fold cross-validated Poisson deviance",
    colour = "Penalty rule"
  ) +
  theme(legend.position = "top", panel.grid.minor = element_blank())

print(g0_cv_annotated)
ggsave(paste0(prints_folder, "g0_cv_annotated.png"),
       g0_cv_annotated, width = 11, height = 6.5, dpi = 300)

# ---- g01 ---------------------------------------------------------------------
# The same x axis, twice. The upper panel is what the rule optimises; the lower
# panel is what it costs. `n_nonzero` counts design columns, not variables.
g01_top <- cv_primary_curve %>%
  ggplot(aes(x = lambda, y = cv_mean)) +
  geom_hline(yintercept = cv_primary_threshold,
             colour = abcol[["magenta"]], linetype = "dotted", linewidth = 0.5) +
  geom_ribbon(aes(ymin = cv_low, ymax = cv_high),
              fill = abcol[["grey"]], alpha = 0.20) +
  geom_line(colour = abcol[["grey"]], linewidth = 0.8) +
  geom_vline(data = cv_primary_marks,
             aes(xintercept = lambda, colour = lambda_rule),
             linetype = "dashed", linewidth = 0.6) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.0001)) +
  scale_colour_manual(values = c("lambda.min" = abcol[["blue"]],
                                 "lambda.1se" = abcol[["magenta"]])) +
  labs(x = NULL, y = "CV Poisson deviance", colour = "Penalty rule") +
  theme(legend.position = "top", axis.text.x = element_blank(),
        panel.grid.minor = element_blank())

g01_bottom <- cv_primary_curve %>%
  ggplot(aes(x = lambda, y = n_nonzero)) +
  geom_step(colour = abcol[["grey"]], linewidth = 0.8) +
  geom_vline(data = cv_primary_marks,
             aes(xintercept = lambda, colour = lambda_rule),
             linetype = "dashed", linewidth = 0.6) +
  geom_point(data = cv_primary_marks,
             aes(x = lambda, y = n_nonzero, colour = lambda_rule), size = 2.6) +
  geom_text(data = cv_primary_marks,
            aes(x = lambda, y = n_nonzero, colour = lambda_rule,
                label = paste0(n_nonzero, " columns")),
            hjust = -0.12, vjust = -0.6, size = 3, show.legend = FALSE) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.0001)) +
  scale_colour_manual(values = c("lambda.min" = abcol[["blue"]],
                                 "lambda.1se" = abcol[["magenta"]]),
                      guide = "none") +
  labs(x = "Lambda, the penalty (log scale)",
       y = "Design columns with a\nnon-zero coefficient") +
  theme(panel.grid.minor = element_blank())

g01_price_of_the_rule <- cowplot::plot_grid(
  cowplot::ggdraw() +
    cowplot::draw_label(
      "Graph g01: The Same Curve, With the Price in Variables",
      fontface = "bold", size = 12, hjust = 0, x = 0.01
    ) +
    cowplot::draw_label(
      paste0(
        "Both panels share the lambda axis. Walking right from lambda.min to ",
        "lambda.1se buys a smaller model; the upper panel shows what that ",
        "purchase costs in fit."
      ),
      size = 9, hjust = 0, x = 0.01, y = 0.18
    ),
  g01_top, g01_bottom,
  ncol = 1, align = "v", axis = "lr", rel_heights = c(0.16, 0.52, 0.32)
)

print(g01_price_of_the_rule)
ggsave(paste0(prints_folder, "g01_price_of_the_rule.png"),
       g01_price_of_the_rule, width = 11, height = 7.5, dpi = 300)

# ---- g02 ---------------------------------------------------------------------
# What the vertical axis of g0 is made of. This chunk plots a function, not a
# fit: the deviance contributed by one respondent whose true count is y when the
# model predicts a mean of mu.
deviance_surface <- tidyr::expand_grid(
  y = c(0, 1, 3, 10, 30),
  mu = 10^seq(log10(0.02), log10(60), length.out = 400)
) %>%
  mutate(
    unit_deviance = poisson_unit_deviance(y, mu),
    y_label = factor(paste0("observed y = ", y),
                     levels = paste0("observed y = ", c(0, 1, 3, 10, 30)))
  )

deviance_minima <- deviance_surface %>%
  distinct(y, y_label) %>%
  filter(y > 0) %>%
  mutate(mu = y, unit_deviance = 0)

g02_deviance_meaning <- deviance_surface %>%
  ggplot(aes(x = mu, y = unit_deviance, colour = y_label)) +
  geom_line(linewidth = 0.8) +
  geom_point(data = deviance_minima, size = 2.2, show.legend = FALSE) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.1)) +
  coord_cartesian(ylim = c(0, 45)) +
  scale_colour_manual(values = unname(abcol[c("grey", "blue", "green", "brown", "magenta")])) +
  labs(
    title = "Graph g02: What Poisson Deviance Counts",
    subtitle = paste0(
      "One respondent's contribution, 2 * (y * log(y / mu) - (y - mu)), as the model's ",
      "predicted mean mu varies.\nThe contribution is zero only where the prediction ",
      "equals the observation (dots), and it rises on both\nsides - which is why the ",
      "curve in Graph g0 has a minimum rather than a plateau. The rise is ASYMMETRIC:\n",
      "under-predicting a large count is punished far harder than over-predicting it. ",
      "The number on the\nvertical axis of g0 is the weighted average of this quantity ",
      "over respondents held out of the fit."
    ),
    x = "Predicted mean days absent, mu (log scale)",
    y = "Deviance contributed by one respondent",
    colour = NULL
  ) +
  theme(legend.position = "top", panel.grid.minor = element_blank())

print(g02_deviance_meaning)
ggsave(paste0(prints_folder, "g02_deviance_meaning.png"),
       g02_deviance_meaning, width = 11, height = 6.5, dpi = 300)

# ---- g03 ---------------------------------------------------------------------
# Local decision 6. model-1 called cv.glmnet() without keep = TRUE, so the five
# individual fold curves were never stored and cannot be recovered without a
# re-run. What WAS stored is their standard error, drawn here as bars.
zoom_window <- cv_primary_curve %>%
  filter(lambda >= cv_primary_marks$lambda[cv_primary_marks$lambda_rule == "lambda.min"] / 3,
         lambda <= cv_primary_marks$lambda[cv_primary_marks$lambda_rule == "lambda.1se"] * 3)

g03_standard_error <- zoom_window %>%
  ggplot(aes(x = lambda, y = cv_mean)) +
  geom_hline(yintercept = cv_primary_threshold,
             colour = abcol[["magenta"]], linetype = "dotted", linewidth = 0.5) +
  geom_errorbar(aes(ymin = cv_low, ymax = cv_high),
                colour = "grey70", width = 0, linewidth = 0.5) +
  geom_line(colour = abcol[["grey"]], linewidth = 0.7) +
  geom_point(colour = abcol[["grey"]], size = 1.3) +
  geom_vline(data = cv_primary_marks,
             aes(xintercept = lambda, colour = lambda_rule),
             linetype = "dashed", linewidth = 0.6) +
  geom_point(data = cv_primary_marks,
             aes(x = lambda, y = cv_mean, colour = lambda_rule), size = 3) +
  geom_errorbar(data = cv_primary_marks %>% filter(lambda_rule == "lambda.min"),
                aes(x = lambda, ymin = cv_mean, ymax = cv_mean + cv_se),
                colour = abcol[["magenta"]], width = 0.02, linewidth = 0.8,
                inherit.aes = FALSE) +
  annotate(
    "label",
    x = cv_primary_marks$lambda[cv_primary_marks$lambda_rule == "lambda.min"],
    y = cv_primary_threshold, hjust = 1.03, vjust = -0.25, size = 3,
    label.size = 0, fill = "white", alpha = 0.85,
    label = "exactly one standard error\nabove the best deviance"
  ) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.0001)) +
  scale_colour_manual(values = c("lambda.min" = abcol[["blue"]],
                                 "lambda.1se" = abcol[["magenta"]])) +
  labs(
    title = "Graph g03: Where the Standard Error Comes From",
    subtitle = paste0(
      "The neighbourhood of the minimum, magnified. Each bar is the mean plus and ",
      "minus one standard\nerror of the 5 held-out fold deviances at that lambda. ",
      "The bars are wide relative to the difference\nbetween the two marked models, ",
      "and that width IS the argument for lambda.1se: if the two models cannot\n",
      "be distinguished by the data, prefer the smaller one.\n",
      "NOTE: the five individual fold curves are not drawn because model-1 called ",
      "cv.glmnet() without\nkeep = TRUE, so they were never stored. Drawing them ",
      "would require re-running the cross-validation."
    ),
    x = "Lambda, the penalty (log scale)",
    y = "5-fold cross-validated Poisson deviance",
    colour = "Penalty rule"
  ) +
  theme(legend.position = "top", panel.grid.minor = element_blank())

print(g03_standard_error)
ggsave(paste0(prints_folder, "g03_standard_error.png"),
       g03_standard_error, width = 11, height = 6.5, dpi = 300)


# ---- SECTION: Step 3 - The Shared Row Axis ------------------------------------
# Everything in the g1 family hangs off one ordered list of rows. Building it
# once, and auditing that every upstream row finds a home in it, is what makes
# the three panels comparable line by line.

# ---- g1-data-prep ------------------------------------------------------------
# Every non-reference level named by either upstream source. `level_index` is
# model-00's within-variable ordering; variables that appear only in the LASSO
# artifacts (the cycle indicator) have no such index and sort last.
level_universe <- dplyr::bind_rows(
  table_two %>% transmute(variable, level, level_index),
  selection_long %>% distinct(variable, level) %>% mutate(level_index = NA_integer_)
) %>%
  group_by(variable, level) %>%
  summarise(level_index = dplyr::first(stats::na.omit(level_index)), .groups = "drop") %>%
  mutate(level_index = tidyr::replace_na(level_index, 99L),
         is_reference = FALSE)

# Local decision 2. A binary No / Yes variable carries its reference in the row
# label already; a multi-level factor has no readable geometry without an anchor.
multilevel_variables <- level_universe %>%
  count(variable, name = "n_levels") %>%
  filter(n_levels >= 2) %>%
  pull(variable)

reference_rows <- table_two %>%
  distinct(variable, reference_level) %>%
  filter(
    switch(reference_row_rule,
           "multilevel_only" = variable %in% multilevel_variables,
           "all"             = TRUE,
           "none"            = FALSE)
  ) %>%
  transmute(variable, level = reference_level, level_index = 0L, is_reference = TRUE)

row_spine <- dplyr::bind_rows(level_universe, reference_rows) %>%
  mutate(
    variable_label = unname(variable_labels[variable]),
    domain = factor(unname(variable_domains[variable]), levels = domain_levels)
  ) %>%
  arrange(domain, variable_label, level_index) %>%
  mutate(
    row_id = dplyr::row_number(),
    term_label = ifelse(is_reference,
                        paste0(variable_label, ": ", level, "  (ref)"),
                        paste0(variable_label, ": ", level))
  )

readr::write_csv(row_spine, paste0(local_data, "row-spine.csv"))

# Left panel. model-00's unadjusted rate ratios, with reference rows pinned at 1.
panel_left <- row_spine %>%
  left_join(
    table_two %>% select(variable, level, rate_ratio, ci_low, ci_high,
                         ci_low_robust, ci_high_robust, p_value),
    by = c("variable", "level")
  ) %>%
  mutate(
    rate_ratio = ifelse(is_reference, 1, rate_ratio),
    marker = dplyr::case_when(
      is_reference        ~ "reference (fixed at 1)",
      is.na(rate_ratio)   ~ "no bivariate estimate",
      p_value < 0.05      ~ "p < 0.05",
      TRUE                ~ "not significant"
    )
  )

# Middle panel. One vertical bracket per variable per model, spanning exactly the
# rows that variable owns on the shared axis.
variable_extent <- row_spine %>%
  group_by(variable, variable_label, domain) %>%
  summarise(y_min = min(row_id) - 0.45, y_max = max(row_id) + 0.45, .groups = "drop")

selection_kept <- selection_long %>%
  group_by(variable, model_label) %>%
  summarise(kept = any(retained), .groups = "drop")

panel_middle <- variable_extent %>%
  tidyr::crossing(model_label = factor(model_labels_all, levels = model_labels_all)) %>%
  left_join(selection_kept, by = c("variable", "model_label")) %>%
  mutate(
    status = dplyr::case_when(
      variable %in% forced_vars         ~ "forced (unpenalised)",
      variable %in% bivariate_only_vars ~ "not offered",
      is.na(kept)                       ~ "not offered",
      kept                              ~ "retained",
      TRUE                              ~ "eliminated"
    ),
    status = factor(status, levels = selection_states)
  )

readr::write_csv(panel_middle %>% select(-y_min, -y_max),
                 paste0(local_data, "selection-status.csv"))

# Right panel. The primary model's adjusted estimates. A variable the primary
# model did not retain contributes no rows here, and that emptiness is the point.
primary_terms <- nb_coefficients %>%
  filter(spec_id == primary_spec) %>%
  select(variable, level, rate_ratio, ci_low, ci_high, p_value)

panel_right <- row_spine %>%
  left_join(primary_terms, by = c("variable", "level")) %>%
  mutate(in_primary = variable %in% unique(primary_terms$variable)) %>%
  mutate(
    rate_ratio = ifelse(is_reference & in_primary, 1, rate_ratio),
    marker = dplyr::case_when(
      is_reference & in_primary ~ "reference (fixed at 1)",
      is.na(rate_ratio)         ~ "not in the primary model",
      p_value < 0.05            ~ "p < 0.05",
      TRUE                      ~ "not significant"
    )
  )

# One axis window for both estimate panels, so a horizontal distance means the
# same thing on the left as on the right.
rr_axis_limits <- c(
  max(0.2, min(c(panel_left$ci_low, panel_right$ci_low), na.rm = TRUE)),
  min(10,  max(c(panel_left$ci_high, panel_right$ci_high), na.rm = TRUE))
)

marker_shapes <- c(
  "p < 0.05"                 = 19,
  "not significant"          = 19,
  "reference (fixed at 1)"   = 21,
  "no bivariate estimate"    = 4,
  "not in the primary model" = 4
)
marker_alpha <- c(
  "p < 0.05"                 = 1.00,
  "not significant"          = 0.35,
  "reference (fixed at 1)"   = 1.00,
  "no bivariate estimate"    = 0.35,
  "not in the primary model" = 0.00
)

g1_figure_height <- 3.2 + nrow(row_spine) * 0.135

# ---- out1 --------------------------------------------------------------------
cat("Row spine join audit\n")
cat("--------------------\n")
cat("Spine rows:                        ", nrow(row_spine), "\n")
cat("  of which reference rows:         ", sum(row_spine$is_reference), "\n")
cat("Distinct variables on the spine:   ", dplyr::n_distinct(row_spine$variable), "\n\n")

unmatched_bivariate <- table_two %>%
  anti_join(row_spine, by = c("variable", "level"))
unmatched_selection <- selection_long %>%
  distinct(variable, level) %>%
  anti_join(row_spine, by = c("variable", "level"))
unmatched_primary <- primary_terms %>%
  anti_join(row_spine, by = c("variable", "level"))

cat("Bivariate levels with no spine row:", nrow(unmatched_bivariate), "\n")
cat("Selection levels with no spine row:", nrow(unmatched_selection), "\n")
cat("Primary NB terms with no spine row:", nrow(unmatched_primary), "\n\n")

if (nrow(unmatched_primary) > 0) {
  cat("Unmatched primary-model terms (these would vanish from the right panel):\n")
  print(as.data.frame(unmatched_primary), row.names = FALSE)
  cat("\n")
}

cat("Spine rows with no bivariate estimate:",
    sum(is.na(panel_left$rate_ratio)), "\n")
cat("Spine rows with no primary-model estimate:",
    sum(is.na(panel_right$rate_ratio)), "\n")
cat("Graph g1 will be drawn at", round(g1_figure_height, 1), "inches tall.\n")

# ---- g1 ----------------------------------------------------------------------
g1_left <- panel_left %>%
  ggplot(aes(y = row_id)) +
  geom_blank(data = row_spine) +
  geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.4) +
  geom_linerange(aes(xmin = ci_low_robust, xmax = ci_high_robust),
                 colour = "grey82", linewidth = 1.5, na.rm = TRUE) +
  geom_linerange(aes(xmin = ci_low, xmax = ci_high, colour = domain),
                 linewidth = 0.5, na.rm = TRUE) +
  geom_point(aes(x = rate_ratio, colour = domain, shape = marker, alpha = marker),
             size = 1.9, fill = "white", stroke = 0.7, na.rm = TRUE) +
  facet_grid(domain ~ ., scales = "free_y", space = "free_y") +
  scale_y_continuous(breaks = row_spine$row_id, labels = row_spine$term_label,
                     expand = expansion(add = 0.7)) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.1)) +
  coord_cartesian(xlim = rr_axis_limits) +
  scale_colour_manual(values = domain_colours, guide = "none") +
  scale_shape_manual(values = marker_shapes, guide = "none") +
  scale_alpha_manual(values = marker_alpha, guide = "none") +
  labs(subtitle = "UNADJUSTED\nmodel-00, one model per predictor",
       x = "Rate ratio (log scale)", y = NULL) +
  theme(strip.text.y = element_blank(), panel.grid.minor = element_blank(),
        axis.text.y = element_text(size = 7.2),
        plot.subtitle = element_text(size = 9, face = "bold"))

g1_middle <- panel_middle %>%
  ggplot(aes(x = model_label)) +
  geom_blank(data = row_spine %>% mutate(model_label = factor("Model 1",
                                                              levels = model_labels_all)),
             aes(x = model_label, y = row_id)) +
  geom_linerange(aes(ymin = y_min, ymax = y_max, colour = status), linewidth = 3.4) +
  facet_grid(domain ~ ., scales = "free_y", space = "free_y") +
  scale_y_continuous(breaks = NULL, expand = expansion(add = 0.7)) +
  scale_x_discrete(labels = c("Model 1" = "M1", "Model 2" = "M2",
                              "Model 3" = "M3", "Model 4" = "M4")) +
  scale_colour_manual(values = selection_colours, drop = FALSE, name = NULL) +
  labs(subtitle = "SELECTED BY\nmodel-1, LASSO", x = NULL, y = NULL) +
  theme(strip.text.y = element_blank(), panel.grid = element_blank(),
        legend.position = "none",
        plot.subtitle = element_text(size = 9, face = "bold"))

g1_right <- panel_right %>%
  ggplot(aes(y = row_id)) +
  geom_blank(data = row_spine) +
  geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.4) +
  geom_linerange(aes(xmin = ci_low, xmax = ci_high, colour = domain),
                 linewidth = 0.5, na.rm = TRUE) +
  geom_point(aes(x = rate_ratio, colour = domain, shape = marker, alpha = marker),
             size = 1.9, fill = "white", stroke = 0.7, na.rm = TRUE) +
  facet_grid(domain ~ ., scales = "free_y", space = "free_y") +
  scale_y_continuous(breaks = NULL, expand = expansion(add = 0.7)) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.1)) +
  coord_cartesian(xlim = rr_axis_limits) +
  scale_colour_manual(values = domain_colours, guide = "none") +
  scale_shape_manual(values = marker_shapes, guide = "none") +
  scale_alpha_manual(values = marker_alpha, guide = "none") +
  labs(subtitle = paste0("ADJUSTED, ", toupper(primary_spec_label),
                         " ONLY\nmodel-1, negative binomial"),
       x = "Rate ratio (log scale)", y = NULL) +
  theme(strip.text.y = element_text(angle = 0, size = 8),
        panel.grid.minor = element_blank(),
        plot.subtitle = element_text(size = 9, face = "bold"))

g1_legend <- extract_legend(
  g1_middle + theme(legend.position = "bottom", legend.direction = "horizontal")
)

g1_panels <- cowplot::plot_grid(
  g1_left, g1_middle, g1_right,
  nrow = 1, align = "h", axis = "tb",
  rel_widths = unname(g1_panel_widths)
)

g1_title <- cowplot::ggdraw() +
  cowplot::draw_label(
    "Graph g1: Bivariate Signal, Selection, and the Primary Model",
    fontface = "bold", size = 13, hjust = 0, x = 0.005, y = 0.80
  ) +
  cowplot::draw_label(
    paste0(
      "One row per candidate level, in the same order in all three panels. LEFT: the unadjusted rate ratio ",
      "model-00 estimated from a model containing that predictor and the cycle indicator alone; grey bars behind the\n",
      "coloured ones are robust intervals. MIDDLE: which of the four LASSO specifications retained the variable; a ",
      "bracket spans every row its variable owns, so a four-level factor is one tall bar, not four short ones.\n",
      "RIGHT: the adjusted rate ratio from ", primary_spec_label, " (", primary_spec_desc,
      "), the primary specification. A blank right-hand row is a variable ", primary_spec_label,
      " declined - that absence is the finding, not a gap in the drawing.\n",
      "Open circles mark reference levels, fixed at 1 by construction. Faded points are p >= 0.05. ",
      "The left and right panels share one x window, so a horizontal distance means the same on both."
    ),
    size = 8, hjust = 0, x = 0.005, y = 0.34, lineheight = 1.25
  )

g1_caveat <- cowplot::ggdraw() +
  cowplot::draw_label(
    paste0(
      "Caveats carried from the source reports. The two estimate panels are not fitted on identical rows: ",
      "model-00 series S1 is per-predictor complete case (up to n = 63,843) while model-1 uses the shared ",
      "complete-case sample (n = 48,967); model-00 series S2 quantifies that gap.\n",
      "Neither panel shows the bootstrap intervals Sections 5.3 and 5.4 ask for - replicate weights are absent ",
      "from the 2010 and 2014 PUMFs. The right panel's intervals additionally ignore the selection step that ",
      "chose its term list, so they are optimistic."
    ),
    size = 7.4, hjust = 0, x = 0.005, colour = "grey35", lineheight = 1.25
  )

g1_selection_and_estimates <- cowplot::plot_grid(
  g1_title,
  g1_panels,
  g1_legend,
  g1_caveat,
  ncol = 1,
  rel_heights = c(1.5, g1_figure_height - 3.2, 0.35, 0.85)
)

print(g1_selection_and_estimates)
ggsave(paste0(prints_folder, "g1_selection_and_estimates.png"),
       g1_selection_and_estimates,
       width = 15, height = g1_figure_height, dpi = 300, limitsize = FALSE)


# ---- SECTION: Step 4 - Reading the Primary Model ------------------------------
# The right panel of g1 in numbers, and the disagreements between the two
# panels that flank the selection grid.

# ---- t3 ----------------------------------------------------------------------
primary_vs_bivariate <- panel_right %>%
  filter(!is.na(rate_ratio), !is_reference) %>%
  select(domain, variable, variable_label, level, term_label,
         adj_rr = rate_ratio, adj_low = ci_low, adj_high = ci_high, adj_p = p_value) %>%
  left_join(
    table_two %>% select(variable, level, biv_rr = rate_ratio,
                         biv_low = ci_low, biv_high = ci_high, biv_p = p_value),
    by = c("variable", "level")
  ) %>%
  mutate(attenuation = adj_rr / biv_rr)

readr::write_csv(primary_vs_bivariate, paste0(local_data, "primary-vs-bivariate.csv"))

primary_vs_bivariate %>%
  arrange(domain, variable_label, level) %>%
  transmute(
    Domain = domain,
    Term = term_label,
    `Adjusted RR (Model 1)` = sprintf("%.3f (%.3f - %.3f)%s", adj_rr, adj_low, adj_high,
                                      ifelse(adj_p < 0.05, "*", "")),
    `Unadjusted RR (model-00)` = ifelse(
      is.na(biv_rr), "not estimated",
      sprintf("%.3f (%.3f - %.3f)%s", biv_rr, biv_low, biv_high,
              ifelse(biv_p < 0.05, "*", ""))
    ),
    `Adjusted / unadjusted` = ifelse(is.na(biv_rr), "", sprintf("%.2f", attenuation))
  ) %>%
  print_table(
    caption = paste0(
      "Table t3: the right panel of Graph g1 in numbers, with the left panel beside it. ",
      "Estimates are from ", primary_spec_label, " (", primary_spec_desc,
      "), the primary specification. An asterisk marks p < 0.05. The last column is the ",
      "ratio of the two: below 1 means adjustment moved the estimate toward the null, ",
      "above 1 means the other predictors were masking it."
    ),
    align = c("l", "l", "r", "r", "r"),
    scroll_height = "600px"
  )

# ---- t4 ----------------------------------------------------------------------
# A variable can carry a strong unadjusted signal and still be eliminated, if
# what it measures is already carried by something else in the design matrix.
bivariate_verdict <- table_two %>%
  group_by(variable) %>%
  summarise(
    biv_significant = any(p_value < 0.05, na.rm = TRUE),
    biv_max_effect = max(pmax(rate_ratio, 1 / rate_ratio), na.rm = TRUE),
    .groups = "drop"
  )

disagreements <- bivariate_verdict %>%
  left_join(selection_kept %>% filter(model_label == primary_spec_label) %>%
              select(variable, kept), by = "variable") %>%
  mutate(
    variable_label = unname(variable_labels[variable]),
    domain = factor(unname(variable_domains[variable]), levels = domain_levels),
    offered = variable %in% selection_long$variable[
      selection_long$model_label == primary_spec_label],
    verdict = dplyr::case_when(
      !offered                        ~ "never offered to the penalty",
      biv_significant & !kept         ~ "significant bivariately, ELIMINATED",
      !biv_significant & kept %in% TRUE ~ "not significant bivariately, RETAINED",
      biv_significant & kept %in% TRUE  ~ "agree: significant and retained",
      TRUE                            ~ "agree: not significant and eliminated"
    )
  ) %>%
  filter(verdict != "agree: significant and retained",
         verdict != "agree: not significant and eliminated")

readr::write_csv(disagreements, paste0(local_data, "selection-disagreements.csv"))

disagreements %>%
  arrange(verdict, domain, variable_label) %>%
  transmute(
    Verdict = verdict,
    Domain = domain,
    Variable = variable_label,
    `Largest unadjusted effect` = sprintf("%.2f", biv_max_effect),
    `Significant bivariately` = ifelse(biv_significant, "yes", "no")
  ) %>%
  print_table(
    caption = paste0(
      "Table t4: where the two flanking panels of Graph g1 disagree, for ",
      primary_spec_label, ". Elimination despite a significant unadjusted ",
      "association is the expected behaviour of a penalty, not a malfunction: the ",
      "variable's signal is already carried by a correlate that entered first. ",
      "'Largest unadjusted effect' is the furthest any of the variable's levels ",
      "sits from 1, expressed as a ratio at or above 1 in either direction."
    ),
    align = c("l", "l", "l", "r", "c"),
    scroll_height = NULL
  )

# nolint end
