# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# EDA-64: Needs Variable Profile — Health Status & Functional Limitations (Andersen Model)
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
local_root    <- "./analysis/eda-64/"
local_data    <- paste0(local_root, "data-local/")
prints_folder <- paste0(local_root, "prints/")
data_private_derived <- "./data-private/derived/eda-64/"

if (!fs::dir_exists(local_data))           fs::dir_create(local_data)
if (!fs::dir_exists(prints_folder))        fs::dir_create(prints_folder)
if (!fs::dir_exists(data_private_derived)) fs::dir_create(data_private_derived)

path_cchs2_parquet  <- "./data-private/derived/cchs-2-tables"
path_analytical_pq  <- file.path(path_cchs2_parquet, "cchs_analytic.parquet")
weight_col          <- "wts_m_pooled"

# The 10 needs variables (perceived health and functional limitations)
needs_vars <- c(
  "health_perceived", "mental_health_perceived", "health_vs_prior_year",
  "injured_past_12m", "adl_meals", "adl_errands", "adl_housework",
  "adl_personal_care", "adl_moving_indoors", "adl_finances"
)

# The 6 ADL items (subset of needs_vars)
adl_vars <- c("adl_meals", "adl_errands", "adl_housework",
              "adl_personal_care", "adl_moving_indoors", "adl_finances")

# Human-readable labels for display
needs_labels <- c(
  "health_perceived"        = "Perceived health",
  "mental_health_perceived" = "Perceived mental health",
  "health_vs_prior_year"    = "Health vs. prior year",
  "injured_past_12m"        = "Injured past 12 months",
  "adl_meals"               = "ADL: Preparing meals",
  "adl_errands"             = "ADL: Running errands",
  "adl_housework"           = "ADL: Housework",
  "adl_personal_care"       = "ADL: Personal care",
  "adl_moving_indoors"      = "ADL: Moving indoors",
  "adl_finances"            = "ADL: Managing finances"
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
  needs_vars
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
    "10 needs variables (perceived health, ADL limitations),",
    "primary outcome days_absent_total, survey weight wts_m_pooled"
  )
)
print(data_context_tables)

# ---- data-context-person -----------------------------------------------------
# A respondent with some ADL limitations — shows the key columns
data_context_person <- ds0 %>%
  select(cchs_cycle_f, !!weight_col, days_absent_total, all_of(needs_vars)) %>%
  mutate(
    n_adl_limitations = rowSums(
      across(all_of(adl_vars), ~ as.numeric(. != "No" & !is.na(.))),
      na.rm = TRUE
    )
  ) %>%
  filter(n_adl_limitations >= 2) %>%
  select(-n_adl_limitations) %>%
  slice_head(n = 2)
print(data_context_person)

# ---- data-context-distributions ----------------------------------------------
# Level counts for each needs variable
data_context_distributions <- purrr::map_dfr(needs_vars, function(v) {
  tbl <- ds0 %>%
    count(value = as.character(.data[[v]])) %>%
    mutate(variable = v, label = needs_labels[v]) %>%
    arrange(desc(n))
  tbl
})
print(data_context_distributions, n = 40)

# ---- tweak-data-0 ------------------------------------------------------------
# Ensure factor types; create collapsed ADL summary
ds1 <- ds0 %>%
  select(
    cchs_cycle, cchs_cycle_f, !!weight_col,
    days_absent_total, days_absent_chronic,
    all_of(needs_vars)
  ) %>%
  mutate(
    across(where(is.character), ~ as.factor(.x)),
    # Collapsed ADL functional limitation count (number of ADL items with any limitation)
    adl_limitation_count = rowSums(
      across(all_of(adl_vars), ~ as.numeric(. != "No" & !is.na(.))),
      na.rm = TRUE
    ),
    has_any_adl_limitation = adl_limitation_count > 0
  )

# ---- inspect-data-0 ----------------------------------------------------------
cat(sprintf("Working dataset: %s rows, %s columns\n",
            format(nrow(ds1), big.mark = ","), ncol(ds1)))
cat("Variable types:\n")
purrr::walk(needs_vars, function(v) {
  cat(sprintf("  %-28s %s (levels: %d)\n", v, class(ds1[[v]])[1],
              length(unique(ds1[[v]]))))
})
cat(sprintf("\nADL limitation count — range: [%d, %d], mean: %.2f\n",
            min(ds1$adl_limitation_count),
            max(ds1$adl_limitation_count),
            mean(ds1$adl_limitation_count)))
cat(sprintf("Any ADL limitation: %.1f%%\n",
            mean(ds1$has_any_adl_limitation) * 100))


# ==============================================================================
# G1 FAMILY — Variable Distributions
# Research question: What is the weighted distribution of each needs variable?
# g1  : unweighted frequency bar chart (perceived health variables)
# g11 : ADL items — individual prevalence (weighted)
# g12 : weighted distribution stratified by CCHS cycle
# ==============================================================================

# ---- g1-data-prep ------------------------------------------------------------
# Perceived health variables (ordinal categories)
g1_health_vars <- c("health_perceived", "mental_health_perceived",
                    "health_vs_prior_year", "injured_past_12m")

g1_data <- purrr::map_dfr(g1_health_vars, function(v) {
  ds1 %>%
    filter(!is.na(.data[[v]])) %>%
    group_by(level = as.character(.data[[v]])) %>%
    summarise(
      n              = n(),
      pct_unweighted = n() / nrow(ds1) * 100,
      pct_weighted   = sum(.data[[weight_col]]) / sum(ds1[[weight_col]]) * 100,
      .groups = "drop"
    ) %>%
    mutate(variable = v, label = needs_labels[v])
})

# ADL items — proportion with any limitation (individual items)
g1_adl_data <- purrr::map_dfr(adl_vars, function(v) {
  ds1 %>%
    filter(!is.na(.data[[v]])) %>%
    mutate(has_limitation = as.character(.data[[v]]) != "No") %>%
    summarise(
      n_total          = n(),
      n_with_limit     = sum(has_limitation),
      pct_unweighted   = mean(has_limitation) * 100,
      pct_weighted     = weighted.mean(has_limitation, w = .data[[weight_col]]) * 100,
      .groups = "drop"
    ) %>%
    mutate(variable = v, label = needs_labels[v])
})

# ---- g1 ---------------------------------------------------------------------
g1_health_distribution <- g1_data %>%
  ggplot(aes(x = pct_weighted, y = level)) +
  geom_col(fill = "#4682B4", alpha = 0.8) +
  facet_wrap(~ label, scales = "free_y", ncol = 2) +
  labs(
    title    = "Weighted Distribution of Health Status Variables",
    subtitle = "Population-weighted proportion in each level (wts_m_pooled)",
    x = "Percentage (%)",
    y = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.major.y = element_blank())
print(g1_health_distribution)
ggsave(paste0(prints_folder, "g1_health_distribution.png"),
       g1_health_distribution, width = 10, height = 6, dpi = 300)

# ---- g11 --------------------------------------------------------------------
g11_adl_prevalence <- g1_adl_data %>%
  ggplot(aes(x = pct_weighted, y = fct_reorder(label, pct_weighted))) +
  geom_col(fill = "#2E8B57", alpha = 0.8) +
  geom_text(aes(label = sprintf("%.1f%%", pct_weighted)), hjust = -0.1, size = 3) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title    = "Weighted Prevalence of ADL Limitations (Individual Items)",
    subtitle = "Proportion reporting any limitation in each ADL domain",
    x = "Prevalence (%)",
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g11_adl_prevalence)
ggsave(paste0(prints_folder, "g11_adl_prevalence.png"),
       g11_adl_prevalence, width = 8.5, height = 5.5, dpi = 300)

# ---- g12 --------------------------------------------------------------------
g12_data <- purrr::map_dfr(g1_health_vars, function(v) {
  ds1 %>%
    filter(!is.na(.data[[v]])) %>%
    group_by(level = as.character(.data[[v]]), cchs_cycle_f) %>%
    summarise(
      pct_weighted = sum(.data[[weight_col]]) /
        sum(ds1[[weight_col]][ds1$cchs_cycle_f == unique(cchs_cycle_f)]) * 100,
      .groups = "drop"
    ) %>%
    mutate(variable = v, label = needs_labels[v])
})

g12_by_cycle <- g12_data %>%
  ggplot(aes(x = pct_weighted, y = level, fill = cchs_cycle_f)) +
  geom_col(position = "dodge", alpha = 0.8) +
  facet_wrap(~ label, scales = "free_y", ncol = 2) +
  scale_fill_manual(values = c("2010-2011" = "#4682B4", "2013-2014" = "#CD853F")) +
  labs(
    title    = "Weighted Distribution by CCHS Cycle",
    subtitle = "Comparing 2010-2011 vs 2013-2014 cycles",
    x = "Percentage (%)",
    y = NULL,
    fill = "Cycle"
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.major.y = element_blank())
print(g12_by_cycle)
ggsave(paste0(prints_folder, "g12_by_cycle.png"),
       g12_by_cycle, width = 10, height = 6, dpi = 300)


# ==============================================================================
# G2 FAMILY — Outcome Relationship
# Research question: How does each needs variable relate to days_absent_total?
# g2  : mean days absent by health status level (dot plot)
# g21 : mean days absent by ADL limitation count (collapsed summary)
# g22 : zero-proportion by perceived health level
# ==============================================================================

# ---- g2-data-prep ------------------------------------------------------------
g2_data <- purrr::map_dfr(g1_health_vars, function(v) {
  ds1 %>%
    filter(!is.na(.data[[v]])) %>%
    group_by(level = as.character(.data[[v]])) %>%
    summarise(
      n           = n(),
      mean_days   = weighted.mean(days_absent_total, w = .data[[weight_col]], na.rm = TRUE),
      median_days = median(days_absent_total, na.rm = TRUE),
      q25         = quantile(days_absent_total, 0.25, na.rm = TRUE),
      q75         = quantile(days_absent_total, 0.75, na.rm = TRUE),
      pct_zero    = weighted.mean(days_absent_total == 0, w = .data[[weight_col]], na.rm = TRUE) * 100,
      .groups = "drop"
    ) %>%
    mutate(variable = v, label = needs_labels[v])
})

# ADL limitation count — collapsed summary
g2_adl_count <- ds1 %>%
  group_by(adl_limitation_count) %>%
  summarise(
    n         = n(),
    mean_days = weighted.mean(days_absent_total, w = .data[[weight_col]], na.rm = TRUE),
    pct_zero  = weighted.mean(days_absent_total == 0, w = .data[[weight_col]], na.rm = TRUE) * 100,
    .groups = "drop"
  )

# ---- g2 ---------------------------------------------------------------------
g2_mean_days <- g2_data %>%
  ggplot(aes(x = mean_days, y = level)) +
  geom_point(size = 2.5, color = "#B22222") +
  geom_segment(aes(xend = 0, yend = level), color = "#B22222", linewidth = 0.4) +
  facet_wrap(~ label, scales = "free_y", ncol = 2) +
  labs(
    title    = "Mean Days Absent by Health Status Variable Level",
    subtitle = "Weighted mean of days_absent_total",
    x = "Weighted Mean Days Absent",
    y = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.major.y = element_blank())
print(g2_mean_days)
ggsave(paste0(prints_folder, "g2_mean_days.png"),
       g2_mean_days, width = 10, height = 6, dpi = 300)

# ---- g21 --------------------------------------------------------------------
g21_adl_count <- g2_adl_count %>%
  ggplot(aes(x = factor(adl_limitation_count), y = mean_days)) +
  geom_col(fill = "#8B008B", alpha = 0.8) +
  geom_text(aes(label = sprintf("%.1f", mean_days)), vjust = -0.3, size = 3.5) +
  labs(
    title    = "Mean Days Absent by Number of ADL Limitations",
    subtitle = "Collapsed functional limitation summary (0 to 6 items)",
    x = "Number of ADL Limitations",
    y = "Weighted Mean Days Absent"
  ) +
  theme_minimal(base_size = 11)
print(g21_adl_count)
ggsave(paste0(prints_folder, "g21_adl_count.png"),
       g21_adl_count, width = 8.5, height = 5.5, dpi = 300)

# ---- g22 --------------------------------------------------------------------
g22_data <- g2_data %>%
  filter(variable == "health_perceived")

g22_zero_by_health <- g22_data %>%
  ggplot(aes(x = pct_zero, y = level)) +
  geom_point(size = 3, color = "#4682B4") +
  geom_segment(aes(xend = 0, yend = level), color = "#4682B4", linewidth = 0.5) +
  labs(
    title    = "Zero-Day Proportion by Perceived Health Level",
    subtitle = "Weighted proportion reporting zero days absent",
    x = "% Reporting Zero Days Absent",
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g22_zero_by_health)
ggsave(paste0(prints_folder, "g22_zero_by_health.png"),
       g22_zero_by_health, width = 8.5, height = 5.5, dpi = 300)


# ==============================================================================
# G3 FAMILY — Missing Data Profile
# Research question: What is the missing-data pattern across needs variables?
# g3  : missingness bar chart
# g31 : missingness by cycle
# ==============================================================================

# ---- g3-data-prep ------------------------------------------------------------
g3_data <- ds0 %>%
  summarise(across(all_of(needs_vars), ~ sum(is.na(.x)))) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "n_missing") %>%
  mutate(
    label       = needs_labels[variable],
    pct_missing = n_missing / nrow(ds0) * 100
  ) %>%
  arrange(desc(pct_missing))

g3_by_cycle <- ds0 %>%
  group_by(cchs_cycle_f) %>%
  summarise(across(all_of(needs_vars), ~ sum(is.na(.x)) / n() * 100)) %>%
  pivot_longer(-cchs_cycle_f, names_to = "variable", values_to = "pct_missing") %>%
  mutate(label = needs_labels[variable])

# ---- g3 ---------------------------------------------------------------------
g3_missing <- g3_data %>%
  ggplot(aes(x = pct_missing, y = fct_reorder(label, pct_missing))) +
  geom_col(fill = "#FF6347", alpha = 0.7) +
  geom_text(aes(label = sprintf("%.1f%% (n=%s)", pct_missing, format(n_missing, big.mark = ","))),
            hjust = -0.1, size = 3) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.3))) +
  labs(
    title    = "Missing Data Profile: Needs Variables",
    subtitle = "Count and percentage of NA values per variable",
    x = "% Missing",
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g3_missing)
ggsave(paste0(prints_folder, "g3_missing.png"),
       g3_missing, width = 8.5, height = 5.5, dpi = 300)

# ---- g31 --------------------------------------------------------------------
g31_missing_by_cycle <- g3_by_cycle %>%
  ggplot(aes(x = pct_missing, y = fct_reorder(label, pct_missing),
             fill = cchs_cycle_f)) +
  geom_col(position = "dodge", alpha = 0.7) +
  scale_fill_manual(values = c("2010-2011" = "#FF6347", "2013-2014" = "#FF8C00")) +
  labs(
    title    = "Missingness by CCHS Cycle",
    subtitle = "Percentage missing per needs variable, by cycle",
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
# G4 FAMILY — Health Gradient / ADL Stacking
# Research question: What health gradient patterns exist?
# g4  : perceived health × ADL limitation count (mean days absent)
# g41 : ADL limitation stacking — which items co-occur
# ==============================================================================

# ---- g4-data-prep ------------------------------------------------------------
g4_health_adl <- ds1 %>%
  filter(!is.na(health_perceived)) %>%
  group_by(health_perceived, adl_limitation_count) %>%
  summarise(
    n         = n(),
    mean_days = weighted.mean(days_absent_total, w = .data[[weight_col]], na.rm = TRUE),
    .groups = "drop"
  )

# ADL stacking: which individual items co-occur
g4_adl_cooccur <- ds1 %>%
  mutate(across(all_of(adl_vars), ~ as.numeric(as.character(.) != "No" & !is.na(.)))) %>%
  select(all_of(adl_vars))

adl_co_matrix <- crossprod(as.matrix(g4_adl_cooccur), as.matrix(g4_adl_cooccur))
diag(adl_co_matrix) <- 0
adl_co_pct <- adl_co_matrix / nrow(g4_adl_cooccur) * 100

g4_adl_cooccur_long <- adl_co_pct %>%
  as.data.frame() %>%
  tibble::rownames_to_column("adl_1") %>%
  pivot_longer(-adl_1, names_to = "adl_2", values_to = "pct_cooccur") %>%
  mutate(
    label_1 = needs_labels[adl_1],
    label_2 = needs_labels[adl_2]
  )

# ---- g4 ---------------------------------------------------------------------
g4_health_adl_plot <- g4_health_adl %>%
  filter(adl_limitation_count <= 4) %>%
  ggplot(aes(x = health_perceived, y = mean_days,
             fill = factor(adl_limitation_count))) +
  geom_col(position = "dodge", alpha = 0.8) +
  labs(
    title    = "Mean Days Absent: Perceived Health × ADL Limitation Count",
    subtitle = "Health gradient with functional limitation stacking",
    x = "Perceived Health",
    y = "Weighted Mean Days Absent",
    fill = "ADL\nLimitations"
  ) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))
print(g4_health_adl_plot)
ggsave(paste0(prints_folder, "g4_health_adl.png"),
       g4_health_adl_plot, width = 8.5, height = 5.5, dpi = 300)

# ---- g41 --------------------------------------------------------------------
g41_adl_cooccurrence <- g4_adl_cooccur_long %>%
  ggplot(aes(x = label_1, y = label_2, fill = pct_cooccur)) +
  geom_tile(color = "white", linewidth = 0.5) +
  scale_fill_gradient(low = "white", high = "#8B008B",
                      name = "Co-occurrence\n(% of sample)") +
  labs(
    title    = "ADL Limitation Co-occurrence Matrix",
    subtitle = "Percentage of sample reporting limitations in both items simultaneously",
    x = NULL, y = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    panel.grid  = element_blank()
  )
print(g41_adl_cooccurrence)
ggsave(paste0(prints_folder, "g41_adl_cooccurrence.png"),
       g41_adl_cooccurrence, width = 8.5, height = 6, dpi = 300)

# nolint end
