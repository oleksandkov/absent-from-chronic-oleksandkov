# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# EDA-5: LOP Component Decomposition — Sections 4.1 and 4.2
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
local_root    <- "./analysis/eda-5/"
local_data    <- paste0(local_root, "data-local/")
prints_folder <- paste0(local_root, "prints/")
data_private_derived <- "./data-private/derived/eda-5/"

if (!fs::dir_exists(local_data))           fs::dir_create(local_data)
if (!fs::dir_exists(prints_folder))        fs::dir_create(prints_folder)
if (!fs::dir_exists(data_private_derived)) fs::dir_create(data_private_derived)

path_cchs2_parquet  <- "./data-private/derived/cchs-2-tables"
path_analytical_pq  <- file.path(path_cchs2_parquet, "cchs_analytic.parquet")
weight_col          <- "wts_m_pooled"

# LOP component columns and their human-readable labels
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

# Day-range bands and their sequential ramp. This palette is the visual signature
# of the "at least one missed day" group throughout this report: it colours the
# non-zero segment of g0 and every bar in g01-g06. Defined here (rather than
# inside g01-data-prep) so that g0 can draw on it too.
day_range_levels  <- c("1 day", "2 days", "3 days", "4 days", "5 days",
                       "6\u201310 days", "11\u201315 days", "16\u201330 days", "31+ days")
day_range_colours <- c(
  "1 day"           = "#f7941d",
  "2 days"          = "#e8601c",
  "3 days"          = "#cc3311",
  "4 days"          = "#aa1133",
  "5 days"          = "#880044",
  "6\u201310 days"  = "#6a0177",
  "11\u201315 days" = "#49006a",
  "16\u201330 days" = "#2d004b",
  "31+ days"        = "#0d0014"
)

# Outcome-group partition, carried over UNCHANGED from analysis/eda-72 (which in
# turn inherits it from eda-71 g2). Reusing the exact levels and hex values is
# what gives eda-5's g07-g09 visual continuity with eda-72's g1 and g2 families.
#   No Days           days_absent_total == 0
#   Chronic Days      days_absent_chronic > 0
#   Non-Chronic Days  days_absent_chronic == 0 & days_absent_total > 0
outcome_group_levels  <- c("No Days", "Chronic Days", "Non-Chronic Days")
outcome_group_colours <- c(
  "No Days"          = "#D9D9D9",
  "Chronic Days"     = "#D08C60",
  "Non-Chronic Days" = "#0B4F6C"
)

# ---- declare-functions -------------------------------------------------------
# Bin a count of days into the day_range bands declared above. Used by g0, g01,
# g03-g06, and g08.
assign_day_range <- function(days) {
  dplyr::case_when(
    days == 1  ~ "1 day",
    days == 2  ~ "2 days",
    days == 3  ~ "3 days",
    days == 4  ~ "4 days",
    days == 5  ~ "5 days",
    days <= 10 ~ "6\u201310 days",
    days <= 15 ~ "11\u201315 days",
    days <= 30 ~ "16\u201330 days",
    TRUE       ~ "31+ days"
  )
}

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
  stop("Missing required columns in cchs_analytic.parquet: ",
       paste(missing_required, collapse = ", "), call. = FALSE)
}

cat(sprintf("Loaded analytical data: %s rows, %s columns\n",
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
# A respondent with activity on at least 3 LOP components — shows the key columns
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
    ) >= 3
  ) %>%
  slice_head(n = 2)
print(data_context_person)

# ---- data-context-distributions ----------------------------------------------
# Non-missing counts, zero counts, and raw prevalence per LOP component
data_context_distributions <- ds0 %>%
  summarise(
    across(
      all_of(names(lop_components)),
      list(
        n_nonmissing = ~ sum(!is.na(.x)),
        n_zero       = ~ sum(.x == 0,  na.rm = TRUE),
        n_positive   = ~ sum(.x > 0,   na.rm = TRUE),
        pct_positive = ~ mean(.x > 0,  na.rm = TRUE) * 100
      )
    )
  ) %>%
  tidyr::pivot_longer(
    cols         = everything(),
    names_to     = c("column", ".value"),
    names_pattern = "^(.+)_(n_nonmissing|n_zero|n_positive|pct_positive)$"
  ) %>%
  mutate(reason_label = lop_components[column])
print(data_context_distributions)

# ---- tweak-data-0 ------------------------------------------------------------
# Long-form LOP component dataset — shared ancestor for G1, G2, G3, G4, G6 families

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
# let's save ds_lop_long as a parquet for potential reuse in later analyses
# arrow::write_parquet(ds_lop_long, file.path(data_private_derived, "ds_lop_long.parquet"))
ds_lop_long %>% glimpse()
# ---- SECTION: G0 Family - Outcome Distribution --------------------------------
# Framing question: How does absence distribute across the analytical sample?
# g0: zero vs non-zero split | g01: total histogram | g02: day-range bar
# g03-g06: reason facets | g07-g09: outcome-group breakdown (continuity w/ eda-72)

# ---- g0-data-prep ------------------------------------------------------------
# The bar carries TWO readings at once. Coarse: zero vs >=1 missed day. Fine: the
# >=1 segment is itself a gradient strip in the day-range ramp, so the reader can
# see at a glance which slice of the sample g01-g06 go on to decompose.

g0_segment_levels  <- c("No missed days (zero)", day_range_levels)
g0_segment_colours <- c("No missed days (zero)" = "#D9D9D9", day_range_colours)

g0_data <- ds0 %>%
  mutate(
    absent_group = dplyr::if_else(
      !is.na(days_absent_total) & days_absent_total >= 1,
      "At least one missed day",
      "No missed days (zero)"
    ),
    absent_group = factor(
      absent_group,
      levels = c("No missed days (zero)", "At least one missed day")
    ),
    segment = dplyr::if_else(
      absent_group == "At least one missed day",
      assign_day_range(days_absent_total),
      "No missed days (zero)"
    ),
    segment = factor(segment, levels = g0_segment_levels)
  ) %>%
  group_by(absent_group, segment) %>%
  summarise(
    n_people  = n(),
    wt_people = sum(.data[[weight_col]], na.rm = TRUE),
    .groups   = "drop"
  ) %>%
  mutate(
    pct_n  = n_people  / sum(n_people)  * 100,
    pct_wt = wt_people / sum(wt_people) * 100
  )

g0_group_totals <- g0_data %>%
  group_by(absent_group) %>%
  summarise(
    n_people = sum(n_people),
    pct_n    = sum(pct_n),
    pct_wt   = sum(pct_wt),
    .groups  = "drop"
  )

# The >=1-day group is the unit that g07-g09 partition into outcome groups.
n_any_days <- g0_group_totals %>%
  filter(absent_group == "At least one missed day") %>%
  pull(n_people)

# ---- g0 ----------------------------------------------------------------------
# Horizontal stacked bar: zero vs >=1 absent day, the latter as a day-range gradient

g0_zero_share_wt <- g0_group_totals %>%
  filter(absent_group == "No missed days (zero)") %>%
  pull(pct_wt)

g0_any_totals <- g0_group_totals %>%
  filter(absent_group == "At least one missed day")

g0_lop_zero_vs_nonzero <- g0_data %>%
  ggplot(aes(x = pct_wt, y = "Analytical sample", fill = segment)) +
  geom_col(width = 0.62, colour = "white", linewidth = 0.25, alpha = 0.95,
           position = position_stack(reverse = TRUE)) +
  geom_text(
    data = dplyr::filter(g0_data, segment == "No missed days (zero)"),
    aes(label = sprintf("No missed days (zero)\nn = %s   (%.1f%%)",
                        scales::comma(n_people), pct_n)),
    position   = position_stack(vjust = 0.5, reverse = TRUE),
    size       = 3.4,
    colour     = "grey15",
    fontface   = "bold",
    lineheight = 1.1
  ) +
  annotate(
    "segment",
    x = g0_zero_share_wt, xend = 100, y = 1.38, yend = 1.38,
    colour = "grey30", linewidth = 0.4
  ) +
  annotate(
    "segment",
    x = c(g0_zero_share_wt, 100), xend = c(g0_zero_share_wt, 100),
    y = c(1.38, 1.38), yend = c(1.31, 1.31),
    colour = "grey30", linewidth = 0.4
  ) +
  annotate(
    "text",
    x     = (g0_zero_share_wt + 100) / 2,
    y     = 1.44,
    label = sprintf(
      "At least one missed day\nn = %s   (%.1f%%)",
      scales::comma(g0_any_totals$n_people), g0_any_totals$pct_n
    ),
    size       = 3.1,
    colour     = "grey20",
    fontface   = "bold",
    vjust      = 0,
    lineheight = 1.1
  ) +
  scale_x_continuous(
    labels = label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.02))
  ) +
  scale_y_discrete(expand = expansion(add = c(0.35, 0.95))) +
  scale_fill_manual(values = g0_segment_colours) +
  labs(
    title    = "G0 (\u00a74.2): Zero vs non-zero absenteeism in the analytical sample",
    subtitle = sprintf(
      paste(
        "Total analytical sample: n = %s respondents.",
        "\nThe non-zero segment is a gradient strip in the day-range ramp \u2014 the palette used in G01\u2013G06.",
        "G07\u2013G09 partition this same group."
      ),
      scales::comma(sum(g0_data$n_people))
    ),
    x        = "Weighted share of respondents (%)",
    y        = NULL,
    fill     = NULL,
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.y        = element_blank(),
    axis.ticks.y       = element_blank(),
    panel.grid.major.y = element_blank(),
    plot.subtitle      = element_text(size = 9),
    legend.position    = "bottom"
  ) +
  guides(fill = guide_legend(nrow = 1))

ggsave(paste0(prints_folder, "g0_lop_zero_vs_nonzero.png"),
       g0_lop_zero_vs_nonzero, width = 10, height = 3.6, dpi = 300)
print(g0_lop_zero_vs_nonzero)

# ---- g01-data-prep -----------------------------------------------------------
# Shared setup for g01 and g02: restrict to ≥1-day group; assign day-range category
# (day_range_levels / day_range_colours now live in declare-globals)

ds_nonzero <- ds0 %>%
  filter(!is.na(days_absent_total), days_absent_total >= 1) %>%
  mutate(
    day_range = factor(assign_day_range(days_absent_total), levels = day_range_levels)
  )

# ---- g01 ---------------------------------------------------------------------
# Frequency histogram: x = total days missed, y = respondents
# Bars coloured by the same day-range palette used in g02

g01_hist_data <- ds_nonzero %>%
  count(days_absent_total, day_range)

g01_lop_days_histogram <- g01_hist_data %>%
  ggplot(aes(x = days_absent_total, y = n, fill = day_range)) +
  geom_col(width = 0.9, alpha = 0.90) +
  geom_col(
    data    = ~ filter(.x, days_absent_total == 1),
    width   = 0.9, colour = "black", fill = NA, alpha = 0.5
  ) +
  scale_x_continuous(
    breaks = c(1, 5, 10, 15, 20, 25, 30, 40, 50, 63),
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(
    labels = scales::label_comma(),
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_fill_manual(values = day_range_colours) +
  labs(
    title    = "G01 (\u00a74.2): Frequency distribution of total missed days (respondents with \u22651 day)",
    subtitle = sprintf("n = %s respondents; x-axis capped at observed maximum",
                       scales::comma(nrow(ds_nonzero))),
    x        = "Total days absent (days_absent_total)",
    y        = "Number of respondents",
    fill     = "Day range",
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(paste0(prints_folder, "g01_lop_days_histogram.png"),
       g01_lop_days_histogram, width = 10, height = 5, dpi = 300)
print(g01_lop_days_histogram)

# ---- g02-data-prep -----------------------------------------------------------
g02_data <- ds_nonzero %>%
  group_by(day_range) %>%
  summarise(
    n_people  = n(),
    wt_people = sum(.data[[weight_col]], na.rm = TRUE),
    .groups   = "drop"
  ) %>%
  mutate(
    pct_n  = n_people  / sum(n_people)  * 100,
    pct_wt = wt_people / sum(wt_people) * 100
  )

# ---- g02 ---------------------------------------------------------------------
# Horizontal stacked bar: day-range breakdown for the ≥1-day group

g02_lop_day_ranges <- g02_data %>%
  ggplot(aes(x = pct_wt, y = "Respondents with \u22651 day", fill = day_range)) +
  geom_col(width = 1.0, alpha = 0.90) +
  geom_text(
    aes(label = sprintf("%s - %.0f%%",
                        stringr::str_remove(as.character(day_range), " days?$"),
                        pct_n)),
    position   = position_stack(vjust = 0.5),
    angle      = 90,
    size       = 3.0,
    colour     = "white",
    fontface   = "bold",
    lineheight = 1.1
  ) +
  scale_x_continuous(
    labels = scales::label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.02))
  ) +
  scale_fill_manual(values = day_range_colours) +
  labs(
    title    = "G02 (\u00a74.2): Day-range breakdown among respondents with \u22651 missed day",
    subtitle = sprintf("Total: n = %s respondents with at least one missed workday",
                       scales::comma(nrow(ds_nonzero))),
    x        = "Weighted share (%)",
    y        = NULL,
    fill     = "Day range",
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.y        = element_blank(),
    axis.ticks.y       = element_blank(),
    panel.grid.major.y = element_blank(),
    legend.position    = "top",
    legend.box.margin  = margin(0, 0, -12, 0)
  ) +
  guides(fill = guide_legend(nrow = 1, reverse = TRUE))

ggsave(paste0(prints_folder, "g02_lop_day_ranges.png"),
       g02_lop_day_ranges, width = 10, height = 4, dpi = 300)
print(g02_lop_day_ranges)

# ---- g03-data-prep -----------------------------------------------------------
# Faceted histograms by reason: for each LOP component, show distribution of
# days_reason among those with ≥1 day for that reason. Includes "Total" facet.
# (assign_day_range now lives in declare-functions)

# Data for each reason: days_reason distribution among those with ≥1 day for that reason
g03_reason_data <- ds_lop_long %>%
  filter(has_days) %>%
  mutate(
    day_range = factor(assign_day_range(days_reason), levels = day_range_levels)
  ) %>%
  group_by(reason_label, days_reason, day_range) %>%
  summarise(n = n(), .groups = "drop")

# Add "Total" facet using days_absent_total for those with ≥1 day
g03_total_data <- ds_nonzero %>%
  mutate(
    reason_label = "Total (all reasons)",
    days_reason  = days_absent_total
  ) %>%
  group_by(reason_label, days_reason, day_range) %>%
  summarise(n = n(), .groups = "drop")

# Combine and ensure consistent ordering
g03_faceted_data <- bind_rows(g03_reason_data, g03_total_data) %>%
  mutate(
    reason_label = factor(
      reason_label,
      levels = c(lop_components, "Total (all reasons)")
    )
  )

# Facet-strip labels with per-reason positive sample size (continuity with table)
facet_n_lookup <- data_context_distributions %>%
  transmute(
    reason_label = as.character(reason_label),
    n_positive = n_positive
  ) %>%
  bind_rows(
    tibble::tibble(
      reason_label = "Total (all reasons)",
      n_positive = nrow(ds_nonzero)
    )
  )

facet_label_map_all <- setNames(
  paste0(
    facet_n_lookup$reason_label,
    "\nN = ",
    scales::comma(facet_n_lookup$n_positive)
  ),
  facet_n_lookup$reason_label
)

facet_label_map_reasons <- facet_label_map_all[unname(lop_components)]

# ---- g03 ---------------------------------------------------------------------
# Faceted histograms: frequency of days absent by reason + total

g03_lop_days_faceted <- g03_faceted_data %>%
  ggplot(aes(x = days_reason, y = n, fill = day_range)) +
  geom_col(width = 0.9, alpha = 0.90) +
  facet_wrap(
    ~ reason_label,
    nrow = 3,
    ncol = 3,
    scales = "free_y",
    labeller = as_labeller(facet_label_map_all)
  ) +
  scale_x_continuous(
    breaks = c(1, 10, 20, 30, 40, 50),
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(
    labels = scales::label_comma(),
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_fill_manual(values = day_range_colours) +
  labs(
    title    = "G03 (\u00a74.2): Frequency distribution of days absent by LOP reason",
    subtitle = "Respondents with \u22651 day absent per reason; total facet shows all reasons combined",
    x        = "Days absent (reason-specific for facets 1–8, combined for Total)",
    y        = "Number of respondents",
    fill     = "Day range",
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 10) +
  theme(
    legend.position = "bottom",
    strip.text      = element_text(size = 10, face = "bold")
  ) +
  guides(fill = guide_legend(nrow = 2))

ggsave(paste0(prints_folder, "g03_lop_days_faceted.png"),
       g03_lop_days_faceted, width = 12, height = 9, dpi = 300)
print(g03_lop_days_faceted)

# ---- g04 ---------------------------------------------------------------------
# Faceted histograms with FREE x and y axes: allows each reason facet to have
# its own scale, revealing distribution shape without shared-axis compression

g04_lop_days_faceted_free <- g03_faceted_data %>%
  ggplot(aes(x = days_reason, y = n, fill = day_range)) +
  geom_col(width = 0.9, alpha = 0.90) +
  facet_wrap(
    ~ reason_label,
    nrow = 3,
    ncol = 3,
    scales = "free",
    labeller = as_labeller(facet_label_map_all)
  ) +
  scale_x_continuous(
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(
    labels = scales::label_comma(),
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_fill_manual(values = day_range_colours) +
  labs(
    title    = "G04 (\u00a74.2): Frequency distribution of days absent by LOP reason (free axes)",
    subtitle = "Respondents with \u22651 day absent per reason; each facet has independent x and y scales",
    x        = "Days absent (reason-specific for facets 1–8, combined for Total)",
    y        = "Number of respondents",
    fill     = "Day range",
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 10) +
  theme(
    legend.position = "bottom",
    strip.text      = element_text(size = 10, face = "bold")
  ) +
  guides(fill = guide_legend(nrow = 2))

ggsave(paste0(prints_folder, "g04_lop_days_faceted_free.png"),
       g04_lop_days_faceted_free, width = 12, height = 9, dpi = 300)
print(g04_lop_days_faceted_free)

# ---- g05 ---------------------------------------------------------------------
# Faceted histograms by reason only (no Total facet), with fixed axis ranges:
# x-axis constrained to 1-31 days and y-axis fixed to the observed maximum.

g05_faceted_data <- g03_reason_data %>%
  filter(days_reason <= 31) %>%
  mutate(
    reason_label = factor(reason_label, levels = lop_components)
  )

# g05/g06 use x <= 31; show both plotted N and full positive N in strip labels.
g05g06_strip_counts <- g03_reason_data %>%
  mutate(
    reason_label = as.character(reason_label),
    in_plot = days_reason <= 31
  ) %>%
  group_by(reason_label) %>%
  summarise(
    n_positive_total = sum(n),
    n_plotted = sum(n[in_plot]),
    .groups = "drop"
  )

facet_label_map_g05g06 <- setNames(
  ifelse(
    g05g06_strip_counts$n_plotted == g05g06_strip_counts$n_positive_total,
    paste0(
      g05g06_strip_counts$reason_label,
      "\nN = ", scales::comma(g05g06_strip_counts$n_plotted)
    ),
    paste0(
      g05g06_strip_counts$reason_label,
      "\nN <= 31d: ", scales::comma(g05g06_strip_counts$n_plotted),
      " (N+ = ", scales::comma(g05g06_strip_counts$n_positive_total), ")"
    )
  ),
  g05g06_strip_counts$reason_label
)

g05_y_max <- max(g05_faceted_data$n, na.rm = TRUE)

g05_lop_days_faceted_x31 <- g05_faceted_data %>%
  ggplot(aes(x = days_reason, y = n, fill = day_range)) +
  geom_col(width = 0.9, alpha = 0.90) +
  facet_wrap(
    ~ reason_label,
    nrow = 3,
    ncol = 3,
    labeller = as_labeller(facet_label_map_g05g06)
  ) +
  scale_x_continuous(
    limits = c(1, 31),
    breaks = c(1, 5, 10, 15, 20, 25, 31),
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(
    limits = c(0, g05_y_max),
    labels = scales::label_comma(),
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_fill_manual(values = day_range_colours) +
  labs(
    title    = "G05 (\u00a74.2): Reason-specific frequency distribution of days absent (x <= 31)",
    subtitle = "Respondents with \u22651 day absent per reason; Total facet removed; fixed x and y ranges",
    x        = "Days absent (reason-specific; capped at 31)",
    y        = "Number of respondents",
    fill     = "Day range",
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 10) +
  theme(
    legend.position = "bottom",
    strip.text      = element_text(size = 10, face = "bold")
  ) +
  guides(fill = guide_legend(nrow = 2))

ggsave(paste0(prints_folder, "g05_lop_days_faceted_x31.png"),
       g05_lop_days_faceted_x31, width = 12, height = 9, dpi = 300)
print(g05_lop_days_faceted_x31)

# ---- g06 ---------------------------------------------------------------------
# Same facet structure as g05, but y-axis represents weighted days contributed
# by each day-count bin: sum(weight * days_reason).

g06_faceted_data <- ds_lop_long %>%
  filter(has_days, days_reason <= 31) %>%
  mutate(
    day_range     = factor(assign_day_range(days_reason), levels = day_range_levels),
    reason_label  = factor(reason_label, levels = lop_components),
    weighted_days = .data[[weight_col]] * days_reason
  ) %>%
  group_by(reason_label, days_reason, day_range) %>%
  summarise(weighted_days = sum(weighted_days, na.rm = TRUE), .groups = "drop")

g06_y_max <- max(g06_faceted_data$weighted_days, na.rm = TRUE)

g06_lop_weighted_days_faceted_x31 <- g06_faceted_data %>%
  ggplot(aes(x = days_reason, y = weighted_days, fill = day_range)) +
  geom_col(width = 0.9, alpha = 0.90) +
  facet_wrap(
    ~ reason_label,
    nrow = 3,
    ncol = 3,
    labeller = as_labeller(facet_label_map_g05g06)
  ) +
  scale_x_continuous(
    limits = c(1, 31),
    breaks = c(1, 5, 10, 15, 20, 25, 31),
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(
    limits = c(0, g06_y_max),
    labels = scales::label_comma(),
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_fill_manual(values = day_range_colours) +
  labs(
    title    = "G06 (§4.2): Reason-specific weighted days contributed (x <= 31)",
    subtitle = "Respondents with >=1 day absent per reason; Total facet removed; fixed x and y ranges",
    x        = "Days absent (reason-specific; capped at 31)",
    y        = "Weighted days contributed (sum of weight x days)",
    fill     = "Day range",
    caption  = "Source: CCHS 2010-11 & 2013-14 pooled analytical sample"
  ) +
  theme_minimal(base_size = 10) +
  theme(
    legend.position = "bottom",
    strip.text      = element_text(size = 10, face = "bold")
  ) +
  guides(fill = guide_legend(nrow = 2))

ggsave(paste0(prints_folder, "g06_lop_weighted_days_faceted_x31.png"),
       g06_lop_weighted_days_faceted_x31, width = 12, height = 9, dpi = 300)
print(g06_lop_weighted_days_faceted_x31)


# ---- SECTION: G0 Family - Outcome Group Breakdown -----------------------------
# Framing question: within the 18,837 respondents who missed at least one day,
# who missed it to a chronic condition?
#
# G0-G06 read the >=1-day group through the REASON lens: eight LOP components,
# each with its own distribution. That lens is deliberately many-to-one - a
# respondent with a cold and a chronic condition appears in two facets. To hand
# this group to eda-72 we need a partition instead: every respondent counted
# once, in exactly one place. So we collapse the seven non-chronic components
# into a single "Non-Chronic" bucket. That bucket is not a substantive category;
# it exists to serve as the REFERENCE against which the chronic group is read.
# The result is the three-group partition eda-72 builds its argument on:
#   No Days           days_absent_total == 0
#   Chronic Days      days_absent_chronic > 0
#   Non-Chronic Days  days_absent_chronic == 0 & days_absent_total > 0
# Colours are carried over unchanged from eda-72 so the two reports interlock.
#
# g07: three-group partition bar | g08: three-facet histogram | g09: overlay

# ---- g07-data-prep -----------------------------------------------------------
ds_outcome_groups <- ds0 %>%
  mutate(
    outcome_group = dplyr::case_when(
      is.na(days_absent_total)                          ~ NA_character_,
      days_absent_total == 0                            ~ "No Days",
      days_absent_chronic > 0                           ~ "Chronic Days",
      days_absent_chronic == 0 & days_absent_total > 0  ~ "Non-Chronic Days",
      TRUE                                              ~ NA_character_
    ),
    outcome_group = factor(outcome_group, levels = outcome_group_levels)
  )

# The chronic component can never exceed the total it is drawn from.
stopifnot(all(ds_outcome_groups$days_absent_chronic <=
                ds_outcome_groups$days_absent_total, na.rm = TRUE))

g07_data <- ds_outcome_groups %>%
  filter(!is.na(outcome_group)) %>%
  group_by(outcome_group) %>%
  summarise(
    n_people  = n(),
    wt_people = sum(.data[[weight_col]], na.rm = TRUE),
    .groups   = "drop"
  ) %>%
  mutate(
    pct_n  = n_people  / sum(n_people)  * 100,
    pct_wt = wt_people / sum(wt_people) * 100
  )

# The two positive-day groups must reconstitute the >=1-day group from g0 exactly.
g07_any_days <- g07_data %>%
  filter(outcome_group != "No Days") %>%
  summarise(
    n_people = sum(n_people),
    pct_n    = sum(pct_n),
    pct_wt   = sum(pct_wt)
  )
stopifnot(g07_any_days$n_people == n_any_days)

g07_no_days_share_wt <- g07_data %>%
  filter(outcome_group == "No Days") %>%
  pull(pct_wt)

# Explicit segment geometry. Chronic Days occupies under 6% of the bar, too
# narrow to hold its own label, so it is annotated below the bar with a leader.
g07_positions <- g07_data %>%
  arrange(outcome_group) %>%
  mutate(
    x_end   = cumsum(pct_wt),
    x_start = x_end - pct_wt,
    x_mid   = (x_start + x_end) / 2,
    label   = sprintf("%s\nn = %s   (%.1f%%)",
                      outcome_group, scales::comma(n_people), pct_n)
  )

g07_inside  <- g07_positions %>% filter(outcome_group != "Chronic Days")
g07_outside <- g07_positions %>% filter(outcome_group == "Chronic Days")

# ---- g07 ---------------------------------------------------------------------
# Horizontal stacked bar, same construction as g0, now partitioned three ways

g07_outcome_group_partition <- g07_data %>%
  ggplot(aes(x = pct_wt, y = "Analytical sample", fill = outcome_group)) +
  geom_col(width = 0.62, colour = "white", linewidth = 0.3, alpha = 0.95,
           position = position_stack(reverse = TRUE)) +
  geom_text(
    data = g07_inside,
    aes(x = x_mid, y = 1, label = label, colour = outcome_group),
    inherit.aes = FALSE,
    size        = 3.2,
    fontface    = "bold",
    lineheight  = 1.1
  ) +
  annotate(
    "segment",
    x = g07_outside$x_mid, xend = g07_outside$x_mid,
    y = 0.69, yend = 0.60,
    colour = outcome_group_colours[["Chronic Days"]], linewidth = 0.4
  ) +
  geom_text(
    data = g07_outside,
    aes(x = x_mid, y = 0.57, label = label),
    inherit.aes = FALSE,
    colour      = outcome_group_colours[["Chronic Days"]],
    size        = 3.2,
    fontface    = "bold",
    vjust       = 1,
    lineheight  = 1.1
  ) +
  annotate(
    "segment",
    x = g07_no_days_share_wt, xend = 100, y = 1.38, yend = 1.38,
    colour = "grey30", linewidth = 0.4
  ) +
  annotate(
    "segment",
    x = c(g07_no_days_share_wt, 100), xend = c(g07_no_days_share_wt, 100),
    y = c(1.38, 1.38), yend = c(1.31, 1.31),
    colour = "grey30", linewidth = 0.4
  ) +
  annotate(
    "text",
    x     = (g07_no_days_share_wt + 100) / 2,
    y     = 1.44,
    label = sprintf(
      "The G0 \"at least one missed day\" group\nn = %s \u2014 split in two",
      scales::comma(g07_any_days$n_people)
    ),
    size       = 3.1,
    colour     = "grey20",
    fontface   = "bold",
    vjust      = 0,
    lineheight = 1.1
  ) +
  scale_x_continuous(
    labels = label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.02))
  ) +
  scale_y_discrete(expand = expansion(add = c(0.85, 0.95))) +
  scale_fill_manual(values = outcome_group_colours, guide = "none") +
  scale_colour_manual(
    values = c(
      "No Days"          = "grey15",
      "Chronic Days"     = "white",
      "Non-Chronic Days" = "white"
    ),
    guide = "none"
  ) +
  labs(
    title    = "G07 (\u00a74.2): The three outcome groups \u2014 same partition as EDA-72",
    subtitle = paste(
      "No Days: days_absent_total = 0  |",
      "Chronic Days: days_absent_chronic > 0  |",
      "Non-Chronic Days: >=1 missed day, none of it chronic",
      "\nThe seven non-chronic LOP reasons are collapsed into one bucket so that it can serve as the reference for the chronic group."
    ),
    x        = "Weighted share of respondents (%)",
    y        = NULL,
    caption  = paste(
      "Group definitions and colours carried over unchanged from analysis/eda-72.",
      "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.y        = element_blank(),
    axis.ticks.y       = element_blank(),
    panel.grid.major.y = element_blank(),
    plot.subtitle      = element_text(size = 9, lineheight = 1.2)
  )

ggsave(paste0(prints_folder, "g07_outcome_group_partition.png"),
       g07_outcome_group_partition, width = 10, height = 4.5, dpi = 300)
print(g07_outcome_group_partition)

# ---- g08-data-prep -----------------------------------------------------------
# Same construction as g03, but the facets are outcome GROUPS, not reasons.
# Because the groups are mutually exclusive, every respondent appears in exactly
# one of the two group facets - unlike g03, where multi-reason respondents were
# counted more than once. Both groups are measured on the SAME variable,
# days_absent_total, which is what makes them comparable (see eda-72: chronic
# days are a component of the total, never a parallel measure).

g08_panel_levels <- c("Chronic Days", "Non-Chronic Days", "Any missed days (combined)")

g08_group_data <- ds_outcome_groups %>%
  filter(outcome_group %in% c("Chronic Days", "Non-Chronic Days")) %>%
  transmute(
    panel     = as.character(outcome_group),
    days      = days_absent_total,
    day_range = factor(assign_day_range(days_absent_total), levels = day_range_levels)
  )

g08_combined_data <- ds_outcome_groups %>%
  filter(!is.na(days_absent_total), days_absent_total >= 1) %>%
  transmute(
    panel     = "Any missed days (combined)",
    days      = days_absent_total,
    day_range = factor(assign_day_range(days_absent_total), levels = day_range_levels)
  )

g08_faceted_data <- bind_rows(g08_group_data, g08_combined_data) %>%
  count(panel, days, day_range, name = "n") %>%
  mutate(panel = factor(panel, levels = g08_panel_levels))

g08_panel_counts <- bind_rows(g08_group_data, g08_combined_data) %>%
  count(panel, name = "n_panel")

facet_label_map_g08 <- setNames(
  paste0(g08_panel_counts$panel, "\nN = ", scales::comma(g08_panel_counts$n_panel)),
  g08_panel_counts$panel
)

# ---- g08 ---------------------------------------------------------------------
# Three facets: chronic, non-chronic, and the two combined

g08_outcome_group_faceted <- g08_faceted_data %>%
  ggplot(aes(x = days, y = n, fill = day_range)) +
  geom_col(width = 0.9, alpha = 0.90) +
  facet_wrap(
    ~ panel,
    nrow     = 3,
    ncol     = 1,
    scales   = "free_y",
    labeller = as_labeller(facet_label_map_g08)
  ) +
  scale_x_continuous(
    breaks = c(1, 5, 10, 15, 20, 25, 30, 40, 50, 63),
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(
    labels = scales::label_comma(),
    expand = expansion(mult = c(0, 0.05))
  ) +
  scale_fill_manual(values = day_range_colours) +
  labs(
    title    = "G08 (\u00a74.2): Days absent by outcome group \u2014 chronic, non-chronic, combined",
    subtitle = paste(
      "Same construction as G03, but facets are mutually exclusive outcome groups, so each respondent is counted exactly once.",
      "\nAll three facets measure the SAME variable, days_absent_total; y is free so each shape is readable."
    ),
    x        = "Total days absent (days_absent_total)",
    y        = "Number of respondents",
    fill     = "Day range",
    caption  = paste(
      "Group definitions follow analysis/eda-72.",
      "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample."
    )
  ) +
  theme_minimal(base_size = 10) +
  theme(
    legend.position = "bottom",
    strip.text      = element_text(size = 10, face = "bold"),
    plot.subtitle   = element_text(size = 9, lineheight = 1.2)
  ) +
  guides(fill = guide_legend(nrow = 1))

ggsave(paste0(prints_folder, "g08_outcome_group_faceted.png"),
       g08_outcome_group_faceted, width = 10, height = 9, dpi = 300)
print(g08_outcome_group_faceted)

# ---- g09-data-prep -----------------------------------------------------------
# Drop the combined facet and overlay the two groups in one panel. The groups
# differ in size by a factor of four, so the shared vertical axis is a
# WITHIN-GROUP percentage: each curve sums to 100% over its own group.

g09_data <- g08_faceted_data %>%
  filter(panel != "Any missed days (combined)") %>%
  mutate(panel = factor(as.character(panel), levels = outcome_group_levels)) %>%
  group_by(panel) %>%
  mutate(pct_within = n / sum(n) * 100) %>%
  ungroup()

g09_group_n <- g08_panel_counts %>%
  filter(panel != "Any missed days (combined)")

# ---- g09 ---------------------------------------------------------------------
# Overlay: within-group day distributions of the chronic and non-chronic groups

g09_outcome_group_overlay <- g09_data %>%
  ggplot(aes(x = days, y = pct_within, fill = panel, colour = panel)) +
  geom_col(position = "identity", width = 0.85, alpha = 0.40, linewidth = 0) +
  geom_line(linewidth = 0.7, alpha = 0.95) +
  geom_point(size = 1.1, alpha = 0.95) +
  scale_x_continuous(
    breaks = c(1, 5, 10, 15, 20, 25, 30, 40, 50, 63),
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(
    labels = scales::label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.06))
  ) +
  scale_fill_manual(values = outcome_group_colours) +
  scale_colour_manual(values = outcome_group_colours) +
  labs(
    title    = "G09 (\u00a74.2): Chronic vs non-chronic day distributions, overlaid",
    subtitle = sprintf(
      paste(
        "Within-group percentages: each curve sums to 100%% over its own group (Chronic n = %s; Non-Chronic n = %s).",
        "\nThe non-chronic group piles up at 1\u20133 days; the chronic group is flatter and carries the long right tail."
      ),
      scales::comma(g09_group_n$n_panel[g09_group_n$panel == "Chronic Days"]),
      scales::comma(g09_group_n$n_panel[g09_group_n$panel == "Non-Chronic Days"])
    ),
    x        = "Total days absent (days_absent_total)",
    y        = "Share of the group's respondents (%)",
    fill     = NULL,
    colour   = NULL,
    caption  = paste(
      "Group definitions and colours carried over unchanged from analysis/eda-72.",
      "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    panel.grid.minor = element_blank(),
    plot.subtitle    = element_text(size = 9, lineheight = 1.2)
  )

ggsave(paste0(prints_folder, "g09_outcome_group_overlay.png"),
       g09_outcome_group_overlay, width = 10, height = 5.5, dpi = 300)
print(g09_outcome_group_overlay)


# ---- SECTION: G1 Family - Reason Prevalence -----------------------------------
# Framing question: What proportion of workers missed >=1 workday for each reason?
# g1: weighted prevalence bar | g11: prevalence by survey cycle

# ---- g1-data-prep ------------------------------------------------------------
g1_data <- ds_lop_long %>%
  group_by(reason_label) %>%
  summarise(
    n_total        = n(),
    n_positive     = sum(has_days, na.rm = TRUE),
    wt_positive    = sum(.data[[weight_col]][has_days], na.rm = TRUE),
    wt_total       = sum(.data[[weight_col]],           na.rm = TRUE),
    pct_weighted   = wt_positive / wt_total * 100,
    pct_unweighted = n_positive  / n_total  * 100,
    .groups = "drop"
  ) %>%
  arrange(desc(pct_weighted)) %>%
  mutate(reason_label = forcats::fct_reorder(reason_label, pct_weighted))

# ---- g1 ----------------------------------------------------------------------
g1_lop_prevalence <- g1_data %>%
  ggplot(aes(x = pct_weighted, y = reason_label)) +
  geom_col(fill = "#2c7bb6", alpha = 0.85, width = 0.65) +
  geom_text(
    aes(label = sprintf("%.1f%%", pct_weighted)),
    hjust = -0.15,
    size  = 3.2
  ) +
  scale_x_continuous(
    labels = label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.15))
  ) +
  labs(
    title    = "G1 (\u00a74.1): Weighted prevalence of each LOP reason category",
    subtitle = "Proportion of analytical-sample respondents reporting \u22651 absent day per reason",
    x        = "Weighted % of respondents with \u22651 day absent",
    y        = NULL,
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample (n = 63,843)"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())

ggsave(paste0(prints_folder, "g1_lop_prevalence.png"),
       g1_lop_prevalence, width = 8.5, height = 5.5, dpi = 300)
print(g1_lop_prevalence)

# ---- g11 ---------------------------------------------------------------------
# Faceted: prevalence by survey cycle

g1_data_by_cycle <- ds_lop_long %>%
  group_by(reason_label, cchs_cycle_f) %>%
  summarise(
    wt_positive  = sum(.data[[weight_col]][has_days], na.rm = TRUE),
    wt_total     = sum(.data[[weight_col]],           na.rm = TRUE),
    pct_weighted = wt_positive / wt_total * 100,
    .groups = "drop"
  ) %>%
  mutate(
    reason_label = forcats::fct_reorder(reason_label, pct_weighted,
                                         .fun = mean, .desc = FALSE)
  )

g11_lop_prevalence_by_cycle <- g1_data_by_cycle %>%
  ggplot(aes(x = pct_weighted, y = reason_label, fill = cchs_cycle_f)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6, alpha = 0.85) +
  geom_text(
    aes(label = sprintf("%.1f%%", pct_weighted)),
    position = position_dodge(width = 0.7),
    hjust    = -0.1,
    size     = 2.8
  ) +
  scale_x_continuous(
    labels = label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.18))
  ) +
  scale_fill_manual(values = c("2010-2011" = "#2c7bb6", "2013-2014" = "#d7191c")) +
  labs(
    title    = "G11 (\u00a74.1): LOP reason prevalence by survey cycle",
    subtitle = "Weighted % of respondents with \u22651 absent day per reason \u2014 2010\u201311 vs 2013\u201314",
    x        = "Weighted % of respondents",
    y        = NULL,
    fill     = "Cycle"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.major.y = element_blank(),
    legend.position    = "bottom"
  )

ggsave(paste0(prints_folder, "g11_lop_prevalence_by_cycle.png"),
       g11_lop_prevalence_by_cycle, width = 8.5, height = 5.5, dpi = 300)
print(g11_lop_prevalence_by_cycle)


# ---- SECTION: G2 Family - Component Contribution ------------------------------
# Framing question: How much does each LOP reason contribute to the weighted mean?
# g2: lollipop absolute mean | g21: stacked share bar

# ---- g2-data-prep ------------------------------------------------------------
g2_data <- ds_lop_long %>%
  group_by(reason_label) %>%
  summarise(
    wt_mean_days = sum(.data[[weight_col]] * days_reason, na.rm = TRUE) /
      sum(.data[[weight_col]], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(wt_mean_days)) %>%
  mutate(
    reason_label = forcats::fct_reorder(reason_label, wt_mean_days),
    pct_of_total = wt_mean_days / sum(wt_mean_days) * 100
  )

# Overall weighted mean of days_absent_total (reference line)
total_wt_mean <- sum(ds0[[weight_col]] * ds0$days_absent_total, na.rm = TRUE) /
  sum(ds0[[weight_col]], na.rm = TRUE)

# ---- g2 ----------------------------------------------------------------------
g2_lop_contribution <- g2_data %>%
  ggplot(aes(x = wt_mean_days, y = reason_label)) +
  geom_segment(aes(xend = 0, yend = reason_label),
               colour = "grey70", linewidth = 0.6) +
  geom_point(aes(size = pct_of_total), colour = "#2c7bb6", alpha = 0.9) +
  geom_text(
    aes(label = sprintf("%.2f d  (%.0f%%)", wt_mean_days, pct_of_total)),
    hjust = -0.15,
    size  = 3.1
  ) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.35))) +
  scale_size_continuous(range = c(2, 8), guide = "none") +
  labs(
    title    = "G2 (\u00a74.1): Weighted mean days absent attributed to each LOP reason",
    subtitle = sprintf(
      "Point size \u221d share of total; reference weighted mean (days_absent_total) = %.2f days",
      total_wt_mean
    ),
    x       = "Weighted mean days absent (all respondents, including zeros)",
    y       = NULL,
    caption = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())

ggsave(paste0(prints_folder, "g2_lop_contribution.png"),
       g2_lop_contribution, width = 8.5, height = 5.5, dpi = 300)
print(g2_lop_contribution)

# ---- g21 ---------------------------------------------------------------------
# Stacked horizontal bar: relative share of each component in the total

# Preserve ordering from g2 (descending wt_mean)
g21_data <- g2_data %>%
  mutate(
    reason_ordered = forcats::fct_reorder(as.character(reason_label),
                                          pct_of_total, .desc = FALSE)
  )

g21_lop_contribution_stacked <- g21_data %>%
  ggplot(aes(x = pct_of_total, y = "Component sum", fill = reason_ordered)) +
  geom_col(width = 0.7, alpha = 0.88) +
  geom_text(
    data = filter(g21_data, pct_of_total > 4),
    aes(
      label = sprintf("%s\n%.0f%%", reason_ordered, pct_of_total)
    ),
    position   = position_stack(vjust = 0.5),
    size       = 2.8,
    colour     = "white",
    fontface   = "bold",
    lineheight = 1.0
  ) +
  scale_x_continuous(
    labels = label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.02))
  ) +
  scale_fill_brewer(palette = "Set2", direction = 1) +
  labs(
    title    = "G21 (\u00a74.1): Relative share of each LOP reason in total absent-day burden",
    subtitle = "Weighted mean days per reason as % of the 8-component sum",
    x        = "Share of total absent-day burden (%)",
    y        = NULL,
    fill     = "LOP reason",
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.y        = element_blank(),
    axis.ticks.y       = element_blank(),
    panel.grid.major.y = element_blank(),
    legend.position    = "right"
  )

ggsave(paste0(prints_folder, "g21_lop_contribution_stacked.png"),
       g21_lop_contribution_stacked, width = 10, height = 3.5, dpi = 300)
print(g21_lop_contribution_stacked)


# ---- SECTION: G3 Family - Reason Co-occurrence --------------------------------
# Framing question: How many reasons does a respondent report simultaneously?
# g3: reason-count bar | g31: pairwise co-occurrence heatmap

# ---- g3-data-prep ------------------------------------------------------------
# Per-respondent count of reason categories with ≥1 day
g3_count_data <- ds0 %>%
  select(cchs_cycle_f, !!weight_col, all_of(names(lop_components))) %>%
  mutate(
    n_reasons = rowSums(
      across(all_of(names(lop_components)), ~ !is.na(.x) & .x > 0),
      na.rm = TRUE
    )
  )

g3_dist <- g3_count_data %>%
  group_by(n_reasons) %>%
  summarise(
    n_obs = n(),
    wt_n  = sum(.data[[weight_col]], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    pct_obs = n_obs / sum(n_obs) * 100,
    pct_wt  = wt_n  / sum(wt_n)  * 100
  )

# Pairwise co-occurrence matrix (% of respondents positive on both)
lop_cols   <- names(lop_components)
lop_labels <- unname(lop_components)

positive_flags <- ds0 %>%
  select(all_of(lop_cols)) %>%
  mutate(across(everything(), ~ !is.na(.x) & .x > 0))

cooccur_mat <- matrix(
  NA_real_,
  nrow     = length(lop_cols),
  ncol     = length(lop_cols),
  dimnames = list(lop_labels, lop_labels)
)

for (i in seq_along(lop_cols)) {
  for (j in seq_along(lop_cols)) {
    cooccur_mat[i, j] <- mean(
      positive_flags[[lop_cols[i]]] & positive_flags[[lop_cols[j]]],
      na.rm = TRUE
    ) * 100
  }
}

g3_cooccur_data <- as.data.frame(cooccur_mat) %>%
  tibble::rownames_to_column("reason_row") %>%
  tidyr::pivot_longer(-reason_row, names_to = "reason_col",
                      values_to = "pct_cooccur") %>%
  mutate(
    reason_row = factor(reason_row, levels = rev(lop_labels)),
    reason_col = factor(reason_col, levels = lop_labels),
    is_diagonal = reason_row == reason_col
  )

# ---- g3 ----------------------------------------------------------------------
g3_lop_nreasons <- g3_dist %>%
  ggplot(aes(x = factor(n_reasons), y = pct_wt)) +
  geom_col(fill = "#2c7bb6", alpha = 0.85, width = 0.65) +
  geom_text(
    aes(label = sprintf("%.1f%%", pct_wt)),
    vjust = -0.35,
    size  = 3.2
  ) +
  scale_y_continuous(
    labels = label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.14))
  ) +
  labs(
    title    = "G3 (\u00a74.1): Number of LOP reason categories reported per respondent",
    subtitle = "Weighted % of respondents by count of reason categories with \u22651 absent day",
    x        = "Number of distinct LOP reason categories reported",
    y        = "Weighted % of respondents",
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.x = element_blank())

ggsave(paste0(prints_folder, "g3_lop_nreasons.png"),
       g3_lop_nreasons, width = 8.5, height = 5.5, dpi = 300)
print(g3_lop_nreasons)

# ---- g31 ---------------------------------------------------------------------
# Pairwise co-occurrence heatmap; diagonal = univariate prevalence

g31_lop_cooccurrence <- g3_cooccur_data %>%
  ggplot(aes(x = reason_col, y = reason_row, fill = pct_cooccur)) +
  geom_tile(colour = "white", linewidth = 0.5) +
  geom_text(
    aes(label = ifelse(pct_cooccur >= 0.3, sprintf("%.1f", pct_cooccur), "")),
    size = 2.8
  ) +
  scale_fill_distiller(
    palette   = "Blues",
    direction = 1,
    name      = "% respondents\n(unweighted)"
  ) +
  labs(
    title    = "G31 (\u00a74.1): Pairwise co-occurrence of LOP reason categories",
    subtitle = "Cell = % of respondents reporting \u22651 day for both reasons; diagonal = univariate prevalence",
    x        = NULL,
    y        = NULL,
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 10) +
  theme(
    axis.text.x = element_text(angle = 30, hjust = 1),
    panel.grid  = element_blank()
  )

ggsave(paste0(prints_folder, "g31_lop_cooccurrence.png"),
       g31_lop_cooccurrence, width = 8.5, height = 5.5, dpi = 300)
print(g31_lop_cooccurrence)


# ---- SECTION: G4 Family - Conditional Intensity -------------------------------
# Framing question: Among reporters of each reason, how many days did it produce?
# g4: mean + median bar (reporters only) | g41: total distribution log-scale

# ---- g4-data-prep ------------------------------------------------------------
# Restrict to respondents who reported ≥1 day for each specific reason
g4_data <- ds_lop_long %>%
  filter(has_days) %>%
  group_by(reason_label) %>%
  summarise(
    wt_mean_days = sum(.data[[weight_col]] * days_reason, na.rm = TRUE) /
      sum(.data[[weight_col]], na.rm = TRUE),
    mean_days    = mean(days_reason, na.rm = TRUE),
    median_days  = median(days_reason, na.rm = TRUE),
    n_reporters  = n(),
    .groups = "drop"
  ) %>%
  mutate(reason_label = forcats::fct_reorder(reason_label, wt_mean_days))

n_zero_total <- sum(ds0$days_absent_total == 0, na.rm = TRUE)
pct_zero_total <- n_zero_total / nrow(ds0) * 100

g41_data <- ds0 %>%
  filter(!is.na(days_absent_total), days_absent_total >= 1) %>%
  count(days_absent_total, name = "n_respondents")

# ---- g4 ----------------------------------------------------------------------
g4_conditional_intensity <- g4_data %>%
  ggplot(aes(x = wt_mean_days, y = reason_label)) +
  geom_col(fill = "#2c7bb6", alpha = 0.75, width = 0.65) +
  geom_point(aes(x = median_days), colour = "#d73027", size = 3.5, shape = 18) +
  geom_text(
    aes(
      label = sprintf("w.mean = %.1f  med = %.0f  (n = %s)",
                      wt_mean_days, median_days,
                      scales::comma(n_reporters))
    ),
    hjust = -0.04,
    size  = 2.9
  ) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.45))) +
  labs(
    title    = "G4 (\u00a74.2): Conditional intensity \u2014 days absent per reason, reporters only",
    subtitle = "Bar = weighted mean; red diamond = median. Restricted to respondents reporting \u22651 day for that reason.",
    x        = "Days absent (among reporters of that reason)",
    y        = NULL,
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())

ggsave(paste0(prints_folder, "g4_conditional_intensity.png"),
       g4_conditional_intensity, width = 8.5, height = 5.5, dpi = 300)
print(g4_conditional_intensity)

# ---- g41 ---------------------------------------------------------------------
# Distribution of days_absent_total: non-zeros, log y-scale

g41_total_distribution <- g41_data %>%
  ggplot(aes(x = days_absent_total, y = n_respondents)) +
  geom_col(fill = "#4575b4", alpha = 0.80, width = 0.85) +
  scale_y_log10(
    labels = label_comma(),
    expand = expansion(mult = c(0, 0.15))
  ) +
  scale_x_continuous(breaks = c(1, 5, 10, 15, 20, 30, 45, 63)) +
  labs(
    title    = sprintf(
      "G41 (\u00a74.2): Distribution of days_absent_total (non-zeros only, log y-scale)\n%s zeros excluded (%.1f%% of full sample)",
      scales::comma(n_zero_total), pct_zero_total
    ),
    subtitle = "One bar per integer value; log y-axis reveals the heavy right tail",
    x        = "Total absent days (days_absent_total)",
    y        = "Number of respondents (log scale)",
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

ggsave(paste0(prints_folder, "g41_total_distribution.png"),
       g41_total_distribution, width = 8.5, height = 5.5, dpi = 300)
print(g41_total_distribution)


# ---- SECTION: G5 Family - Chronic Role ----------------------------------------
# Framing question: Among absent workers, how central is the chronic component?
# g5: three-group bar (none/mixed/entirely chronic) | g51: chronic vs total bubble

# ---- g5-data-prep ------------------------------------------------------------
g5_data <- ds0 %>%
  filter(!is.na(days_absent_total), days_absent_total > 0) %>%
  mutate(
    chr   = ifelse(is.na(days_absent_chronic), 0L, days_absent_chronic),
    group = dplyr::case_when(
      chr == 0                 ~ "No chronic days\n(non-chronic absence only)",
      chr == days_absent_total ~ "Entirely chronic\n(chronic = total)",
      TRUE                     ~ "Mixed\n(some chronic + other reasons)"
    ),
    group = factor(group, levels = c(
      "No chronic days\n(non-chronic absence only)",
      "Mixed\n(some chronic + other reasons)",
      "Entirely chronic\n(chronic = total)"
    ))
  ) %>%
  group_by(group) %>%
  summarise(
    n        = n(),
    wt_n     = sum(.data[[weight_col]], na.rm = TRUE),
    .groups  = "drop"
  ) %>%
  mutate(
    pct_n  = n    / sum(n)    * 100,
    pct_wt = wt_n / sum(wt_n) * 100
  )

n_absent_total <- sum(g5_data$n)

g51_data <- ds0 %>%
  filter(
    !is.na(days_absent_total),    days_absent_total > 0,
    !is.na(days_absent_chronic),  days_absent_chronic > 0
  ) %>%
  count(days_absent_total, days_absent_chronic, name = "n_combo")

# ---- g5 ----------------------------------------------------------------------
g5_chronic_role <- g5_data %>%
  ggplot(aes(x = group, y = pct_wt, fill = group)) +
  geom_col(width = 0.6, alpha = 0.85) +
  geom_text(
    aes(label = sprintf("%.1f%%\n(n = %s)", pct_wt, scales::comma(n))),
    vjust = -0.3,
    size  = 3.5
  ) +
  scale_y_continuous(
    labels = label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.22))
  ) +
  scale_fill_manual(
    values = c(
      "No chronic days\n(non-chronic absence only)" = "#74add1",
      "Mixed\n(some chronic + other reasons)"        = "#f46d43",
      "Entirely chronic\n(chronic = total)"          = "#d73027"
    ),
    guide = "none"
  ) +
  labs(
    title    = "G5 (\u00a74.2): Role of chronic absence among workers with any absence",
    subtitle = sprintf(
      "Three-group classification among the %s respondents with days_absent_total > 0 (weighted %%)",
      scales::comma(n_absent_total)
    ),
    x        = NULL,
    y        = "Weighted % of absent respondents",
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.x = element_blank())

ggsave(paste0(prints_folder, "g5_chronic_role.png"),
       g5_chronic_role, width = 8.5, height = 5.5, dpi = 300)
print(g5_chronic_role)

# ---- g51 ---------------------------------------------------------------------
# Bubble chart: chronic days vs total days, 1:1 reference line

g51_max_axis <- max(g51_data$days_absent_total, g51_data$days_absent_chronic)

g51_chronic_vs_total <- g51_data %>%
  ggplot(aes(x = days_absent_total, y = days_absent_chronic, size = n_combo)) +
  geom_abline(slope = 1, intercept = 0, colour = "grey50", linetype = "dashed",
              linewidth = 0.7) +
  geom_point(alpha = 0.55, colour = "#4575b4") +
  scale_size_continuous(
    name   = "# respondents\nat combination",
    range  = c(1, 12),
    labels = label_comma()
  ) +
  scale_x_continuous(breaks = c(1, 5, 10, 20, 30, 60)) +
  scale_y_continuous(breaks = c(1, 5, 10, 20, 30)) +
  coord_fixed(
    xlim = c(0, g51_max_axis),
    ylim = c(0, g51_max_axis)
  ) +
  annotate(
    "text",
    x      = g51_max_axis * 0.60,
    y      = g51_max_axis * 0.68,
    label  = "chronic = total\n(1:1 line)",
    colour = "grey40",
    size   = 3.2,
    hjust  = 0
  ) +
  labs(
    title    = "G51 (\u00a74.2): Chronic days vs. total days absent \u2014 bubble chart (both > 0)",
    subtitle = "Points on 1:1 line: all absence is chronic. Points below: chronic + other reasons combined.",
    x        = "Total absent days (days_absent_total)",
    y        = "Chronic-condition absent days (days_absent_chronic)",
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 11)

ggsave(paste0(prints_folder, "g51_chronic_vs_total.png"),
       g51_chronic_vs_total, width = 7.0, height = 7.0, dpi = 300)
print(g51_chronic_vs_total)


# ---- SECTION: G6 Family - Data Quality ----------------------------------------
# Framing question: Are all 8 LOP components complete and zeros preserved?
# g6: zero vs positive stacked bar | g61: population mean lollipop | g62: completeness

# ---- g6-data-prep ------------------------------------------------------------
# Per-component: count of zeros, positives, and missing (should be 0 after exclusion)

g6_long <- ds0 %>%
  select(all_of(names(lop_components)), !!weight_col) %>%
  tidyr::pivot_longer(
    cols      = all_of(names(lop_components)),
    names_to  = "lop_col",
    values_to = "days"
  ) %>%
  mutate(
    reason_label = factor(lop_components[lop_col], levels = lop_components),
    status = dplyr::case_when(
      is.na(days) ~ "Missing (NA)",
      days == 0   ~ "Zero days",
      TRUE        ~ "\u22651 day absent"
    ),
    status = factor(status, levels = c("\u22651 day absent", "Zero days", "Missing (NA)"))
  )

g6_data <- g6_long %>%
  group_by(reason_label, status) %>%
  summarise(
    n    = n(),
    wt_n = sum(.data[[weight_col]], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(reason_label) %>%
  mutate(
    pct_n  = n    / sum(n)    * 100,
    pct_wt = wt_n / sum(wt_n) * 100
  ) %>%
  ungroup() %>%
  # Order reasons by descending % positive
  mutate(
    reason_label = forcats::fct_reorder(
      reason_label,
      ifelse(status == "\u22651 day absent", pct_n, NA_real_),
      .fun  = function(x) max(x, na.rm = TRUE),
      .desc = FALSE
    )
  )

# Weighted mean raw days per component (across all respondents, including zeros)
g61_data <- ds_lop_long %>%
  group_by(reason_label) %>%
  summarise(
    wt_mean_raw = sum(.data[[weight_col]] * days_reason, na.rm = TRUE) /
      sum(.data[[weight_col]], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(reason_label = forcats::fct_reorder(reason_label, wt_mean_raw))

# ---- g6 ----------------------------------------------------------------------
g6_lop_availability <- g6_data %>%
  ggplot(aes(x = pct_n, y = reason_label, fill = status)) +
  geom_col(width = 0.70, alpha = 0.88) +
  geom_text(
    data = filter(g6_data, status == "\u22651 day absent"),
    aes(label = sprintf("%.1f%%", pct_n), x = pct_n / 2),
    colour   = "white",
    fontface = "bold",
    size     = 3.2
  ) +
  scale_x_continuous(
    labels = scales::label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.02))
  ) +
  scale_fill_manual(
    values = c(
      "\u22651 day absent" = "#d73027",
      "Zero days"          = "#4575b4",
      "Missing (NA)"       = "#969696"
    )
  ) +
  labs(
    title    = "G6 (\u00a74.1 data quality): LOP component availability in the analytical sample",
    subtitle = "Zero is preserved as a valid response; 0 missing values confirm 405-row element-wise exclusion was resolved upstream",
    x        = "Share of respondents (%)",
    y        = NULL,
    fill     = NULL,
    caption  = "Source: CCHS analytical sample (n = 63,843); 405 rows with any missing LOP value excluded at Ellis step 4"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.major.y = element_blank(),
    legend.position    = "bottom"
  )

ggsave(paste0(prints_folder, "g6_lop_availability.png"),
       g6_lop_availability, width = 8.5, height = 5.5, dpi = 300)
print(g6_lop_availability)

# ---- g61 ---------------------------------------------------------------------
# Lollipop: weighted mean raw days per LOP component (population average)

g61_lop_mean_raw <- g61_data %>%
  ggplot(aes(x = wt_mean_raw, y = reason_label)) +
  geom_segment(aes(xend = 0, yend = reason_label),
               colour = "grey70", linewidth = 0.6) +
  geom_point(colour = "#2c7bb6", size = 3.5, alpha = 0.9) +
  geom_text(
    aes(label = sprintf("%.3f d", wt_mean_raw)),
    hjust = -0.2,
    size  = 3.1
  ) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.30))) +
  labs(
    title    = "G61 (\u00a74.1): Weighted mean raw days per LOP component (population-level average)",
    subtitle = "Numerator includes zeros; shows the unconditional contribution of each reason to population absenteeism",
    x        = "Weighted mean days absent (all respondents, including zeros)",
    y        = NULL,
    caption  = "Source: CCHS 2010\u201311 & 2013\u201314 pooled analytical sample"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank())

ggsave(paste0(prints_folder, "g61_lop_mean_raw.png"),
       g61_lop_mean_raw, width = 8.5, height = 5.5, dpi = 300)
print(g61_lop_mean_raw)

# ---- g62 ---------------------------------------------------------------------
# Per-component: percent of respondents with a non-missing, non-zero response
# Color-mapped to % non-missing (completeness gradient) per Marc-André feedback
# (2026-05-15: "colors should probably be remapped to percent non-missing")

g62_data <- g6_long %>%
  group_by(reason_label) %>%
  summarise(
    n_total      = n(),
    n_missing    = sum(status == "Missing (NA)"),
    n_nonmissing = n_total - n_missing,
    pct_complete = n_nonmissing / n_total * 100,
    n_positive   = sum(status == "\u22651 day absent"),
    pct_positive = n_positive / n_total * 100,
    .groups = "drop"
  ) %>%
  mutate(reason_label = forcats::fct_reorder(reason_label, pct_positive))

g62_completeness <- g62_data %>%
  ggplot(aes(x = pct_positive, y = reason_label, fill = pct_complete)) +
  geom_col(width = 0.65, alpha = 0.9) +
  geom_text(aes(label = sprintf("%.1f%% reported\n(%.0f%% complete)",
                                pct_positive, pct_complete)),
            hjust = -0.05, size = 2.8, lineheight = 0.9) +
  scale_x_continuous(
    expand = expansion(mult = c(0, 0.35)),
    labels = scales::label_percent(scale = 1)
  ) +
  scale_fill_gradient(
    low  = "#fee0d2",
    high = "#2ca02c",
    name = "% Non-Missing\n(completeness)",
    limits = c(95, 100)
  ) +
  labs(
    title    = "G62: LOP Component Reporting Rate — Colour = Data Completeness",
    subtitle = "Bar length = % of respondents reporting \u22651 day absent; fill intensity = % non-missing",
    x        = "% of Respondents Reporting \u22651 Absent Day",
    y        = NULL,
    caption  = "Source: CCHS analytical sample (n = 63,843). All components 100% complete post-exclusion."
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.major.y = element_blank(),
    legend.position    = "right"
  )
print(g62_completeness)
ggsave(paste0(prints_folder, "g62_completeness.png"),
       g62_completeness, width = 9, height = 5.5, dpi = 300)

# nolint end
