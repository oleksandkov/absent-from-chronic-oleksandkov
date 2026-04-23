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

# Six demographic variables for the sociodemographic portrait
demo_vars <- c(
  "age_group", "sex", "education",
  "income_5cat", "immigration_status", "visible_minority"
)

demo_labels <- c(
  age_group          = "Age group",
  sex                = "Sex",
  education          = "Education",
  income_5cat        = "Household income",
  immigration_status = "Immigration status",
  visible_minority   = "Visible minority status"
)

# Province / territory lookup (Statistics Canada geodgprv codes)
province_lookup <- c(
  "10" = "NL", "11" = "PEI", "12" = "NS", "13" = "NB",
  "24" = "QC", "35" = "ON", "46" = "MB", "47" = "SK",
  "48" = "AB", "59" = "BC", "60" = "YK", "61" = "NWT", "62" = "NU"
)

# ---- declare-functions -------------------------------------------------------
# (no notebook-specific helpers needed)

# ---- load-data ---------------------------------------------------------------
path_parquet <- "./data-private/derived/cchs-2-tables/cchs_analytical.parquet"
ds0 <- arrow::read_parquet(path_parquet)

message("Data loaded: ", nrow(ds0), " rows x ", ncol(ds0), " columns")

# ---- tweak-data-0 ------------------------------------------------------------
# Add province label column
ds0 <- ds0 %>%
  mutate(province = dplyr::recode(
    as.character(geodgprv),
    !!!province_lookup,
    .default = "Unknown"
  ))

# ---- data-context-tables -----------------------------------------------------
cat("\nTable: cchs_analytical.parquet\n")
cat("  Grain: one row per survey respondent\n")
cat("  Cycle 0 = CCHS 2010/2011 | Cycle 1 = CCHS 2013/2014\n\n")
cat("Cycle breakdown:\n")
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
         employment_type, work_schedule, province) %>%
  print()

# ---- data-context-distributions ----------------------------------------------
cat("\nAge group distribution (pooled):\n")
ds0 %>%
  count(age_group) %>%
  mutate(pct = scales::percent(n / sum(n), accuracy = 0.1)) %>%
  print()

cat("\nSex distribution (pooled):\n")
ds0 %>%
  count(sex) %>%
  mutate(pct = scales::percent(n / sum(n), accuracy = 0.1)) %>%
  print()

# ---- g1-data-prep ------------------------------------------------------------
# Six demographic dimensions as a long table suitable for faceted small-multiples
g1_data <- ds0 %>%
  select(all_of(demo_vars), cycle_f) %>%
  pivot_longer(all_of(demo_vars),
               names_to = "variable",
               values_to = "level",
               values_transform = list(level = as.character)) %>%
  mutate(level = as.character(level)) %>%
  filter(!is.na(level)) %>%
  group_by(variable, level) %>%
  summarise(n = n(), .groups = "drop_last") %>%
  mutate(pct = n / sum(n)) %>%
  ungroup() %>%
  mutate(
    variable = factor(variable, levels = demo_vars, labels = unname(demo_labels))
  )

# ---- g1 ----------------------------------------------------------------------
# Faceted horizontal bars — pooled sample proportions across 6 demographic vars
g1_demo_portrait <- g1_data %>%
  ggplot(aes(x = pct,
             y = fct_reorder(level, pct),
             fill = variable)) +
  geom_col(width = 0.7, show.legend = FALSE) +
  geom_text(aes(label = scales::percent(pct, accuracy = 0.1)),
            hjust = -0.1, size = 2.9) +
  facet_wrap(~variable, scales = "free_y", ncol = 2) +
  scale_x_continuous(
    labels = scales::percent_format(accuracy = 1),
    expand = expansion(mult = c(0, 0.20))
  ) +
  scale_fill_manual(values = unname(clr[c(
    "sky_blue", "orange", "green", "blue", "vermillon", "pink"
  )])) +
  labs(
    title   = "Sociodemographic portrait of the analytical sample",
    subtitle = "Pooled CCHS 2010/2011 + 2013/2014 (n = 63,843 employed respondents)",
    x       = "Proportion of sample",
    y       = NULL,
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    strip.text    = element_text(face = "bold"),
    panel.spacing = unit(1.2, "lines")
  )

ggsave(paste0(prints_folder, "g1_demo_portrait.png"),
       g1_demo_portrait, width = 8.5, height = 9, dpi = 300)
print(g1_demo_portrait)

# ---- g11 ---------------------------------------------------------------------
# Same six variables, split by cycle — cross-cycle demographic consistency check
g11_data <- ds0 %>%
  select(all_of(demo_vars), cycle_f) %>%
  pivot_longer(all_of(demo_vars),
               names_to = "variable",
               values_to = "level",
               values_transform = list(level = as.character)) %>%
  mutate(level = as.character(level)) %>%
  filter(!is.na(level)) %>%
  group_by(cycle_f, variable, level) %>%
  summarise(n = n(), .groups = "drop_last") %>%
  mutate(pct = n / sum(n)) %>%
  ungroup() %>%
  mutate(
    variable = factor(variable, levels = demo_vars, labels = unname(demo_labels))
  )

g11_cycle_consistency <- g11_data %>%
  ggplot(aes(x = pct,
             y = fct_reorder(level, pct),
             fill = cycle_f)) +
  geom_col(position = "dodge", width = 0.65) +
  facet_wrap(~variable, scales = "free_y", ncol = 2) +
  scale_x_continuous(
    labels = scales::percent_format(accuracy = 1),
    expand = expansion(mult = c(0, 0.08))
  ) +
  scale_fill_manual(values = c(clr["sky_blue"], clr["orange"])) +
  labs(
    title   = "Demographic profile by survey cycle",
    subtitle = "Parallel bars test for demographic shifts between 2010/11 and 2013/14",
    x       = "Proportion within cycle",
    y       = NULL,
    fill    = "Cycle",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    strip.text      = element_text(face = "bold"),
    legend.position = "bottom",
    panel.spacing   = unit(1.2, "lines")
  )

ggsave(paste0(prints_folder, "g11_cycle_consistency.png"),
       g11_cycle_consistency, width = 8.5, height = 9, dpi = 300)
print(g11_cycle_consistency)

# ---- g2-data-prep ------------------------------------------------------------
# Employment type × work schedule cross-tabulation
g2_data <- ds0 %>%
  filter(!is.na(employment_type), !is.na(work_schedule)) %>%
  count(employment_type, work_schedule) %>%
  group_by(employment_type) %>%
  mutate(pct_within = n / sum(n)) %>%
  ungroup()

# ---- g2 ----------------------------------------------------------------------
# Grouped bar: employment type × work schedule (absolute counts)
g2_employment_schedule <- g2_data %>%
  ggplot(aes(x = work_schedule, y = n, fill = employment_type)) +
  geom_col(position = "dodge", width = 0.65) +
  geom_text(aes(label = scales::comma(n)),
            position = position_dodge(width = 0.65),
            vjust = -0.4, size = 3) +
  scale_y_continuous(
    labels = scales::comma,
    expand = expansion(mult = c(0, 0.12))
  ) +
  scale_fill_manual(values = c(clr["blue"], clr["green"], clr["orange"])) +
  labs(
    title   = "Employment type by work schedule",
    subtitle = "Most employees work full-time; part-time is more common among self-employed",
    x       = "Work schedule",
    y       = "Number of respondents",
    fill    = "Employment type",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

ggsave(paste0(prints_folder, "g2_employment_schedule.png"),
       g2_employment_schedule, width = 8.5, height = 5.5, dpi = 300)
print(g2_employment_schedule)

# ---- g21 ---------------------------------------------------------------------
# Employment type composition by sex — stacked proportions
g21_employment_by_sex <- ds0 %>%
  filter(!is.na(employment_type), !is.na(sex)) %>%
  count(sex, employment_type) %>%
  group_by(sex) %>%
  mutate(pct = n / sum(n)) %>%
  ungroup() %>%
  ggplot(aes(x = sex, y = pct, fill = employment_type)) +
  geom_col(width = 0.55) +
  geom_text(aes(label = scales::percent(pct, accuracy = 1)),
            position = position_stack(vjust = 0.5),
            colour = "white", size = 3.5, fontface = "bold") +
  scale_y_continuous(labels = scales::percent_format()) +
  scale_fill_manual(values = c(clr["blue"], clr["green"], clr["orange"])) +
  labs(
    title   = "Employment type composition by sex",
    subtitle = "Gender differences in self-employment and unpaid/family work",
    x       = NULL,
    y       = "Proportion within sex",
    fill    = "Employment type",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

ggsave(paste0(prints_folder, "g21_employment_by_sex.png"),
       g21_employment_by_sex, width = 6.5, height = 5.5, dpi = 300)
print(g21_employment_by_sex)

# ---- g3-data-prep ------------------------------------------------------------
# Province distribution — total and by cycle
g3_data <- ds0 %>%
  filter(province != "Unknown") %>%
  count(province, cycle_f) %>%
  group_by(cycle_f) %>%
  mutate(pct_within_cycle = n / sum(n)) %>%
  ungroup()

# ---- g3 ----------------------------------------------------------------------
# Horizontal bar: total sample by province, sorted
g3_province <- g3_data %>%
  group_by(province) %>%
  summarise(n_total = sum(n), .groups = "drop") %>%
  ggplot(aes(x = n_total, y = fct_reorder(province, n_total))) +
  geom_col(fill = clr["blue"], width = 0.7) +
  geom_text(aes(label = scales::comma(n_total)), hjust = -0.1, size = 3.5) +
  scale_x_continuous(
    labels = scales::comma,
    expand = expansion(mult = c(0, 0.14))
  ) +
  labs(
    title   = "Sample size by province / territory",
    subtitle = "Pooled CCHS 2010/2011 + 2013/2014, unweighted counts",
    x       = "Number of respondents",
    y       = "Province / territory",
    caption = "Source: cchs_analytical.parquet (geodgprv)"
  ) +
  theme_minimal(base_size = 12)

ggsave(paste0(prints_folder, "g3_province.png"),
       g3_province, width = 8.5, height = 5.5, dpi = 300)
print(g3_province)

# ---- g31 ---------------------------------------------------------------------
# Province × cycle balance — same provinces should have similar shares each cycle
g31_province_cycle <- g3_data %>%
  ggplot(aes(x = pct_within_cycle,
             y = fct_reorder(province, pct_within_cycle),
             fill = cycle_f)) +
  geom_col(position = "dodge", width = 0.65) +
  scale_x_continuous(
    labels = scales::percent_format(accuracy = 0.1),
    expand = expansion(mult = c(0, 0.06))
  ) +
  scale_fill_manual(values = c(clr["sky_blue"], clr["orange"])) +
  labs(
    title   = "Provincial sample share by survey cycle",
    subtitle = "Consistent provincial representation across cycles confirms stable sampling frame",
    x       = "Share of cycle sample",
    y       = "Province / territory",
    fill    = "Cycle",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

ggsave(paste0(prints_folder, "g31_province_cycle.png"),
       g31_province_cycle, width = 8.5, height = 5.5, dpi = 300)
print(g31_province_cycle)

# nolint end
