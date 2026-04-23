# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
rm(list = ls(all.names = TRUE))
cat("\014")
cat("Working directory: ", getwd())

# ---- load-packages -----------------------------------------------------------
library(magrittr)
library(purrr)
library(dplyr)
library(tidyr)
library(stringr)
library(forcats)
library(ggplot2)
library(scales)
library(knitr)
library(janitor)
library(fs)

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R")
# operational-functions.R not sourced here (requires tidyverse which is not installed)

# ---- declare-globals ---------------------------------------------------------
local_root <- "./analysis/data-primer-1/"
local_data <- paste0(local_root, "data-local/")
if (!fs::dir_exists(local_data)) { fs::dir_create(local_data) }

prints_folder <- paste0(local_root, "prints/")
if (!fs::dir_exists(prints_folder)) { fs::dir_create(prints_folder) }

# ---- declare-functions -------------------------------------------------------

# Compact numeric summary for one or more continuous variables
# Returns a data.frame row per variable: n_valid, n_miss, mean, sd, min, p25, median, p75, max
summarize_continuous <- function(ds, vars) {
  purrr::map_dfr(vars, function(v) {
    x <- ds[[v]]
    x_num <- suppressWarnings(as.numeric(x))
    x_valid <- x_num[!is.na(x_num)]
    data.frame(
      variable  = v,
      n_valid   = length(x_valid),
      n_miss    = sum(is.na(x_num)),
      mean      = if (length(x_valid) > 0) round(mean(x_valid), 2) else NA_real_,
      sd        = if (length(x_valid) > 0) round(sd(x_valid), 2) else NA_real_,
      min       = if (length(x_valid) > 0) round(min(x_valid), 2) else NA_real_,
      p25       = if (length(x_valid) > 0) round(unname(quantile(x_valid, 0.25)), 2) else NA_real_,
      median    = if (length(x_valid) > 0) round(median(x_valid), 2) else NA_real_,
      p75       = if (length(x_valid) > 0) round(unname(quantile(x_valid, 0.75)), 2) else NA_real_,
      max       = if (length(x_valid) > 0) round(max(x_valid), 2) else NA_real_,
      stringsAsFactors = FALSE
    )
  })
}

# Frequency table for one discrete variable
# Returns a data.frame with: value, n, pct (of non-missing)
# When all values are NA, returns a 0-row data.frame with correct column structure
summarize_discrete <- function(ds, var) {
  x <- ds[[var]]
  total   <- length(x)
  n_miss  <- sum(is.na(x))
  n_valid <- total - n_miss
  if (n_valid == 0) {
    freq <- data.frame(value = character(0), n = integer(0), pct = numeric(0),
                       stringsAsFactors = FALSE)
  } else {
    tbl  <- table(x, useNA = "no")
    freq <- as.data.frame(tbl, stringsAsFactors = FALSE)
    colnames(freq) <- c("value", "n")
    freq <- freq[order(-freq$n), ]
    freq$pct <- round(freq$n / n_valid * 100, 1)
  }
  attr(freq, "n_miss")  <- n_miss
  attr(freq, "n_valid") <- n_valid
  freq
}

# Prevalence table for multiple binary (Yes/No) variables in one combined frame
# Returns a data.frame with one row per condition: n_yes, pct_yes, n_no, pct_no, n_miss
prevalence_table <- function(ds, vars, labels = NULL) {
  purrr::map_dfr(vars, function(v) {
    x <- ds[[v]]
    n_total <- length(x)
    n_miss  <- sum(is.na(x))
    n_valid <- n_total - n_miss
    n_yes   <- sum(x == "Yes", na.rm = TRUE)
    n_no    <- sum(x == "No",  na.rm = TRUE)
    data.frame(
      condition = if (!is.null(labels)) labels[v] else v,
      n_yes     = n_yes,
      pct_yes   = if (n_valid > 0) round(n_yes / n_valid * 100, 1) else NA_real_,
      n_no      = n_no,
      pct_no    = if (n_valid > 0) round(n_no  / n_valid * 100, 1) else NA_real_,
      n_miss    = n_miss,
      stringsAsFactors = FALSE
    )
  })
}

# ---- load-data ---------------------------------------------------------------
cnn <- DBI::dbConnect(RSQLite::SQLite(), "data-private/derived/cchs-2.sqlite")
ds0 <- DBI::dbReadTable(cnn, "cchs_analytical")
DBI::dbDisconnect(cnn)

cat("Rows:", nrow(ds0), "| Cols:", ncol(ds0), "\n")

# ---- section-outcomes --------------------------------------------------------
# Primary and sensitivity outcomes (continuous counts)
outcome_vars <- c("days_absent_total", "days_absent_chronic")
t_outcomes_summary <- summarize_continuous(ds0, outcome_vars)

# LOP component variables (the eight absence-reason sub-counts)
lop_vars <- c("lopg040", "lopg070", "lopg082", "lopg083",
              "lopg084", "lopg085", "lopg086", "lopg100")
t_lop_summary <- summarize_continuous(ds0, lop_vars)

lop_labels <- c(
  lopg040 = "Chronic condition",
  lopg070 = "Injury",
  lopg082 = "Cold",
  lopg083 = "Flu / influenza",
  lopg084 = "Stomach flu / gastroenteritis",
  lopg085 = "Respiratory infection",
  lopg086 = "Other infectious disease",
  lopg100 = "Other physical / mental health"
)
t_lop_summary$label <- lop_labels[t_lop_summary$variable]

# ---- section-chronic-conditions ----------------------------------------------
cc_vars <- c(
  "cc_asthma", "cc_fibromyalgia",
  "cc_arthritis", "cc_back_problems", "cc_hypertension", "cc_migraine",
  "cc_copd", "cc_diabetes", "cc_heart_disease", "cc_cancer", "cc_ulcer",
  "cc_stroke", "cc_bowel_disorder", "cc_chronic_fatigue",
  "cc_chemical_sensitiv", "cc_mood_disorder", "cc_anxiety_disorder"
)

cc_labels <- c(
  cc_asthma           = "Asthma",
  cc_fibromyalgia     = "Fibromyalgia",
  cc_arthritis        = "Arthritis (excl. fibromyalgia)",
  cc_back_problems    = "Back problems",
  cc_hypertension     = "Hypertension",
  cc_migraine         = "Migraine",
  cc_copd             = "COPD / chronic bronchitis / emphysema",
  cc_diabetes         = "Diabetes",
  cc_heart_disease    = "Cardiovascular / heart disease",
  cc_cancer           = "Cancer (any type)",
  cc_ulcer            = "Intestinal / stomach ulcer",
  cc_stroke           = "Stroke",
  cc_bowel_disorder   = "Bowel disorder (Crohn's / colitis / IBS)",
  cc_chronic_fatigue  = "Chronic fatigue syndrome (CFS)",
  cc_chemical_sensitiv = "Multiple chemical sensitivities (MCS)",
  cc_mood_disorder    = "Mood disorder (depression / bipolar)",
  cc_anxiety_disorder = "Anxiety disorder (phobia / OCD / panic)"
)

t_chronic_conditions <- prevalence_table(ds0, cc_vars, labels = cc_labels)

# ---- section-predisposing ----------------------------------------------------
# Discrete predisposing variables
pred_discrete_vars <- c(
  "age_group", "sex", "marital_status", "education",
  "immigration_status", "visible_minority", "homeownership", "student_status"
)

# Named list of frequency tables (one per variable)
t_pred_freq <- lapply(pred_discrete_vars, function(v) summarize_discrete(ds0, v))
names(t_pred_freq) <- pred_discrete_vars

# Raw dhhgage (integer age group code from PUMF) - continuous
t_dhhgage_summary <- summarize_continuous(ds0, "dhhgage")

# ---- section-facilitating ----------------------------------------------------
facil_discrete_vars <- c(
  "income_5cat", "has_family_doctor", "employment_type", "work_schedule",
  "alcohol_type", "smoking_status", "bmi_category", "physical_activity",
  "job_stress", "occupation_category"
)

t_facil_freq <- lapply(facil_discrete_vars, function(v) summarize_discrete(ds0, v))
names(t_facil_freq) <- facil_discrete_vars

# Province of residence - keep as numeric summary (integer code)
t_province_summary <- summarize_continuous(ds0, "geodgprv")

# Province frequency (useful to see distribution)
t_province_freq <- summarize_discrete(ds0, "geodgprv")

# ---- section-needs -----------------------------------------------------------
needs_discrete_vars <- c(
  "self_health_general", "self_health_mental", "health_vs_lastyear",
  "activity_limitation", "injury_past_year"
)

t_needs_freq <- lapply(needs_discrete_vars, function(v) summarize_discrete(ds0, v))
names(t_needs_freq) <- needs_discrete_vars

# ---- section-survey-design ---------------------------------------------------
# Survey weight numeric summaries
weight_vars <- c("wts_m_pooled", "wts_m_original")
t_weights_summary <- summarize_continuous(ds0, weight_vars)

# Cycle distribution
t_cycle_freq <- summarize_discrete(ds0, "cycle_f")

# Health region strata: count of unique values
t_geodpmf_summary <- data.frame(
  variable      = "geodpmf",
  n_valid       = sum(!is.na(ds0$geodpmf)),
  n_miss        = sum(is.na(ds0$geodpmf)),
  n_unique      = length(unique(ds0$geodpmf[!is.na(ds0$geodpmf)])),
  type          = "character (strata proxy)"
)

# Administrative / metadata variables (misc numeric)
admin_vars <- c("dhhgage", "lop_015", "adm_prx", "adm_rno", "cycle")
t_admin_summary <- summarize_continuous(ds0, admin_vars)

# ---- save-outputs ------------------------------------------------------------
# Save processed objects so QMD chunks can load them via readRDS()
saveRDS(list(
  t_outcomes_summary       = t_outcomes_summary,
  t_lop_summary            = t_lop_summary,
  t_chronic_conditions     = t_chronic_conditions,
  t_pred_freq              = t_pred_freq,
  t_dhhgage_summary        = t_dhhgage_summary,
  t_facil_freq             = t_facil_freq,
  t_province_summary       = t_province_summary,
  t_province_freq          = t_province_freq,
  t_needs_freq             = t_needs_freq,
  t_weights_summary        = t_weights_summary,
  t_cycle_freq             = t_cycle_freq,
  t_geodpmf_summary        = t_geodpmf_summary,
  t_admin_summary          = t_admin_summary
), file = paste0(local_data, "univariate-distributions.rds"))

cat("Outputs saved to", paste0(local_data, "univariate-distributions.rds"), "\n")
# nolint end
