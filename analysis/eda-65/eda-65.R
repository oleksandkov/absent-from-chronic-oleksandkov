# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# EDA-65: Missing Data Mechanism — Little's MCAR Test & Variable-Level Missingness
# Mode: EDA (explore with open mind)
rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014") # Clear the console

# Guard: ensure working directory is the project root (where flow.R lives).
if (!file.exists("flow.R")) {
  candidate <- getwd()
  while (!file.exists(file.path(candidate, "flow.R")) &&
         candidate != dirname(candidate)) {
    candidate <- dirname(candidate)
  }
  if (file.exists(file.path(candidate, "flow.R"))) {
    setwd(candidate)
  }
}

# verify root location
cat("Working directory: ", getwd()) # Must be set to Project Directory

# ---- load-packages -----------------------------------------------------------
library(magrittr)
library(ggplot2)
library(forcats)
library(stringr)
library(dplyr)
library(tidyr)
library(scales)
library(fs)
requireNamespace("arrow")
requireNamespace("mice")       # md.pattern

# naniar provides vis_miss() and mcar_test(); install if not present
if (!requireNamespace("naniar", quietly = TRUE)) {
  message("Installing naniar (required for MCAR test)...")
  install.packages("naniar")
}
library(naniar)

# ---- httpgd (VS Code interactive plots) ------------------------------------
if (requireNamespace("httpgd", quietly = TRUE)) {
  tryCatch({
    if (is.function(httpgd::hgd)) {
      httpgd::hgd()
    } else if (is.function(httpgd::httpgd)) {
      httpgd::httpgd()
    } else {
      httpgd::hgd()
    }
    message("httpgd started. Configure VS Code R extension to use it for plots.")
  }, error = function(e) {
    message("httpgd detected but failed to start: ", conditionMessage(e))
  })
} else {
  message("httpgd not installed. Install with: install.packages('httpgd')")
}

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R")
base::source("./scripts/operational-functions.R")
if (file.exists("./scripts/graphing/graph-presets.R")) {
  base::source("./scripts/graphing/graph-presets.R")
}

# ---- declare-globals ---------------------------------------------------------
local_root    <- "./analysis/eda-65/"
local_data    <- paste0(local_root, "data-local/")
prints_folder <- paste0(local_root, "prints/")
data_private_derived <- "./data-private/derived/eda-65/"

if (!fs::dir_exists(local_data))           fs::dir_create(local_data)
if (!fs::dir_exists(prints_folder))        fs::dir_create(prints_folder)
if (!fs::dir_exists(data_private_derived)) fs::dir_create(data_private_derived)

path_cchs2_parquet  <- "./data-private/derived/cchs-2-tables"
path_analytical_pq  <- file.path(path_cchs2_parquet, "cchs_analytic.parquet")
weight_col          <- "wts_m_pooled"

# Variable groups for MCAR testing
outcome_vars <- c("days_absent_total", "days_absent_chronic")

cc_vars <- c(
  "cc_asthma", "cc_fibromyalgia", "cc_arthritis", "cc_back_problems",
  "cc_hypertension", "cc_migraine", "cc_copd", "cc_diabetes",
  "cc_heart_disease", "cc_cancer", "cc_ulcer", "cc_stroke",
  "cc_bowel_disorder", "cc_fatigue_syndrome", "cc_chem_sensitivity",
  "cc_mood_disorder", "cc_anxiety"
)

predisposing_vars <- c(
  "age_group_3", "sex", "marital_status", "household_size",
  "education", "immigration_status", "visible_minority", "home_ownership",
  "living_arrangements"
)

facilitating_vars <- c(
  "income_hh", "province", "has_family_doctor", "employment_type",
  "work_schedule", "occupation_category", "work_stress",
  "fruit_veg_daily", "alcohol_type", "smoking_status",
  "bmi_category", "physical_activity"
)

needs_vars <- c(
  "health_perceived", "mental_health_perceived", "health_vs_prior_year",
  "injured_past_12m",
  "adl_meals", "adl_errands", "adl_housework",
  "adl_personal_care", "adl_moving_indoors", "adl_finances"
)

# All analysis variables
all_analysis_vars <- c(outcome_vars, cc_vars, predisposing_vars,
                       facilitating_vars, needs_vars)

# Human-readable domain labels
domain_map <- c(
  setNames(rep("Outcome", length(outcome_vars)), outcome_vars),
  setNames(rep("Chronic Conditions", length(cc_vars)), cc_vars),
  setNames(rep("Predisposing", length(predisposing_vars)), predisposing_vars),
  setNames(rep("Facilitating", length(facilitating_vars)), facilitating_vars),
  setNames(rep("Needs", length(needs_vars)), needs_vars)
)

# ---- declare-functions -------------------------------------------------------
# Safe wrapper for naniar::mcar_test that handles errors gracefully
safe_mcar_test <- function(data, label = "block") {
  tryCatch({
    # naniar::mcar_test requires numeric data; convert factors to numeric codes
    data_numeric <- data %>%
      mutate(across(where(is.factor), ~ as.numeric(.x))) %>%
      mutate(across(where(is.logical), ~ as.numeric(.x)))

    # Only run if there is some missingness to test
    n_miss <- sum(is.na(data_numeric))
    n_complete <- sum(complete.cases(data_numeric))

    if (n_miss == 0) {
      return(tibble::tibble(
        block     = label,
        statistic = NA_real_,
        df        = NA_integer_,
        p_value   = NA_real_,
        n_vars    = ncol(data_numeric),
        n_obs     = nrow(data_numeric),
        n_complete = n_complete,
        note      = "No missing data — MCAR test not applicable"
      ))
    }

    result <- naniar::mcar_test(data_numeric)

    tibble::tibble(
      block     = label,
      statistic = result$statistic,
      df        = as.integer(result$df),
      p_value   = result$p.value,
      n_vars    = ncol(data_numeric),
      n_obs     = nrow(data_numeric),
      n_complete = n_complete,
      note      = ifelse(result$p.value < 0.05,
                         "Reject MCAR (p < 0.05): missingness is NOT completely at random",
                         "Fail to reject MCAR (p >= 0.05): consistent with MCAR")
    )
  }, error = function(e) {
    tibble::tibble(
      block     = label,
      statistic = NA_real_,
      df        = NA_integer_,
      p_value   = NA_real_,
      n_vars    = ncol(data),
      n_obs     = nrow(data),
      n_complete = NA_integer_,
      note      = paste0("Error: ", conditionMessage(e))
    )
  })
}

# ---- load-data ---------------------------------------------------------------
if (!file.exists(path_analytical_pq)) {
  stop("Missing required file: ", path_analytical_pq, call. = FALSE)
}

ds0 <- arrow::read_parquet(path_analytical_pq)

# Subset to analysis variables that exist in the dataset
available_vars <- intersect(all_analysis_vars, names(ds0))
missing_vars   <- setdiff(all_analysis_vars, names(ds0))
if (length(missing_vars) > 0) {
  warning("Variables not found in dataset: ", paste(missing_vars, collapse = ", "))
}

cat(sprintf("Loaded analytical data: %s rows, %s columns\n",
            format(nrow(ds0), big.mark = ","),
            format(ncol(ds0), big.mark = ",")))
cat(sprintf("Analysis variables available: %d of %d\n",
            length(available_vars), length(all_analysis_vars)))

# ---- data-context-tables -----------------------------------------------------
data_context_tables <- tibble::tibble(
  source_table = "cchs_analytic.parquet",
  location     = path_analytical_pq,
  rows         = nrow(ds0),
  columns      = ncol(ds0),
  usage        = "All analysis variables — missingness profiling and MCAR testing"
)
print(data_context_tables)


# ==============================================================================
# G1 FAMILY — Variable-Level Missingness Profile
# Research question: What is the missingness rate for each analysis variable?
# g1  : horizontal bar chart of % missing per variable, coloured by domain
# g11 : missingness heatmap (variables × respondents subsample)
# ==============================================================================

# ---- g1-data-prep ------------------------------------------------------------
ds_miss <- ds0 %>% select(all_of(available_vars))

g1_data <- tibble::tibble(
  variable = available_vars,
  n_miss   = purrr::map_int(available_vars, ~ sum(is.na(ds_miss[[.x]]))),
  n_valid  = nrow(ds_miss) - purrr::map_int(available_vars, ~ sum(is.na(ds_miss[[.x]]))),
  pct_miss = n_miss / nrow(ds_miss) * 100,
  domain   = domain_map[available_vars]
) %>%
  arrange(desc(pct_miss))

# ---- g1 ---------------------------------------------------------------------
g1_miss_by_variable <- g1_data %>%
  mutate(variable = fct_reorder(variable, pct_miss)) %>%
  ggplot(aes(x = pct_miss, y = variable, fill = domain)) +
  geom_col(alpha = 0.85) +
  geom_text(
    data = . %>% filter(pct_miss > 1),
    aes(label = sprintf("%.1f%%", pct_miss)),
    hjust = -0.1, size = 2.5
  ) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15)),
                     labels = scales::label_percent(scale = 1)) +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title    = "Missingness Rate by Variable",
    subtitle = "Percentage of 63,843 analytical rows with NA, coloured by Andersen model domain",
    x = "% Missing",
    y = NULL,
    fill = "Domain"
  ) +
  theme_minimal(base_size = 9) +
  theme(panel.grid.major.y = element_blank())
print(g1_miss_by_variable)
ggsave(paste0(prints_folder, "g1_miss_by_variable.png"),
       g1_miss_by_variable, width = 8.5, height = 9, dpi = 300)

# ---- g11 --------------------------------------------------------------------
# naniar visual missingness matrix (subsampled for performance)
set.seed(42)
ds_subsample <- ds_miss %>% slice_sample(n = min(5000, nrow(ds_miss)))

g11_miss_heatmap <- naniar::vis_miss(ds_subsample, sort_miss = TRUE, cluster = TRUE) +
  labs(
    title    = "Missingness Pattern Heatmap (random subsample n = 5,000)",
    subtitle = "Black = missing, grey = observed; variables sorted by % missing"
  ) +
  theme(axis.text.x = element_text(angle = 60, hjust = 1, size = 6))
print(g11_miss_heatmap)
ggsave(paste0(prints_folder, "g11_miss_heatmap.png"),
       g11_miss_heatmap, width = 10, height = 7, dpi = 300)


# ==============================================================================
# G2 FAMILY — Missingness Patterns (combinatoric)
# Research question: What are the most common missingness patterns?
# g2  : upset-style plot of top missingness patterns
# g21 : number of variables missing per respondent
# ==============================================================================

# ---- g2-data-prep ------------------------------------------------------------
# Count of variables missing per respondent
ds_miss_count <- ds_miss %>%
  mutate(n_vars_missing = rowSums(is.na(across(everything())))) %>%
  pull(n_vars_missing)

g2_count_data <- tibble::tibble(n_missing = ds_miss_count) %>%
  count(n_missing) %>%
  mutate(pct = n / sum(n) * 100)

# Top 15 unique missingness patterns
miss_patterns <- ds_miss %>%
  mutate(across(everything(), ~ as.integer(is.na(.)))) %>%
  group_by(across(everything())) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(desc(n)) %>%
  slice_head(n = 15) %>%
  mutate(
    pattern_id = row_number(),
    pct = n / nrow(ds_miss) * 100
  )

# ---- g2 ---------------------------------------------------------------------
g2_vars_missing <- g2_count_data %>%
  ggplot(aes(x = factor(n_missing), y = pct)) +
  geom_col(fill = "#4575b4", alpha = 0.8) +
  geom_text(aes(label = sprintf("%.1f%%", pct)), vjust = -0.3, size = 3) +
  labs(
    title    = "Number of Missing Variables per Respondent",
    subtitle = "Distribution of missingness burden across the analytical sample",
    x = "Number of Variables with NA",
    y = "% of Respondents"
  ) +
  theme_minimal(base_size = 11)
print(g2_vars_missing)
ggsave(paste0(prints_folder, "g2_vars_missing.png"),
       g2_vars_missing, width = 8.5, height = 5.5, dpi = 300)

# ---- g21 --------------------------------------------------------------------
# Upset-style: which variables are jointly missing in the top patterns
g21_data <- miss_patterns %>%
  select(-n, -pct) %>%
  pivot_longer(-pattern_id, names_to = "variable", values_to = "is_missing") %>%
  filter(is_missing == 1) %>%
  mutate(variable = factor(variable, levels = g1_data$variable))

g21_pattern_plot <- g21_data %>%
  ggplot(aes(x = factor(pattern_id), y = variable)) +
  geom_point(size = 2, color = "#d73027") +
  geom_line(aes(group = pattern_id), color = "#d73027", alpha = 0.5) +
  labs(
    title    = "Top 15 Missingness Patterns — Variables Jointly Missing",
    subtitle = "Each column is a unique missingness pattern; dots indicate which variables are NA",
    x = "Pattern Rank (by frequency)",
    y = NULL
  ) +
  theme_minimal(base_size = 9) +
  theme(panel.grid.major = element_blank())
print(g21_pattern_plot)
ggsave(paste0(prints_folder, "g21_pattern_plot.png"),
       g21_pattern_plot, width = 8.5, height = 7, dpi = 300)


# ==============================================================================
# G3 FAMILY — Little's MCAR Test
# Research question: Is missingness completely at random, or is there structure?
# Tests run separately for each variable domain block.
# g3  : summary table of MCAR test results by domain
# ==============================================================================

# ---- g3-data-prep ------------------------------------------------------------
# Run Little's MCAR test by domain block
mcar_results <- bind_rows(
  safe_mcar_test(ds0 %>% select(any_of(cc_vars)), "Chronic Conditions (17 vars)"),
  safe_mcar_test(ds0 %>% select(any_of(predisposing_vars)),
                 paste0("Predisposing (", length(predisposing_vars), " vars)")),
  safe_mcar_test(ds0 %>% select(any_of(facilitating_vars)), "Facilitating (12 vars)"),
  safe_mcar_test(ds0 %>% select(any_of(needs_vars)), "Needs (10 vars)"),
  safe_mcar_test(ds0 %>% select(any_of(c(cc_vars, predisposing_vars,
                                          facilitating_vars, needs_vars))),
                 "All predictors combined")
)

cat("\n---- Little's MCAR Test Results ----\n")
print(mcar_results, n = Inf)

# ---- g3 ---------------------------------------------------------------------
g3_mcar_summary <- mcar_results %>%
  mutate(
    significance = case_when(
      is.na(p_value)  ~ "N/A",
      p_value < 0.001 ~ "***",
      p_value < 0.01  ~ "**",
      p_value < 0.05  ~ "*",
      TRUE            ~ "n.s."
    ),
    block = factor(block, levels = block)
  ) %>%
  ggplot(aes(x = block, y = -log10(pmax(p_value, 1e-300)))) +
  geom_col(fill = "#B22222", alpha = 0.7) +
  geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "grey40") +
  annotate("text", x = 0.5, y = -log10(0.05) + 0.3, label = "p = 0.05",
           hjust = 0, size = 3, color = "grey40") +
  coord_flip() +
  labs(
    title    = "Little's MCAR Test by Variable Domain",
    subtitle = "Bar height = -log10(p-value); dashed line = significance threshold (p = 0.05)",
    x = NULL,
    y = "-log10(p-value)",
    caption  = "Interpretation: bars above dashed line → reject MCAR (missingness is structured)"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g3_mcar_summary)
ggsave(paste0(prints_folder, "g3_mcar_summary.png"),
       g3_mcar_summary, width = 8.5, height = 5.5, dpi = 300)


# ==============================================================================
# G4 FAMILY — Missingness by Age Group
# Research question: Does missingness concentrate in younger age groups (age-gating)?
# g4  : heatmap of % missing by variable × age_group_3
# ==============================================================================

# ---- g4-data-prep ------------------------------------------------------------
# Variables with any missingness
vars_with_miss <- g1_data %>% filter(pct_miss > 0) %>% pull(variable)

g4_data <- ds0 %>%
  select(age_group_3, all_of(vars_with_miss)) %>%
  filter(!is.na(age_group_3)) %>%
  group_by(age_group_3) %>%
  summarise(
    across(all_of(vars_with_miss), ~ sum(is.na(.x)) / n() * 100),
    .groups = "drop"
  ) %>%
  pivot_longer(-age_group_3, names_to = "variable", values_to = "pct_missing") %>%
  mutate(
    domain = domain_map[variable],
    variable = factor(variable, levels = rev(g1_data$variable[g1_data$variable %in% vars_with_miss]))
  )

# ---- g4 ---------------------------------------------------------------------
g4_miss_by_age <- g4_data %>%
  ggplot(aes(x = age_group_3, y = variable, fill = pct_missing)) +
  geom_tile(color = "white", linewidth = 0.3) +
  geom_text(aes(label = sprintf("%.0f%%", pct_missing)), size = 2.5) +
  scale_fill_gradient(low = "#f7fbff", high = "#d73027",
                      name = "% Missing", limits = c(0, NA)) +
  labs(
    title    = "Missingness by Age Group — Identifying Age-Gated Variables",
    subtitle = "Variables with higher missingness in young (15-24) group are likely age-gated questions",
    x = "Age Group",
    y = NULL
  ) +
  theme_minimal(base_size = 9) +
  theme(panel.grid = element_blank())
print(g4_miss_by_age)
ggsave(paste0(prints_folder, "g4_miss_by_age.png"),
       g4_miss_by_age, width = 8.5, height = 8, dpi = 300)


# ==============================================================================
# G5 FAMILY — Missingness by Cycle
# Research question: Does missingness differ between the two CCHS cycles?
# g5  : paired dot-plot of % missing per variable, by cycle
# ==============================================================================

# ---- g5-data-prep ------------------------------------------------------------
g5_data <- ds0 %>%
  select(cchs_cycle_f, all_of(vars_with_miss)) %>%
  group_by(cchs_cycle_f) %>%
  summarise(
    across(all_of(vars_with_miss), ~ sum(is.na(.x)) / n() * 100),
    .groups = "drop"
  ) %>%
  pivot_longer(-cchs_cycle_f, names_to = "variable", values_to = "pct_missing") %>%
  mutate(variable = factor(variable, levels = rev(g1_data$variable[g1_data$variable %in% vars_with_miss])))

# ---- g5 ---------------------------------------------------------------------
g5_miss_by_cycle <- g5_data %>%
  ggplot(aes(x = pct_missing, y = variable, color = cchs_cycle_f)) +
  geom_point(size = 2.5, alpha = 0.8) +
  scale_color_manual(values = c("2010-2011" = "#4682B4", "2013-2014" = "#CD853F")) +
  labs(
    title    = "Missingness by CCHS Cycle",
    subtitle = "Comparing % missing between 2010-2011 and 2013-2014 cycles",
    x = "% Missing",
    y = NULL,
    color = "Cycle"
  ) +
  theme_minimal(base_size = 9) +
  theme(panel.grid.major.y = element_blank())
print(g5_miss_by_cycle)
ggsave(paste0(prints_folder, "g5_miss_by_cycle.png"),
       g5_miss_by_cycle, width = 8.5, height = 8, dpi = 300)

# ---- save-results ------------------------------------------------------------
# Save MCAR results for use in QMD
saveRDS(
  list(
    mcar_results = mcar_results,
    g1_data      = g1_data,
    g2_count     = g2_count_data,
    miss_patterns = miss_patterns,
    n_total       = nrow(ds0)
  ),
  file = paste0(local_data, "eda-65.rds")
)
cat("\nResults saved to:", paste0(local_data, "eda-65.rds"), "\n")

# nolint end
