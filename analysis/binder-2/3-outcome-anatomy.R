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

# Ordered outcome bands (cap at 90 per CCHS LOP design)
absence_band_levels <- c("0 days", "1-5 days", "6-15 days",
                          "16-30 days", "31-90 days", "Missing")

# LOP component variable names present in cchs_analytical
lop_candidate_vars <- c("lopg040", "lopg045", "lopg050", "lopg055",
                         "lopg060", "lopg065", "lopg070", "lopg100")

# Short labels for LOP components (used in graphs)
lop_short_labels <- c(
  lopg040 = "LOP040: Chronic condition",
  lopg045 = "LOP045: Emotional/mental",
  lopg050 = "LOP050: Acute/injury",
  lopg055 = "LOP055: Unclassified",
  lopg060 = "LOP060: Side effects",
  lopg065 = "LOP065: Maternity",
  lopg070 = "LOP070: Work-related",
  lopg100 = "LOP100: Other reason"
)

# ---- declare-functions -------------------------------------------------------
# (no notebook-specific helpers needed)

# ---- load-data ---------------------------------------------------------------
path_parquet <- "./data-private/derived/cchs-2-tables/cchs_analytical.parquet"
ds0 <- arrow::read_parquet(path_parquet)

message("Data loaded: ", nrow(ds0), " rows x ", ncol(ds0), " columns")

# ---- tweak-data-0 ------------------------------------------------------------
# Store only actually available LOP variables
lop_vars_present <- intersect(lop_candidate_vars, colnames(ds0))
message("LOP components found: ", paste(lop_vars_present, collapse = ", "))

# Add outcome band column
ds0 <- ds0 %>%
  mutate(
    absence_band = dplyr::case_when(
      is.na(days_absent_total)       ~ "Missing",
      days_absent_total == 0         ~ "0 days",
      days_absent_total <= 5         ~ "1-5 days",
      days_absent_total <= 15        ~ "6-15 days",
      days_absent_total <= 30        ~ "16-30 days",
      TRUE                           ~ "31-90 days"
    ),
    absence_band = factor(absence_band, levels = absence_band_levels)
  )

# ---- data-context-tables -----------------------------------------------------
cat("\nOutcome variable: days_absent_total\n")
cat("  N non-missing :", sum(!is.na(ds0$days_absent_total)), "\n")
cat("  % zero        :", scales::percent(
    mean(ds0$days_absent_total == 0, na.rm = TRUE), accuracy = 0.1), "\n")
cat("  Mean  (non-zero)  :", round(
    mean(ds0$days_absent_total[ds0$days_absent_total > 0], na.rm = TRUE), 2), "\n")
cat("  Median (non-zero) :", median(
    ds0$days_absent_total[ds0$days_absent_total > 0], na.rm = TRUE), "\n")
cat("  SD    (non-zero)  :", round(
    sd(ds0$days_absent_total[ds0$days_absent_total > 0], na.rm = TRUE), 2), "\n")

# ---- data-context-person -----------------------------------------------------
cat("\nZero-absence respondent:\n")
ds0 %>%
  filter(days_absent_total == 0) %>%
  slice(1) %>%
  select(cycle_f, age_group, sex, days_absent_total, absence_band) %>%
  print()

cat("\nHigh-absence respondent (> 30 days):\n")
ds0 %>%
  filter(!is.na(days_absent_total), days_absent_total > 30) %>%
  slice(1) %>%
  select(cycle_f, age_group, sex, days_absent_total, absence_band) %>%
  print()

# ---- data-context-distributions ----------------------------------------------
cat("\nOutcome band distribution (pooled):\n")
ds0 %>%
  count(absence_band) %>%
  mutate(pct = scales::percent(n / sum(n), accuracy = 0.1)) %>%
  print()

# ---- g1-data-prep ------------------------------------------------------------
# Outcome band counts, pooled and by cycle
g1_data <- ds0 %>%
  count(absence_band, cycle_f)

g1_pooled <- ds0 %>%
  count(absence_band) %>%
  mutate(pct = n / sum(n))

# ---- g1 ----------------------------------------------------------------------
# Zero-inflation portrait — pooled sample
g1_zero_inflation <- g1_pooled %>%
  ggplot(aes(x = absence_band, y = pct,
             fill = absence_band == "0 days")) +
  geom_col(width = 0.7, show.legend = FALSE) +
  geom_text(aes(label = scales::percent(pct, accuracy = 0.1)),
            vjust = -0.4, size = 4) +
  scale_y_continuous(
    labels = scales::percent_format(),
    expand = expansion(mult = c(0, 0.12))
  ) +
  scale_fill_manual(values = c("FALSE" = clr["sky_blue"],
                               "TRUE"  = clr["vermillon"])) +
  labs(
    title   = "Distribution of work-absence days — zero-inflation portrait",
    subtitle = "Red bar = structural zero cluster (~70%); blue bars = positive-count distribution",
    x       = "Absence band",
    y       = "Proportion of sample",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 12)

ggsave(paste0(prints_folder, "g1_zero_inflation.png"),
       g1_zero_inflation, width = 8.5, height = 5.5, dpi = 300)
print(g1_zero_inflation)

# ---- g11 ---------------------------------------------------------------------
# Absence band distribution by cycle — did the zero-inflation shift?
g11_by_cycle <- g1_data %>%
  group_by(cycle_f) %>%
  mutate(pct = n / sum(n)) %>%
  ungroup() %>%
  ggplot(aes(x = absence_band, y = pct, fill = cycle_f)) +
  geom_col(position = "dodge", width = 0.7) +
  scale_y_continuous(
    labels = scales::percent_format(),
    expand = expansion(mult = c(0, 0.08))
  ) +
  scale_fill_manual(values = c(clr["sky_blue"], clr["orange"])) +
  labs(
    title   = "Absence band distribution by survey cycle",
    subtitle = "Parallel bars reveal whether zero-inflation and positive tails shifted between cycles",
    x       = "Absence band",
    y       = "Proportion within cycle",
    fill    = "Cycle",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

ggsave(paste0(prints_folder, "g11_by_cycle.png"),
       g11_by_cycle, width = 8.5, height = 5.5, dpi = 300)
print(g11_by_cycle)

# ---- g2-data-prep ------------------------------------------------------------
# LOP component statistics: completeness + mean days for positive cases
g2_data <- ds0 %>%
  select(all_of(lop_vars_present)) %>%
  pivot_longer(everything(), names_to = "component", values_to = "days") %>%
  group_by(component) %>%
  summarise(
    pct_nonmissing      = mean(!is.na(days)),
    mean_days_nonzero   = mean(days[days > 0], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    component_label = dplyr::recode(component, !!!lop_short_labels),
    component_label = fct_reorder(component_label, mean_days_nonzero,
                                  .na_rm = TRUE)
  )

# ---- g2 ----------------------------------------------------------------------
# Mean absence days per LOP component (positive cases only), fill = completeness
g2_lop_components <- g2_data %>%
  ggplot(aes(x = mean_days_nonzero,
             y = component_label,
             fill = pct_nonmissing)) +
  geom_col(width = 0.7) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.08))) +
  scale_fill_gradient(
    low    = clr["sky_blue"],
    high   = clr["blue"],
    labels = scales::percent_format(accuracy = 1)
  ) +
  labs(
    title   = "Mean absence days per LOP component (positive cases only)",
    subtitle = "Fill intensity = proportion of respondents with non-missing LOP value",
    x       = "Mean days absent (positive cases)",
    y       = NULL,
    fill    = "% non-missing",
    caption = "Source: cchs_analytical.parquet | lopg040 – lopg100"
  ) +
  theme_minimal(base_size = 11)

ggsave(paste0(prints_folder, "g2_lop_components.png"),
       g2_lop_components, width = 8.5, height = 5.5, dpi = 300)
print(g2_lop_components)

# ---- g21 ---------------------------------------------------------------------
# LOP completeness portrait — % non-missing per component
g21_lop_completeness <- g2_data %>%
  ggplot(aes(x = pct_nonmissing,
             y = fct_reorder(component_label, pct_nonmissing))) +
  geom_col(fill = clr["green"], width = 0.7) +
  geom_text(aes(label = scales::percent(pct_nonmissing, accuracy = 0.1)),
            hjust = -0.1, size = 3.5) +
  scale_x_continuous(
    labels = scales::percent_format(accuracy = 1),
    limits = c(0, 1.05),
    expand = expansion(mult = c(0, 0))
  ) +
  labs(
    title   = "LOP component data availability",
    subtitle = "% of respondents with a non-missing value for each work-absence component",
    x       = "% non-missing",
    y       = NULL,
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 11)

ggsave(paste0(prints_folder, "g21_lop_completeness.png"),
       g21_lop_completeness, width = 8.5, height = 5.5, dpi = 300)
print(g21_lop_completeness)

# ---- g3-data-prep ------------------------------------------------------------
# Restrict to positive-absence cases; compute median for annotation
ds_positive <- ds0 %>%
  filter(!is.na(days_absent_total), days_absent_total > 0)

median_days <- median(ds_positive$days_absent_total)
mean_days   <- round(mean(ds_positive$days_absent_total), 1)

message("Positive-absence subset: n = ", nrow(ds_positive),
        " | median = ", median_days, " | mean = ", mean_days)

# ---- g3 ----------------------------------------------------------------------
# Histogram of non-zero absence days with median annotation
g3_nonzero_hist <- ds_positive %>%
  ggplot(aes(x = days_absent_total)) +
  geom_histogram(binwidth = 3, fill = clr["sky_blue"],
                 colour = "white", boundary = 0) +
  geom_vline(xintercept = median_days, linetype = "dashed",
             colour = clr["vermillon"], linewidth = 0.9) +
  annotate("text",
           x = median_days + 1.5, y = Inf,
           vjust = 1.6, hjust = 0,
           label = paste0("Median = ", median_days, " days"),
           colour = clr["vermillon"], size = 3.5) +
  scale_x_continuous(breaks = seq(0, 90, 10),
                     expand = expansion(mult = c(0.01, 0.01))) +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title   = "Distribution of work-absence days (positive cases only)",
    subtitle = paste0(scales::comma(nrow(ds_positive)),
                      " respondents reporting > 0 absent days (", 
                      scales::percent(nrow(ds_positive) / nrow(ds0), accuracy = 0.1),
                      " of sample)"),
    x       = "Days absent (total)",
    y       = "Count",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 12)

ggsave(paste0(prints_folder, "g3_nonzero_hist.png"),
       g3_nonzero_hist, width = 8.5, height = 5.5, dpi = 300)
print(g3_nonzero_hist)

# ---- g31 ---------------------------------------------------------------------
# Non-zero absence distribution by age group — first bivariate signal
g31_nonzero_by_age <- ds_positive %>%
  filter(!is.na(age_group)) %>%
  ggplot(aes(x = days_absent_total, fill = age_group)) +
  geom_histogram(binwidth = 5, colour = "white", boundary = 0) +
  facet_wrap(~age_group, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(0, 90, 15),
                     expand = expansion(mult = c(0.01, 0.01))) +
  scale_y_continuous(labels = scales::comma) +
  scale_fill_manual(values = c(clr["sky_blue"], clr["orange"], clr["green"])) +
  labs(
    title   = "Non-zero absence days by age group",
    subtitle = "First bivariate signal — does the positive-count distribution shift with age?",
    x       = "Days absent (total)",
    y       = "Count",
    fill    = "Age group",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none",
        strip.text = element_text(face = "bold"))

ggsave(paste0(prints_folder, "g31_nonzero_by_age.png"),
       g31_nonzero_by_age, width = 8.5, height = 7, dpi = 300)
print(g31_nonzero_by_age)

# nolint end
