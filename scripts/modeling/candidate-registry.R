# nolint start
# CANDIDATE REGISTRY: the single source of truth for which variables are
# eligible to enter the Section 5.3 bivariate series and the Section 5.4
# selection procedure, which Andersen domain each belongs to, and - where a
# variable is excluded - the evidence that excludes it.
#
# Ratified in analysis/model-1/model-1.R on 2026-07-29. Earlier exploratory work
# kept these lists in several places (eda-62 declared 11 predisposing variables,
# eda-65 declared 8) and they drifted. Any report that needs the candidate list
# should source this file rather than re-typing a vector.
#
# Requires: tibble. Provides: candidate_registry, perceived_health_vars,
# included_vars, bivariate_only_vars, lasso_vars, vars_excluding_perceived,
# vars_including_perceived, variable_labels_registry, variable_domains_registry.
#
# Two eligibility axes:
#   included_vars  - everything in the study (descriptives + Section 5.3 bivariate)
#   lasso_vars     - the subset offered to the Section 5.4 penalised selection

candidate_registry <- tibble::tribble(
  ~variable,                 ~domain,        ~variable_label,                  ~status,   ~exclusion_reason,
  "cc_asthma",               "Exposure",     "Asthma",                         "include", "",
  "cc_fibromyalgia",         "Exposure",     "Fibromyalgia",                   "include", "",
  "cc_arthritis",            "Exposure",     "Arthritis",                      "include", "",
  "cc_back_problems",        "Exposure",     "Back problems",                  "include", "",
  "cc_hypertension",         "Exposure",     "Hypertension",                   "include", "",
  "cc_migraine",             "Exposure",     "Migraine",                       "include", "",
  "cc_copd",                 "Exposure",     "COPD",                           "exclude", "Asked only of respondents aged 35+; 100% missing below 35",
  "cc_diabetes",             "Exposure",     "Diabetes",                       "include", "",
  "cc_heart_disease",        "Exposure",     "Heart disease",                  "include", "",
  "cc_cancer",               "Exposure",     "Cancer",                         "include", "",
  "cc_ulcer",                "Exposure",     "Stomach / intestinal ulcer",     "include", "",
  "cc_stroke",               "Exposure",     "Stroke",                         "include", "",
  "cc_bowel_disorder",       "Exposure",     "Bowel disorder",                 "include", "",
  "cc_fatigue_syndrome",     "Exposure",     "Chronic fatigue syndrome",       "include", "",
  "cc_chem_sensitivity",     "Exposure",     "Multiple chemical sensitivities", "include", "",
  "cc_mood_disorder",        "Exposure",     "Mood disorder",                  "include", "",
  "cc_anxiety",              "Exposure",     "Anxiety disorder",               "include", "",
  "age_group_3",             "Predisposing", "Age group",                      "include", "",
  "dhhgage",                 "Predisposing", "Age (5-year group)",             "exclude", "Same construct as age_group_3; Section 2.2 specifies the 3-category recode",
  "sex",                     "Predisposing", "Sex",                            "include", "",
  "marital_status",          "Predisposing", "Marital status",                 "include", "",
  "household_size",          "Predisposing", "Household size",                 "include", "",
  "dhhgle5",                 "Predisposing", "Child aged 0-5 in household",    "include", "",
  "dhhg611",                 "Predisposing", "Child aged 6-11 in household",   "include", "",
  # QC 2026-08-01: dhhgl12 is "child UNDER 12" (it was previously mislabelled
  # "Children age 12+", conflating it with dhhdfc12p, which has no PUMF
  # equivalent). It is redundant by construction - dhhgl12 == (dhhgle5 |
  # dhhg611) in all 63,843 rows - so ~ dhhgle5 + dhhg611 + dhhgl12 spans the
  # same column space as ~ dhhgle5 * dhhg611. Retained pending the human
  # decision recorded against the CACHE-manifest QC note.
  "dhhgl12",                 "Predisposing", "Child under 12 in household",    "include", "",
  "education",               "Predisposing", "Education",                      "include", "",
  "immigration_status",      "Predisposing", "Immigration status",             "include", "",
  "visible_minority",        "Predisposing", "Visible minority",               "include", "",
  "home_ownership",          "Predisposing", "Home ownership",                 "include", "",
  "living_arrangements",     "Predisposing", "Living arrangements",            "include", "",
  "income_hh",               "Facilitating", "Household income",               "include", "",
  "province",                "Facilitating", "Province",                       "include", "",
  "has_family_doctor",       "Facilitating", "Has family doctor",              "exclude", "Optional content: 100% missing in 2010-2011 outside Ontario; aliases cycle x province",
  "employment_type",         "Facilitating", "Employment type",                "include", "",
  "work_schedule",           "Facilitating", "Work schedule",                  "include", "",
  "occupation_category",     "Facilitating", "Occupation category",            "include", "",
  "smoking_status",          "Facilitating", "Smoking status",                 "include", "",
  "bmi_category",            "Facilitating", "BMI category",                   "include", "",
  "physical_activity",       "Facilitating", "Physical activity",              "include", "",
  "alcohol_type",            "Facilitating", "Alcohol consumption",            "include", "",
  "fruit_veg_daily",         "Facilitating", "Fruit / vegetable servings",     "include", "",
  "work_stress",             "Facilitating", "Work stress",                    "include", "",
  "health_perceived",        "Needs",        "Self-perceived general health",  "include", "",
  "mental_health_perceived", "Needs",        "Self-perceived mental health",   "include", "",
  "health_vs_prior_year",    "Needs",        "Health vs prior year",           "include", "",
  "injured_past_12m",        "Needs",        "Injured in past 12 months",      "include", "",
  "adl_meals",               "Needs",        "Needs help: meals",              "include", "",
  "adl_errands",             "Needs",        "Needs help: errands",            "include", "",
  "adl_housework",           "Needs",        "Needs help: housework",          "include", "",
  "adl_personal_care",       "Needs",        "Needs help: personal care",      "include", "",
  "adl_moving_indoors",      "Needs",        "Needs help: moving indoors",     "include", "",
  "adl_finances",            "Needs",        "Needs help: finances",           "include", ""
)

# The three self-perceived measures that Section 5.4 toggles on and off.
# Ratified 2026-07-29: functional-limitation items and injury status are NOT
# perceived-health variables and remain in every specification.
perceived_health_vars <- c(
  "health_perceived", "mental_health_perceived", "health_vs_prior_year"
)

included_vars <- candidate_registry$variable[candidate_registry$status == "include"]

# Second eligibility axis, ratified 2026-08-01.
#
# `status` answers "is this variable in the study at all?". This vector answers
# a narrower question: "may it enter the Section 5.4 penalised selection?".
#
# A variable listed here is retained for descriptive reporting and for the
# Section 5.3 bivariate series, but withheld from LASSO. The reason is
# structural redundancy rather than data quality: `dhhgl12` is a deterministic
# function of `dhhgle5` and `dhhg611` (identical to their logical OR in all
# 63,843 rows), so a design matrix carrying all three spans the same column
# space as `dhhgle5* dhhg611`. Penalised selection among near-duplicate columns
# is arbitrary — the penalty splits a shared coefficient unpredictably between
# them. Its bivariate rate ratio remains interpretable and is worth reporting,
# which is why it is not simply excluded.
bivariate_only_vars <- c("dhhgl12")

# The predictor set offered to cv.glmnet.
lasso_vars <- setdiff(included_vars, bivariate_only_vars)

vars_excluding_perceived <- setdiff(lasso_vars, perceived_health_vars)
vars_including_perceived <- lasso_vars

variable_labels_registry <- stats::setNames(
  candidate_registry$variable_label, candidate_registry$variable
)
variable_domains_registry <- stats::setNames(
  candidate_registry$domain, candidate_registry$variable
)

# Guard against silent divergence.
#   52 registered candidates
#    3 excluded outright (cc_copd, has_family_doctor, dhhgage) -> 49 included
#    1 of those 49 is bivariate-only (dhhgl12)                 -> 48 LASSO-eligible
# `home_ownership` was admitted 2026-08-01 after QC established that DHH_OWN is
# present in both cycles with 99.67% coverage in the analytic sample; it
# satisfies the Section 2.2 "homeownership" requirement that was previously
# believed to have no PUMF equivalent.
stopifnot(
  nrow(candidate_registry) == 52L,
  length(included_vars) == 49L,
  length(lasso_vars) == 48L,
  all(bivariate_only_vars %in% included_vars),
  all(candidate_registry$status %in% c("include", "exclude")),
  !any(duplicated(candidate_registry$variable))
)

# nolint end
