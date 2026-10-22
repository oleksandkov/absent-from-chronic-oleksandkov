# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# EDA-61: Exposure Variable Profile — 17 Chronic Condition Flags (Andersen Model)
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
local_root    <- "./analysis/eda-61/"
local_data    <- paste0(local_root, "data-local/")
prints_folder <- paste0(local_root, "prints/")
data_private_derived <- "./data-private/derived/eda-61/"

if (!fs::dir_exists(local_data))           fs::dir_create(local_data)
if (!fs::dir_exists(prints_folder))        fs::dir_create(prints_folder)
if (!fs::dir_exists(data_private_derived)) fs::dir_create(data_private_derived)

path_cchs2_parquet  <- "./data-private/derived/cchs-2-tables"
path_analytical_pq  <- file.path(path_cchs2_parquet, "cchs_analytic.parquet")
weight_col          <- "wts_m_pooled"

# The 17 chronic condition exposure variables (logical flags)
cc_vars <- c(
  "cc_asthma", "cc_fibromyalgia", "cc_arthritis", "cc_back_problems",
  "cc_hypertension", "cc_migraine", "cc_copd", "cc_diabetes",
  "cc_heart_disease", "cc_cancer", "cc_ulcer", "cc_stroke",
  "cc_bowel_disorder", "cc_fatigue_syndrome", "cc_chem_sensitivity",
  "cc_mood_disorder", "cc_anxiety"
)

# Human-readable labels for display
cc_labels <- c(
  "cc_asthma"           = "Asthma",
  "cc_fibromyalgia"     = "Fibromyalgia",
  "cc_arthritis"        = "Arthritis",
  "cc_back_problems"    = "Back problems",
  "cc_hypertension"     = "High blood pressure",
  "cc_migraine"         = "Migraine headaches",
  "cc_copd"             = "COPD",
  "cc_diabetes"         = "Diabetes",
  "cc_heart_disease"    = "Heart disease",
  "cc_cancer"           = "Cancer",
  "cc_ulcer"            = "Stomach/intestinal ulcers",
  "cc_stroke"           = "Stroke effects",
  "cc_bowel_disorder"   = "Bowel disorder",
  "cc_fatigue_syndrome" = "Chronic fatigue syndrome",
  "cc_chem_sensitivity" = "Chemical sensitivity",
  "cc_mood_disorder"    = "Mood disorder",
  "cc_anxiety"          = "Anxiety disorder"
)

# ---- declare-functions -------------------------------------------------------
# No analysis-specific helpers required at this stage.

# ---- load-data ---------------------------------------------------------------
if (!file.exists(path_analytical_pq)) {
  stop("Missing required file: ", path_analytical_pq, call. = FALSE)
}

ds0 <- arrow::read_parquet(path_analytical_pq)

required_cols <- c(
  weight_col, "days_absent_total", "days_absent_chronic",
  "cchs_cycle", "cchs_cycle_f",
  cc_vars
)
missing_required <- setdiff(required_cols, names(ds0))
if (length(missing_required) > 0) {
  stop("Missing required columns in cchs_analytic.parquet: ",
       paste(missing_required, collapse = ", "), call. = FALSE)
}

cat(sprintf("Loaded analytical data: %s rows, %s columns\n",
            format(nrow(ds0), big.mark = ","),
            format(ncol(ds0), big.mark = ",")))

# ---- data-context-tables -----------------------------------------------------
data_context_tables <- tibble::tibble(
  source_table = "cchs_analytic.parquet",
  location     = path_analytical_pq,
  rows         = nrow(ds0),
  columns      = ncol(ds0),
  usage        = paste(
    "17 chronic-condition logical flags (cc_*),",
    "primary outcome days_absent_total, survey weight wts_m_pooled"
  )
)
print(data_context_tables)

# ---- data-context-person -----------------------------------------------------
# A respondent with multiple chronic conditions — shows the key columns
data_context_person <- ds0 %>%
  select(cchs_cycle_f, !!weight_col, days_absent_total, all_of(cc_vars)) %>%
  mutate(n_conditions = rowSums(across(all_of(cc_vars)), na.rm = TRUE)) %>%
  filter(n_conditions >= 3) %>%
  select(-n_conditions) %>%
  slice_head(n = 2)
print(data_context_person)

# ---- data-context-distributions ----------------------------------------------
# Prevalence summary for each cc_* variable
data_context_distributions <- ds0 %>%
  summarise(
    across(
      all_of(cc_vars),
      list(
        n_total    = ~ n(),
        n_true     = ~ sum(.x == TRUE, na.rm = TRUE),
        n_false    = ~ sum(.x == FALSE, na.rm = TRUE),
        n_na       = ~ sum(is.na(.x)),
        pct_true   = ~ mean(.x == TRUE, na.rm = TRUE) * 100
      )
    )
  ) %>%
  pivot_longer(
    cols         = everything(),
    names_to     = c("variable", ".value"),
    names_pattern = "^(.+)_(n_total|n_true|n_false|n_na|pct_true)$"
  ) %>%
  mutate(label = cc_labels[variable]) %>%
  arrange(desc(pct_true))
print(data_context_distributions)

# ---- tweak-data-0 ------------------------------------------------------------
# Long-form chronic condition dataset — shared ancestor for G1, G2, G4 families
ds_cc_long <- ds0 %>%
  select(
    cchs_cycle, cchs_cycle_f, !!weight_col,
    days_absent_total, days_absent_chronic,
    all_of(cc_vars)
  ) %>%
  pivot_longer(
    cols      = all_of(cc_vars),
    names_to  = "condition",
    values_to = "has_condition"
  ) %>%
  mutate(
    condition_label = cc_labels[condition],
    condition_label = factor(condition_label, levels = cc_labels)
  )

# Multimorbidity count per respondent
ds_multimorbidity <- ds0 %>%
  select(cchs_cycle, cchs_cycle_f, !!weight_col,
         days_absent_total, days_absent_chronic, all_of(cc_vars)) %>%
  mutate(
    n_conditions = rowSums(across(all_of(cc_vars)), na.rm = TRUE)
  )

# ---- inspect-data-0 ----------------------------------------------------------
cat(sprintf("Long-form dataset: %s rows\n", format(nrow(ds_cc_long), big.mark = ",")))
cat(sprintf("Conditions per respondent — range: [%d, %d], mean: %.1f\n",
            min(ds_multimorbidity$n_conditions),
            max(ds_multimorbidity$n_conditions),
            mean(ds_multimorbidity$n_conditions)))


# ==============================================================================
# G1 FAMILY — Condition Prevalence
# Research question: What is the weighted prevalence of each chronic condition?
# g1  : unweighted prevalence (horizontal bar chart)
# g11 : weighted prevalence (horizontal bar chart)
# g12 : weighted prevalence stratified by CCHS cycle
# ==============================================================================

# ---- g1-data-prep ------------------------------------------------------------
g1_data <- ds_cc_long %>%
  group_by(condition, condition_label) %>%
  summarise(
    n_total       = n(),
    n_with        = sum(has_condition == TRUE, na.rm = TRUE),
    pct_unweighted = mean(has_condition == TRUE, na.rm = TRUE) * 100,
    pct_weighted   = weighted.mean(has_condition == TRUE, w = .data[[weight_col]], na.rm = TRUE) * 100,
    .groups = "drop"
  ) %>%
  arrange(desc(pct_weighted))

# ---- g1 ---------------------------------------------------------------------
g1_prevalence_unweighted <- g1_data %>%
  ggplot(aes(x = pct_unweighted, y = fct_reorder(condition_label, pct_unweighted))) +
  geom_col(fill = "#4682B4", alpha = 0.8) +
  geom_text(aes(label = sprintf("%.1f%%", pct_unweighted)),
            hjust = -0.1, size = 3) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title    = "Unweighted Prevalence of Chronic Conditions",
    subtitle = "Proportion of analytical sample reporting each condition (n = 63,843)",
    x = "Prevalence (%)",
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g1_prevalence_unweighted)
ggsave(paste0(prints_folder, "g1_prevalence_unweighted.png"),
       g1_prevalence_unweighted, width = 8.5, height = 5.5, dpi = 300)

# ---- g11 --------------------------------------------------------------------
g11_prevalence_weighted <- g1_data %>%
  ggplot(aes(x = pct_weighted, y = fct_reorder(condition_label, pct_weighted))) +
  geom_col(fill = "#2E8B57", alpha = 0.8) +
  geom_text(aes(label = sprintf("%.1f%%", pct_weighted)),
            hjust = -0.1, size = 3) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title    = "Weighted Prevalence of Chronic Conditions",
    subtitle = "Population-weighted proportion (wts_m_pooled)",
    x = "Prevalence (%)",
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g11_prevalence_weighted)
ggsave(paste0(prints_folder, "g11_prevalence_weighted.png"),
       g11_prevalence_weighted, width = 8.5, height = 5.5, dpi = 300)

# ---- g12 --------------------------------------------------------------------
g12_data <- ds_cc_long %>%
  group_by(condition, condition_label, cchs_cycle_f) %>%
  summarise(
    pct_weighted = weighted.mean(has_condition == TRUE, w = .data[[weight_col]], na.rm = TRUE) * 100,
    .groups = "drop"
  )

g12_prevalence_by_cycle <- g12_data %>%
  ggplot(aes(x = pct_weighted, y = fct_reorder(condition_label, pct_weighted),
             fill = cchs_cycle_f)) +
  geom_col(position = "dodge", alpha = 0.8) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  scale_fill_manual(values = c("2010-2011" = "#4682B4", "2013-2014" = "#CD853F")) +
  labs(
    title    = "Weighted Prevalence by CCHS Cycle",
    subtitle = "Comparing 2010-2011 vs 2013-2014 cycles",
    x = "Prevalence (%)",
    y = NULL,
    fill = "Cycle"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g12_prevalence_by_cycle)
ggsave(paste0(prints_folder, "g12_prevalence_by_cycle.png"),
       g12_prevalence_by_cycle, width = 8.5, height = 5.5, dpi = 300)


# ==============================================================================
# G1a FAMILY — COPD Age-Gated Prevalence
# Context: The COPD question (CCC_091) was administered only to respondents
#   aged 35+ in the CCHS. Younger respondents have NA on cc_copd because they
#   were never asked the question — NOT because data is missing.
#   Marc-André Blanchette (2026-05-15) recommended showing an age-gated
#   alternative that imputes FALSE for respondents below the threshold and
#   recalculates prevalence within the target age group only.
#
# DHHGAGE code mapping: code 8 = 35-39 yrs → codes 8-15 represent 35-75.
# g1a  : COPD prevalence with age-gating vs naive (full-sample)
# g1a1 : All 17 conditions — prevalence restricted to 35+ subsample
# ==============================================================================

# ---- g1a-data-prep -----------------------------------------------------------
# Age threshold: DHHGAGE code 8 = 35-39 years (first group >= 35)
COPD_AGE_THRESHOLD <- 8L

# Respondents aged 35+ (eligible for the COPD question)
ds0_age35plus <- ds0 %>% filter(dhhgage >= COPD_AGE_THRESHOLD)
n_age35plus <- nrow(ds0_age35plus)

# Comparison data: COPD prevalence full-sample (naive) vs age-gated
copd_naive <- ds0 %>%

  summarise(
    pct_weighted = weighted.mean(cc_copd == TRUE, w = .data[[weight_col]], na.rm = TRUE) * 100,
    n_valid = sum(!is.na(cc_copd)),
    n_na    = sum(is.na(cc_copd))
  ) %>%
  mutate(approach = "Full sample (N = 63,843)\nNA excluded from denominator")

copd_agegated <- ds0_age35plus %>%
  mutate(cc_copd_gated = coalesce(cc_copd, FALSE)) %>%
  summarise(
    pct_weighted = weighted.mean(cc_copd_gated == TRUE, w = .data[[weight_col]], na.rm = TRUE) * 100,
    n_valid = n(),
    n_na    = 0L
  ) %>%
  mutate(approach = sprintf("Age-gated 35+ (n = %s)\nNA imputed as FALSE", format(n_age35plus, big.mark = ",")))

g1a_comparison <- bind_rows(copd_naive, copd_agegated)

# All 17 conditions restricted to 35+ subsample
g1a1_data <- ds0_age35plus %>%
  select(all_of(cc_vars), !!weight_col) %>%
  pivot_longer(cols = all_of(cc_vars), names_to = "condition", values_to = "has_condition") %>%
  mutate(condition_label = cc_labels[condition]) %>%
  group_by(condition, condition_label) %>%
  summarise(
    pct_weighted = weighted.mean(has_condition == TRUE, w = .data[[weight_col]], na.rm = TRUE) * 100,
    .groups = "drop"
  ) %>%
  arrange(desc(pct_weighted))

# ---- g1a --------------------------------------------------------------------
g1a_copd_agegated <- g1a_comparison %>%
  ggplot(aes(x = pct_weighted, y = approach)) +
  geom_col(fill = "#2E8B57", alpha = 0.8, width = 0.5) +
  geom_text(aes(label = sprintf("%.1f%%", pct_weighted)), hjust = -0.1, size = 4) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.2))) +
  labs(
    title    = "COPD Prevalence: Full-Sample (naive) vs. Age-Gated (35+)",
    subtitle = "CCC_091 administered only to respondents aged 35+; younger respondents = not applicable, not missing",
    x = "Weighted Prevalence (%)",
    y = NULL,
    caption  = "Age-gating: DHHGAGE >= 8 (35-39 yrs+). Imputes FALSE for respondents below threshold."
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g1a_copd_agegated)
ggsave(paste0(prints_folder, "g1a_copd_agegated.png"),
       g1a_copd_agegated, width = 8.5, height = 5.5, dpi = 300)

# ---- g1a1 -------------------------------------------------------------------
g1a1_prevalence_35plus <- g1a1_data %>%
  ggplot(aes(x = pct_weighted, y = fct_reorder(condition_label, pct_weighted))) +
  geom_col(fill = "#4682B4", alpha = 0.8) +
  geom_text(aes(label = sprintf("%.1f%%", pct_weighted)), hjust = -0.1, size = 3) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title    = "Weighted Prevalence — Restricted to Respondents Aged 35+",
    subtitle = sprintf("Subsample n = %s; COPD missingness resolved by age-gating", format(n_age35plus, big.mark = ",")),
    x = "Prevalence (%)",
    y = NULL,
    caption  = "COPD: respondents below 35 imputed as FALSE (not asked the question)"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g1a1_prevalence_35plus)
ggsave(paste0(prints_folder, "g1a1_prevalence_35plus.png"),
       g1a1_prevalence_35plus, width = 8.5, height = 5.5, dpi = 300)


# ==============================================================================
# G2 FAMILY — Outcome Relationship
# Research question: How does each condition relate to days_absent_total?
# g2  : mean days absent by condition presence (dot plot)
# g21 : median + IQR by condition presence
# g22 : zero-proportion by condition presence
# ==============================================================================

# ---- g2-data-prep ------------------------------------------------------------
g2_data <- ds_cc_long %>%
  filter(!is.na(has_condition)) %>%
  group_by(condition, condition_label, has_condition) %>%
  summarise(
    n             = n(),
    mean_days     = weighted.mean(days_absent_total, w = .data[[weight_col]], na.rm = TRUE),
    median_days   = median(days_absent_total, na.rm = TRUE),
    q25           = quantile(days_absent_total, 0.25, na.rm = TRUE),
    q75           = quantile(days_absent_total, 0.75, na.rm = TRUE),
    pct_zero      = weighted.mean(days_absent_total == 0, w = .data[[weight_col]], na.rm = TRUE) * 100,
    .groups = "drop"
  )

# ---- g2 ---------------------------------------------------------------------
g2_mean_days <- g2_data %>%
  filter(has_condition == TRUE) %>%
  ggplot(aes(x = mean_days, y = fct_reorder(condition_label, mean_days))) +
  geom_point(size = 3, color = "#B22222") +
  geom_segment(aes(xend = 0, yend = condition_label), color = "#B22222", linewidth = 0.5) +
  labs(
    title    = "Mean Days Absent by Chronic Condition (Those WITH Condition)",
    subtitle = "Weighted mean of days_absent_total among respondents reporting the condition",
    x = "Weighted Mean Days Absent (past 3 months)",
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g2_mean_days)
ggsave(paste0(prints_folder, "g2_mean_days.png"),
       g2_mean_days, width = 8.5, height = 5.5, dpi = 300)

# ---- g21 --------------------------------------------------------------------
g21_median_iqr <- g2_data %>%
  filter(has_condition == TRUE) %>%
  ggplot(aes(y = fct_reorder(condition_label, median_days))) +
  geom_errorbarh(aes(xmin = q25, xmax = q75), height = 0.3, color = "grey50") +
  geom_point(aes(x = median_days), size = 3, color = "#8B008B") +
  labs(
    title    = "Median Days Absent (IQR) by Chronic Condition",
    subtitle = "Among respondents reporting the condition — unweighted quantiles",
    x = "Days Absent (past 3 months)",
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g21_median_iqr)
ggsave(paste0(prints_folder, "g21_median_iqr.png"),
       g21_median_iqr, width = 8.5, height = 5.5, dpi = 300)

# ---- g22 --------------------------------------------------------------------
g22_zero_prop <- g2_data %>%
  ggplot(aes(x = pct_zero, y = fct_reorder(condition_label, pct_zero),
             color = has_condition)) +
  geom_point(size = 3) +
  scale_color_manual(
    values = c("TRUE" = "#B22222", "FALSE" = "#4682B4"),
    labels = c("TRUE" = "Has condition", "FALSE" = "No condition")
  ) +
  labs(
    title    = "Zero-Day Proportion by Condition Status",
    subtitle = "Weighted proportion reporting zero days absent",
    x = "% Reporting Zero Days Absent",
    y = NULL,
    color = "Condition Status"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g22_zero_prop)
ggsave(paste0(prints_folder, "g22_zero_prop.png"),
       g22_zero_prop, width = 8.5, height = 5.5, dpi = 300)


# ==============================================================================
# G3 FAMILY — Missing Data Profile
# Research question: What is the missing-data pattern across 17 cc_* variables?
# g3  : missingness tile (variable × completeness)
# g31 : missingness by cycle
# ==============================================================================

# ---- g3-data-prep ------------------------------------------------------------
g3_data <- ds0 %>%
  summarise(
    across(all_of(cc_vars), ~ sum(is.na(.x)))
  ) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "n_missing") %>%
  mutate(
    label      = cc_labels[variable],
    pct_missing = n_missing / nrow(ds0) * 100
  ) %>%
  arrange(desc(pct_missing))

g3_by_cycle <- ds0 %>%
  group_by(cchs_cycle_f) %>%
  summarise(
    across(all_of(cc_vars), ~ sum(is.na(.x)) / n() * 100)
  ) %>%
  pivot_longer(-cchs_cycle_f, names_to = "variable", values_to = "pct_missing") %>%
  mutate(label = cc_labels[variable])

# ---- g3 ---------------------------------------------------------------------
g3_missing_tile <- g3_data %>%
  ggplot(aes(x = pct_missing, y = fct_reorder(label, pct_missing))) +
  geom_col(fill = "#FF6347", alpha = 0.7) +
  geom_text(aes(label = sprintf("%.1f%% (n=%s)", pct_missing, format(n_missing, big.mark = ","))),
            hjust = -0.1, size = 3) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.3))) +
  labs(
    title    = "Missing Data Profile: Chronic Condition Variables",
    subtitle = "Count and percentage of NA values per condition flag",
    x = "% Missing",
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g3_missing_tile)
ggsave(paste0(prints_folder, "g3_missing_tile.png"),
       g3_missing_tile, width = 8.5, height = 5.5, dpi = 300)

# ---- g31 --------------------------------------------------------------------
g31_missing_by_cycle <- g3_by_cycle %>%
  ggplot(aes(x = pct_missing, y = fct_reorder(label, pct_missing),
             fill = cchs_cycle_f)) +
  geom_col(position = "dodge", alpha = 0.7) +
  scale_fill_manual(values = c("2010-2011" = "#FF6347", "2013-2014" = "#FF8C00")) +
  labs(
    title    = "Missingness by CCHS Cycle",
    subtitle = "Percentage missing per condition, by cycle",
    x = "% Missing",
    y = NULL,
    fill = "Cycle"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g31_missing_by_cycle)
ggsave(paste0(prints_folder, "g31_missing_by_cycle.png"),
       g31_missing_by_cycle, width = 8.5, height = 5.5, dpi = 300)


# ==============================================================================
# G4 FAMILY — Multimorbidity / Co-occurrence
# Research question: What is the multimorbidity structure among respondents?
# g4  : condition-count distribution (bar chart)
# g41 : pairwise co-occurrence matrix (tile heatmap)
# ==============================================================================

# ---- g4-data-prep ------------------------------------------------------------
# Condition count distribution
g4_count_data <- ds_multimorbidity %>%
  group_by(n_conditions) %>%
  summarise(
    n           = n(),
    pct         = n() / nrow(ds_multimorbidity) * 100,
    pct_weighted = sum(.data[[weight_col]]) /
                   sum(ds_multimorbidity[[weight_col]]) * 100,
    .groups = "drop"
  )

# Pairwise co-occurrence matrix (treat NA as FALSE — condition not reported)
cc_matrix <- ds0 %>%
  select(all_of(cc_vars)) %>%
  mutate(across(everything(), ~ as.numeric(coalesce(.x, FALSE))))

n_complete <- nrow(cc_matrix)
co_occurrence <- crossprod(as.matrix(cc_matrix), as.matrix(cc_matrix))
diag(co_occurrence) <- 0
co_occurrence_pct <- co_occurrence / n_complete * 100

# Keep only lower triangle (unique pairs), rank by co-occurrence
g4_cooccur_long <- co_occurrence_pct %>%
  as.data.frame() %>%
  tibble::rownames_to_column("condition_1") %>%
  pivot_longer(-condition_1, names_to = "condition_2", values_to = "pct_cooccur") %>%
  filter(condition_1 < condition_2) %>%
  mutate(
    label_1 = cc_labels[condition_1],
    label_2 = cc_labels[condition_2],
    pair_label = paste0(label_1, " + ", label_2)
  ) %>%
  arrange(desc(pct_cooccur))

# ---- g4 ---------------------------------------------------------------------
g4_condition_count <- g4_count_data %>%
  ggplot(aes(x = factor(n_conditions), y = pct_weighted)) +
  geom_col(fill = "#6A5ACD", alpha = 0.8) +
  geom_text(aes(label = sprintf("%.1f%%", pct_weighted)), vjust = -0.3, size = 3) +
  labs(
    title    = "Multimorbidity: Number of Chronic Conditions per Respondent",
    subtitle = "Weighted population distribution",
    x = "Number of Chronic Conditions",
    y = "% of Population (weighted)"
  ) +
  theme_minimal(base_size = 11)
print(g4_condition_count)
ggsave(paste0(prints_folder, "g4_condition_count.png"),
       g4_condition_count, width = 8.5, height = 5.5, dpi = 300)

# ---- g41 --------------------------------------------------------------------
# Top 20 co-occurring condition pairs — dot plot ranked by % of sample
g41_top_pairs <- g4_cooccur_long %>%
  slice_head(n = 20) %>%
  mutate(pair_label = fct_reorder(pair_label, pct_cooccur))

g41_cooccurrence <- g41_top_pairs %>%
  ggplot(aes(x = pct_cooccur, y = pair_label)) +
  geom_point(size = 3, color = "#B22222") +
  geom_segment(aes(x = 0, xend = pct_cooccur, yend = pair_label),
               color = "#B22222", linewidth = 0.4) +
  geom_text(aes(label = sprintf("%.1f%%", pct_cooccur)),
            hjust = -0.3, size = 2.8) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title    = "Top 20 Co-occurring Chronic Condition Pairs",
    subtitle = "Percentage of sample reporting both conditions simultaneously",
    x = "Co-occurrence (% of sample)",
    y = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.major.y = element_blank())
print(g41_cooccurrence)
ggsave(paste0(prints_folder, "g41_cooccurrence.png"),
       g41_cooccurrence, width = 8.5, height = 5.5, dpi = 300)

# nolint end
