# nolint start
rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014")                      # Clear the console
cat("Working directory: ", getwd())

# ---- load-packages -----------------------------------------------------------
library(magrittr)
library(ggplot2)
library(dplyr)
library(tidyr)
library(forcats)
library(stringr)
library(scales)
library(arrow)
library(fs)

# httpgd for VS Code interactive plots (optional)
if (requireNamespace("httpgd", quietly = TRUE)) {
  tryCatch({
    if (is.function(httpgd::hgd)) httpgd::hgd() else httpgd::httpgd()
    message("httpgd started.")
  }, error = function(e) message("httpgd failed: ", conditionMessage(e)))
} else {
  message("httpgd not installed. Plots will use default device.")
}

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R")
base::source("./scripts/operational-functions.R")

# ---- declare-globals ---------------------------------------------------------
local_root    <- "./analysis/binder-2/"
local_data    <- paste0(local_root, "data-local/")
prints_folder <- paste0(local_root, "prints/")

if (!fs::dir_exists(local_data))    fs::dir_create(local_data)
if (!fs::dir_exists(prints_folder)) fs::dir_create(prints_folder)

# Wong colorblind-safe palette
clr <- c(
  orange    = "#E69F00",
  sky_blue  = "#56B4E9",
  green     = "#009E73",
  yellow    = "#F0E442",
  blue      = "#0072B2",
  vermillon = "#D55E00",
  pink      = "#CC79A7"
)

# Domain classification for all 62 cchs_analytical columns
domain_map <- tribble(
  ~varname,               ~domain,
  # Outcome
  "days_absent_total",    "Outcome",
  "days_absent_chronic",  "Outcome",
  "outcome_all_na",       "Outcome",
  "lopg040",              "Outcome",
  "lopg045",              "Outcome",
  "lopg050",              "Outcome",
  "lopg055",              "Outcome",
  "lopg060",              "Outcome",
  "lopg065",              "Outcome",
  "lopg070",              "Outcome",
  "lopg100",              "Outcome",
  # Chronic conditions
  "cc_asthma",            "Chronic Condition",
  "cc_fibromyalgia",      "Chronic Condition",
  "cc_arthritis",         "Chronic Condition",
  "cc_back_problems",     "Chronic Condition",
  "cc_hypertension",      "Chronic Condition",
  "cc_migraine",          "Chronic Condition",
  "cc_copd",              "Chronic Condition",
  "cc_diabetes",          "Chronic Condition",
  "cc_heart_disease",     "Chronic Condition",
  "cc_cancer",            "Chronic Condition",
  "cc_ulcer",             "Chronic Condition",
  "cc_stroke",            "Chronic Condition",
  "cc_bowel_disorder",    "Chronic Condition",
  "cc_chronic_fatigue",   "Chronic Condition",
  "cc_chemical_sensitiv", "Chronic Condition",
  "cc_mood_disorder",     "Chronic Condition",
  "cc_anxiety_disorder",  "Chronic Condition",
  # Predisposing predictors
  "age_group",            "Predisposing",
  "sex",                  "Predisposing",
  "marital_status",       "Predisposing",
  "education",            "Predisposing",
  "immigration_status",   "Predisposing",
  "visible_minority",     "Predisposing",
  "homeownership",        "Predisposing",
  "student_status",       "Predisposing",
  "dhhdghsz",             "Predisposing",
  # Facilitating predictors
  "income_5cat",          "Facilitating",
  "has_family_doctor",    "Facilitating",
  "employment_type",      "Facilitating",
  "work_schedule",        "Facilitating",
  "smoking_status",       "Facilitating",
  "physical_activity",    "Facilitating",
  "job_stress",           "Facilitating",
  "alcohol_type",         "Facilitating",
  "bmi_category",         "Facilitating",
  "occupation_category",  "Facilitating",
  "geodgprv",             "Facilitating",
  "fvcdgtot",             "Facilitating",
  # Needs / health status
  "self_health_general",  "Needs",
  "self_health_mental",   "Needs",
  "health_vs_lastyear",   "Needs",
  "activity_limitation",  "Needs",
  "injury_past_year",     "Needs",
  # Survey design
  "wts_m_pooled",         "Survey Design",
  "wts_m_original",       "Survey Design",
  "geodpmf",              "Survey Design",
  "cycle",                "Survey Design",
  "cycle_f",              "Survey Design"
)

# ---- declare-functions -------------------------------------------------------
classify_var_type <- function(x) {
  if (is.ordered(x))  return("Ordered factor")
  if (is.factor(x))   return("Nominal factor")
  if (is.logical(x))  return("Logical")
  if (is.integer(x))  return("Integer")
  if (is.numeric(x))  return("Numeric")
  return("Other")
}

# ---- load-data ---------------------------------------------------------------
path_parquet <- "./data-private/derived/cchs-2-tables/cchs_analytical.parquet"
ds0 <- arrow::read_parquet(path_parquet)

message("Data loaded: ", nrow(ds0), " rows x ", ncol(ds0), " columns")

# ---- tweak-data-0 ------------------------------------------------------------
# No global tweaks — each graph family operates on its own derived view.

# ---- data-context-tables -----------------------------------------------------
cat("\nTable: cchs_analytical.parquet\n")
cat("  Grain : one row per survey respondent\n")
cat("  Rows  :", nrow(ds0), "\n")
cat("  Columns:", ncol(ds0), "\n\n")
cat("Cycle distribution (unweighted):\n")
ds0 %>%
  count(cycle_f) %>%
  mutate(pct = scales::percent(n / sum(n), accuracy = 0.1)) %>%
  print()

# ---- data-context-person -----------------------------------------------------
cat("\nRepresentative respondent — one row per cycle:\n")
ds0 %>%
  group_by(cycle_f) %>%
  slice(1) %>%
  ungroup() %>%
  select(cycle_f, age_group, sex, education, income_5cat,
         days_absent_total, wts_m_pooled) %>%
  print()

# ---- data-context-distributions ----------------------------------------------
cat("\nColumn completeness summary across all 62 variables:\n")
ds0 %>%
  summarise(across(everything(), ~ mean(!is.na(.)))) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "pct_complete") %>%
  summarise(
    n_fully_complete = sum(pct_complete == 1),
    n_all_na         = sum(pct_complete == 0),
    n_partial        = sum(pct_complete > 0 & pct_complete < 1)
  ) %>%
  print()

# ---- g1-data-prep ------------------------------------------------------------
# Completeness + domain classification for every column in ds0
g1_data <- ds0 %>%
  summarise(across(everything(), ~ mean(!is.na(.)))) %>%
  pivot_longer(everything(), names_to = "varname", values_to = "pct_complete") %>%
  left_join(domain_map, by = "varname") %>%
  mutate(
    domain  = replace_na(domain, "Other"),
    domain  = factor(domain, levels = c("Outcome", "Chronic Condition",
                                        "Predisposing", "Facilitating",
                                        "Needs", "Survey Design", "Other")),
    varname = fct_reorder2(varname, domain, pct_complete)
  )

domain_palette <- c(
  "Outcome"          = clr["orange"],
  "Chronic Condition"= clr["green"],
  "Predisposing"     = clr["sky_blue"],
  "Facilitating"     = clr["blue"],
  "Needs"            = clr["pink"],
  "Survey Design"    = clr["vermillon"],
  "Other"            = "grey70"
)

# ---- g1 ----------------------------------------------------------------------
# All 62 variables, grouped by domain, coloured by completeness
g1_variable_map <- g1_data %>%
  ggplot(aes(x = pct_complete, y = varname, fill = domain)) +
  geom_col(width = 0.7) +
  scale_x_continuous(
    labels = scales::percent_format(accuracy = 1),
    limits = c(0, 1),
    expand = expansion(mult = c(0, 0.03))
  ) +
  scale_fill_manual(values = domain_palette) +
  labs(
    title   = "cchs_analytical: variable completeness by analytical domain",
    subtitle = "White/empty bars = ALL-NA (PUMF-suppressed variables)",
    x       = "% Non-missing",
    y       = NULL,
    fill    = "Domain",
    caption = "Source: Ellis lane → cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "right",
        axis.text.y    = element_text(size = 7))

ggsave(paste0(prints_folder, "g1_variable_map.png"),
       g1_variable_map, width = 8.5, height = 11, dpi = 300)
print(g1_variable_map)

# ---- g11 ---------------------------------------------------------------------
# Same data, re-sorted by completeness only — surfaces PUMF gaps at the bottom
g11_missing_ranked <- g1_data %>%
  ggplot(aes(x = pct_complete,
             y = fct_reorder(varname, pct_complete),
             fill = domain)) +
  geom_col(width = 0.7) +
  scale_x_continuous(
    labels = scales::percent_format(accuracy = 1),
    limits = c(0, 1),
    expand = expansion(mult = c(0, 0.03))
  ) +
  scale_fill_manual(values = domain_palette) +
  labs(
    title   = "Variables ranked by completeness — PUMF gaps cluster at the bottom",
    subtitle = "Any bar at 0% is suppressed in the public-use microdata file",
    x       = "% Non-missing",
    y       = NULL,
    fill    = "Domain",
    caption = "Source: Ellis lane → cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "right",
        axis.text.y    = element_text(size = 7))

ggsave(paste0(prints_folder, "g11_missing_ranked.png"),
       g11_missing_ranked, width = 8.5, height = 11, dpi = 300)
print(g11_missing_ranked)

# ---- g2-data-prep ------------------------------------------------------------
# Cycle obs count + weighted population estimates
g2_data <- ds0 %>%
  group_by(cycle_f) %>%
  summarise(
    n_obs     = n(),
    n_pct     = n() / nrow(ds0),
    wt_sum    = sum(wts_m_pooled, na.rm = TRUE),
    wt_pct    = wt_sum / sum(ds0$wts_m_pooled, na.rm = TRUE),
    .groups   = "drop"
  )

# ---- g2 ----------------------------------------------------------------------
# Observed sample size by cycle
g2_sample_by_cycle <- g2_data %>%
  ggplot(aes(x = cycle_f, y = n_obs, fill = cycle_f)) +
  geom_col(width = 0.5, show.legend = FALSE) +
  geom_text(aes(label = scales::comma(n_obs)), vjust = -0.4, size = 4.5) +
  scale_y_continuous(
    labels = scales::comma,
    expand = expansion(mult = c(0, 0.14))
  ) +
  scale_fill_manual(values = c(clr["sky_blue"], clr["orange"])) +
  labs(
    title   = "Unweighted sample size by survey cycle",
    subtitle = "Pooled dataset: CCHS 2010/2011 + 2013/2014",
    x       = "Survey cycle",
    y       = "Number of respondents",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 12)

ggsave(paste0(prints_folder, "g2_sample_by_cycle.png"),
       g2_sample_by_cycle, width = 6, height = 5, dpi = 300)
print(g2_sample_by_cycle)

# ---- g21 ---------------------------------------------------------------------
# Weighted vs unweighted proportions — verify the wts_m / 2 pooling rule
g21_pooling_check <- g2_data %>%
  select(cycle_f,
         `Unweighted share` = n_pct,
         `Weighted share`   = wt_pct) %>%
  pivot_longer(-cycle_f, names_to = "measure", values_to = "proportion") %>%
  ggplot(aes(x = cycle_f, y = proportion, fill = measure)) +
  geom_col(position = "dodge", width = 0.6) +
  geom_hline(yintercept = 0.5, linetype = "dashed", colour = "grey40") +
  annotate("text", x = 0.55, y = 0.52, label = "50% reference",
           colour = "grey40", size = 3.5, hjust = 0) +
  scale_y_continuous(
    labels = scales::percent_format(accuracy = 1),
    limits = c(0, 0.62),
    expand = expansion(mult = c(0, 0))
  ) +
  scale_fill_manual(values = c(clr["sky_blue"], clr["orange"])) +
  labs(
    title   = "Pooling check: weighted vs unweighted cycle shares",
    subtitle = "Both shares should be ~50%, confirming the wts_m / 2 halving rule",
    x       = "Survey cycle",
    y       = "Share of total",
    fill    = NULL,
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

ggsave(paste0(prints_folder, "g21_pooling_check.png"),
       g21_pooling_check, width = 7, height = 5, dpi = 300)
print(g21_pooling_check)

# ---- g3-data-prep ------------------------------------------------------------
# Variable type inventory by domain
g3_data <- ds0 %>%
  summarise(across(everything(), classify_var_type)) %>%
  pivot_longer(everything(), names_to = "varname", values_to = "var_type") %>%
  left_join(domain_map, by = "varname") %>%
  mutate(domain = replace_na(domain, "Other")) %>%
  count(domain, var_type) %>%
  mutate(
    domain   = factor(domain, levels = c("Outcome", "Chronic Condition",
                                         "Predisposing", "Facilitating",
                                         "Needs", "Survey Design", "Other")),
    var_type = factor(var_type, levels = c("Ordered factor", "Nominal factor",
                                           "Logical", "Integer", "Numeric", "Other"))
  )

# ---- g3 ----------------------------------------------------------------------
# Stacked bar: variable types by domain
g3_type_inventory <- g3_data %>%
  ggplot(aes(x = fct_rev(domain), y = n, fill = var_type)) +
  geom_col(width = 0.65) +
  coord_flip() +
  geom_text(aes(label = n),
            position = position_stack(vjust = 0.5),
            colour = "white", size = 3.5, fontface = "bold") +
  scale_fill_manual(values = c(
    "Ordered factor" = clr["blue"],
    "Nominal factor" = clr["sky_blue"],
    "Logical"        = clr["green"],
    "Integer"        = clr["orange"],
    "Numeric"        = clr["vermillon"],
    "Other"          = "grey70"
  )) +
  labs(
    title   = "Variable type inventory by analytical domain",
    subtitle = "Ordered factors carry explicit level ordering for regression models",
    x       = NULL,
    y       = "Number of variables",
    fill    = "Variable type",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

ggsave(paste0(prints_folder, "g3_type_inventory.png"),
       g3_type_inventory, width = 8.5, height = 5.5, dpi = 300)
print(g3_type_inventory)

# nolint end
