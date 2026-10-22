# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# EDA-71: LOP Outcome Profile — Distribution Structure for Statistical Modeling Context
# Mode: EDA (explore with open mind)
rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014") # Clear the console

# Guard: ensure working directory is the project root (where flow.R lives).
# VS Code's R extension may launch scripts from the file's own directory.
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
library(kableExtra)
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
local_root           <- "./analysis/eda-71/"
local_data           <- paste0(local_root, "data-local/")
prints_folder        <- paste0(local_root, "prints/")
data_private_derived <- "./data-private/derived/eda-71/"

if (!fs::dir_exists(local_data))           fs::dir_create(local_data)
if (!fs::dir_exists(prints_folder))        fs::dir_create(prints_folder)
if (!fs::dir_exists(data_private_derived)) fs::dir_create(data_private_derived)

path_cchs2_parquet <- "./data-private/derived/cchs-2-tables"
path_analytical_pq <- file.path(path_cchs2_parquet, "cchs_analytic.parquet")
weight_col         <- "wts_m_pooled"

lop_components <- c(
  "lopg040" = "Chronic condition",
  "lopg070" = "Injury",
  "lopg082" = "Cold",
  "lopg083" = "Flu / influenza",
  "lopg084" = "Gastroenteritis",
  "lopg085" = "Respiratory infection",
  "lopg086" = "Other infectious disease",
  "lopg100" = "Other physical / mental health"
)

# Ordered factor levels for frequency bins (positive counts only; 0-day excluded from x-axis)
bin_levels <- c(
  "1 day", "2 days", "3 days", "4 days", "5 days",
  "6\u201310 days", "11\u201315 days", "16\u201330 days", "31+ days"
)

# Ordered factor levels for G2/G21 individual-day display (1-30 days + 31+)
day_levels_g2 <- c(
  paste(1:30, ifelse(1:30 == 1, "day", "days")),
  "31+ days"
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
  names(lop_components)
)
missing_required <- setdiff(required_cols, names(ds0))
if (length(missing_required) > 0) {
  stop("Missing required columns: ", paste(missing_required, collapse = ", "), call. = FALSE)
}

cat(sprintf("Loaded: %s rows, %s columns\n",
            format(nrow(ds0), big.mark = ","),
            format(ncol(ds0), big.mark = ",")))

# ---- data-context-tables -----------------------------------------------------
data_context_tables <- tibble::tibble(
  source_table = "cchs_analytic.parquet",
  location     = path_analytical_pq,
  rows         = nrow(ds0),
  columns      = ncol(ds0),
  usage        = paste(
    "All 8 raw LOP component columns + derived days_absent_total,",
    "days_absent_chronic, and pooled survey weight wts_m_pooled"
  )
)
print(data_context_tables)

# ---- data-context-person -----------------------------------------------------
# A respondent with >=1 day on at least two LOP components — shows the key columns
data_context_person <- ds0 %>%
  select(
    cchs_cycle_f, !!weight_col,
    days_absent_total, days_absent_chronic,
    all_of(names(lop_components))
  ) %>%
  filter(
    rowSums(
      select(., all_of(names(lop_components))) > 0,
      na.rm = TRUE
    ) >= 2
  ) %>%
  slice_head(n = 2)
print(data_context_person)

# ---- data-context-distributions ----------------------------------------------
# Per-component: weighted prevalence (% positive), unweighted mean, and median
data_context_distributions <- ds0 %>%
  summarise(
    across(
      all_of(names(lop_components)),
      list(
        n_positive   = ~ sum(.x > 0,  na.rm = TRUE),
        pct_positive = ~ mean(.x > 0, na.rm = TRUE) * 100,
        mean_days    = ~ mean(.x,     na.rm = TRUE),
        median_days  = ~ median(.x,   na.rm = TRUE)
      )
    )
  ) %>%
  tidyr::pivot_longer(
    cols          = everything(),
    names_to      = c("column", ".value"),
    names_pattern = "^(.+)_(n_positive|pct_positive|mean_days|median_days)$"
  ) %>%
  mutate(reason_label = lop_components[column]) %>%
  select(reason_label, column, n_positive, pct_positive, mean_days, median_days) %>%
  arrange(desc(pct_positive))
print(data_context_distributions)

# ---- data-context-response-span -----------------------------------------------
# Comprehensive LOP response span: raw counts for each LOP variable by day value
lop_response_span <- tibble::tibble(day_value = 0:90)

# Add counts for each LOP variable
for (var in names(lop_components)) {
  lop_response_span <- lop_response_span %>%
    mutate(
      !!var := sapply(day_value, function(d) sum(ds0[[var]] == d, na.rm = TRUE))
    )
}

# Add days_absent_total
lop_response_span <- lop_response_span %>%
  mutate(
    days_absent_total = sapply(day_value, function(d) sum(ds0$days_absent_total == d, na.rm = TRUE))
  ) %>%
  # Filter to rows where at least one LOP variable has > 0 count
  filter(if_any(!day_value, ~ . > 0)) %>%
  # Reorder columns: Day first, then Total, then Chronic (lopg040), then other LOP vars
  select(day_value, days_absent_total, lopg040, lopg070, lopg082, lopg083, lopg084, lopg085, lopg086, lopg100) %>%
  # Rename columns with descriptive labels and LOP IDs
  rename(
    "Day" = day_value,
    "Total\n(all components)" = days_absent_total,
    "Chronic\n(lopg040)" = lopg040,
    "Injury\n(lopg070)" = lopg070,
    "Cold\n(lopg082)" = lopg082,
    "Flu\n(lopg083)" = lopg083,
    "Gastroenteritis\n(lopg084)" = lopg084,
    "Respiratory Infection\n(lopg085)" = lopg085,
    "Asthma/Bronchitis\n(lopg086)" = lopg086,
    "Other Health\n(lopg100)" = lopg100
  ) %>%
  arrange(as.numeric(Day))

# ---- lop-response-span-display ----------------------------------------------
lop_response_span_html <- lop_response_span %>%
  knitr::kable(
    format = "html",
    caption = "Empirical distribution of observed values in the outcome",
    escape = FALSE,
    align = c("c", "r", "r", "r", "r", "r", "r", "r", "r", "r")
  ) %>%
  kableExtra::kable_styling(
    bootstrap_options = c("striped", "hover", "condensed"),
    full_width = FALSE
  ) %>%
  kableExtra::scroll_box(width = "100%") %>%
  as.character()

cat(lop_response_span_html)

# ---- tweak-data-0 ------------------------------------------------------------
# Long-form LOP dataset — shared ancestor for all graph families in eda-71
ds_lop_long <- ds0 %>%
  select(
    cchs_cycle, cchs_cycle_f, !!weight_col,
    days_absent_total, days_absent_chronic,
    all_of(names(lop_components))
  ) %>%
  tidyr::pivot_longer(
    cols      = all_of(names(lop_components)),
    names_to  = "lop_col",
    values_to = "days_reason"
  ) %>%
  mutate(
    reason_label = lop_components[lop_col],
    reason_label = factor(reason_label, levels = lop_components),
    has_days     = !is.na(days_reason) & days_reason > 0
  )


# =============================================================================
# G0 OPENING — Criterion Interpretation and Two-Perspective Orientation
# Purpose: clarify what days_absent_total measures and how weighted quantities
# in later graphs should be interpreted.
# =============================================================================

# ---- g0-data-prep ------------------------------------------------------------
# Perspective A (population burden): weighted expected days per worker in 3 months
# and each reason's relative share of total days_absent_total.
# Perspective B (reporter intensity): conditional mean among respondents with >0
# days for the specific reason.

g0_denom_w <- sum(ds0[[weight_col]], na.rm = TRUE)
g0_total_mean_days <- sum(ds0[[weight_col]] * ds0$days_absent_total, na.rm = TRUE) / g0_denom_w

g0_reason_summary <- ds_lop_long %>%
  group_by(reason_label) %>%
  summarise(
    weighted_prev_pct = sum(.data[[weight_col]] * (days_reason > 0), na.rm = TRUE) / g0_denom_w * 100,
    weighted_mean_days_per_worker = sum(.data[[weight_col]] * days_reason, na.rm = TRUE) / g0_denom_w,
    weighted_mean_days_among_reporters = dplyr::if_else(
      sum(.data[[weight_col]] * (days_reason > 0), na.rm = TRUE) > 0,
      sum(.data[[weight_col]] * days_reason, na.rm = TRUE) /
        sum(.data[[weight_col]] * (days_reason > 0), na.rm = TRUE),
      NA_real_
    ),
    .groups = "drop"
  ) %>%
  mutate(
    absolute_days_per_100_workers = weighted_mean_days_per_worker * 100,
    relative_share_pct = weighted_mean_days_per_worker / g0_total_mean_days * 100,
    reason_label = factor(reason_label, levels = lop_components)
  )

g0_total_row <- tibble::tibble(
  reason_label = factor("Total outcome", levels = c(lop_components, "Total outcome")),
  weighted_prev_pct = sum(ds0[[weight_col]] * (ds0$days_absent_total > 0), na.rm = TRUE) / g0_denom_w * 100,
  weighted_mean_days_per_worker = g0_total_mean_days,
  weighted_mean_days_among_reporters = sum(ds0[[weight_col]] * ds0$days_absent_total, na.rm = TRUE) /
    sum(ds0[[weight_col]] * (ds0$days_absent_total > 0), na.rm = TRUE),
  absolute_days_per_100_workers = g0_total_mean_days * 100,
  relative_share_pct = 100
)

g0_opening_table <- bind_rows(g0_reason_summary, g0_total_row) %>%
  mutate(
    reason_label = as.character(reason_label),
    weighted_prev_pct = sprintf("%.2f%%", weighted_prev_pct),
    weighted_mean_days_per_worker = sprintf("%.3f", weighted_mean_days_per_worker),
    weighted_mean_days_among_reporters = sprintf("%.2f", weighted_mean_days_among_reporters),
    absolute_days_per_100_workers = sprintf("%.2f", absolute_days_per_100_workers),
    relative_share_pct = sprintf("%.2f%%", relative_share_pct)
  )

if (isTRUE(getOption("knitr.in.progress"))) {
  knitr::kable(
    g0_opening_table,
    format = "html",
    col.names = c(
      "Reason",
      "Prevalence (% with >=1 day)",
      "Mean days per worker",
      "Mean days among reporters",
      "Days per 100 workers",
      "Share of total days"
    ),
    align = c("l", "r", "r", "r", "r", "r"),
    caption = "Opening lens table: absolute and relative burden by reason (includes total outcome reference row)"
  )
} else {
  print(g0_opening_table)
}

# ---- g0-chronic-interpretation ----------------------------------------------
# Concrete interpretation block for the chronic-condition row in the opening lens table.
g0_chronic <- g0_reason_summary %>%
  filter(reason_label == "Chronic condition") %>%
  slice(1)

g0_chronic_interpretation <- tibble::tibble(
  metric = c(
    "weighted_prev_pct",
    "weighted_mean_days_per_worker",
    "weighted_mean_days_among_reporters",
    "absolute_days_per_100_workers",
    "relative_share_pct"
  ),
  value = c(
    sprintf("%.2f%%", g0_chronic$weighted_prev_pct),
    sprintf("%.3f days", g0_chronic$weighted_mean_days_per_worker),
    sprintf("%.2f days", g0_chronic$weighted_mean_days_among_reporters),
    sprintf("%.2f days", g0_chronic$absolute_days_per_100_workers),
    sprintf("%.2f%%", g0_chronic$relative_share_pct)
  ),
  interpretation = c(
    sprintf(
      "Estimated %.2f%% of employed workers had >=1 missed work day in the past 3 months due to a chronic condition.",
      g0_chronic$weighted_prev_pct
    ),
    sprintf(
      "Averaged across all employed workers (including those with 0 chronic-condition days), chronic condition contributes %.3f lost days per worker over 3 months.",
      g0_chronic$weighted_mean_days_per_worker
    ),
    sprintf(
      "Among workers with >=1 chronic-condition day, the mean intensity is %.2f days lost over 3 months.",
      g0_chronic$weighted_mean_days_among_reporters
    ),
    sprintf(
      "Equivalent burden scale: %.2f chronic-condition days lost per 100 employed workers over 3 months.",
      g0_chronic$absolute_days_per_100_workers
    ),
    sprintf(
      "Chronic condition accounts for %.2f%% of total days_absent_total (all 8 reasons combined).",
      g0_chronic$relative_share_pct
    )
  )
)

g0_chronic_interpretation <- g0_chronic_interpretation %>%
  mutate(
    metric = factor(
      metric,
      levels = c(
        "weighted_prev_pct",
        "weighted_mean_days_per_worker",
        "weighted_mean_days_among_reporters",
        "absolute_days_per_100_workers",
        "relative_share_pct"
      ),
      labels = c(
        "Prevalence among workers",
        "Mean chronic days per worker",
        "Mean chronic days among reporters",
        "Burden per 100 workers",
        "Share of total days_absent_total"
      )
    ),
    interpretation = stringr::str_wrap(interpretation, width = 92)
  )

if (isTRUE(getOption("knitr.in.progress"))) {
  knitr::kable(
    g0_chronic_interpretation,
    format = "html",
    col.names = c("Metric", "Value", "Interpretation"),
    align = c("l", "r", "l"),
    caption = "Chronic condition: concrete interpretation of each opening-lens value"
  )
} else {
  print(g0_chronic_interpretation)
}

# ---- g0 ----------------------------------------------------------------------
# Compact duality map: each point is one LOP reason.
# X = prevalence among workers; Y = average days among reporters.
# Point area = absolute burden (days per 100 workers), colour = relative share.
g0_duality_map <- g0_reason_summary %>%
  ggplot(aes(
    x = weighted_prev_pct,
    y = weighted_mean_days_among_reporters,
    size = absolute_days_per_100_workers,
    colour = relative_share_pct,
    label = reason_label
  )) +
  geom_hline(yintercept = mean(g0_reason_summary$weighted_mean_days_among_reporters, na.rm = TRUE),
             linewidth = 0.25, colour = "#7A7A7A", linetype = "dashed") +
  geom_vline(xintercept = mean(g0_reason_summary$weighted_prev_pct, na.rm = TRUE),
             linewidth = 0.25, colour = "#7A7A7A", linetype = "dashed") +
  geom_point(alpha = 0.9) +
  geom_text(size = 2.8, nudge_y = 0.06, check_overlap = TRUE) +
  scale_size_continuous(range = c(3, 11), name = "Days per 100 workers") +
  scale_colour_gradient(
    low = "#9BC6D9",
    high = "#0B4F6C",
    name = "Share of total days"
  ) +
  labs(
    title = "G0: Criterion orientation — burden vs intensity across LOP reasons",
    subtitle = paste0(
      "Weights: ", weight_col,
      ". All quantities refer to the past 3-month recall window among employed workers."
    ),
    x = "Prevalence (% with >=1 day)",
    y = "Mean days among reporters",
    caption = paste0(
      "Read points with two lenses: larger/darker = larger contribution to aggregate productivity loss; ",
      "higher y = longer episodes among affected workers."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "right",
    panel.grid.minor = element_blank(),
    plot.title.position = "plot"
  )

ggsave(
  paste0(prints_folder, "g0_duality_map.png"),
  g0_duality_map, width = 8.5, height = 5.5, dpi = 300
)
print(g0_duality_map)


# =============================================================================
# G1 FAMILY — Frequency Distribution Curves per LOP Reason
# Framing question: How does each LOP component variable distribute across
#   positive day-count bins?
# g1: marginal prevalence lines — one per reason, x = day-count bin, y = %
# =============================================================================

# ---- g1-data-prep ------------------------------------------------------------
# Bin each day count into ordered categories; compute weighted marginal prevalence.
# Y = weighted % of ALL respondents (including 0-day) at each positive bin.
# Denominator includes all respondents — giving population-level marginal probabilities.

g1_bin_data <- ds_lop_long %>%
  mutate(
    day_bin = dplyr::case_when(
      is.na(days_reason) | days_reason == 0 ~ NA_character_,
      days_reason == 1   ~ "1 day",
      days_reason == 2   ~ "2 days",
      days_reason == 3   ~ "3 days",
      days_reason == 4   ~ "4 days",
      days_reason == 5   ~ "5 days",
      days_reason <= 10  ~ "6\u201310 days",
      days_reason <= 15  ~ "11\u201315 days",
      days_reason <= 30  ~ "16\u201330 days",
      TRUE               ~ "31+ days"
    ),
    day_bin = factor(day_bin, levels = bin_levels)
  )

# Denominator: total weight per reason (all respondents, including zero-day)
g1_denom <- g1_bin_data %>%
  group_by(reason_label) %>%
  summarise(wt_total = sum(.data[[weight_col]], na.rm = TRUE), .groups = "drop")

g1_data <- g1_bin_data %>%
  filter(!is.na(day_bin)) %>%
  group_by(reason_label, day_bin) %>%
  summarise(
    wt_bin = sum(.data[[weight_col]], na.rm = TRUE),
    n_bin  = n(),
    .groups = "drop"
  ) %>%
  left_join(g1_denom, by = "reason_label") %>%
  mutate(pct_weighted = wt_bin / wt_total * 100)

# ---- g1 ----------------------------------------------------------------------
# Line graph: each line traces the marginal-prevalence frequency distribution of
# one LOP component variable across ordered positive day-count bins.
# Reason: set2 palette (8 qualitative colours, printer-friendly).

g1_lop_freq_curves <- g1_data %>%
  ggplot(aes(
    x      = day_bin,
    y      = pct_weighted,
    colour = reason_label,
    group  = reason_label
  )) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.2) +
  scale_y_continuous(
    labels = scales::label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.08))
  ) +
  scale_colour_brewer(palette = "Set2", name = "Reason for absence") +
  labs(
    title   = "G1: Frequency distribution of absent days per LOP reason \u2014 marginal prevalence",
    subtitle = paste(
      "Y = weighted % of all workers in each positive bin (about cases per 100 workers).",
      "Summing bins for a reason gives its % with >=1 day.",
      sep = "\n"
    ),
    x       = "Days absent (frequency bin)",
    y       = "Weighted % of respondents",
    caption = paste(
      "Bins are collapsed in the upper tail (6\u201310, 11\u201315, 16\u201330, 31+) to stabilize sparse counts and preserve cross-reason shape comparability.",
      "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample (n = 63,843).",
      sep = "\n"
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x      = element_text(angle = 35, hjust = 1),
    legend.position  = "bottom",
    legend.title     = element_text(size = 9),
    legend.text      = element_text(size = 8),
    panel.grid.minor = element_blank()
  ) +
  guides(colour = guide_legend(nrow = 2))

ggsave(
  paste0(prints_folder, "g1_lop_freq_curves.png"),
  g1_lop_freq_curves, width = 8.5, height = 5.5, dpi = 300
)
print(g1_lop_freq_curves)

# ---- g11-data-prep -----------------------------------------------------------
# Faceted shape comparison:
# each panel = one LOP component, overlaid with two benchmarks:
# (1) chronic outcome, (2) total outcome.
# To compare shape (not prevalence level), y is normalised within positives.

bin_count_days <- function(x) {
  dplyr::case_when(
    is.na(x) | x == 0 ~ NA_character_,
    x == 1   ~ "1 day",
    x == 2   ~ "2 days",
    x == 3   ~ "3 days",
    x == 4   ~ "4 days",
    x == 5   ~ "5 days",
    x <= 10  ~ "6\u201310 days",
    x <= 15  ~ "11\u201315 days",
    x <= 30  ~ "16\u201330 days",
    TRUE     ~ "31+ days"
  )
}

g11_lop_series <- ds_lop_long %>%
  mutate(day_bin = factor(bin_count_days(days_reason), levels = bin_levels)) %>%
  filter(!is.na(day_bin)) %>%
  group_by(reason_label, day_bin) %>%
  summarise(wt_bin = sum(.data[[weight_col]], na.rm = TRUE), .groups = "drop") %>%
  group_by(reason_label) %>%
  mutate(
    wt_pos_total = sum(wt_bin, na.rm = TRUE),
    pct_shape = wt_bin / wt_pos_total * 100
  ) %>%
  ungroup() %>%
  transmute(
    facet_reason = reason_label,
    day_bin,
    series = "Facet LOP variable",
    pct_shape
  )

# Add a 9th focal facet: days_absent_total as the focal series
g11_focal_total <- ds0 %>%
  transmute(day_bin = factor(bin_count_days(days_absent_total), levels = bin_levels),
            wt = .data[[weight_col]]) %>%
  filter(!is.na(day_bin)) %>%
  group_by(day_bin) %>%
  summarise(wt_bin = sum(wt, na.rm = TRUE), .groups = "drop") %>%
  mutate(
    wt_pos_total = sum(wt_bin, na.rm = TRUE),
    pct_shape = wt_bin / wt_pos_total * 100,
    facet_reason = factor("Total outcome", levels = c(lop_components, "Total outcome")),
    series = "Facet LOP variable"
  ) %>%
  select(facet_reason, day_bin, series, pct_shape)

# Combine all focal series (8 LOP components + 1 total)
g11_all_focal <- bind_rows(g11_lop_series, g11_focal_total) %>%
  mutate(facet_reason = factor(facet_reason, levels = c(lop_components, "Total outcome")))

g11_bench_chronic <- ds0 %>%
  transmute(day_bin = factor(bin_count_days(days_absent_chronic), levels = bin_levels),
            wt = .data[[weight_col]]) %>%
  filter(!is.na(day_bin)) %>%
  group_by(day_bin) %>%
  summarise(wt_bin = sum(wt, na.rm = TRUE), .groups = "drop") %>%
  mutate(
    wt_pos_total = sum(wt_bin, na.rm = TRUE),
    pct_shape = wt_bin / wt_pos_total * 100,
    series = "Benchmark: chronic",
    key = 1L
  )

g11_bench_total <- ds0 %>%
  transmute(day_bin = factor(bin_count_days(days_absent_total), levels = bin_levels),
            wt = .data[[weight_col]]) %>%
  filter(!is.na(day_bin)) %>%
  group_by(day_bin) %>%
  summarise(wt_bin = sum(wt, na.rm = TRUE), .groups = "drop") %>%
  mutate(
    wt_pos_total = sum(wt_bin, na.rm = TRUE),
    pct_shape = wt_bin / wt_pos_total * 100,
    series = "Benchmark: total",
    key = 1L
  )

g11_facet_keys <- tibble::tibble(
  facet_reason = factor(c(lop_components, "Total outcome"), levels = c(lop_components, "Total outcome")),
  key = 1L
)

g11_bench_all <- bind_rows(g11_bench_chronic, g11_bench_total) %>%
  left_join(g11_facet_keys, by = "key") %>%
  select(facet_reason, day_bin, series, pct_shape)

g11_data <- bind_rows(g11_all_focal, g11_bench_all) %>%
  mutate(
    facet_reason = factor(facet_reason, levels = c(lop_components, "Total outcome")),
    series = factor(
      series,
      levels = c("Facet LOP variable", "Benchmark: chronic", "Benchmark: total")
    )
  ) %>%
  filter(!(facet_reason == "Chronic condition" & series == "Benchmark: chronic")) %>%
  filter(!(facet_reason == "Total outcome" & series == "Benchmark: total"))

# Unweighted n of positive reporters per facet — annotated in each panel
g11_n_labels <- ds_lop_long %>%
  filter(!is.na(days_reason) & days_reason > 0) %>%
  group_by(reason_label) %>%
  summarise(n_pos = n(), .groups = "drop") %>%
  transmute(
    facet_reason = factor(reason_label, levels = c(lop_components, "Total outcome")),
    n_label = paste0("n = ", scales::comma(n_pos))
  )

g11_n_total <- ds0 %>%
  filter(days_absent_total > 0) %>%
  summarise(n_pos = n()) %>%
  transmute(
    facet_reason = factor("Total outcome", levels = c(lop_components, "Total outcome")),
    n_label = paste0("n = ", scales::comma(n_pos))
  )

g11_n_all <- bind_rows(g11_n_labels, g11_n_total)

# ---- g11 ---------------------------------------------------------------------
# Faceted overlay to inspect relative shape per LOP variable against benchmarks.
g11_facet_shape_benchmarks <- g11_data %>%
  ggplot(aes(x = day_bin, y = pct_shape, group = series, colour = series, linetype = series)) +
  geom_hline(yintercept = 0, linewidth = 0.25, colour = "#1F1F1F", linetype = "solid") +
  geom_area(
    data = dplyr::filter(g11_data, series == "Facet LOP variable"),
    aes(fill = series),
    alpha = 0.14,
    colour = NA,
    inherit.aes = TRUE,
    show.legend = FALSE
  ) +
  geom_line(linewidth = 0.9) +
  geom_point(
    data = dplyr::filter(g11_data, series == "Facet LOP variable"),
    size = 1.8, alpha = 0.9
  ) +
  geom_text(
    data = g11_n_all,
    aes(x = Inf, y = Inf, label = n_label),
    inherit.aes = FALSE,
    hjust = 1.1, vjust = 1.5,
    size = 2.8, colour = "#555555"
  ) +
  facet_wrap(~ facet_reason, ncol = 3) +
  scale_y_continuous(
    labels = scales::label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.08))
  ) +
  scale_colour_manual(
    values = c(
      "Facet LOP variable" = "#0B4F6C",
      "Benchmark: chronic" = "#B25D00",
      "Benchmark: total" = "#5A5A5A"
    ),
    name = NULL
  ) +
  scale_fill_manual(
    values = c("Facet LOP variable" = "#8FB8CC"),
    guide = "none"
  ) +
  scale_linetype_manual(
    values = c(
      "Facet LOP variable" = "solid",
      "Benchmark: chronic" = "dashed",
      "Benchmark: total" = "dotted"
    ),
    name = NULL
  ) +
  labs(
    title = "G11: Faceted LOP shape comparison against chronic and total benchmarks",
    subtitle = paste0(
      "Y = within-positive weighted distribution across day bins.",
      " This isolates shape from prevalence level."
    ),
    x = "Days absent (frequency bin)",
    y = "Share of positive-day mass",
    caption = paste0(
      "Benchmarks are repeated in every facet.",
      " In the chronic facet, the chronic benchmark is omitted because it is identical to the focal series."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x = element_text(angle = 35, hjust = 1),
    strip.text = element_text(face = "bold", size = 9),
    strip.background = element_rect(fill = "#EEF3F7", colour = NA),
    legend.position = "bottom",
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank()
  )

ggsave(
  paste0(prints_folder, "g11_facet_shape_benchmarks.png"),
  g11_facet_shape_benchmarks, width = 8.5, height = 8.5, dpi = 300
)
print(g11_facet_shape_benchmarks)


# =============================================================================
# G2 FAMILY — Distribution of the Modeled Chronic-Absence Outcome
# Framing question: How does days_absent_chronic distribute in the analytical
# sample, first as raw respondent counts and then as weighted population shares?
# g2: composite raw view = left sample partition, right exact positive-day counts
# g21: composite weighted view = left weighted partition, right exact positive-day shares
# =============================================================================

# ---- g2-data-prep ------------------------------------------------------------
g2_partition <- ds0 %>%
  transmute(
    category = dplyr::case_when(
      days_absent_total == 0 ~ "No missed days",
      days_absent_chronic > 0 ~ ">=1 chronic day",
      days_absent_chronic == 0 & days_absent_total > 0 ~ "Other-only missed day",
      TRUE ~ NA_character_
    ),
    weight_value = .data[[weight_col]],
    days_absent_chronic = as.integer(days_absent_chronic)
  ) %>%
  filter(!is.na(category))

g2_partition_summary <- g2_partition %>%
  group_by(category) %>%
  summarise(
    n_raw = dplyr::n(),
    wt_sum = sum(weight_value, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    pct_raw = n_raw / sum(n_raw) * 100,
    pct_weighted = wt_sum / sum(wt_sum) * 100,
    category = factor(
      category,
      levels = c("No missed days", ">=1 chronic day", "Other-only missed day")
    )
  )

g2_chronic_positive_distribution <- g2_partition %>%
  filter(days_absent_chronic > 0) %>%
  mutate(
    # Keep day_range for color mapping on numeric day bars
    day_range = dplyr::case_when(
      days_absent_chronic == 1  ~ "1 day",
      days_absent_chronic == 2  ~ "2 days",
      days_absent_chronic == 3  ~ "3 days",
      days_absent_chronic == 4  ~ "4 days",
      days_absent_chronic == 5  ~ "5 days",
      days_absent_chronic <= 10 ~ "6\u201310 days",
      days_absent_chronic <= 15 ~ "11\u201315 days",
      days_absent_chronic <= 30 ~ "16\u201330 days",
      TRUE ~ "31+ days"
    ),
    day_range = factor(day_range, levels = bin_levels)
  )

g2_partition_colors <- c(
  "No missed days" = "#D9D9D9",
  ">=1 chronic day" = "#D08C60",
  "Other-only missed day" = "#0B4F6C"
)

# Aggregate by exact numeric day for the right-panel distributions
g2_chronic_binned_distribution <- g2_chronic_positive_distribution %>%
  group_by(days_absent_chronic, day_range) %>%
  summarise(
    n_raw = dplyr::n(),
    wt_sum = sum(weight_value, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  # Ensure every observed day is shown on the x-axis (step = 1).
  tidyr::complete(
    days_absent_chronic = seq(
      0,
      max(g2_chronic_positive_distribution$days_absent_chronic, na.rm = TRUE),
      by = 1
    ),
    fill = list(n_raw = 0, wt_sum = 0)
  ) %>%
  mutate(
    day_range = dplyr::case_when(
      days_absent_chronic == 0  ~ NA_character_,
      days_absent_chronic == 1  ~ "1 day",
      days_absent_chronic == 2  ~ "2 days",
      days_absent_chronic == 3  ~ "3 days",
      days_absent_chronic == 4  ~ "4 days",
      days_absent_chronic == 5  ~ "5 days",
      days_absent_chronic <= 10 ~ "6\u201310 days",
      days_absent_chronic <= 15 ~ "11\u201315 days",
      days_absent_chronic <= 30 ~ "16\u201330 days",
      TRUE ~ "31+ days"
    ),
    day_range = factor(day_range, levels = bin_levels),
    pct_raw_among_sample = n_raw / nrow(ds0) * 100,
    pct_weighted_among_sample = wt_sum / sum(ds0[[weight_col]], na.rm = TRUE) * 100,
    pct_weighted_among_reporters = wt_sum / sum(wt_sum, na.rm = TRUE) * 100
  )

g2_x_min <- 0
g2_x_max <- max(31, max(g2_chronic_binned_distribution$days_absent_chronic, na.rm = TRUE))
g2_x_major_breaks <- sort(unique(c(
  0,
  if (g2_x_min <= 1 && g2_x_max >= 1) 1 else numeric(0),
  seq(5 * ceiling(g2_x_min / 5), 5 * floor(g2_x_max / 5), by = 5)
)))
g2_x_major_breaks <- sort(unique(c(g2_x_major_breaks, g2_x_max)))
g2_x_minor_breaks <- seq(g2_x_min, g2_x_max, by = 1)
g2_x_ten_guides <- seq(10 * ceiling(g2_x_min / 10), 10 * floor(g2_x_max / 10), by = 10)

g2_day_range_colours <- c(
  "1 day" = "#f7941d",
  "2 days" = "#e8601c",
  "3 days" = "#cc3311",
  "4 days" = "#aa1133",
  "5 days" = "#880044",
  "6\u201310 days" = "#6a0177",
  "11\u201315 days" = "#49006a",
  "16\u201330 days" = "#2d004b",
  "31+ days" = "#0d0014"
)

compose_two_panel_grob <- function(left_plot, right_plot, left_width = 0.23, right_width = 0.77) {
  left_grob <- ggplot2::ggplotGrob(left_plot)
  right_grob <- ggplot2::ggplotGrob(right_plot)

  grid::grid.grabExpr({
    grid::grid.newpage()
    grid::pushViewport(
      grid::viewport(
        layout = grid::grid.layout(
          nrow = 1,
          ncol = 2,
          widths = grid::unit(c(left_width, right_width), "npc")
        )
      )
    )
    grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
    grid::grid.draw(left_grob)
    grid::upViewport()
    grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
    grid::grid.draw(right_grob)
    grid::upViewport(2)
  }, wrap.grobs = TRUE)
}

# ---- g2 ----------------------------------------------------------------------
g2_left_raw_bar <- g2_partition_summary %>%
  ggplot(aes(x = "Analytic sample", y = pct_raw, fill = category)) +
  geom_col(width = 0.45, colour = "white", linewidth = 0.3) +
  geom_text(
    aes(
      label = paste0(scales::comma(n_raw), "\n", sprintf("%.1f%%", pct_raw))
    ),
    position = position_stack(vjust = 0.5),
    size = 3,
    lineheight = 0.95
  ) +
  scale_fill_manual(values = g2_partition_colors, guide = "none") +
  scale_y_continuous(
    labels = scales::label_percent(scale = 1),
    limits = c(0, 100),
    expand = expansion(mult = c(0, 0))
  ) +
  labs(
    x = NULL,
    y = "Share of sample"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    plot.margin = margin(5.5, 0, 5.5, 5.5)
  )

g2_right_raw_distribution <- g2_chronic_binned_distribution %>%
  ggplot(aes(x = days_absent_chronic, y = n_raw, fill = day_range)) +
  geom_vline(
    xintercept = g2_x_ten_guides,
    colour = "#D9D9D9",
    linewidth = 0.35
  ) +
  geom_col(width = 0.9, alpha = 0.90) +
  geom_col(
    data = ~ dplyr::filter(.x, days_absent_chronic == 1),
    width = 0.9, colour = "black", fill = NA, alpha = 0.5
  ) +
  scale_x_continuous(
    breaks = g2_x_major_breaks,
    minor_breaks = g2_x_minor_breaks,
    limits = c(g2_x_min, g2_x_max + 1),
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(
    labels = scales::label_comma(),
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_fill_manual(values = g2_day_range_colours, name = "Day range") +
  labs(
    x = "Chronic-absence days (numeric)",
    y = "Respondent count"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_line(colour = "#ECECEC", linewidth = 0.20),
    panel.grid.minor.y = element_blank(),
    axis.text.x = element_text(size = 8),
    legend.position = c(0.985, 0.985),
    legend.justification = c(1, 1),
    legend.background = element_rect(fill = "#FFFFFFDD", colour = "#D0D0D0"),
    legend.key.size = grid::unit(0.28, "cm"),
    legend.title = element_text(size = 7),
    legend.text = element_text(size = 6),
    plot.margin = margin(5.5, 5.5, 5.5, 6)
  ) +
  guides(fill = guide_legend(ncol = 1, byrow = TRUE))

g2_positive_n <- sum(g2_chronic_binned_distribution$n_raw, na.rm = TRUE)

g2_right_raw_distribution <- g2_right_raw_distribution +
  labs(
    title = "G2: Positive chronic-day distribution",
    subtitle = paste0("n = ", scales::comma(g2_positive_n), " chronic reporters")
  )

g2_chronic_raw_distribution <- compose_two_panel_grob(
  g2_left_raw_bar,
  g2_right_raw_distribution,
  left_width = 0.22,
  right_width = 0.78
)

ggsave(
  paste0(prints_folder, "g2_chronic_raw_distribution.png"),
  g2_chronic_raw_distribution, width = 8.5, height = 5.5, dpi = 300
)

grid::grid.newpage()
grid::grid.draw(g2_chronic_raw_distribution)

# ---- g21 ---------------------------------------------------------------------
g21_left_weighted_bar <- g2_partition_summary %>%
  ggplot(aes(x = "Weighted population", y = pct_weighted, fill = category)) +
  geom_col(width = 0.45, colour = "white", linewidth = 0.3) +
  geom_text(
    aes(
      label = paste0(sprintf("%.1f%%", pct_weighted))
    ),
    position = position_stack(vjust = 0.5),
    size = 3,
    lineheight = 0.95
  ) +
  scale_fill_manual(values = g2_partition_colors, guide = "none") +
  scale_y_continuous(
    labels = scales::label_percent(scale = 1),
    limits = c(0, 100),
    expand = expansion(mult = c(0, 0))
  ) +
  labs(
    x = NULL,
    y = "Weighted % of workers"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    plot.margin = margin(5.5, 0, 5.5, 5.5)
  )

g21_right_weighted_distribution <- g2_chronic_binned_distribution %>%
  ggplot(aes(x = days_absent_chronic, y = pct_weighted_among_reporters, fill = day_range)) +
  geom_vline(
    xintercept = g2_x_ten_guides,
    colour = "#D9D9D9",
    linewidth = 0.35
  ) +
  geom_col(width = 0.9, alpha = 0.90) +
  geom_col(
    data = ~ dplyr::filter(.x, days_absent_chronic == 1),
    width = 0.9, colour = "black", fill = NA, alpha = 0.5
  ) +
  scale_x_continuous(
    breaks = g2_x_major_breaks,
    minor_breaks = g2_x_minor_breaks,
    limits = c(g2_x_min, g2_x_max + 1),
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(
    labels = scales::label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_fill_manual(values = g2_day_range_colours, name = "Day range") +
  labs(
    x = "Chronic-absence days (numeric)",
    y = "Weighted % among chronic reporters"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_line(colour = "#ECECEC", linewidth = 0.20),
    panel.grid.minor.y = element_blank(),
    axis.text.x = element_text(size = 8),
    legend.position = c(0.985, 0.985),
    legend.justification = c(1, 1),
    legend.background = element_rect(fill = "#FFFFFFDD", colour = "#D0D0D0"),
    legend.key.size = grid::unit(0.28, "cm"),
    legend.title = element_text(size = 7),
    legend.text = element_text(size = 6),
    plot.margin = margin(5.5, 5.5, 5.5, 6)
  ) +
  guides(fill = guide_legend(ncol = 1, byrow = TRUE))

g21_right_weighted_distribution <- g21_right_weighted_distribution +
  labs(
    title = "G21: Weighted positive chronic-day distribution",
    subtitle = "Bars sum to 100% across chronic reporters"
  )

g21_chronic_weighted_distribution <- compose_two_panel_grob(
  g21_left_weighted_bar,
  g21_right_weighted_distribution,
  left_width = 0.22,
  right_width = 0.78
)

ggsave(
  paste0(prints_folder, "g21_chronic_weighted_distribution.png"),
  g21_chronic_weighted_distribution, width = 8.5, height = 5.5, dpi = 300
)

grid::grid.newpage()
grid::grid.draw(g21_chronic_weighted_distribution)

# ---- g22-data-prep -----------------------------------------------------------
# g22 splits the right panel into two: top shows chronic-day distribution (same as g2 right),
# bottom shows distribution of days_absent_other for the same chronic-reporter cohort.

# Create days_absent_other variable: total days minus chronic days
g22_other_analysis <- ds0 %>%
  transmute(
    category = dplyr::case_when(
      days_absent_total == 0 ~ "No missed days",
      days_absent_chronic > 0 ~ ">=1 chronic day",
      days_absent_chronic == 0 & days_absent_total > 0 ~ "Other-only missed day",
      TRUE ~ NA_character_
    ),
    weight_value = .data[[weight_col]],
    days_absent_chronic = as.integer(days_absent_chronic),
    days_absent_total = as.integer(days_absent_total),
    days_absent_other = as.integer(days_absent_total - days_absent_chronic)
  ) %>%
  filter(!is.na(category) & days_absent_chronic > 0)

# Get the other-reason positive distribution with day-range mapping
g22_other_positive_distribution <- g22_other_analysis %>%
  mutate(
    day_range = dplyr::case_when(
      days_absent_other == 0  ~ "0 days",
      days_absent_other == 1  ~ "1 day",
      days_absent_other == 2  ~ "2 days",
      days_absent_other == 3  ~ "3 days",
      days_absent_other == 4  ~ "4 days",
      days_absent_other == 5  ~ "5 days",
      days_absent_other <= 10 ~ "6–10 days",
      days_absent_other <= 15 ~ "11–15 days",
      days_absent_other <= 30 ~ "16–30 days",
      TRUE ~ "31+ days"
    ),
    day_range = factor(day_range, levels = c("0 days", bin_levels))
  )

# Aggregate by exact numeric day for other-reason distribution
g22_other_binned_distribution <- g22_other_positive_distribution %>%
  group_by(days_absent_other, day_range) %>%
  summarise(
    n_raw = dplyr::n(),
    wt_sum = sum(weight_value, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  # Ensure every observed day is shown (step = 1)
  tidyr::complete(
    days_absent_other = seq(
      0,
      max(g22_other_positive_distribution$days_absent_other, na.rm = TRUE),
      by = 1
    ),
    fill = list(n_raw = 0, wt_sum = 0)
  ) %>%
  mutate(
    day_range = dplyr::case_when(
      days_absent_other == 0  ~ "0 days",
      days_absent_other == 1  ~ "1 day",
      days_absent_other == 2  ~ "2 days",
      days_absent_other == 3  ~ "3 days",
      days_absent_other == 4  ~ "4 days",
      days_absent_other == 5  ~ "5 days",
      days_absent_other <= 10 ~ "6–10 days",
      days_absent_other <= 15 ~ "11–15 days",
      days_absent_other <= 30 ~ "16–30 days",
      TRUE ~ "31+ days"
    ),
    day_range = factor(day_range, levels = c("0 days", bin_levels))
  )

g22_other_x_min <- 0
g22_other_x_max <- max(g22_other_binned_distribution$days_absent_other, na.rm = TRUE)
g22_other_x_major_breaks <- sort(unique(c(
  g22_other_x_min,
  if (g22_other_x_min <= 1 && g22_other_x_max >= 1) 1 else numeric(0),
  seq(5 * ceiling(g22_other_x_min / 5), 5 * floor(g22_other_x_max / 5), by = 5)
)))
g22_other_x_major_breaks <- sort(unique(c(g22_other_x_major_breaks, g22_other_x_max)))
g22_other_x_minor_breaks <- seq(g22_other_x_min, g22_other_x_max, by = 1)
g22_other_x_ten_guides <- seq(10 * ceiling(g22_other_x_min / 10), 10 * floor(g22_other_x_max / 10), by = 10)
g22_top_y_max <- max(g2_chronic_binned_distribution$n_raw, na.rm = TRUE)
g22_top_y_limits <- c(0, g22_top_y_max * 1.08)
g22_top_y_breaks <- seq(0, 800, by = 100)

g22_bottom_plot_data <- g22_other_binned_distribution %>%
  dplyr::filter(days_absent_other >= 0)
g22_bottom_y_max <- max(g22_bottom_plot_data$n_raw, na.rm = TRUE)
g22_bottom_y_limits <- c(0, g22_bottom_y_max * 1.08)
g22_bottom_y_breaks <- pretty(g22_bottom_y_limits, n = 6)

g22_other_day_range_colours <- c("0 days" = "#B8B8B8", g2_day_range_colours)

# ---- compose_three_panel_grob ------------------------------------------------
# Compose left-spanning panel + top-right + bottom-right layout
compose_three_panel_grob <- function(left_plot, top_right_plot, bottom_right_plot,
                                      left_width = 0.22, right_width = 0.78) {
  left_grob <- ggplot2::ggplotGrob(left_plot)
  top_right_grob <- ggplot2::ggplotGrob(top_right_plot)
  bottom_right_grob <- ggplot2::ggplotGrob(bottom_right_plot)

  grid::grid.grabExpr({
    grid::grid.newpage()
    grid::pushViewport(
      grid::viewport(
        layout = grid::grid.layout(
          nrow = 2,
          ncol = 2,
          heights = grid::unit(c(0.5, 0.5), "npc"),
          widths = grid::unit(c(left_width, right_width), "npc")
        )
      )
    )
    # Left column (spans both rows)
    grid::pushViewport(grid::viewport(layout.pos.row = 1:2, layout.pos.col = 1))
    grid::grid.draw(left_grob)
    grid::upViewport()
    # Top-right
    grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
    grid::grid.draw(top_right_grob)
    grid::upViewport()
    # Bottom-right
    grid::pushViewport(grid::viewport(layout.pos.row = 2, layout.pos.col = 2))
    grid::grid.draw(bottom_right_grob)
    grid::upViewport(2)
  }, wrap.grobs = TRUE)
}

# ---- g22 - top-right (chronic days) -------------------------------------------
# Reuse the g2 right panel (chronic distribution) as the top-right of g22
g22_top_right_raw_distribution <- g2_chronic_binned_distribution %>%
  ggplot(aes(x = days_absent_chronic, y = n_raw, fill = day_range)) +
  geom_vline(
    xintercept = g2_x_ten_guides,
    colour = "#D9D9D9",
    linewidth = 0.35
  ) +
  geom_col(width = 0.9, alpha = 0.90) +
  geom_col(
    data = ~ dplyr::filter(.x, days_absent_chronic == 1),
    width = 0.9, colour = "black", fill = NA, alpha = 0.5
  ) +
  scale_x_continuous(
    breaks = g2_x_major_breaks,
    minor_breaks = g2_x_minor_breaks,
    limits = c(g2_x_min, g2_x_max + 1),
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(
    labels = scales::label_comma(),
    breaks = g22_top_y_breaks,
    limits = g22_top_y_limits,
    expand = expansion(mult = c(0, 0))
  ) +
  scale_fill_manual(values = g2_day_range_colours, name = "Day range") +
  labs(
    title = "G22: Chronic-absence distribution",
    subtitle = paste0("n = ", scales::comma(g2_positive_n), " with ≥1 chronic day"),
    x = "Chronic-absence days (numeric)",
    y = "Respondent count"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_line(colour = "#ECECEC", linewidth = 0.20),
    panel.grid.minor.y = element_blank(),
    axis.text.x = element_text(size = 8),
    legend.position = c(0.985, 0.985),
    legend.justification = c(1, 1),
    legend.background = element_rect(fill = "#FFFFFFDD", colour = "#D0D0D0"),
    legend.key.size = grid::unit(0.28, "cm"),
    legend.title = element_text(size = 7),
    legend.text = element_text(size = 6),
    plot.margin = margin(5.5, 5.5, 2.75, 6)
  ) +
  guides(fill = guide_legend(ncol = 1, byrow = TRUE))

# ---- g22 - bottom-right (other-reason days) -----------------------------------
# Create distribution plot for days_absent_other
g22_bottom_right_other_distribution <- g22_bottom_plot_data %>%
  ggplot(aes(x = days_absent_other, y = n_raw, fill = day_range)) +
  geom_vline(
    xintercept = g22_other_x_ten_guides,
    colour = "#D9D9D9",
    linewidth = 0.35
  ) +
  geom_col(width = 0.9, alpha = 0.90) +
  geom_col(
    data = ~ dplyr::filter(.x, days_absent_other == 1),
    width = 0.9, colour = "black", fill = NA, alpha = 0.5
  ) +
  scale_x_continuous(
    breaks = g22_other_x_major_breaks,
    minor_breaks = g22_other_x_minor_breaks,
    limits = c(g22_other_x_min - 1, g22_other_x_max + 1),
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(
    labels = scales::label_comma(),
    breaks = g22_bottom_y_breaks,
    limits = g22_bottom_y_limits,
    expand = expansion(mult = c(0, 0))
  ) +
  scale_fill_manual(values = g22_other_day_range_colours, name = "Day range") +
  labs(
    title = "G22: Other-reason absence distribution",
    subtitle = paste0("Same cohort as top panel (n = ", scales::comma(sum(g22_other_binned_distribution$n_raw, na.rm = TRUE)), "); bars include the 0-day non-chronic bin"),
    x = "Other-reason absence days (numeric)",
    y = "Respondent count"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_line(colour = "#ECECEC", linewidth = 0.20),
    panel.grid.minor.y = element_blank(),
    axis.text.x = element_text(size = 8),
    legend.position = c(0.985, 0.985),
    legend.justification = c(1, 1),
    legend.background = element_rect(fill = "#FFFFFFDD", colour = "#D0D0D0"),
    legend.key.size = grid::unit(0.28, "cm"),
    legend.title = element_text(size = 7),
    legend.text = element_text(size = 6),
    plot.margin = margin(2.75, 5.5, 5.5, 6)
  ) +
  guides(fill = guide_legend(ncol = 1, byrow = TRUE))

# ---- g22 -----------------------------------------------------------------------
# Compose three-panel layout: left chronic partition spans both rows, right split vertically

g22_chronic_raw_split_distribution <- compose_three_panel_grob(
  g2_left_raw_bar,
  g22_top_right_raw_distribution,
  g22_bottom_right_other_distribution,
  left_width = 0.22,
  right_width = 0.78
)

# Display for Quarto figure capture
grid::grid.draw(g22_chronic_raw_split_distribution)

# Save high-res version to prints folder
ggsave(
  paste0(prints_folder, "g22_chronic_vs_other_raw_split_distribution.png"),
  g22_chronic_raw_split_distribution, width = 8.5, height = 7, dpi = 300
)


# ---- g23-data-prep -----------------------------------------------------------
# g23 keeps g22 geometry but changes the lower-right panel to the "other-only" cohort:
# respondents with >=1 non-chronic day and 0 chronic days (n = 15,211).
g23_other_only_analysis <- ds0 %>%
  transmute(
    category = dplyr::case_when(
      days_absent_total == 0 ~ "No missed days",
      days_absent_chronic > 0 ~ ">=1 chronic day",
      days_absent_chronic == 0 & days_absent_total > 0 ~ "Other-only missed day",
      TRUE ~ NA_character_
    ),
    weight_value = .data[[weight_col]],
    days_absent_chronic = as.integer(days_absent_chronic),
    days_absent_total = as.integer(days_absent_total),
    days_absent_other = as.integer(days_absent_total - days_absent_chronic)
  ) %>%
  filter(!is.na(category) & days_absent_chronic == 0 & days_absent_total > 0)

g23_other_only_binned_distribution <- g23_other_only_analysis %>%
  mutate(
    day_range = dplyr::case_when(
      days_absent_other == 1  ~ "1 day",
      days_absent_other == 2  ~ "2 days",
      days_absent_other == 3  ~ "3 days",
      days_absent_other == 4  ~ "4 days",
      days_absent_other == 5  ~ "5 days",
      days_absent_other <= 10 ~ "6–10 days",
      days_absent_other <= 15 ~ "11–15 days",
      days_absent_other <= 30 ~ "16–30 days",
      TRUE ~ "31+ days"
    ),
    day_range = factor(day_range, levels = bin_levels)
  ) %>%
  group_by(days_absent_other, day_range) %>%
  summarise(
    n_raw = dplyr::n(),
    wt_sum = sum(weight_value, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  tidyr::complete(
    days_absent_other = seq(
      1,
      max(days_absent_other, na.rm = TRUE),
      by = 1
    ),
    fill = list(n_raw = 0, wt_sum = 0)
  ) %>%
  mutate(
    day_range = dplyr::case_when(
      days_absent_other == 1  ~ "1 day",
      days_absent_other == 2  ~ "2 days",
      days_absent_other == 3  ~ "3 days",
      days_absent_other == 4  ~ "4 days",
      days_absent_other == 5  ~ "5 days",
      days_absent_other <= 10 ~ "6–10 days",
      days_absent_other <= 15 ~ "11–15 days",
      days_absent_other <= 30 ~ "16–30 days",
      TRUE ~ "31+ days"
    ),
    day_range = factor(day_range, levels = bin_levels)
  )

g23_other_x_min <- 0
g23_other_x_max <- max(g23_other_only_binned_distribution$days_absent_other, na.rm = TRUE)
g23_other_x_major_breaks <- sort(unique(c(
  0,
  1,
  seq(5 * ceiling(g23_other_x_min / 5), 5 * floor(g23_other_x_max / 5), by = 5)
)))
g23_other_x_major_breaks <- sort(unique(c(g23_other_x_major_breaks, g23_other_x_max)))
g23_other_x_minor_breaks <- seq(g23_other_x_min, g23_other_x_max, by = 1)
g23_other_x_ten_guides <- seq(10 * ceiling(g23_other_x_min / 10), 10 * floor(g23_other_x_max / 10), by = 10)

g23_bottom_y_max <- max(g23_other_only_binned_distribution$n_raw, na.rm = TRUE)
g23_bottom_y_limits <- c(0, g23_bottom_y_max * 1.08)
g23_bottom_y_breaks <- pretty(g23_bottom_y_limits, n = 6)

# ---- g23 - bottom-right (other-only non-chronic days) ------------------------
g23_bottom_right_other_only_distribution <- g23_other_only_binned_distribution %>%
  ggplot(aes(x = days_absent_other, y = n_raw, fill = day_range)) +
  geom_vline(
    xintercept = g23_other_x_ten_guides,
    colour = "#D9D9D9",
    linewidth = 0.35
  ) +
  geom_col(width = 0.9, alpha = 0.90) +
  geom_col(
    data = ~ dplyr::filter(.x, days_absent_other == 1),
    width = 0.9, colour = "black", fill = NA, alpha = 0.5
  ) +
  scale_x_continuous(
    breaks = g23_other_x_major_breaks,
    minor_breaks = g23_other_x_minor_breaks,
    limits = c(g23_other_x_min, g23_other_x_max + 1),
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(
    labels = scales::label_comma(),
    breaks = g23_bottom_y_breaks,
    limits = g23_bottom_y_limits,
    expand = expansion(mult = c(0, 0))
  ) +
  scale_fill_manual(values = g2_day_range_colours, name = "Day range") +
  labs(
    title = "G23: Other-only non-chronic distribution",
    subtitle = paste0(
      "n = ", scales::comma(sum(g23_other_only_binned_distribution$n_raw, na.rm = TRUE)),
      " with 0 chronic day and ",
      "≥1 non-chronic day"
    ),
    x = "Other-reason absence days (numeric)",
    y = "Respondent count"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_line(colour = "#ECECEC", linewidth = 0.20),
    panel.grid.minor.y = element_blank(),
    axis.text.x = element_text(size = 8),
    legend.position = c(0.985, 0.985),
    legend.justification = c(1, 1),
    legend.background = element_rect(fill = "#FFFFFFDD", colour = "#D0D0D0"),
    legend.key.size = grid::unit(0.28, "cm"),
    legend.title = element_text(size = 7),
    legend.text = element_text(size = 6),
    plot.margin = margin(2.75, 5.5, 5.5, 6)
  ) +
  guides(fill = guide_legend(ncol = 1, byrow = TRUE))

# ---- g23 ---------------------------------------------------------------------
g23_chronic_vs_other_only_split_distribution <- compose_three_panel_grob(
  g2_left_raw_bar,
  g22_top_right_raw_distribution,
  g23_bottom_right_other_only_distribution,
  left_width = 0.22,
  right_width = 0.78
)

grid::grid.draw(g23_chronic_vs_other_only_split_distribution)

ggsave(
  paste0(prints_folder, "g23_chronic_vs_other_only_raw_split_distribution.png"),
  g23_chronic_vs_other_only_split_distribution, width = 8.5, height = 7, dpi = 300
)



# =============================================================================
# G3 FAMILY — Modeled-Outcome Shape Checks for days_absent_chronic
# Purpose: Evaluate candidate transformations for two-part/hurdle modeling:
# (g31) Full distribution (y >= 0): compare transformations that handle zero,
#       informing zero-inflation / hurdle probability component
# (g32) Positive-part only (y > 0): assess normality of conditional distribution,
#       informing model specification for chronic reporters
# =============================================================================


# ---- t1-modeling-assumptions -------------------------------------------------
t1_modeling_assumptions <- tibble::tribble(
  ~candidate_scale, ~formula, ~requires_strictly_positive, ~handles_zero_directly,
  ~primary_assumption, ~implication_for_modeling,
  "Raw count", "y", "No", "Yes",
  "Count process with potentially strong right-skew", "Natural scale for Poisson / NB / hurdle count models",
  "Square root", "sqrt(y)", "No", "Yes",
  "Variance stabilisation for moderate counts", "Useful descriptive view when tail is less extreme",
  "Log-shift", "log1p(y)", "No", "Yes",
  "Multiplicative effects become additive on transformed scale", "Common for linear-model diagnostics on skewed outcomes",
  "Inverse hyperbolic sine", "asinh(y)", "No", "Yes",
  "Log-like in upper tail while remaining defined at zero", "Robust alternative when zeros are frequent",
  "Positive-part log", "log(y) for y > 0", "Yes", "No",
  "Conditional model after a separate zero process", "Aligned with two-part / hurdle interpretation"
)

if (isTRUE(getOption("knitr.in.progress"))) {
  knitr::kable(
    t1_modeling_assumptions,
    format = "html",
    col.names = c(
      "Candidate scale",
      "Formula",
      "Requires y > 0",
      "Handles zero directly",
      "Primary assumption",
      "Modeling implication"
    ),
    align = c("l", "l", "c", "c", "l", "l"),
    caption = "Modeled-outcome table: transformation assumptions for days_absent_chronic"
  )
} else {
  print(t1_modeling_assumptions)
}

# ---- g31-data-prep -----------------------------------------------------------
# Build long-form transformed variants of days_absent_chronic (full sample, y >= 0)
# to compare shape diagnostics side-by-side.
g31_transform_data <- ds0 %>%
  transmute(
    y_raw   = days_absent_chronic,
    y_sqrt  = sqrt(days_absent_chronic),
    y_log1p = log1p(days_absent_chronic),
    y_asinh = asinh(days_absent_chronic)
  ) %>%
  tidyr::pivot_longer(
    cols = everything(),
    names_to = "scale_id",
    values_to = "value"
  ) %>%
  mutate(
    scale_label = factor(
      dplyr::recode(
        scale_id,
        y_raw = "Raw count (y)",
        y_sqrt = "Square root: sqrt(y)",
        y_log1p = "Log-shift: log1p(y)",
        y_asinh = "IHS: asinh(y)"
      ),
      levels = c(
        "Raw count (y)",
        "Square root: sqrt(y)",
        "Log-shift: log1p(y)",
        "IHS: asinh(y)"
      )
    )
  )

skewness_estimate <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 3) return(NA_real_)
  m <- mean(x)
  s <- stats::sd(x)
  if (!is.finite(s) || s == 0) return(0)
  mean((x - m)^3) / (s^3)
}

g31_shape_summary <- g31_transform_data %>%
  group_by(scale_label) %>%
  summarise(
    zero_mass_pct = mean(value == 0, na.rm = TRUE) * 100,
    p90           = stats::quantile(value, probs = 0.90, na.rm = TRUE, names = FALSE),
    p99           = stats::quantile(value, probs = 0.99, na.rm = TRUE, names = FALSE),
    skewness      = skewness_estimate(value),
    .groups = "drop"
  )

g31_shape_table <- g31_shape_summary %>%
  mutate(
    scale_label = as.character(scale_label),
    zero_mass_pct = sprintf("%.2f%%", zero_mass_pct),
    p90 = sprintf("%.2f", p90),
    p99 = sprintf("%.2f", p99),
    skewness = sprintf("%.2f", skewness)
  )

if (isTRUE(getOption("knitr.in.progress"))) {
  knitr::kable(
    g31_shape_table,
    format = "html",
    col.names = c("Scale", "Zero mass", "P90", "P99", "Skewness"),
    align = c("l", "r", "r", "r", "r"),
    caption = "g31 table: shape diagnostics (full sample) for days_absent_chronic across candidate scales"
  )
} else {
  print(g31_shape_table)
}

# ---- g31 ---------------------------------------------------------------------
# g31: ECDF overlays (full sample, y >= 0) in faceted panels make skew reduction
# and tail compression easy to compare. Informs zero-inflation / hurdle probability.
g31_transform_ecdf <- g31_transform_data %>%
  ggplot(aes(x = value)) +
  stat_ecdf(linewidth = 0.9, colour = "#005072") +
  facet_wrap(~ scale_label, scales = "free_x", ncol = 2) +
  labs(
    title = "g31: Transformation diagnostics for days_absent_chronic (full sample, y ≥ 0)",
    subtitle = "Full analytic sample including zero chronic absences. Examines zero-inflation structure and tail behavior.",
    x = "Outcome value on candidate scale",
    y = "Empirical cumulative proportion",
    caption = "Full sample perspective: evaluates zero mass (94.3%) and skew among all respondents. Lower skew and compressed upper tail suggest easier Gaussian approximation in the zero-inflation component."
  ) +
  theme_minimal(base_size = 11) +
  theme(
    strip.text = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

ggsave(
  paste0(prints_folder, "g31_transform_ecdf.png"),
  g31_transform_ecdf, width = 8.5, height = 5.5, dpi = 300
)
print(g31_transform_ecdf)

# ---- g32-data-prep -----------------------------------------------------------
# Build long-form transformed variants of days_absent_chronic (positive part only, y > 0)
# to assess Gaussian approximation among chronic reporters.
g32_transform_data <- ds0 %>%
  filter(days_absent_chronic > 0) %>%  # Focus on positive-part only
  transmute(
    y_raw   = days_absent_chronic,
    y_sqrt  = sqrt(days_absent_chronic),
    y_log1p = log1p(days_absent_chronic),
    y_asinh = asinh(days_absent_chronic),
    y_poslog = log(days_absent_chronic)  # Positive-part log (only valid for y > 0)
  ) %>%
  tidyr::pivot_longer(
    cols = everything(),
    names_to = "scale_id",
    values_to = "value"
  ) %>%
  mutate(
    scale_label = factor(
      dplyr::recode(
        scale_id,
        y_raw = "Raw count (y)",
        y_sqrt = "Square root: sqrt(y)",
        y_log1p = "Log-shift: log1p(y)",
        y_asinh = "IHS: asinh(y)",
        y_poslog = "Log (positive-part): log(y)"
      ),
      levels = c(
        "Raw count (y)",
        "Square root: sqrt(y)",
        "Log-shift: log1p(y)",
        "IHS: asinh(y)",
        "Log (positive-part): log(y)"
      )
    )
  )

g32_shape_summary <- g32_transform_data %>%
  group_by(scale_label) %>%
  summarise(
    n_obs     = n(),
    p90       = stats::quantile(value, probs = 0.90, na.rm = TRUE, names = FALSE),
    p99       = stats::quantile(value, probs = 0.99, na.rm = TRUE, names = FALSE),
    skewness  = skewness_estimate(value),
    .groups = "drop"
  )

g32_shape_table <- g32_shape_summary %>%
  mutate(
    scale_label = as.character(scale_label),
    n_obs = sprintf("%d", n_obs),
    p90 = sprintf("%.2f", p90),
    p99 = sprintf("%.2f", p99),
    skewness = sprintf("%.2f", skewness)
  )

if (isTRUE(getOption("knitr.in.progress"))) {
  knitr::kable(
    g32_shape_table,
    format = "html",
    col.names = c("Scale", "N (y > 0)", "P90", "P99", "Skewness"),
    align = c("l", "r", "r", "r", "r"),
    caption = "g32 table: shape diagnostics (positive-part only) for days_absent_chronic across candidate scales"
  )
} else {
  print(g32_shape_table)
}

# ---- g32 ---------------------------------------------------------------------
# g32: ECDF overlays (positive part only, y > 0) in faceted panels.
# Three reference lines per facet:
#   Empirical  — orange solid (actual data)
#   Gaussian   — purple dashed (same mean/SD, continuous)
#   Poisson    — teal dotted (lambda = mean of raw positive part; x-grid transformed per scale)
# Informs model specification for the conditional distribution among chronic reporters.

# Gaussian reference parameters per scale
g32_gauss_params <- g32_transform_data %>%
  group_by(scale_label) %>%
  summarise(
    mu = mean(value, na.rm = TRUE),
    sigma = sd(value, na.rm = TRUE),
    min_val = min(value, na.rm = TRUE),
    max_val = max(value, na.rm = TRUE),
    .groups = "drop"
  )

# Gaussian ECDF reference curves
g32_gauss_ecdf <- g32_gauss_params %>%
  rowwise() %>%
  mutate(
    x_grid  = list(seq(min_val, max_val, length.out = 300)),
    cdf_grid = list(pnorm(x_grid, mean = mu, sd = sigma))
  ) %>%
  unnest(cols = c(x_grid, cdf_grid)) %>%
  ungroup() %>%
  mutate(series = "Gaussian")

# Poisson reference: lambda = mean of raw positive-part days_absent_chronic.
# For each scale, compute ppois() on the raw integer grid then apply the
# same transformation to the x values so the CDF is plotted on each panel's axis.
g32_lambda <- mean(ds0$days_absent_chronic[ds0$days_absent_chronic > 0], na.rm = TRUE)
g32_raw_x_max <- max(ds0$days_absent_chronic[ds0$days_absent_chronic > 0], na.rm = TRUE)

g32_pois_ecdf <- tibble::tibble(
  x_raw    = seq_len(g32_raw_x_max),
  cdf_grid = ppois(x_raw, lambda = g32_lambda)
) %>%
  tidyr::crossing(
    tibble::tibble(scale_label = levels(g32_transform_data$scale_label))
  ) %>%
  mutate(
    x_grid = dplyr::case_when(
      scale_label == "Raw count (y)"               ~ as.double(x_raw),
      scale_label == "Square root: sqrt(y)"        ~ sqrt(x_raw),
      scale_label == "Log-shift: log1p(y)"         ~ log1p(x_raw),
      scale_label == "IHS: asinh(y)"               ~ asinh(x_raw),
      scale_label == "Log (positive-part): log(y)" ~ log(x_raw)
    ),
    scale_label = factor(scale_label, levels = levels(g32_transform_data$scale_label)),
    series = "Poisson"
  ) %>%
  select(scale_label, x_grid, cdf_grid, series)

# Combine reference curves for a single geom_line call
g32_ref_curves <- bind_rows(
  g32_gauss_ecdf %>% select(scale_label, x_grid, cdf_grid, series),
  g32_pois_ecdf
)

# Colour and linetype mappings
g32_ref_colours   <- c("Empirical" = "#D55E00", "Gaussian" = "#7030A0", "Poisson" = "#009E73")
g32_ref_linetypes <- c("Empirical" = "solid",   "Gaussian" = "dashed",  "Poisson" = "dotted")
g32_ref_linewidths <- c("Empirical" = 0.9,       "Gaussian" = 0.5,       "Poisson" = 0.5)

# Create the g32 plot
g32_transform_ecdf <- g32_transform_data %>%
  ggplot(aes(x = value)) +
  # Empirical ECDF
  stat_ecdf(
    aes(colour = "Empirical", linetype = "Empirical"),
    linewidth = 0.9
  ) +
  # Gaussian + Poisson reference ECDFs
  geom_line(
    data = g32_ref_curves,
    aes(x = x_grid, y = cdf_grid, colour = series, linetype = series),
    linewidth = 0.5,
    alpha = 0.90
  ) +
  scale_colour_manual(values = g32_ref_colours,   name = NULL) +
  scale_linetype_manual(values = g32_ref_linetypes, name = NULL) +
  facet_wrap(~ scale_label, scales = "free_x", ncol = 2) +
  labs(
    title = "g32: Transformation diagnostics for days_absent_chronic (positive part, y > 0)",
    subtitle = paste0(
      "Chronic reporters only (n = 3,626). ",
      "Orange solid = empirical ECDF; purple dashed = Gaussian (same mean/SD); ",
      "teal dotted = Poisson (\u03bb = ", sprintf("%.2f", g32_lambda), "). ",
      "Closer overlap = better approximation."
    ),
    x = "Outcome value on candidate scale",
    y = "Empirical cumulative proportion",
    caption = paste0(
      "Poisson CDF uses lambda = mean of raw positive-part days; x-axis reflects the same transformation applied to each scale's panel. ",
      "Where empirical lies between Gaussian and Poisson, neither model is a perfect fit. ",
      "Where empirical tracks Gaussian most closely (log scale), a log-link or Gaussian model is most appropriate."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    strip.text = element_text(face = "bold"),
    panel.grid.minor = element_blank(),
    legend.position = "bottom"
  )

ggsave(
  paste0(prints_folder, "g32_transform_ecdf.png"),
  g32_transform_ecdf, width = 8.5, height = 5.5, dpi = 300
)
print(g32_transform_ecdf)

# ---- g33-data-prep -----------------------------------------------------------
# Density vs fitted Gaussian overlay per transformation scale.
# Shows how well each scale's empirical distribution matches a normal with the
# same mean and SD — the better the match, the more its mean captures "typical"
# and its SD captures "spread" in the intuitive, symmetric sense.
# Computed for positive-part only (y > 0).

g33_gauss_ref <- g32_transform_data %>%
  group_by(scale_label) %>%
  summarise(
    mu = mean(value, na.rm = TRUE),
    sigma = sd(value, na.rm = TRUE),
    .groups = "drop"
  )

g33_gauss_curve <- g33_gauss_ref %>%
  rowwise() %>%
  mutate(
    x_grid = list(seq(mu - 4 * sigma, mu + 4 * sigma, length.out = 300)),
    y_grid = list(dnorm(x_grid, mean = mu, sd = sigma))
  ) %>%
  unnest(cols = c(x_grid, y_grid)) %>%
  ungroup()

# ---- g33 ---------------------------------------------------------------------
g33_density_vs_gaussian <- g32_transform_data %>%
  ggplot(aes(x = value)) +
  geom_density(
    aes(colour = "Empirical density"),
    linewidth = 0.9, key_glyph = "path"
  ) +
  geom_line(
    data = g33_gauss_curve,
    aes(x = x_grid, y = y_grid, colour = "Gaussian (same mean & SD)"),
    linewidth = 0.7, linetype = "dashed", key_glyph = "path"
  ) +
  facet_wrap(~ scale_label, scales = "free", ncol = 2) +
  scale_colour_manual(
    values = c("Empirical density" = "#D55E00", "Gaussian (same mean & SD)" = "#005072"),
    name = NULL
  ) +
  labs(
    title = "g33: Why reduced skew matters for positive-part modeling (y > 0)",
    subtitle = paste0(
      "Chronic reporters only. When orange curve matches blue dashed curve, the mean and SD\n",
      "fully characterize the conditional distribution -- each transformation's behavior is predictable."
    ),
    x = "Outcome value on candidate scale",
    y = "Density",
    caption = paste0(
      "Blue dashed = N(mean, SD) fitted to positive-part data.\n ",
      "Better overlap = mean/SD statistics are trustworthy for conditional modeling. Informs choice of log-link or power transformation."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    strip.text = element_text(face = "bold"),
    legend.position = "bottom",
    panel.grid.minor = element_blank()
  )

ggsave(
  paste0(prints_folder, "g33_density_vs_gaussian.png"),
  g33_density_vs_gaussian, width = 8.5, height = 5.5, dpi = 300
)
print(g33_density_vs_gaussian)


# =============================================================================
# G3 FAMILY — Composite Outcome Distribution    [STUB]
# Framing question: How does days_absent_total distribute — its zero mass,
#   right-tail shape, and key quantiles?
# g3: annotated histogram with zero-inflation and quantile markers
# =============================================================================

# ---- g3-data-prep ------------------------------------------------------------
# TODO: prepare days_absent_total distribution (zero vs positive split, quantiles)

# ---- g3 ----------------------------------------------------------------------
# TODO: histogram with zero-inflation annotation and quantile reference lines


# =============================================================================
# G4 FAMILY — Individual Respondent Contribution to Chronic-Absence Burden
# Framing question: How do individual respondents with chronic absences
#   distribute in their weighted-day contribution to total population burden?
# g41: frequency distribution of respondent-level weighted chronic days
# g42: histogram of weighted days with burden decomposition
# =============================================================================

# ---- g4-data-prep ------------------------------------------------------------
# Calculate individual respondent weighted contribution to chronic-absence burden.
# weighted_days = days_absent_chronic * weight_col
# This represents each respondent's population-level contribution to total burden.

g4_respondent_contribution <- ds0 %>%
  transmute(
    days_absent_chronic = as.integer(days_absent_chronic),
    weight_value        = .data[[weight_col]],
    weighted_days       = days_absent_chronic * weight_value,
    is_chronic_reporter = days_absent_chronic > 0
  ) %>%
  filter(is_chronic_reporter)

# Summary statistics for respondent-level weighted contribution
g4_contribution_summary <- g4_respondent_contribution %>%
  summarise(
    n_respondents = n(),
    sum_weighted_days = sum(weighted_days, na.rm = TRUE),
    mean_weighted_days = mean(weighted_days, na.rm = TRUE),
    median_weighted_days = median(weighted_days, na.rm = TRUE),
    sd_weighted_days = sd(weighted_days, na.rm = TRUE),
    min_weighted_days = min(weighted_days, na.rm = TRUE),
    max_weighted_days = max(weighted_days, na.rm = TRUE),
    q25_weighted_days = quantile(weighted_days, probs = 0.25, na.rm = TRUE),
    q75_weighted_days = quantile(weighted_days, probs = 0.75, na.rm = TRUE),
    p90_weighted_days = quantile(weighted_days, probs = 0.90, na.rm = TRUE),
    p95_weighted_days = quantile(weighted_days, probs = 0.95, na.rm = TRUE),
    p99_weighted_days = quantile(weighted_days, probs = 0.99, na.rm = TRUE)
  )

# Create weighted-day bins for frequency display
# Bins selected to reveal distribution structure while maintaining stability
g4_respondent_binned <- g4_respondent_contribution %>%
  mutate(
    weighted_day_bin = dplyr::case_when(
      weighted_days < 1           ~ "< 1",
      weighted_days < 2           ~ "1 to < 2",
      weighted_days < 5           ~ "2 to < 5",
      weighted_days < 10          ~ "5 to < 10",
      weighted_days < 20          ~ "10 to < 20",
      weighted_days < 50          ~ "20 to < 50",
      weighted_days < 100         ~ "50 to < 100",
      weighted_days < 200         ~ "100 to < 200",
      TRUE                        ~ "200+"
    ),
    weighted_day_bin = factor(
      weighted_day_bin,
      levels = c("< 1", "1 to < 2", "2 to < 5", "5 to < 10", 
                 "10 to < 20", "20 to < 50", "50 to < 100", 
                 "100 to < 200", "200+")
    )
  )

# Compute bin frequencies (count of respondents, not weighted)
g4_bin_freq <- g4_respondent_binned %>%
  group_by(weighted_day_bin) %>%
  summarise(
    n_respondents = n(),
    wt_sum_days = sum(weighted_days, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    pct_respondents = n_respondents / sum(n_respondents) * 100,
    pct_burden = wt_sum_days / sum(wt_sum_days) * 100,
    cumsum_pct_respondents = cumsum(pct_respondents),
    cumsum_pct_burden = cumsum(pct_burden)
  )

# ---- g41 ---------------------------------------------------------------------
# g41: Frequency distribution of respondents by their weighted-day contribution.
# Y-axis: count of respondents (sample perspective)
# X-axis: weighted-day bins (individual contribution to population burden)
# Caption: reveals concentration of burden — are respondents evenly distributed
#   or is burden concentrated in small group of high-weight chronic reporters?

g41_respondent_freq_by_burden <- g4_bin_freq %>%
  ggplot(aes(x = weighted_day_bin, y = n_respondents, fill = weighted_day_bin)) +
  geom_col(width = 0.8, alpha = 0.85, colour = "white", linewidth = 0.3) +
  geom_text(
    aes(label = paste0(scales::comma(n_respondents), "\n(", sprintf("%.1f%%", pct_respondents), ")")),
    vjust = -0.2,
    size = 3,
    lineheight = 0.95
  ) +
  scale_y_continuous(
    labels = scales::label_comma(),
    expand = expansion(mult = c(0, 0.08))
  ) +
  scale_fill_brewer(palette = "YlOrRd", direction = 1, name = "Weighted-day bin") +
  labs(
    title = "G41: Respondent frequency by weighted-day contribution to chronic-absence burden",
    subtitle = paste0(
      "Respondents with ≥1 chronic-absence day (n = ", scales::comma(g4_contribution_summary$n_respondents),
      "). Each respondent weighted by ", weight_col, "."
    ),
    x = "Individual weighted-day contribution",
    y = "Number of respondents",
    caption = paste0(
      "Weighted days per respondent = days_absent_chronic × ", weight_col, ". ",
      "Reveals whether chronic-absence burden is concentrated or distributed. ",
      "Large right tail suggests few high-weight respondents drive majority of population burden."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x = element_text(angle = 35, hjust = 1),
    legend.position = "none",
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank()
  )

ggsave(
  paste0(prints_folder, "g41_respondent_freq_by_burden.png"),
  g41_respondent_freq_by_burden, width = 8.5, height = 5.5, dpi = 300
)
print(g41_respondent_freq_by_burden)

# Mini validation: print bin summary table for verification
if (isTRUE(getOption("knitr.in.progress"))) {
  g4_bin_display <- g4_bin_freq %>%
    transmute(
      `Weighted-day bin` = weighted_day_bin,
      `Respondent count` = scales::comma(n_respondents),
      `% of respondents` = sprintf("%.1f%%", pct_respondents),
      `Total burden (weighted days)` = sprintf("%.0f", wt_sum_days),
      `% of total burden` = sprintf("%.1f%%", pct_burden),
      `Cumulative % burden` = sprintf("%.1f%%", cumsum_pct_burden)
    )

  knitr::kable(
    g4_bin_display,
    format = "html",
    align = c("l", "r", "r", "r", "r", "r"),
    caption = "G41 validation table: respondent frequency and burden contribution by weighted-day bin"
  )
}

# nolint end
