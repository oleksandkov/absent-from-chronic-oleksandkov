# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run. This is not called by knitr, because it's above the first chunk.
cat("\014") # Clear the console
# verify root location
cat("Working directory: ", getwd()) # Must be set to Project Directory

# ---- load-packages -----------------------------------------------------------
# Choose to be greedy: load only what's needed
# Three ways, from least (1) to most(3) greedy:
# -- 1.Attach these packages so their functions don't need to be qualified:
# http://r-pkgs.had.co.nz/namespace.html#search-path
library(magrittr)
library(dplyr)     # data wrangling
library(tidyr)     # data wrangling
library(forcats)   # factors
library(stringr)   # strings
library(purrr)     # functional programming
library(knitr)     # kable tables
library(kableExtra) # kable styling (striped, condensed)
library(janitor)   # clean_names, tabyl
library(fs)        # file system operations
requireNamespace("arrow", quietly = TRUE)  # parquet I/O

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R") # project-level

# ---- declare-globals ---------------------------------------------------------
local_root <- "./analysis/data-primer-1/"
local_data <- paste0(local_root, "data-local/")
prints_folder <- paste0(local_root, "prints/")

if (!fs::dir_exists(local_data)) fs::dir_create(local_data, recurse = TRUE)
if (!fs::dir_exists(prints_folder)) fs::dir_create(prints_folder, recurse = TRUE)

path_parquet <- "data-private/derived/cchs-2-tables/cchs_analytic.parquet"

# ---- declare-functions -------------------------------------------------------

# 9-number summary for one or more continuous variables.
# Returns one row per variable: n_valid, n_miss, mean, sd, min, p25, median, p75, max.
summarize_continuous <- function(ds, vars) {
  purrr::map_dfr(vars, function(v) {
    x_raw   <- ds[[v]]
    x_num   <- suppressWarnings(as.numeric(x_raw))
    x_valid <- x_num[!is.na(x_num)]
    data.frame(
      variable = v,
      n_valid  = length(x_valid),
      n_miss   = sum(is.na(x_num)),
      mean     = if (length(x_valid) > 0) round(mean(x_valid), 2)                        else NA_real_,
      sd       = if (length(x_valid) > 0) round(sd(x_valid), 2)                          else NA_real_,
      min      = if (length(x_valid) > 0) round(min(x_valid), 2)                         else NA_real_,
      p25      = if (length(x_valid) > 0) round(unname(quantile(x_valid, 0.25)), 2)      else NA_real_,
      median   = if (length(x_valid) > 0) round(median(x_valid), 2)                      else NA_real_,
      p75      = if (length(x_valid) > 0) round(unname(quantile(x_valid, 0.75)), 2)      else NA_real_,
      max      = if (length(x_valid) > 0) round(max(x_valid), 2)                         else NA_real_,
      stringsAsFactors = FALSE
    )
  })
}

# Frequency table for one discrete / factor variable.
# Returns data.frame: value, n, pct (% of non-missing rows).
# Preserves factor level order; handles all-NA gracefully.
summarize_discrete <- function(ds, var) {
  x       <- ds[[var]]
  n_miss  <- sum(is.na(x))
  n_valid <- length(x) - n_miss
  if (n_valid == 0) {
    freq <- data.frame(value = character(0), n = integer(0), pct = numeric(0),
                       stringsAsFactors = FALSE)
  } else {
    tbl  <- table(x, useNA = "no")
    freq <- as.data.frame(tbl, stringsAsFactors = FALSE)
    colnames(freq) <- c("value", "n")
    # Preserve factor order if available; otherwise sort by n descending
    if (is.factor(x)) {
      lvl_order <- levels(x)
      freq <- freq[match(lvl_order, freq$value), ]
      freq <- freq[!is.na(freq$value), ]
    } else {
      freq <- freq[order(-freq$n), ]
    }
    freq$pct <- round(freq$n / n_valid * 100, 1)
  }
  attr(freq, "n_miss")  <- n_miss
  attr(freq, "n_valid") <- n_valid
  freq
}

# Thin wrapper: knitr::kable() + Bootstrap striped/condensed styling.
styled_kable <- function(...) {
  knitr::kable(...) |>
    kableExtra::kable_styling(
      bootstrap_options = c("striped", "hover", "condensed"),
      full_width        = FALSE,
      position          = "center"
    )
}

# Prevalence table for multiple binary logical (TRUE/FALSE) variables.
# Returns one row per variable: condition, n_yes, pct_yes, n_no, pct_no, n_miss.
# NOTE: cc_* columns are stored as R logical, not factor "Yes"/"No".
prevalence_table <- function(ds, vars, labels = NULL) {
  purrr::map_dfr(vars, function(v) {
    x       <- ds[[v]]
    n_miss  <- sum(is.na(x))
    n_valid <- length(x) - n_miss
    n_yes   <- sum(x == TRUE,  na.rm = TRUE)
    n_no    <- sum(x == FALSE, na.rm = TRUE)
    data.frame(
      condition = if (!is.null(labels) && v %in% names(labels)) labels[v] else v,
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
ds0 <- arrow::read_parquet(path_parquet)
cat("Parquet loaded: ", nrow(ds0), "rows x", ncol(ds0), "cols\n")

# ---- section-outcomes --------------------------------------------------------
outcome_vars    <- intersect(c("days_absent_total", "days_absent_chronic"), names(ds0))
t_outcomes_summary <- summarize_continuous(ds0, outcome_vars)

lop_vars <- intersect(
  c("lopg040", "lopg070", "lopg082", "lopg083",
    "lopg084", "lopg085", "lopg086", "lopg100"),
  names(ds0)
)
t_lop_summary <- summarize_continuous(ds0, lop_vars)

lop_labels <- c(
  lopg040 = "Chronic condition",
  lopg070 = "Injury",
  lopg082 = "Cold",
  lopg083 = "Flu / influenza",
  lopg084 = "Stomach flu / gastroenteritis",
  lopg085 = "Respiratory infection",
  lopg086 = "Other infectious disease",
  lopg100 = "Other physical / mental health reason"
)
t_lop_summary$label <- lop_labels[t_lop_summary$variable]

# ---- display-outcomes --------------------------------------------------------
print(styled_kable(
  t_outcomes_summary,
  col.names = c("Variable", "N valid", "N missing", "Mean", "SD",
                "Min", "P25", "Median", "P75", "Max"),
  caption   = "Table 1.1 \u2014 Summary statistics: primary and sensitivity outcomes",
  align     = c("l", rep("r", 9))
))

# ---- display-lop -------------------------------------------------------------
lop_display <- t_lop_summary[, c("label", "variable", "n_valid", "n_miss",
                                  "mean", "sd", "min", "p25", "median", "p75", "max")]
print(styled_kable(
  lop_display,
  col.names = c("Reason for absence", "Variable", "N valid", "N missing", "Mean", "SD",
                "Min", "P25", "Median", "P75", "Max"),
  caption   = "Table 1.2 \u2014 Summary statistics: LOP component variables",
  align     = c("l", "l", rep("r", 9))
))

# ---- section-chronic-conditions ----------------------------------------------
# cc_* columns are logical (TRUE / FALSE), not factor "Yes" / "No"
cc_vars <- intersect(
  c("cc_asthma", "cc_fibromyalgia", "cc_arthritis", "cc_back_problems",
    "cc_hypertension", "cc_migraine", "cc_copd", "cc_diabetes",
    "cc_heart_disease", "cc_cancer", "cc_ulcer", "cc_stroke",
    "cc_bowel_disorder", "cc_fatigue_syndrome", "cc_chem_sensitivity",
    "cc_mood_disorder", "cc_anxiety"),
  names(ds0)
)

cc_labels <- c(
  cc_asthma            = "Asthma",
  cc_fibromyalgia      = "Fibromyalgia",
  cc_arthritis         = "Arthritis (excl. fibromyalgia)",
  cc_back_problems     = "Back problems",
  cc_hypertension      = "Hypertension",
  cc_migraine          = "Migraine",
  cc_copd              = "COPD / chronic bronchitis / emphysema",
  cc_diabetes          = "Diabetes",
  cc_heart_disease     = "Cardiovascular / heart disease",
  cc_cancer            = "Cancer (any type)",
  cc_ulcer             = "Intestinal / stomach ulcer",
  cc_stroke            = "Stroke",
  cc_bowel_disorder    = "Bowel disorder (Crohn\u2019s / colitis / IBS)",
  cc_fatigue_syndrome  = "Chronic fatigue syndrome (CFS)",
  cc_chem_sensitivity  = "Multiple chemical sensitivities (MCS)",
  cc_mood_disorder     = "Mood disorder (depression / bipolar)",
  cc_anxiety           = "Anxiety disorder (phobia / OCD / panic)"
)

t_chronic_conditions <- prevalence_table(ds0, cc_vars, labels = cc_labels)

# ---- display-chronic-conditions ----------------------------------------------
print(styled_kable(
  t_chronic_conditions,
  col.names = c("Condition", "Yes (n)", "Yes (%)", "No (n)", "No (%)", "Missing (n)"),
  caption   = paste0(
    "Table 2.1 \u2014 Prevalence of ", length(cc_vars),
    " available chronic conditions (17 of 19 from \u00a72.2 available in PUMF)"
  ),
  align     = c("l", "r", "r", "r", "r", "r")
))

# ---- section-predisposing ----------------------------------------------------
pred_discrete_vars <- intersect(
  c("age_group_3", "sex", "marital_status", "household_size",
    "education", "immigration_status", "visible_minority", "home_ownership",
    "living_arrangements"),
  names(ds0)
)
t_pred_freq <- lapply(pred_discrete_vars, function(v) summarize_discrete(ds0, v))
names(t_pred_freq) <- pred_discrete_vars

# Raw PUMF age group code — treated as ordered factor for frequency table
if ("dhhgage" %in% names(ds0)) {
  dhhgage_levels <- sort(unique(na.omit(ds0[["dhhgage"]])))
  dhhgage_factor <- factor(ds0[["dhhgage"]], levels = dhhgage_levels)
  tmp_freq <- summarize_discrete(data.frame(dhhgage = dhhgage_factor), "dhhgage")
  dhhgage_brackets <- c(
    "2"  = "15\u201317 yrs", "3"  = "18\u201319 yrs", "4"  = "20\u201324 yrs",
    "5"  = "25\u201329 yrs", "6"  = "30\u201334 yrs", "7"  = "35\u201339 yrs",
    "8"  = "40\u201344 yrs", "9"  = "45\u201349 yrs", "10" = "50\u201354 yrs",
    "11" = "55\u201359 yrs", "12" = "60\u201364 yrs", "13" = "65\u201369 yrs",
    "14" = "70\u201374 yrs", "15" = "75\u201379 yrs"
  )
  t_dhhgage_freq <- data.frame(
    code    = tmp_freq$value,
    bracket = dhhgage_brackets[as.character(tmp_freq$value)],
    n       = tmp_freq$n,
    pct     = tmp_freq$pct,
    stringsAsFactors = FALSE
  )
} else {
  t_dhhgage_freq <- data.frame(code = character(0), bracket = character(0),
                                n = integer(0), pct = numeric(0),
                                stringsAsFactors = FALSE)
}

# Children in household by age band. Despite the "count" naming inherited from
# the PUMF documentation, DHHGLE5 / DHHG611 / DHHGL12 are BINARY 0/1 presence
# flags (0 = none, 1 = one or more). Treated as ordered factors here.
make_count_freq <- function(ds, var) {
  if (!var %in% names(ds)) return(NULL)
  vals   <- sort(unique(na.omit(ds[[var]])))
  f      <- factor(ds[[var]], levels = vals)
  summarize_discrete(data.frame(x = f), "x")
}
t_children_le5  <- make_count_freq(ds0, "dhhgle5")
t_children_6_11 <- make_count_freq(ds0, "dhhg611")
t_children_l12  <- make_count_freq(ds0, "dhhgl12")

# student_status: suppressed in PUMF; create all-NA stub for QMD guard
if ("student_status" %in% names(ds0)) {
  t_student_status <- summarize_discrete(ds0, "student_status")
} else {
  t_student_status <- data.frame(value = character(0), n = integer(0), pct = numeric(0),
                                  stringsAsFactors = FALSE)
  attr(t_student_status, "n_miss")  <- nrow(ds0)
  attr(t_student_status, "n_valid") <- 0L
}

# ---- display-age-group -------------------------------------------------------
print(styled_kable(
  t_pred_freq[["age_group_3"]],
  col.names = c("Age group", "N", "% (of valid)"),
  caption   = "age_group_3 \u2014 Ordered factor: 15-24 / 25-54 / 55-75",
  align     = c("l", "r", "r")
))

# ---- display-sex -------------------------------------------------------------
print(styled_kable(
  t_pred_freq[["sex"]],
  col.names = c("Sex", "N", "% (of valid)"),
  caption   = "sex \u2014 Binary: Male / Female",
  align     = c("l", "r", "r")
))

# ---- display-marital-status --------------------------------------------------
print(styled_kable(
  t_pred_freq[["marital_status"]],
  col.names = c("Marital status", "N", "% (of valid)"),
  caption   = "marital_status \u2014 Single / Married / Common-law / Widowed-Divorced-Separated",
  align     = c("l", "r", "r")
))

# ---- display-household-size --------------------------------------------------
print(styled_kable(
  t_pred_freq[["household_size"]],
  col.names = c("Household size", "N", "% (of valid)"),
  caption   = "household_size \u2014 Ordered: 1 / 2 / 3 / 4 / 5+",
  align     = c("l", "r", "r")
))

# ---- display-education -------------------------------------------------------
print(styled_kable(
  t_pred_freq[["education"]],
  col.names = c("Education level", "N", "% (of valid)"),
  caption   = "education \u2014 Ordered: Less than secondary \u2192 Post-secondary graduate",
  align     = c("l", "r", "r")
))

# ---- display-immigration-status ----------------------------------------------
print(styled_kable(
  t_pred_freq[["immigration_status"]],
  col.names = c("Immigration status", "N", "% (of valid)"),
  caption   = "immigration_status \u2014 Non-immigrant / Immigrant / Non-permanent resident",
  align     = c("l", "r", "r")
))

# ---- display-visible-minority ------------------------------------------------
print(styled_kable(
  t_pred_freq[["visible_minority"]],
  col.names = c("Ethnic origin", "N", "% (of valid)"),
  caption   = "visible_minority \u2014 White / Visible minority",
  align     = c("l", "r", "r")
))

# ---- display-home-ownership --------------------------------------------------
print(styled_kable(
  t_pred_freq[["home_ownership"]],
  col.names = c("Home ownership", "N", "% (of valid)"),
  caption   = "home_ownership \u2014 Dwelling owned by a member of the household",
  align     = c("l", "r", "r")
))

# ---- display-living-arrangements ---------------------------------------------
{
  n_miss_la  <- attr(t_pred_freq[["living_arrangements"]], "n_miss")
  n_valid_la <- attr(t_pred_freq[["living_arrangements"]], "n_valid")
  if (is.null(n_valid_la) || n_valid_la == 0) {
    cat(sprintf(
      "**All-NA variable.** `living_arrangements` is all-missing (%d missing, %d valid).",
      n_miss_la, 0L
    ))
  } else {
    print(styled_kable(
      t_pred_freq[["living_arrangements"]],
      col.names = c("Living arrangements", "N", "% (of valid)"),
      caption   = "living_arrangements \u2014 8-level household arrangement factor",
      align     = c("l", "r", "r")
    ))
  }
}

# ---- display-student-status --------------------------------------------------
{
  n_valid_ss <- attr(t_student_status, "n_valid")
  if (is.null(n_valid_ss) || n_valid_ss == 0) {
    cat(
      "**All-NA variable.** `student_status` is all-missing.",
      " `sdcdgstud` is suppressed in the CCHS PUMF; requires RDC access."
    )
  } else {
    print(styled_kable(
      t_student_status,
      col.names = c("Student status", "N", "% (of valid)"),
      caption   = "student_status"
    ))
  }
}

# ---- display-dhhgage ---------------------------------------------------------
if (nrow(t_dhhgage_freq) > 0) {
  print(styled_kable(
    t_dhhgage_freq,
    col.names = c("Code", "Age bracket", "N", "% (of valid)"),
    caption   = "dhhgage \u2014 Raw PUMF age group code",
    align     = c("l", "l", "r", "r"),
    row.names = FALSE
  ))
}

# ---- display-children --------------------------------------------------------
if (!is.null(t_children_le5) && nrow(t_children_le5) > 0) {
  print(styled_kable(
    t_children_le5,
    col.names = c("Presence (0/1)", "N", "% (of valid)"),
    caption   = "dhhgle5 \u2014 Any child aged \u2264 5 in household (0 = none, 1 = one or more)",
    align     = c("l", "r", "r"),
    row.names = FALSE
  ))
}
if (!is.null(t_children_6_11) && nrow(t_children_6_11) > 0) {
  print(styled_kable(
    t_children_6_11,
    col.names = c("Presence (0/1)", "N", "% (of valid)"),
    caption   = "dhhg611 \u2014 Any child aged 6\u201311 in household (0 = none, 1 = one or more)",
    align     = c("l", "r", "r"),
    row.names = FALSE
  ))
}
if (!is.null(t_children_l12) && nrow(t_children_l12) > 0) {
  print(styled_kable(
    t_children_l12,
    col.names = c("Presence (0/1)", "N", "% (of valid)"),
    caption   = "dhhgl12 \u2014 Any child aged under 12 in household (0 = none, 1 = one or more)",
    align     = c("l", "r", "r"),
    row.names = FALSE
  ))
}

# ---- section-facilitating ----------------------------------------------------
facil_discrete_vars <- intersect(
  c("income_hh", "has_family_doctor", "employment_type", "work_schedule",
    "smoking_status", "bmi_category", "physical_activity",
    "alcohol_type", "fruit_veg_daily", "occupation_category",
    "work_stress", "province"),
  names(ds0)
)
t_facil_freq <- lapply(facil_discrete_vars, function(v) summarize_discrete(ds0, v))
names(t_facil_freq) <- facil_discrete_vars

t_bmi_continuous <- if ("hwtgbmi" %in% names(ds0)) {
  summarize_continuous(ds0, "hwtgbmi")
} else {
  data.frame()
}

# ---- display-income ----------------------------------------------------------
print(styled_kable(
  t_facil_freq[["income_hh"]],
  col.names = c("Household income category", "N", "% (of valid)"),
  caption   = "income_hh \u2014 5-category derived household income (< $20k \u2192 $80k+)",
  align     = c("l", "r", "r")
))

# ---- display-family-doctor ---------------------------------------------------
print(styled_kable(
  t_facil_freq[["has_family_doctor"]],
  col.names = c("Has regular family doctor", "N", "% (of valid)"),
  caption   = "has_family_doctor \u2014 Yes / No",
  align     = c("l", "r", "r")
))

# ---- display-employment-type -------------------------------------------------
print(styled_kable(
  t_facil_freq[["employment_type"]],
  col.names = c("Employment type", "N", "% (of valid)"),
  caption   = "employment_type \u2014 Employee / Self-employed (PUMF LBSG31, 2 levels)",
  align     = c("l", "r", "r")
))

# ---- display-work-schedule ---------------------------------------------------
print(styled_kable(
  t_facil_freq[["work_schedule"]],
  col.names = c("Work schedule", "N", "% (of valid)"),
  caption   = "work_schedule \u2014 Full-time / Part-time",
  align     = c("l", "r", "r")
))

# ---- display-smoking ---------------------------------------------------------
print(styled_kable(
  t_facil_freq[["smoking_status"]],
  col.names = c("Smoking status", "N", "% (of valid)"),
  caption   = "smoking_status \u2014 Ordered: Never / Former / Occasional / Daily",
  align     = c("l", "r", "r")
))

# ---- display-bmi-category ----------------------------------------------------
{
  n_valid_bmi <- attr(t_facil_freq[["bmi_category"]], "n_valid")
  if (!is.null(n_valid_bmi) && n_valid_bmi > 0) {
    print(styled_kable(
      t_facil_freq[["bmi_category"]],
      col.names = c("BMI category", "N", "% (of valid)"),
      caption   = "bmi_category \u2014 Ordered: Underweight / Normal weight / Overweight / Obese",
      align     = c("l", "r", "r")
    ))
  }
  if (nrow(t_bmi_continuous) > 0) {
    print(styled_kable(
      t_bmi_continuous,
      col.names = c("Variable", "N valid", "N missing", "Mean", "SD",
                    "Min", "P25", "Median", "P75", "Max"),
      caption   = "hwtgbmi \u2014 Continuous BMI (continuous underlying variable)",
      align     = c("l", rep("r", 9))
    ))
  }
}

# ---- display-physical-activity -----------------------------------------------
print(styled_kable(
  t_facil_freq[["physical_activity"]],
  col.names = c("Physical activity level", "N", "% (of valid)"),
  caption   = "physical_activity \u2014 Ordered: Active / Moderately active / Inactive",
  align     = c("l", "r", "r")
))

# ---- display-alcohol ---------------------------------------------------------
{
  n_valid_al <- attr(t_facil_freq[["alcohol_type"]], "n_valid")
  if (!is.null(n_valid_al) && n_valid_al > 0) {
    print(styled_kable(
      t_facil_freq[["alcohol_type"]],
      col.names = c("Alcohol use", "N", "% (of valid)"),
      caption   = "alcohol_type \u2014 Former or never / Occasional / Regular drinker",
      align     = c("l", "r", "r")
    ))
  } else {
    cat("**All-NA variable.** `alcohol_type` is all-missing. Source variable `alcdttm` may be absent from PUMF.")
  }
}

# ---- display-fruit-veg -------------------------------------------------------
print(styled_kable(
  t_facil_freq[["fruit_veg_daily"]],
  col.names = c("Fruit & vegetable consumption", "N", "% (of valid)"),
  caption   = "fruit_veg_daily \u2014 3-cat derived: < 5 / 5\u201310 / > 10 servings per day",
  align     = c("l", "r", "r")
))

# ---- display-occupation-category ---------------------------------------------
{
  n_valid_oc <- attr(t_facil_freq[["occupation_category"]], "n_valid")
  if (!is.null(n_valid_oc) && n_valid_oc > 0) {
    print(styled_kable(
      t_facil_freq[["occupation_category"]],
      col.names = c("Occupation category", "N", "% (of valid)"),
      caption   = "occupation_category \u2014 5-group PUMF occupation (LBSGSOC)",
      align     = c("l", "r", "r")
    ))
  } else {
    cat("**All-NA variable.** `occupation_category` is all-missing.")
  }
}

# ---- display-work-stress -----------------------------------------------------
print(styled_kable(
  t_facil_freq[["work_stress"]],
  col.names = c("Work stress level", "N", "% (of valid)"),
  caption   = "work_stress \u2014 Ordered: Not at all \u2192 Extremely stressful (GEN_09)",
  align     = c("l", "r", "r")
))

# ---- display-province --------------------------------------------------------
print(styled_kable(
  t_facil_freq[["province"]],
  col.names = c("Province / territory", "N", "% (of valid)"),
  caption   = "province \u2014 13-level factor (includes Nunavut and NWT combined)",
  align     = c("l", "r", "r")
))

# ---- section-needs -----------------------------------------------------------
needs_discrete_vars <- intersect(
  c("health_perceived", "mental_health_perceived", "health_vs_prior_year",
    "injured_past_12m"),
  names(ds0)
)
t_needs_freq <- lapply(needs_discrete_vars, function(v) summarize_discrete(ds0, v))
names(t_needs_freq) <- needs_discrete_vars

adl_vars <- intersect(
  c("adl_meals", "adl_errands", "adl_housework",
    "adl_personal_care", "adl_moving_indoors", "adl_finances"),
  names(ds0)
)
t_adl_freq <- lapply(adl_vars, function(v) summarize_discrete(ds0, v))
names(t_adl_freq) <- adl_vars

adl_labels <- c(
  adl_meals          = "Meal preparation (ADL_01)",
  adl_errands        = "Appointments / errands (ADL_02)",
  adl_housework      = "Housework (ADL_03)",
  adl_personal_care  = "Personal care (ADL_04)",
  adl_moving_indoors = "Moving inside home (ADL_05)",
  adl_finances       = "Personal finances (ADL_06)"
)

# ---- display-health-perceived ------------------------------------------------
print(styled_kable(
  t_needs_freq[["health_perceived"]],
  col.names = c("Self-perceived general health", "N", "% (of valid)"),
  caption   = "health_perceived \u2014 Ordered: Excellent \u2192 Poor (GEN_01)",
  align     = c("l", "r", "r")
))

# ---- display-mental-health ---------------------------------------------------
print(styled_kable(
  t_needs_freq[["mental_health_perceived"]],
  col.names = c("Self-perceived mental health", "N", "% (of valid)"),
  caption   = "mental_health_perceived \u2014 Ordered: Excellent \u2192 Poor (GEN_02B)",
  align     = c("l", "r", "r")
))

# ---- display-health-vs-prior-year --------------------------------------------
print(styled_kable(
  t_needs_freq[["health_vs_prior_year"]],
  col.names = c("Health vs. prior year", "N", "% (of valid)"),
  caption   = "health_vs_prior_year \u2014 Ordered: Much better \u2192 Much worse (GEN_02)",
  align     = c("l", "r", "r")
))

# ---- display-injury ----------------------------------------------------------
print(styled_kable(
  t_needs_freq[["injured_past_12m"]],
  col.names = c("Injured in past 12 months", "N", "% (of valid)"),
  caption   = "injured_past_12m \u2014 Yes / No (INJ_01)",
  align     = c("l", "r", "r")
))

# ---- display-adl -------------------------------------------------------------
adl_tables <- lapply(adl_vars, function(v) {
  tbl <- t_adl_freq[[v]]
  tbl$variable <- adl_labels[v]
  tbl
})
t_adl_combined <- do.call(rbind, adl_tables)
print(styled_kable(
  t_adl_combined,
  col.names = c("Response", "N", "% (of valid)", "ADL item"),
  caption   = "Table 5.5 \u2014 Activity limitations (ADL items; Yes = limitation reported)",
  align     = c("l", "r", "r", "l")
))

# ---- section-survey-design ---------------------------------------------------
weight_vars <- intersect(c("wts_m", "wts_m_pooled"), names(ds0))
t_weights_summary <- summarize_continuous(ds0, weight_vars)

t_cycle_freq <- summarize_discrete(ds0, "cchs_cycle_f")

flag_vars <- intersect(
  c("flag_complete_ccc", "flag_complete_predictors", "flag_analytic_complete"),
  names(ds0)
)
t_flags_summary <- if (length(flag_vars) > 0) {
  data.frame(
    flag    = flag_vars,
    n_true  = sapply(flag_vars, function(v) sum(ds0[[v]] == TRUE,  na.rm = TRUE)),
    n_false = sapply(flag_vars, function(v) sum(ds0[[v]] == FALSE, na.rm = TRUE)),
    n_miss  = sapply(flag_vars, function(v) sum(is.na(ds0[[v]]))),
    stringsAsFactors = FALSE
  )
} else {
  data.frame()
}

# ---- display-weights ---------------------------------------------------------
print(styled_kable(
  t_weights_summary,
  col.names = c("Weight variable", "N valid", "N missing", "Mean", "SD",
                "Min", "P25", "Median", "P75", "Max"),
  caption   = "Survey sampling weights: wts_m (per-cycle) and wts_m_pooled (pooled across cycles)",
  align     = c("l", rep("r", 9))
))

# ---- display-cycle -----------------------------------------------------------
print(styled_kable(
  t_cycle_freq,
  col.names = c("CCHS cycle", "N", "% (of valid)"),
  caption   = "cchs_cycle_f \u2014 CCHS 2010 and 2014 pooled sample",
  align     = c("l", "r", "r")
))

# ---- display-flags -----------------------------------------------------------
if (nrow(t_flags_summary) > 0) {
  print(styled_kable(
    t_flags_summary,
    col.names = c("Completeness flag", "N TRUE", "N FALSE", "N missing"),
    caption   = "Analytic completeness flags (TRUE = complete for that dimension)",
    align     = c("l", "r", "r", "r")
  ))
}

# ---- save-outputs ------------------------------------------------------------
saveRDS(
  list(
    t_outcomes_summary   = t_outcomes_summary,
    t_lop_summary        = t_lop_summary,
    t_chronic_conditions = t_chronic_conditions,
    t_pred_freq          = t_pred_freq,
    t_dhhgage_freq       = t_dhhgage_freq,
    t_children_le5       = t_children_le5,
    t_children_6_11      = t_children_6_11,
    t_children_l12       = t_children_l12,
    t_student_status     = t_student_status,
    t_facil_freq         = t_facil_freq,
    t_bmi_continuous     = t_bmi_continuous,
    t_needs_freq         = t_needs_freq,
    t_adl_freq           = t_adl_freq,
    adl_labels           = adl_labels,
    t_weights_summary    = t_weights_summary,
    t_cycle_freq         = t_cycle_freq,
    t_flags_summary      = t_flags_summary
  ),
  file = paste0(local_data, "univariate-distributions.rds")
)
cat("Outputs saved to:", paste0(local_data, "univariate-distributions.rds"), "\n")
# nolint end
