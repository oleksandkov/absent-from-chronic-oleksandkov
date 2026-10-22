# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# EDA-63: Facilitating Variable Profile — Access & Behaviours (Andersen Model)
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
local_root    <- "./analysis/eda-63/"
local_data    <- paste0(local_root, "data-local/")
prints_folder <- paste0(local_root, "prints/")
data_private_derived <- "./data-private/derived/eda-63/"

if (!fs::dir_exists(local_data))           fs::dir_create(local_data)
if (!fs::dir_exists(prints_folder))        fs::dir_create(prints_folder)
if (!fs::dir_exists(data_private_derived)) fs::dir_create(data_private_derived)

path_cchs2_parquet  <- "./data-private/derived/cchs-2-tables"
path_analytical_pq  <- file.path(path_cchs2_parquet, "cchs_analytic.parquet")
weight_col          <- "wts_m_pooled"

# The 12 facilitating variables (access and health behaviours)
facilitating_vars <- c(
  "income_hh", "province", "has_family_doctor", "employment_type",
  "work_schedule", "occupation_category", "smoking_status",
  "bmi_category", "physical_activity", "alcohol_type",
  "fruit_veg_daily", "work_stress"
)

# Human-readable labels for display
facilitating_labels <- c(
  "income_hh"           = "Household income",
  "province"            = "Province",
  "has_family_doctor"   = "Has family doctor",
  "employment_type"     = "Employment type",
  "work_schedule"       = "Work schedule",
  "occupation_category" = "Occupation category",
  "smoking_status"      = "Smoking status",
  "bmi_category"        = "BMI category",
  "physical_activity"   = "Physical activity level",
  "alcohol_type"        = "Alcohol consumption type",
  "fruit_veg_daily"     = "Fruit/vegetable daily servings",
  "work_stress"         = "Work stress"
)

# Regional grouping for province (used in G2 and G4)
# Keys must match Ellis-coded abbreviations in cchs_analytic.parquet
province_regions <- c(
  "NL"  = "Atlantic",
  "PEI" = "Atlantic",
  "NS"  = "Atlantic",
  "NB"  = "Atlantic",
  "QC"  = "Quebec",
  "ON"  = "Ontario",
  "MB"  = "Prairies",
  "SK"  = "Prairies",
  "AB"  = "Prairies",
  "BC"  = "British Columbia",
  "YK"  = "Territories",
  "NT"  = "Territories",
  "NU"  = "Territories"
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
  facilitating_vars
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
    "12 facilitating variables (access, behaviours, work context),",
    "primary outcome days_absent_total, survey weight wts_m_pooled"
  )
)
print(data_context_tables)

# ---- data-context-person -----------------------------------------------------
data_context_person <- ds0 %>%
  select(cchs_cycle_f, !!weight_col, days_absent_total, all_of(facilitating_vars)) %>%
  slice_head(n = 2)
print(data_context_person)

# ---- data-context-distributions ----------------------------------------------
# Level counts for each facilitating variable
data_context_distributions <- purrr::map_dfr(facilitating_vars, function(v) {
  tbl <- ds0 %>%
    count(value = as.character(.data[[v]])) %>%
    mutate(variable = v, label = facilitating_labels[v]) %>%
    arrange(desc(n))
  tbl
})
print(data_context_distributions, n = 50)

# ---- tweak-data-0 ------------------------------------------------------------
# Ensure factor types; add regional grouping for province
ds1 <- ds0 %>%
  select(
    cchs_cycle, cchs_cycle_f, !!weight_col,
    days_absent_total, days_absent_chronic,
    all_of(facilitating_vars)
  ) %>%
  mutate(
    across(where(is.character), ~ as.factor(.x)),
    province_region = factor(province_regions[as.character(province)],
                             levels = c("Atlantic", "Quebec", "Ontario",
                                        "Prairies", "British Columbia", "Territories"))
  )

# ---- inspect-data-0 ----------------------------------------------------------
cat(sprintf("Working dataset: %s rows, %s columns\n",
            format(nrow(ds1), big.mark = ","), ncol(ds1)))
cat("Variable types:\n")
purrr::walk(facilitating_vars, function(v) {
  cat(sprintf("  %-22s %s (levels: %d)\n", v, class(ds1[[v]])[1],
              length(unique(ds1[[v]]))))
})


# ==============================================================================
# G1 FAMILY — Variable Distributions
# Research question: What is the weighted distribution of each facilitating variable?
# g1  : unweighted frequency bar chart (select key variables)
# g11 : weighted frequency bar chart
# g12 : weighted distribution stratified by CCHS cycle
# ==============================================================================

# ---- g1-data-prep ------------------------------------------------------------
# Variables with manageable levels for faceted bar chart
g1_vars <- c("income_hh", "has_family_doctor", "employment_type",
             "smoking_status", "bmi_category", "physical_activity",
             "alcohol_type", "work_stress")

g1_data <- purrr::map_dfr(g1_vars, function(v) {
  ds1 %>%
    filter(!is.na(.data[[v]])) %>%
    group_by(level = as.character(.data[[v]])) %>%
    summarise(
      n              = n(),
      pct_unweighted = n() / nrow(ds1) * 100,
      pct_weighted   = sum(.data[[weight_col]]) / sum(ds1[[weight_col]]) * 100,
      .groups = "drop"
    ) %>%
    mutate(variable = v, label = facilitating_labels[v])
})

# Province separately (13 levels — horizontal bars sorted by prevalence)
g1_province <- ds1 %>%
  filter(!is.na(province)) %>%
  group_by(level = as.character(province)) %>%
  summarise(
    n              = n(),
    pct_unweighted = n() / nrow(ds1) * 100,
    pct_weighted   = sum(.data[[weight_col]]) / sum(ds1[[weight_col]]) * 100,
    .groups = "drop"
  )

# ---- g1 ---------------------------------------------------------------------
g1_distribution <- g1_data %>%
  ggplot(aes(x = pct_unweighted, y = level)) +
  geom_col(fill = "#4682B4", alpha = 0.8) +
  facet_wrap(~ label, scales = "free_y", ncol = 2) +
  labs(
    title    = "Unweighted Distribution of Facilitating Variables",
    subtitle = "Proportion of analytical sample in each level",
    x = "Percentage (%)",
    y = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.major.y = element_blank())
print(g1_distribution)
ggsave(paste0(prints_folder, "g1_distribution.png"),
       g1_distribution, width = 10, height = 8, dpi = 300)

# ---- g11 --------------------------------------------------------------------
g11_province <- g1_province %>%
  ggplot(aes(x = pct_weighted, y = fct_reorder(level, pct_weighted))) +
  geom_col(fill = "#2E8B57", alpha = 0.8) +
  geom_text(aes(label = sprintf("%.1f%%", pct_weighted)), hjust = -0.1, size = 3) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title    = "Weighted Distribution: Province",
    subtitle = "Population-weighted proportion by province (wts_m_pooled)",
    x = "Percentage (%)",
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g11_province)
ggsave(paste0(prints_folder, "g11_province.png"),
       g11_province, width = 8.5, height = 5.5, dpi = 300)

# ---- g12 --------------------------------------------------------------------
g12_data <- purrr::map_dfr(g1_vars, function(v) {
  ds1 %>%
    filter(!is.na(.data[[v]])) %>%
    group_by(level = as.character(.data[[v]]), cchs_cycle_f) %>%
    summarise(
      pct_weighted = sum(.data[[weight_col]]) /
        sum(ds1[[weight_col]][ds1$cchs_cycle_f == unique(cchs_cycle_f)]) * 100,
      .groups = "drop"
    ) %>%
    mutate(variable = v, label = facilitating_labels[v])
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
       g12_by_cycle, width = 10, height = 8, dpi = 300)


# ==============================================================================
# G2 FAMILY — Outcome Relationship
# Research question: How does each facilitating variable relate to days_absent_total?
# g2  : mean days absent by variable level (dot plot)
# g21 : mean days by province (granular) — horizontal bars sorted by value
# g22 : mean days by region (grouped) — bar chart
# ==============================================================================

# ---- g2-data-prep ------------------------------------------------------------
g2_data <- purrr::map_dfr(g1_vars, function(v) {
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
    mutate(variable = v, label = facilitating_labels[v])
})

g2_province <- ds1 %>%
  filter(!is.na(province)) %>%
  group_by(level = as.character(province)) %>%
  summarise(
    n         = n(),
    mean_days = weighted.mean(days_absent_total, w = .data[[weight_col]], na.rm = TRUE),
    pct_zero  = weighted.mean(days_absent_total == 0, w = .data[[weight_col]], na.rm = TRUE) * 100,
    .groups = "drop"
  )

g2_region <- ds1 %>%
  filter(!is.na(province_region)) %>%
  group_by(level = as.character(province_region)) %>%
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
    title    = "Mean Days Absent by Facilitating Variable Level",
    subtitle = "Weighted mean of days_absent_total",
    x = "Weighted Mean Days Absent",
    y = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.major.y = element_blank())
print(g2_mean_days)
ggsave(paste0(prints_folder, "g2_mean_days.png"),
       g2_mean_days, width = 10, height = 8, dpi = 300)

# ---- g21 --------------------------------------------------------------------
g21_province <- g2_province %>%
  ggplot(aes(x = mean_days, y = fct_reorder(level, mean_days))) +
  geom_point(size = 3, color = "#B22222") +
  geom_segment(aes(xend = 0, yend = fct_reorder(level, mean_days)),
               color = "#B22222", linewidth = 0.5) +
  labs(
    title    = "Mean Days Absent by Province",
    subtitle = "Weighted mean of days_absent_total — all 13 provinces/territories",
    x = "Weighted Mean Days Absent",
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g21_province)
ggsave(paste0(prints_folder, "g21_province.png"),
       g21_province, width = 8.5, height = 5.5, dpi = 300)

# ---- g22 --------------------------------------------------------------------
g22_region <- g2_region %>%
  ggplot(aes(x = mean_days, y = fct_reorder(level, mean_days))) +
  geom_col(fill = "#4682B4", alpha = 0.8) +
  geom_text(aes(label = sprintf("%.2f", mean_days)), hjust = -0.1, size = 3.5) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title    = "Mean Days Absent by Region",
    subtitle = "Provinces grouped into regions — weighted mean",
    x = "Weighted Mean Days Absent",
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())
print(g22_region)
ggsave(paste0(prints_folder, "g22_region.png"),
       g22_region, width = 8.5, height = 5.5, dpi = 300)


# ==============================================================================
# G3 FAMILY — Missing Data Profile
# Research question: What is the missing-data pattern across facilitating variables?
# g3  : missingness bar chart
# g31 : missingness by cycle
# ==============================================================================

# ---- g3-data-prep ------------------------------------------------------------
g3_data <- ds0 %>%
  summarise(across(all_of(facilitating_vars), ~ sum(is.na(.x)))) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "n_missing") %>%
  mutate(
    label       = facilitating_labels[variable],
    pct_missing = n_missing / nrow(ds0) * 100
  ) %>%
  arrange(desc(pct_missing))

g3_by_cycle <- ds0 %>%
  group_by(cchs_cycle_f) %>%
  summarise(across(all_of(facilitating_vars), ~ sum(is.na(.x)) / n() * 100)) %>%
  pivot_longer(-cchs_cycle_f, names_to = "variable", values_to = "pct_missing") %>%
  mutate(label = facilitating_labels[variable])

# ---- g3 ---------------------------------------------------------------------
g3_missing <- g3_data %>%
  ggplot(aes(x = pct_missing, y = fct_reorder(label, pct_missing))) +
  geom_col(fill = "#FF6347", alpha = 0.7) +
  geom_text(aes(label = sprintf("%.1f%% (n=%s)", pct_missing, format(n_missing, big.mark = ","))),
            hjust = -0.1, size = 3) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.3))) +
  labs(
    title    = "Missing Data Profile: Facilitating Variables",
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
    subtitle = "Percentage missing per facilitating variable, by cycle",
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
# G4 FAMILY — Behaviour Clustering
# Research question: What behaviour clustering patterns exist?
# g4  : smoking × BMI cross-tab (mean days absent)
# g41 : smoking × physical activity cross-tab
# ==============================================================================

# ---- g4-data-prep ------------------------------------------------------------
g4_smoke_bmi <- ds1 %>%
  filter(!is.na(smoking_status), !is.na(bmi_category)) %>%
  group_by(smoking_status, bmi_category) %>%
  summarise(
    n         = n(),
    mean_days = weighted.mean(days_absent_total, w = .data[[weight_col]], na.rm = TRUE),
    pct_zero  = weighted.mean(days_absent_total == 0, w = .data[[weight_col]], na.rm = TRUE) * 100,
    .groups = "drop"
  )

g4_smoke_activity <- ds1 %>%
  filter(!is.na(smoking_status), !is.na(physical_activity)) %>%
  group_by(smoking_status, physical_activity) %>%
  summarise(
    n         = n(),
    mean_days = weighted.mean(days_absent_total, w = .data[[weight_col]], na.rm = TRUE),
    pct_zero  = weighted.mean(days_absent_total == 0, w = .data[[weight_col]], na.rm = TRUE) * 100,
    .groups = "drop"
  )

# ---- g4 ---------------------------------------------------------------------
g4_smoke_bmi_plot <- g4_smoke_bmi %>%
  ggplot(aes(x = smoking_status, y = mean_days, fill = bmi_category)) +
  geom_col(position = "dodge", alpha = 0.8) +
  labs(
    title    = "Mean Days Absent: Smoking Status × BMI Category",
    subtitle = "Weighted mean of days_absent_total",
    x = "Smoking Status",
    y = "Weighted Mean Days Absent",
    fill = "BMI Category"
  ) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))
print(g4_smoke_bmi_plot)
ggsave(paste0(prints_folder, "g4_smoke_bmi.png"),
       g4_smoke_bmi_plot, width = 8.5, height = 5.5, dpi = 300)

# ---- g41 --------------------------------------------------------------------
g41_smoke_activity_plot <- g4_smoke_activity %>%
  ggplot(aes(x = smoking_status, y = mean_days, fill = physical_activity)) +
  geom_col(position = "dodge", alpha = 0.8) +
  labs(
    title    = "Mean Days Absent: Smoking Status × Physical Activity",
    subtitle = "Weighted mean of days_absent_total",
    x = "Smoking Status",
    y = "Weighted Mean Days Absent",
    fill = "Physical Activity"
  ) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))
print(g41_smoke_activity_plot)
ggsave(paste0(prints_folder, "g41_smoke_activity.png"),
       g41_smoke_activity_plot, width = 8.5, height = 5.5, dpi = 300)

# nolint end
