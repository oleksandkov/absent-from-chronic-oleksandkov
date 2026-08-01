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
# included_vars, vars_excluding_perceived, vars_including_perceived,
# variable_labels_registry, variable_domains_registry.

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
  "dhhgle5",                 "Predisposing", "Children age 0-5",               "include", "",
  "dhhg611",                 "Predisposing", "Children age 6-11",              "include", "",
  "dhhgl12",                 "Predisposing", "Children age 12+",               "include", "",
  "education",               "Predisposing", "Education",                      "include", "",
  "immigration_status",      "Predisposing", "Immigration status",             "include", "",
  "visible_minority",        "Predisposing", "Visible minority",               "include", "",
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
vars_excluding_perceived <- setdiff(included_vars, perceived_health_vars)
vars_including_perceived <- included_vars

variable_labels_registry <- stats::setNames(
  candidate_registry$variable_label, candidate_registry$variable
)
variable_domains_registry <- stats::setNames(
  candidate_registry$domain, candidate_registry$variable
)

# Guard against silent divergence. The registry holds 51 variables, of which 3
# are excluded, leaving 48 eligible. Note that the narrative in model-1.qmd says
# "50 registered candidates" and "47 of 50" in places; those figures are prose
# and are off by one. The computed captions in model-1 are correct.
stopifnot(
  nrow(candidate_registry) == 51L,
  length(included_vars) == 48L,
  all(candidate_registry$status %in% c("include", "exclude")),
  !any(duplicated(candidate_registry$variable))
)

# nolint end
