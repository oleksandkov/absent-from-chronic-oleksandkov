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
library(DBI)
library(RSQLite)
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
path_parquet  <- "./data-private/derived/cchs-2-tables/cchs_analytical.parquet"
path_sqlite   <- "./data-private/derived/cchs-1.sqlite"

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

# Special / invalid codes common across CCHS variables (→ NA in Ellis)
special_codes <- c(6, 7, 8, 9, 96, 97, 98, 99)

# ---- declare-functions -------------------------------------------------------
# Mark whether a raw code is a valid response or a special code
label_special <- function(x) {
  dplyr::if_else(x %in% special_codes, "Special / NA", "Valid response")
}

# Safely pivot a raw table column into a long freq tibble
raw_freq <- function(tbl, varname, cycle_label) {
  if (!varname %in% names(tbl)) return(tibble())
  tbl %>%
    transmute(raw_code = as.integer(.data[[varname]])) %>%
    count(raw_code) %>%
    mutate(cycle = cycle_label,
           code_type = label_special(raw_code))
}

# ---- load-data ---------------------------------------------------------------
ds0 <- arrow::read_parquet(path_parquet)

con      <- DBI::dbConnect(RSQLite::SQLite(), path_sqlite)
raw_2010 <- DBI::dbReadTable(con, "cchs_2010_raw") %>% as_tibble()
raw_2014 <- DBI::dbReadTable(con, "cchs_2014_raw") %>% as_tibble()
DBI::dbDisconnect(con)

# Standardise column names to uppercase
names(raw_2010) <- toupper(names(raw_2010))
names(raw_2014) <- toupper(names(raw_2014))

message("Analytical : ", nrow(ds0),     " rows x ", ncol(ds0),     " cols")
message("Raw 2010   : ", nrow(raw_2010), " rows x ", ncol(raw_2010), " cols")
message("Raw 2014   : ", nrow(raw_2014), " rows x ", ncol(raw_2014), " cols")

# ---- tweak-data-0 ------------------------------------------------------------
# No global tweaks — each graph family works on its own derived slice.

# ---- data-context-tables -----------------------------------------------------
cat("\nData sources used in this notebook:\n")
cat("  Raw (Ferry)  : cchs-1.sqlite  →  cchs_2010_raw, cchs_2014_raw\n")
cat("  Analytical   : cchs_analytical.parquet  (Ellis output)\n\n")

cat("Raw 2010 column count:", ncol(raw_2010), "\n")
cat("Raw 2014 column count:", ncol(raw_2014), "\n\n")

cat("Candidate raw variables — availability check:\n")
candidates <- c("GENDHDI", "SMKDSCTY", "INCDGHH", "INCDH")
for (v in candidates) {
  cat(sprintf("  %-12s  in 2010: %-3s  in 2014: %-3s\n",
              v,
              ifelse(v %in% names(raw_2010), "YES", "no"),
              ifelse(v %in% names(raw_2014), "YES", "no")))
}

# ---- data-context-person -----------------------------------------------------
# One raw respondent from 2014 for the three focal variables
focal_raw <- c("GENDHDI", "SMKDSCTY")
focal_raw_present <- intersect(focal_raw, names(raw_2014))

if (length(focal_raw_present) > 0) {
  cat("\nFirst raw 2014 respondent (focal variables only):\n")
  raw_2014 %>%
    select(all_of(focal_raw_present)) %>%
    slice(1) %>%
    print()
}

# ---- data-context-distributions ----------------------------------------------
cat("\nAnalytical self_health_general distribution:\n")
ds0 %>%
  count(self_health_general) %>%
  mutate(pct = scales::percent(n / sum(n), accuracy = 0.1)) %>%
  print()

cat("\nAnalytical smoking_status distribution:\n")
ds0 %>%
  count(smoking_status) %>%
  mutate(pct = scales::percent(n / sum(n), accuracy = 0.1)) %>%
  print()

# ---- g1-data-prep ------------------------------------------------------------
# Transformation 1: GENDHDI → self_health_general
# Raw: 1 = Excellent, 2 = Very good, 3 = Good, 4 = Fair, 5 = Poor, 6–9 = special → NA
g1_raw_data <- bind_rows(
  raw_freq(raw_2010, "GENDHDI", "2010/11"),
  raw_freq(raw_2014, "GENDHDI", "2013/14")
)

g1_code_labels <- c(
  "1" = "1 – Excellent",
  "2" = "2 – Very good",
  "3" = "3 – Good",
  "4" = "4 – Fair",
  "5" = "5 – Poor"
)

if (nrow(g1_raw_data) > 0) {
  g1_raw_data <- g1_raw_data %>%
    mutate(
      label = dplyr::recode(as.character(raw_code),
                            !!!g1_code_labels,
                            .default = paste0(raw_code, " (special/NA)")),
      label = fct_inorder(label)
    )
}

# ---- g1 ----------------------------------------------------------------------
# Before Ellis: raw GENDHDI codes by cycle
g1_raw_health <- if (nrow(g1_raw_data) > 0) {
  g1_raw_data %>%
    ggplot(aes(x = label, y = n, fill = code_type)) +
    geom_col(width = 0.7, show.legend = FALSE) +
    facet_wrap(~cycle, nrow = 1) +
    scale_y_continuous(labels = scales::comma) +
    scale_fill_manual(values = c("Valid response"  = clr["sky_blue"],
                                 "Special / NA"    = "grey70")) +
    labs(
      title   = "Before Ellis: raw GENDHDI codes from Ferry output",
      subtitle = "Grey bars (codes 6–9) are special / refusal codes → recoded to NA by Ellis",
      x       = "Raw GENDHDI code",
      y       = "Count",
      caption = "Source: cchs_2010_raw / cchs_2014_raw (cchs-1.sqlite)"
    ) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 25, hjust = 1))
} else {
  ggplot() +
    annotate("text", x = 0.5, y = 0.5,
             label = "GENDHDI not found in raw tables") +
    theme_void()
}

ggsave(paste0(prints_folder, "g1_raw_health.png"),
       g1_raw_health, width = 8.5, height = 5.5, dpi = 300)
print(g1_raw_health)

# ---- g11 ---------------------------------------------------------------------
# After Ellis: self_health_general analytical ordered factor
g11_analytical_health <- ds0 %>%
  filter(!is.na(self_health_general)) %>%
  count(cycle_f, self_health_general) %>%
  group_by(cycle_f) %>%
  mutate(pct = n / sum(n)) %>%
  ungroup() %>%
  ggplot(aes(x = self_health_general, y = pct, fill = cycle_f)) +
  geom_col(position = "dodge", width = 0.65) +
  scale_y_continuous(
    labels = scales::percent_format(),
    expand = expansion(mult = c(0, 0.08))
  ) +
  scale_fill_manual(values = c(clr["sky_blue"], clr["orange"])) +
  labs(
    title   = "After Ellis: self_health_general — ordered factor, special codes removed",
    subtitle = "Levels are properly ordered Excellent → Poor; codes 6–9 excluded as NA",
    x       = "Self-rated general health",
    y       = "Proportion within cycle",
    fill    = "Cycle",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 20, hjust = 1))

ggsave(paste0(prints_folder, "g11_analytical_health.png"),
       g11_analytical_health, width = 8.5, height = 5.5, dpi = 300)
print(g11_analytical_health)

# ---- g2-data-prep ------------------------------------------------------------
# Transformation 2: SMKDSCTY → smoking_status
# Raw: 1 = Daily, 2 = Occasional, 3 = Former, 4 = Never; 6–9/96–99 = special → NA
g2_raw_data <- bind_rows(
  raw_freq(raw_2010, "SMKDSCTY", "2010/11"),
  raw_freq(raw_2014, "SMKDSCTY", "2013/14")
)

g2_code_labels <- c(
  "1" = "1 – Daily",
  "2" = "2 – Occasional",
  "3" = "3 – Former",
  "4" = "4 – Never"
)

if (nrow(g2_raw_data) > 0) {
  g2_raw_data <- g2_raw_data %>%
    mutate(
      label = dplyr::recode(as.character(raw_code),
                            !!!g2_code_labels,
                            .default = paste0(raw_code, " (special/NA)")),
      label = fct_inorder(label)
    )
}

# ---- g2 ----------------------------------------------------------------------
# Before Ellis: raw SMKDSCTY codes by cycle
g2_raw_smoking <- if (nrow(g2_raw_data) > 0) {
  g2_raw_data %>%
    ggplot(aes(x = label, y = n, fill = code_type)) +
    geom_col(width = 0.7, show.legend = FALSE) +
    facet_wrap(~cycle, nrow = 1) +
    scale_y_continuous(labels = scales::comma) +
    scale_fill_manual(values = c("Valid response" = clr["green"],
                                 "Special / NA"   = "grey70")) +
    labs(
      title   = "Before Ellis: raw SMKDSCTY codes from Ferry output",
      subtitle = "Grey bars = special / refusal codes → recoded to NA by Ellis",
      x       = "Raw SMKDSCTY code",
      y       = "Count",
      caption = "Source: cchs_2010_raw / cchs_2014_raw (cchs-1.sqlite)"
    ) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 25, hjust = 1))
} else {
  ggplot() +
    annotate("text", x = 0.5, y = 0.5,
             label = "SMKDSCTY not found in raw tables") +
    theme_void()
}

ggsave(paste0(prints_folder, "g2_raw_smoking.png"),
       g2_raw_smoking, width = 8.5, height = 5.5, dpi = 300)
print(g2_raw_smoking)

# ---- g21 ---------------------------------------------------------------------
# After Ellis: smoking_status analytical ordered factor
# Ellis reverses the raw ordering → Never < Former < Occasional < Daily
g21_analytical_smoking <- ds0 %>%
  filter(!is.na(smoking_status)) %>%
  count(cycle_f, smoking_status) %>%
  group_by(cycle_f) %>%
  mutate(pct = n / sum(n)) %>%
  ungroup() %>%
  ggplot(aes(x = smoking_status, y = pct, fill = cycle_f)) +
  geom_col(position = "dodge", width = 0.65) +
  scale_y_continuous(
    labels = scales::percent_format(),
    expand = expansion(mult = c(0, 0.08))
  ) +
  scale_fill_manual(values = c(clr["sky_blue"], clr["orange"])) +
  labs(
    title   = "After Ellis: smoking_status — ordered factor (Never → Daily)",
    subtitle = "Special codes removed; level order reversed vs raw for natural gradient",
    x       = "Smoking status",
    y       = "Proportion within cycle",
    fill    = "Cycle",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(paste0(prints_folder, "g21_analytical_smoking.png"),
       g21_analytical_smoking, width = 8.5, height = 5.5, dpi = 300)
print(g21_analytical_smoking)

# ---- g3-data-prep ------------------------------------------------------------
# Transformation 3: Raw household income → income_5cat
# Try known CCHS income variable names in order of likelihood
income_var_candidates_2010 <- intersect(
  c("INCDGHH", "INCDH", "INCDHH", "INCADGHH"), names(raw_2010)
)
income_var_candidates_2014 <- intersect(
  c("INCDGHH", "INCDH", "INCDHH", "INCADGHH"), names(raw_2014)
)

income_var_2010 <- if (length(income_var_candidates_2010) > 0) income_var_candidates_2010[1] else NULL
income_var_2014 <- if (length(income_var_candidates_2014) > 0) income_var_candidates_2014[1] else NULL

g3_raw_data <- bind_rows(
  if (!is.null(income_var_2010)) raw_freq(raw_2010, income_var_2010, "2010/11"),
  if (!is.null(income_var_2014)) raw_freq(raw_2014, income_var_2014, "2013/14")
)

message("Income variable used — 2010: ", ifelse(is.null(income_var_2010), "none", income_var_2010),
        " | 2014: ", ifelse(is.null(income_var_2014), "none", income_var_2014))

# ---- g3 ----------------------------------------------------------------------
# Before Ellis: raw income codes by cycle
g3_raw_income <- if (nrow(g3_raw_data) > 0) {
  g3_raw_data %>%
    ggplot(aes(x = factor(raw_code), y = n, fill = code_type)) +
    geom_col(width = 0.7, show.legend = FALSE) +
    facet_wrap(~cycle, nrow = 1) +
    scale_y_continuous(labels = scales::comma) +
    scale_fill_manual(values = c("Valid response" = clr["orange"],
                                 "Special / NA"   = "grey70")) +
    labs(
      title   = "Before Ellis: raw household income codes from Ferry output",
      subtitle = "Grey bars = special / refusal codes → recoded to NA by Ellis",
      x       = "Raw income code",
      y       = "Count",
      caption = paste0("Source: cchs-1.sqlite (",
                       ifelse(!is.null(income_var_2014), income_var_2014, "not found"), ")")
    ) +
    theme_minimal(base_size = 11)
} else {
  ggplot() +
    annotate("text", x = 0.5, y = 0.5,
             label = "No household income variable found in raw tables.\nCheck raw column names in data-context chunk.") +
    labs(title = "Before Ellis: raw income variable not found") +
    theme_void()
}

ggsave(paste0(prints_folder, "g3_raw_income.png"),
       g3_raw_income, width = 8.5, height = 5.5, dpi = 300)
print(g3_raw_income)

# ---- g31 ---------------------------------------------------------------------
# After Ellis: income_5cat analytical ordered factor
g31_analytical_income <- ds0 %>%
  filter(!is.na(income_5cat)) %>%
  count(cycle_f, income_5cat) %>%
  group_by(cycle_f) %>%
  mutate(pct = n / sum(n)) %>%
  ungroup() %>%
  ggplot(aes(x = income_5cat, y = pct, fill = cycle_f)) +
  geom_col(position = "dodge", width = 0.65) +
  scale_y_continuous(
    labels = scales::percent_format(),
    expand = expansion(mult = c(0, 0.08))
  ) +
  scale_fill_manual(values = c(clr["sky_blue"], clr["orange"])) +
  labs(
    title   = "After Ellis: income_5cat — ordered 5-level income factor",
    subtitle = "Cross-cycle harmonized into 5 comparable income bands; refusal codes removed",
    x       = "Household income category",
    y       = "Proportion within cycle",
    fill    = "Cycle",
    caption = "Source: cchs_analytical.parquet"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        axis.text.x     = element_text(angle = 20, hjust = 1))

ggsave(paste0(prints_folder, "g31_analytical_income.png"),
       g31_analytical_income, width = 8.5, height = 5.5, dpi = 300)
print(g31_analytical_income)

# nolint end
