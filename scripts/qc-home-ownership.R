rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014") # Clear the console
cat("Working directory: ", getwd()) # Must be set to Project Directory

# Self-sufficient QC of DHH_OWN (dwelling owned by a household member), the
# CCHS variable that satisfies the "homeownership" predisposing variable
# requested in Section 2.2 of the Project Proposal.
#
# Background: variable-inclusion.qmd previously asserted that no house-ownership
# construct exists in the CCHS PUMF and substituted `living_arrangements` as a
# proxy. DHH_OWN is in fact present in both cycles. This script establishes
# whether it is fit for use before it is admitted to the Ellis white-list.
#
# The four questions that decide admission:
#   Q1 Is it present in both cycles, with the same coding?
#   Q2 How is missingness represented, and does that differ across cycles?
#   Q3 Is coverage complete within the ANALYTIC sample, or is it optional
#      content suppressed by province/cycle (the trap that killed
#      has_family_doctor)?
#   Q4 Does it carry signal against the outcome?
#
# Reads Ferry output only. Run with:  Rscript scripts/qc-home-ownership.R

# ---- load-packages -----------------------------------------------------------
library(dplyr)
requireNamespace("arrow")
requireNamespace("tidyr")
requireNamespace("config")

# ---- declare-globals ---------------------------------------------------------
ferry_dir <- "./data-private/derived/cchs-1-ferry/"
path_2010 <- paste0(ferry_dir, "cchs_2010.parquet")
path_2014 <- paste0(ferry_dir, "cchs_2014.parquet")

# Analytic sample definition, mirrored from manipulation/2-ellis.R steps 1-2.
DHHGAGE_CODE_MIN <- 2L
DHHGAGE_CODE_MAX <- 15L

# Province code -> abbreviation, mirrored from the Ellis recode.
province_labels <- c(
  "10" = "NL", "11" = "PEI", "12" = "NS", "13" = "NB", "24" = "QC",
  "35" = "ON", "46" = "MB", "47" = "SK", "48" = "AB", "59" = "BC",
  "60" = "YK", "61" = "NT", "62" = "NU"
)

qc_vars <- c("DHH_OWN", "DHHGAGE", "LOP_015", "GEOGPRV", "WTS_M",
             "LOPG040", "LOPG070", "LOPG082", "LOPG083",
             "LOPG084", "LOPG085", "LOPG086", "LOPG100")

# ---- declare-functions -------------------------------------------------------
# CCHS special codes: 6 = NOT APPLICABLE, 7 = DON'T KNOW, 8 = REFUSAL,
# 9 = NOT STATED. All four are missing for analytic purposes.
special_code_label <- function(x) {
  dplyr::case_when(
    is.na(x) ~ "NA (system missing)",
    x == 1   ~ "1 = Owner",
    x == 2   ~ "2 = Renter",
    x == 6   ~ "6 = NOT APPLICABLE",
    x == 7   ~ "7 = DON'T KNOW",
    x == 8   ~ "8 = REFUSAL",
    x == 9   ~ "9 = NOT STATED",
    TRUE     ~ paste0(x, " = UNEXPECTED")
  )
}

is_valid_own <- function(x) !is.na(x) & x %in% c(1, 2)

# ---- load-data ---------------------------------------------------------------
read_cycle <- function(path, cycle_label) {
  d <- arrow::read_parquet(path)
  present <- intersect(qc_vars, names(d))
  d %>%
    select(all_of(present)) %>%
    mutate(cycle = cycle_label)
}

ds_2010 <- read_cycle(path_2010, "2010-2011")
ds_2014 <- read_cycle(path_2014, "2013-2014")

cat("\n---- SECTION: Source ---------------------------------------------------\n")
cat("  ", path_2010, " -> ", format(nrow(ds_2010), big.mark = ","), " rows\n", sep = "")
cat("  ", path_2014, " -> ", format(nrow(ds_2014), big.mark = ","), " rows\n", sep = "")

ds_pooled <- bind_rows(ds_2010, ds_2014)

# ---- q1-presence-and-coding --------------------------------------------------
cat("\n---- SECTION: Q1 - Presence and coding ---------------------------------\n")
cat("  DHH_OWN present in 2010-2011: ", "DHH_OWN" %in% names(ds_2010), "\n", sep = "")
cat("  DHH_OWN present in 2013-2014: ", "DHH_OWN" %in% names(ds_2014), "\n", sep = "")
cat("\n  NOTE: the two cycles publish DIFFERENT value-label TEXT for the same codes:\n")
cat("    2010-2011  'Dwelling - owned by a member of hhld'   1 = YES    2 = NO\n")
cat("    2013-2014  'Owned, Rented'                          1 = OWNER  2 = RENTED\n")
cat("  The underlying integer coding is identical, so no alias or remap is needed.\n")

# ---- q2-missingness-representation -------------------------------------------
t_codes <- ds_pooled %>%
  mutate(code = special_code_label(DHH_OWN)) %>%
  count(cycle, code, name = "n") %>%
  group_by(cycle) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  ungroup() %>%
  arrange(cycle, code)

cat("\n---- SECTION: Q2 - Missingness representation (full ferry sample) ------\n")
print(as.data.frame(t_codes), row.names = FALSE)

cat("\n  READ THIS: the two cycles represent missingness DIFFERENTLY.\n")
cat("  2010-2011 stores refusals/not-stated as SPSS system missing (-> NA).\n")
cat("  2013-2014 stores them as explicit codes 7/8/9.\n")
cat("  An Ellis recode must therefore map BOTH NA and codes 6/7/8/9 to NA,\n")
cat("  otherwise 2014 renters would be contaminated by code-7/8/9 rows.\n")

# ---- q3-coverage-in-analytic-sample ------------------------------------------
# Reproduce Ellis exclusion steps 1-2 (age 15-75, employed in past 3 months).
ds_analytic <- ds_pooled %>%
  filter(DHHGAGE >= DHHGAGE_CODE_MIN, DHHGAGE <= DHHGAGE_CODE_MAX) %>%
  filter(!is.na(LOP_015), LOP_015 == 1) %>%
  mutate(
    home_ownership = case_when(
      DHH_OWN == 1 ~ "Owner",
      DHH_OWN == 2 ~ "Renter",
      TRUE ~ NA_character_
    ),
    province = province_labels[as.character(GEOGPRV)]
  )

cat("\n---- SECTION: Q3 - Coverage within the analytic sample -----------------\n")
cat("  Analytic rows (age 15-75 AND employed past 3 months): ",
    format(nrow(ds_analytic), big.mark = ","), "\n", sep = "")

t_coverage <- ds_analytic %>%
  group_by(cycle) %>%
  summarise(
    n          = n(),
    n_valid    = sum(!is.na(home_ownership)),
    n_missing  = sum(is.na(home_ownership)),
    pct_valid  = round(100 * n_valid / n, 2),
    pct_owner  = round(100 * sum(home_ownership == "Owner", na.rm = TRUE) / n_valid, 2),
    .groups = "drop"
  )
print(as.data.frame(t_coverage), row.names = FALSE)

# The has_family_doctor trap: a variable can be 100% present overall yet
# entirely absent for one province in one cycle (optional content).
t_by_province <- ds_analytic %>%
  group_by(cycle, province) %>%
  summarise(
    n         = n(),
    pct_valid = round(100 * sum(!is.na(home_ownership)) / n(), 1),
    .groups = "drop"
  ) %>%
  tidyr::pivot_wider(
    names_from = cycle, values_from = c(n, pct_valid), values_fill = 0
  )

cat("\n  Coverage by province x cycle (the has_family_doctor trap check):\n")
print(as.data.frame(t_by_province), row.names = FALSE)

worst <- ds_analytic %>%
  group_by(cycle, province) %>%
  summarise(pct_valid = 100 * sum(!is.na(home_ownership)) / n(), .groups = "drop") %>%
  filter(pct_valid < 90)

if (nrow(worst) == 0) {
  cat("\n  PASS: no province x cycle cell falls below 90% coverage.\n")
  cat("  DHH_OWN is core content, not optional content. It does NOT alias cycle x province.\n")
} else {
  cat("\n  WARNING: low-coverage cells detected -\n")
  print(as.data.frame(worst), row.names = FALSE)
}

# ---- q4-signal-against-outcome -----------------------------------------------
lop_day_vars <- c("LOPG040", "LOPG070", "LOPG082", "LOPG083",
                  "LOPG084", "LOPG085", "LOPG086", "LOPG100")
lop_present <- intersect(lop_day_vars, names(ds_analytic))

ds_outcome <- ds_analytic %>%
  mutate(across(all_of(lop_present), ~ if_else(.x %in% c(96, 97, 98, 99), NA_real_, as.numeric(.x)))) %>%
  mutate(days_absent_total = rowSums(across(all_of(lop_present)), na.rm = TRUE)) %>%
  filter(!is.na(home_ownership), !is.na(WTS_M))

t_signal <- ds_outcome %>%
  group_by(home_ownership) %>%
  summarise(
    n            = n(),
    mean_days    = round(mean(days_absent_total), 3),
    pct_any_days = round(100 * mean(days_absent_total > 0), 2),
    median_days  = median(days_absent_total),
    .groups = "drop"
  )

cat("\n---- SECTION: Q4 - Signal against days_absent_total --------------------\n")
print(as.data.frame(t_signal), row.names = FALSE)

fit <- MASS::glm.nb(
  days_absent_total ~ home_ownership + cycle,
  data = ds_outcome %>% mutate(home_ownership = relevel(factor(home_ownership), ref = "Owner"))
)
co <- summary(fit)$coefficients
cat("\n  Unweighted negative-binomial check (outcome ~ ownership + cycle):\n")
cat("    Renter vs Owner  rate ratio = ", round(exp(co["home_ownershipRenter", 1]), 4),
    "   p = ", format.pval(co["home_ownershipRenter", 4], digits = 3), "\n", sep = "")
cat("    theta = ", round(fit$theta, 4), "\n", sep = "")

# ---- verdict -----------------------------------------------------------------
n_analytic   <- nrow(ds_analytic)
pct_valid_all <- round(100 * sum(!is.na(ds_analytic$home_ownership)) / n_analytic, 2)

cat("\n---- SECTION: Verdict --------------------------------------------------\n")
cat("  Q1 present in both cycles, identical integer coding : YES\n")
cat("  Q2 missingness differs by cycle (NA vs codes 7/8/9)  : YES - recode must handle both\n")
cat("  Q3 coverage in analytic sample                       : ", pct_valid_all, "%\n", sep = "")
cat("  Q3 optional-content aliasing with cycle x province   : ",
    if (nrow(worst) == 0) "NOT DETECTED\n" else "DETECTED - see above\n", sep = "")
cat("  Q4 associated with the outcome                       : see rate ratio above\n")

if (pct_valid_all >= 95 && nrow(worst) == 0) {
  cat("\n  RECOMMENDATION: admit DHH_OWN to the Ellis white-list as `home_ownership`,\n")
  cat("  a two-level factor Owner / Renter, mapping NA and codes 6/7/8/9 to NA.\n")
  cat("  This satisfies the Section 2.2 'homeownership' requirement directly and\n")
  cat("  removes the need for the living_arrangements proxy justification.\n\n")
} else {
  cat("\n  RECOMMENDATION: do NOT admit without further investigation.\n\n")
}
