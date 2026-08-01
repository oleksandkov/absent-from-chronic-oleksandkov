# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# EDA-72: Outcome groups and the days_absent scale.
# Theme 1 (g1): the three mutually exclusive outcome groups and the rescaling of
#   days_absent, the numeric outcome. Chronic days are a subset of days_absent,
#   not a parallel measure.
# Theme 2 (g2): an illustration of how a set of variables -- here the project's
#   predisposing domain -- can be evaluated against those three groups.
# g3 is a reference profile of the No Days group, kept for lookup, not argument.
rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014") # Clear the console
cat("Working directory: ", getwd()) # Must be set to Project Directory

# ---- load-packages -----------------------------------------------------------
library(magrittr)
library(ggplot2)
library(dplyr)
library(tidyr)
library(forcats)
library(purrr)
library(scales)
library(fs)
requireNamespace("arrow", quietly = TRUE)

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R")
base::source("./scripts/graphing/graph-presets.R")

# ---- declare-globals ---------------------------------------------------------
local_root <- "./analysis/eda-72/"
local_data <- paste0(local_root, "data-local/")
prints_folder <- paste0(local_root, "prints/")
data_private_derived <- "./data-private/derived/eda-72/"
path_parquet <- "./data-private/derived/cchs-2-tables/cchs_analytic.parquet"
weight_col <- "wts_m_pooled"
a4_landscape_width <- 11.69
a4_landscape_height <- 8.27

if (!fs::dir_exists(local_data)) { fs::dir_create(local_data) }
if (!fs::dir_exists(prints_folder)) { fs::dir_create(prints_folder) }
if (!fs::dir_exists(data_private_derived)) {
  fs::dir_create(data_private_derived, recurse = TRUE)
}

predisposition_specs <- tibble::tribble(
  ~variable, ~variable_label,
  "age_group_3", "Age group",
  "dhhgage", "Age (5-year group)",
  "sex", "Sex",
  "marital_status", "Marital status",
  "household_size", "Household size",
  "dhhgle5", "Children age 0-5",
  "dhhg611", "Children age 6-11",
  "education", "Education",
  "immigration_status", "Immigration status",
  "visible_minority", "Visible minority",
  "living_arrangements", "Living arrangements"
)

outcome_group_levels <- c("No Days", "Chronic Days", "Non-Chronic Days")
comparison_group_levels <- c("No Days", "Chronic Days")
comparison_group_colours <- c(
  "No Days" = abcol[["grey"]],
  "Chronic Days" = abcol[["brown"]],
  "Non-Chronic Days" = abcol[["blue"]]
)

# Outcome-group palette carried over from EDA-71 graph g2. Every sequential ramp
# in this report is anchored to it: displays of days_absent (the whole measure)
# take the bluish Non-Chronic hue, displays of chronic days take the reddish
# Chronic hue. Colour therefore signals which slice of the outcome is on screen.
outcome_group_colours <- c(
  "No Days" = "#D9D9D9",
  "Chronic Days" = "#D08C60",
  "Non-Chronic Days" = "#0B4F6C"
)
days_absent_ramp <- grDevices::colorRampPalette(c("#DCEAF1", "#3E7F9B", "#0B4F6C"))
chronic_days_ramp <- grDevices::colorRampPalette(c("#FBE7D6", "#D08C60", "#8C4A1E"))

# Observed support of the two day counts (CACHE-manifest: total 0-63, chronic 0-31).
days_absent_max <- 63L
chronic_days_max <- 31L

dhhgage_labels <- c(
  "2" = "15-17 yrs", "3" = "18-19 yrs", "4" = "20-24 yrs",
  "5" = "25-29 yrs", "6" = "30-34 yrs", "7" = "35-39 yrs",
  "8" = "40-44 yrs", "9" = "45-49 yrs", "10" = "50-54 yrs",
  "11" = "55-59 yrs", "12" = "60-64 yrs", "13" = "65-69 yrs",
  "14" = "70-74 yrs", "15" = "75-79 yrs"
)

# ---- declare-functions -------------------------------------------------------
make_predictor_long <- function(data, specifications) {
  purrr::map2_dfr(
    specifications$variable,
    specifications$variable_label,
    function(variable_name, display_name) {
      source_value <- data[[variable_name]]
      if (identical(variable_name, "dhhgage")) {
        value_levels <- names(dhhgage_labels)
        level_value <- factor(
          dhhgage_labels[as.character(source_value)],
          levels = unname(dhhgage_labels[value_levels])
        )
      } else {
        value_levels <- if (is.factor(source_value)) {
          levels(source_value)
        } else {
          sort(unique(stats::na.omit(source_value))) |> as.character()
        }
        level_value <- factor(as.character(source_value), levels = value_levels)
      }

      tibble::tibble(
        respondent_id = data$.respondent_id,
        outcome_group = data$outcome_group,
        weight_value = data$weight_value,
        days_absent_chronic = data$days_absent_chronic,
        variable = variable_name,
        variable_label = display_name,
        level = level_value
      )
    }
  )
}

add_facet_level <- function(data) {
  ordered_levels <- data %>%
    distinct(variable_label, level) %>%
    mutate(facet_level = paste(variable_label, level, sep = "___")) %>%
    pull(facet_level)

  data %>%
    mutate(
      facet_level = factor(
        paste(variable_label, level, sep = "___"),
        levels = rev(unique(ordered_levels))
      )
    )
}

strip_facet_level <- function(value) sub("^.*___", "", value)

weighted_mean <- function(value, weight) {
  stats::weighted.mean(value, weight, na.rm = TRUE)
}

# --- Day-scale coarsening rules -----------------------------------------------
# These helpers are deliberately measure-agnostic. They take a count of days
# absent and return the bin it falls into. The same rules apply to
# days_absent_total and to days_absent_chronic; only the upper bound differs.
work_week_index <- function(days) as.integer(ceiling(days / 5))

hybrid_bin_index <- function(days) {
  dplyr::if_else(
    days <= 5,
    as.integer(days),
    5L + as.integer(ceiling((days - 5) / 5))
  )
}

week_bin_label <- function(week_index, max_days) {
  lower <- (week_index - 1L) * 5L + 1L
  upper <- pmin(week_index * 5L, max_days)
  dplyr::if_else(lower == upper, as.character(lower), paste0(lower, "-", upper))
}

hybrid_bin_label <- function(days, max_days) {
  dplyr::if_else(
    days <= 5,
    as.character(days),
    week_bin_label(hybrid_bin_index(days) - 4L, max_days)
  )
}

make_scale_mapping <- function(max_days) {
  tidyr::crossing(
    days_absent = seq_len(max_days),
    scale = factor(
      c("Exact reported days", "Five-day work weeks", "First week exact; tail coarsened"),
      levels = c("Exact reported days", "First week exact; tail coarsened", "Five-day work weeks")
    )
  ) %>%
    mutate(
      bin_index = case_when(
        scale == "Exact reported days" ~ as.integer(days_absent),
        scale == "Five-day work weeks" ~ work_week_index(days_absent),
        TRUE ~ hybrid_bin_index(days_absent)
      ),
      bin_label = case_when(
        scale == "Exact reported days" ~ as.character(days_absent),
        scale == "Five-day work weeks" ~ paste0(
          work_week_index(days_absent),
          if_else(work_week_index(days_absent) == 1L, " week", " weeks")
        ),
        TRUE ~ hybrid_bin_label(days_absent, max_days)
      ),
      band = factor(bin_index %% 2)
    )
}

# Attach both coarsened scales to a per-day frequency table.
add_day_scales <- function(data, day_column, max_days) {
  week_levels <- unique(week_bin_label(work_week_index(seq_len(max_days)), max_days))
  hybrid_levels <- unique(hybrid_bin_label(seq_len(max_days), max_days))

  data %>%
    mutate(
      day_value = as.integer(.data[[day_column]]),
      exact_day = factor(day_value, levels = seq_len(max_days)),
      work_week = work_week_index(day_value),
      work_week_label = factor(week_bin_label(work_week, max_days), levels = week_levels),
      hybrid_index = hybrid_bin_index(day_value),
      hybrid_label = factor(hybrid_bin_label(day_value, max_days), levels = hybrid_levels)
    )
}

# The outcome-group partition panel. It is the visual anchor of this report and
# is reproduced unchanged at the left of every graph in family g1.
build_partition_panel <- function(partition_data, artifact_id) {
  partition_data %>%
    ggplot(aes(x = "Analytic sample", y = pct_raw, fill = outcome_group)) +
    geom_col(width = 0.48, colour = "white", linewidth = 0.3) +
    geom_text(
      aes(label = paste0(scales::comma(n_raw), "\n", sprintf("%.1f%%", pct_raw))),
      position = position_stack(vjust = 0.5), size = 2.8, lineheight = 0.95
    ) +
    scale_fill_manual(values = outcome_group_colours, guide = "none") +
    scale_y_continuous(
      labels = scales::label_percent(scale = 1), limits = c(0, 100),
      expand = expansion(mult = c(0, 0))
    ) +
    labs(
      title = paste0("Graph ", artifact_id, ": Outcome groups"),
      subtitle = "No Days / Chronic / Non-Chronic",
      x = NULL,
      y = "Share of sample"
    ) +
    theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(size = 10),
      plot.subtitle = element_text(size = 9),
      axis.text.x = element_blank(), panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank(), plot.margin = margin(5.5, 0, 5.5, 5.5)
    )
}

# Split a hybrid-binned frequency table into the two display panels used by g12
# and g121: exact days 1-5 on the left, work-week numbers 2 and up on the right.
hybrid_panel_frame <- function(data) {
  data %>%
    mutate(
      scale_panel = factor(
        if_else(hybrid_index <= 5L, "A Week or Less", "More than a Week"),
        levels = c("A Week or Less", "More than a Week")
      ),
      bin_label = factor(
        if_else(
          hybrid_index <= 5L,
          as.character(hybrid_index),
          as.character(hybrid_index - 4L)
        ),
        levels = as.character(seq_len(work_week_index(days_absent_max)))
      )
    )
}

# Build the four-panel scale composite used by g11 and g111: the outcome-group
# partition at left, and the same day count at the exact, five-day, and hybrid
# scales stacked at right. Both artifacts share this construction so that the
# whole measure and its chronic component can be read against each other.
build_day_scale_composite <- function(exact_data, partition_data, artifact_id,
                                      basis_label, day_axis_label, ramp, max_days) {
  week_levels <- levels(exact_data$work_week_label)
  exact_colours <- stats::setNames(ramp(max_days), as.character(seq_len(max_days)))
  week_colours <- stats::setNames(ramp(length(week_levels)), week_levels)

  weekly_data <- exact_data %>%
    group_by(work_week, work_week_label) %>%
    summarise(n_raw = sum(n_raw), .groups = "drop")

  hybrid_data <- exact_data %>%
    group_by(hybrid_index, hybrid_label, work_week_label) %>%
    summarise(n_raw = sum(n_raw), .groups = "drop")

  left_panel <- build_partition_panel(partition_data, artifact_id)

  top_panel <- exact_data %>%
    ggplot(aes(x = day_value, y = n_raw, fill = exact_day)) +
    geom_col(width = 0.9) +
    scale_fill_manual(values = exact_colours, guide = "none") +
    scale_x_continuous(
      breaks = unique(c(1, seq(5, max_days - 3, 5), max_days)),
      limits = c(0.5, max_days + 0.5)
    ) +
    scale_y_continuous(labels = scales::label_comma(), expand = expansion(mult = c(0, 0.08))) +
    labs(
      title = paste0("Graph ", artifact_id, ": Exact reported days"),
      subtitle = paste0(basis_label, "; one-day bars from 1 to ", max_days),
      x = day_axis_label, y = "Respondent count"
    ) +
    theme_minimal(base_size = 8) +
    theme(
      panel.grid.major.x = element_blank(), panel.grid.minor = element_blank(),
      plot.margin = margin(5.5, 5.5, 1, 6)
    )

  middle_panel <- weekly_data %>%
    ggplot(aes(x = work_week_label, y = n_raw, fill = work_week_label)) +
    geom_col(width = 0.78) +
    geom_text(aes(label = scales::comma(n_raw)), vjust = -0.3, size = 2.2) +
    scale_fill_manual(values = week_colours, guide = "none") +
    scale_y_continuous(labels = scales::label_comma(), expand = expansion(mult = c(0, 0.14))) +
    labs(
      title = paste0("Graph ", artifact_id, ": Five-day work-week bins"),
      subtitle = paste0(basis_label, "; bins: 1-5, 6-10, ..., ", dplyr::last(week_levels), " days"),
      x = NULL, y = "Respondent count"
    ) +
    theme_minimal(base_size = 8) +
    theme(
      panel.grid.major.x = element_blank(), panel.grid.minor = element_blank(),
      axis.text.x = element_text(size = 6.5, angle = 30, hjust = 1),
      plot.margin = margin(1, 5.5, 1, 6)
    )

  bottom_panel <- hybrid_data %>%
    ggplot(aes(x = hybrid_label, y = n_raw, fill = work_week_label)) +
    geom_col(width = 0.78) +
    scale_fill_manual(values = week_colours, guide = "none") +
    scale_y_continuous(labels = scales::label_comma(), expand = expansion(mult = c(0, 0.08))) +
    labs(
      title = paste0("Graph ", artifact_id, ": First week exact; tail coarsened"),
      subtitle = paste0(
        basis_label,
        "; days 1-5 exact, tail binned. Fill marks the five-day band each bar belongs to."
      ),
      x = NULL, y = "Respondent count"
    ) +
    theme_minimal(base_size = 8) +
    theme(
      panel.grid.major.x = element_blank(), panel.grid.minor = element_blank(),
      axis.text.x = element_text(size = 6.5, angle = 30, hjust = 1),
      plot.margin = margin(1, 5.5, 5.5, 6)
    )

  grid::grid.grabExpr({
    grid::grid.newpage()
    grid::pushViewport(
      grid::viewport(
        layout = grid::grid.layout(
          nrow = 3, ncol = 2,
          heights = grid::unit(c(1 / 3, 1 / 3, 1 / 3), "npc"),
          widths = grid::unit(c(0.22, 0.78), "npc")
        )
      )
    )
    grid::pushViewport(grid::viewport(layout.pos.row = 1:3, layout.pos.col = 1))
    grid::grid.draw(ggplot2::ggplotGrob(left_panel))
    grid::upViewport()
    grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
    grid::grid.draw(ggplot2::ggplotGrob(top_panel))
    grid::upViewport()
    grid::pushViewport(grid::viewport(layout.pos.row = 2, layout.pos.col = 2))
    grid::grid.draw(ggplot2::ggplotGrob(middle_panel))
    grid::upViewport()
    grid::pushViewport(grid::viewport(layout.pos.row = 3, layout.pos.col = 2))
    grid::grid.draw(ggplot2::ggplotGrob(bottom_panel))
    grid::upViewport(2)
  }, wrap.grobs = TRUE)
}

compose_two_panel_grob <- function(left_plot, right_plot, left_width = 0.22, right_width = 0.78) {
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

# ---- load-data ---------------------------------------------------------------
ds0 <- arrow::read_parquet(path_parquet) %>%
  mutate(
    .respondent_id = dplyr::row_number(),
    outcome_group = case_when(
      days_absent_total == 0 ~ "No Days",
      days_absent_chronic > 0 ~ "Chronic Days",
      days_absent_chronic == 0 & days_absent_total > 0 ~ "Non-Chronic Days",
      TRUE ~ NA_character_
    ),
    outcome_group = factor(outcome_group, levels = outcome_group_levels),
    weight_value = .data[[weight_col]],
    days_absent_total = as.integer(days_absent_total),
    days_absent_chronic = as.integer(days_absent_chronic)
  )

missing_predictors <- setdiff(predisposition_specs$variable, names(ds0))
if (length(missing_predictors) > 0) {
  stop("Missing predisposing variables: ", paste(missing_predictors, collapse = ", "))
}

predictor_long <- make_predictor_long(ds0, predisposition_specs)

# ---- tweak-data-0 ------------------------------------------------------------
outcome_group_summary <- ds0 %>%
  filter(!is.na(outcome_group)) %>%
  count(outcome_group, name = "n_raw") %>%
  mutate(expected_n = c(45006L, 3626L, 15211L))

stopifnot(all(outcome_group_summary$n_raw == outcome_group_summary$expected_n))
stopifnot(max(ds0$days_absent_total, na.rm = TRUE) == days_absent_max)
stopifnot(max(ds0$days_absent_chronic, na.rm = TRUE) == chronic_days_max)
# Chronic days can never exceed total days absent: the subset relation must hold.
stopifnot(all(ds0$days_absent_chronic <= ds0$days_absent_total, na.rm = TRUE))

n_no_days <- outcome_group_summary %>% filter(outcome_group == "No Days") %>% pull(n_raw)
n_chronic_days <- outcome_group_summary %>% filter(outcome_group == "Chronic Days") %>% pull(n_raw)
n_non_chronic_days <- outcome_group_summary %>% filter(outcome_group == "Non-Chronic Days") %>% pull(n_raw)
n_any_days <- n_chronic_days + n_non_chronic_days
stopifnot(n_any_days == sum(ds0$days_absent_total > 0, na.rm = TRUE))

group_definition_short <- paste0(
  "No Days: n = ", scales::comma(n_no_days),
  "; Chronic: >=1 chronic day (n = ", scales::comma(n_chronic_days),
  "); Non-Chronic: >0 missed days and 0 chronic days (n = ", scales::comma(n_non_chronic_days), ")."
)

# ---- inspect-data-0 ----------------------------------------------------------
cat("Analytical rows:", scales::comma(nrow(ds0)), "\n")
print(outcome_group_summary %>% select(-expected_n))

# ---- inspect-data-1 ----------------------------------------------------------
cat("Predisposition variables used in the graph family g2 illustration:\n")
print(predisposition_specs)

# ---- data-context-tables -----------------------------------------------------
cat("This analysis uses cchs_analytic.parquet at one row per CCHS respondent.\n")
cat("Outcome measure: days_absent_total, workdays missed for any health reason\n")
cat("in the past three months, support 0-63.\n")
cat("Subset measure: days_absent_chronic, the portion of those days attributed to\n")
cat("a chronic condition, support 0-31. It is a component of days_absent_total.\n")
cat("Grouping: outcome_group, derived from the two measures above.\n")
cat("Illustration variables: 11 non-student predisposing fields.\n")
cat("Weight: wts_m_pooled.\n")

# ---- data-context-person -----------------------------------------------------
example_rows <- bind_rows(
  ds0 %>% filter(outcome_group == "No Days") %>% slice(1),
  ds0 %>% filter(outcome_group == "Chronic Days") %>% slice(1)
) %>%
  select(
    .respondent_id, outcome_group, days_absent_total, days_absent_chronic,
    all_of(predisposition_specs$variable)
  )
print(example_rows)

# ---- data-context-distributions ---------------------------------------------
print(outcome_group_summary %>% select(outcome_group, n_raw))
print(
  predictor_long %>%
    group_by(variable_label) %>%
    summarise(
      n_valid = sum(!is.na(level)),
      n_missing = sum(is.na(level)),
      .groups = "drop"
    )
)

# ---- SECTION: Outputs --------------------------------------------------------
# Raw text checks that establish the respondent-level grain.

# ---- out1 --------------------------------------------------------------------
cat("Output out1: Respondent grain proof\n")
cat("Rows:", nrow(ds0), " Unique generated row IDs:", n_distinct(ds0$.respondent_id), "\n")
stopifnot(nrow(ds0) == n_distinct(ds0$.respondent_id))

# ---- SECTION: Graph Family g1 ------------------------------------------------
# THEME 1 and THEME 2 of this report.
#
# The three outcome groups are exhaustive and mutually exclusive:
#   No Days           days_absent_total == 0
#   Chronic Days      days_absent_chronic > 0
#   Non-Chronic Days  days_absent_chronic == 0 & days_absent_total > 0
#
# Every graph in this family carries that partition on the left. The panels at
# right show the numeric outcome, days_absent_total, at the exact and coarsened
# scales. Chronic days are a component of days_absent_total, not a parallel
# measure, so chronic-day displays appear as explicitly labelled subsets and
# carry the reddish Chronic hue; whole-measure displays carry the bluish hue.

# ---- g1-data-prep ------------------------------------------------------------
# The coarsening rules are applied to the full days_absent support, 1 to 63.
g1_scale_mapping <- make_scale_mapping(days_absent_max)

# Labels are drawn only on the two coarsened rows; the exact row is read off the
# x axis, which stays legible where 63 in-tile labels would not.
g1_scale_labels <- g1_scale_mapping %>%
  filter(scale != "Exact reported days") %>%
  group_by(scale, bin_index, bin_label) %>%
  summarise(label_x = mean(days_absent), .groups = "drop")

# ---- g1 ----------------------------------------------------------------------
g1_coarsening_map <- g1_scale_mapping %>%
  ggplot(aes(x = days_absent, y = scale, fill = band)) +
  geom_tile(colour = "white", linewidth = 0.2, height = 0.78) +
  geom_text(
    data = g1_scale_labels,
    aes(x = label_x, y = scale, label = bin_label),
    inherit.aes = FALSE,
    size = 2.0
  ) +
  geom_vline(
    xintercept = chronic_days_max + 0.5,
    colour = outcome_group_colours[["Chronic Days"]],
    linewidth = 0.7,
    linetype = "dashed"
  ) +
  scale_fill_manual(values = c("0" = "#DCEAF1", "1" = "#FCE2CF"), guide = "none") +
  scale_x_continuous(
    breaks = c(1, seq(5, 60, 5), days_absent_max),
    expand = expansion(add = 0.5)
  ) +
  labs(
    title = "Graph g1: Mapping Exact Days Absent to Coarser Work-Week Scales",
    subtitle = paste0(
      "days_absent_total runs 1 to ", days_absent_max,
      " among respondents who missed any work. Five reported workdays are treated as one display week;\n",
      "this is a coarsening rule, not elapsed time. The dashed rule marks day ", chronic_days_max,
      ", the ceiling of the chronic-day component."
    ),
    x = "Exact reported days absent",
    y = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(
    panel.grid = element_blank(),
    axis.text.y = element_text(face = "bold"),
    axis.text.x = element_text(size = 7),
    plot.title.position = "plot"
  )

print(g1_coarsening_map)
ggsave(
  paste0(prints_folder, "g1_days_absent_coarsening_map.png"),
  g1_coarsening_map, width = 11.69, height = 4.6, dpi = 300
)

# ---- g11-data-prep -----------------------------------------------------------
# Extend the EDA-71 G22 composition: the unchanged three-way respondent partition
# sits at left, while the distribution of days_absent_total among every
# respondent who missed at least one day is shown at three scales. The bluish
# ramp signals that this is the whole outcome measure, not the chronic subset.
g11_partition_summary <- ds0 %>%
  filter(!is.na(outcome_group)) %>%
  count(outcome_group, name = "n_raw") %>%
  mutate(
    pct_raw = n_raw / sum(n_raw) * 100,
    outcome_group = factor(outcome_group, levels = outcome_group_levels)
  )

g11_days_absent_exact <- ds0 %>%
  filter(days_absent_total > 0) %>%
  count(days_absent_total, name = "n_raw") %>%
  tidyr::complete(days_absent_total = 1:days_absent_max, fill = list(n_raw = 0L)) %>%
  add_day_scales("days_absent_total", days_absent_max)

stopifnot(sum(g11_days_absent_exact$n_raw) == n_any_days)

g11_basis_label <- paste0(
  "All respondents with >0 days absent (Chronic + Non-Chronic), n = ",
  scales::comma(n_any_days)
)

# ---- g11 ---------------------------------------------------------------------
g11_days_absent_scales <- build_day_scale_composite(
  exact_data = g11_days_absent_exact,
  partition_data = g11_partition_summary,
  artifact_id = "g11",
  basis_label = g11_basis_label,
  day_axis_label = "Days absent (days_absent_total)",
  ramp = days_absent_ramp,
  max_days = days_absent_max
)

grid::grid.draw(g11_days_absent_scales)
ggsave(
  paste0(prints_folder, "g11_days_absent_scales.png"),
  g11_days_absent_scales, width = a4_landscape_width, height = a4_landscape_height, dpi = 300
)

# ---- g111-data-prep ----------------------------------------------------------
# The same construction restricted to the chronic component. Read against g11,
# it shows that chronic days are one slice of days_absent: a shorter support
# (1 to 31) held by a smaller group.
g111_chronic_exact <- ds0 %>%
  filter(outcome_group == "Chronic Days") %>%
  count(days_absent_chronic, name = "n_raw") %>%
  tidyr::complete(days_absent_chronic = 1:chronic_days_max, fill = list(n_raw = 0L)) %>%
  add_day_scales("days_absent_chronic", chronic_days_max)

stopifnot(sum(g111_chronic_exact$n_raw) == n_chronic_days)

g111_basis_label <- paste0(
  "Chronic Days group only (>=1 chronic day), n = ", scales::comma(n_chronic_days)
)

# ---- g111 --------------------------------------------------------------------
g111_chronic_day_scales <- build_day_scale_composite(
  exact_data = g111_chronic_exact,
  partition_data = g11_partition_summary,
  artifact_id = "g111",
  basis_label = g111_basis_label,
  day_axis_label = "Chronic days (days_absent_chronic)",
  ramp = chronic_days_ramp,
  max_days = chronic_days_max
)

grid::grid.draw(g111_chronic_day_scales)
ggsave(
  paste0(prints_folder, "g111_chronic_day_scales.png"),
  g111_chronic_day_scales, width = a4_landscape_width, height = a4_landscape_height, dpi = 300
)

# ---- g12-data-prep -----------------------------------------------------------
# Both positive-day groups placed on the SAME measure, days_absent_total. An
# earlier version of this graph mixed measures -- chronic days for one group,
# total days for the other -- and labelled both "missed days". Bar colour is the
# group colour carried over from the partition panel at left.
g12_partition_summary <- g11_partition_summary

hybrid_index_max <- hybrid_bin_index(days_absent_max)

g12_hybrid_distribution <- ds0 %>%
  filter(days_absent_total > 0) %>%
  transmute(
    outcome_group = factor(
      as.character(outcome_group),
      levels = c("Chronic Days", "Non-Chronic Days")
    ),
    hybrid_index = hybrid_bin_index(days_absent_total)
  ) %>%
  count(outcome_group, hybrid_index, name = "n_raw") %>%
  tidyr::complete(
    outcome_group,
    hybrid_index = seq_len(hybrid_index_max),
    fill = list(n_raw = 0L)
  ) %>%
  hybrid_panel_frame()

stopifnot(sum(g12_hybrid_distribution$n_raw) == n_any_days)

# ---- g12 ---------------------------------------------------------------------
g12_left_partition <- build_partition_panel(g12_partition_summary, "g12")

g12_right_hybrid_distribution <- g12_hybrid_distribution %>%
  ggplot(aes(x = bin_label, y = n_raw, fill = outcome_group)) +
  geom_col(width = 0.82) +
  facet_grid(
    outcome_group ~ scale_panel,
    scales = "free",
    space = "free_x"
  ) +
  scale_fill_manual(values = outcome_group_colours, guide = "none") +
  scale_y_continuous(labels = scales::label_comma(), expand = expansion(mult = c(0, 0.08))) +
  labs(
    title = "Graph g12: Days Absent by Outcome Group, Hybrid Scale",
    subtitle = paste0(
      "Both rows show the same measure, days_absent_total.\n",
      "Chronic = >=1 chronic day (n = ", scales::comma(n_chronic_days),
      "); Non-Chronic = >0 days absent and 0 chronic days (n = ",
      scales::comma(n_non_chronic_days), ").\n",
      "Days 1-5 stay exact; the tail is grouped into five-day work weeks. Row scales are free."
    ),
    x = "Exact day within week 1, or work-week number",
    y = "Respondent count"
  ) +
  theme_minimal(base_size = 10) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold"),
    axis.text.x = element_text(size = 7),
    plot.title.position = "plot"
  )

g12_group_hybrid_distribution <- compose_two_panel_grob(
  g12_left_partition,
  g12_right_hybrid_distribution,
  left_width = 0.22,
  right_width = 0.78
)

grid::grid.draw(g12_group_hybrid_distribution)
ggsave(
  paste0(prints_folder, "g12_group_hybrid_distribution.png"),
  g12_group_hybrid_distribution,
  width = a4_landscape_width, height = a4_landscape_height, dpi = 300
)

# ---- g121-data-prep ----------------------------------------------------------
# The subset relation on one set of people. Within the Chronic Days group, the
# same respondents are counted twice: once by all days absent, once by the
# chronic component of those days. The chronic bars can never sit to the right
# of the total bars, because chronic days are drawn from the same total.
g121_measure_levels <- c("All days absent", "Chronic days only")
g121_measure_colours <- c(
  "All days absent" = unname(outcome_group_colours[["Non-Chronic Days"]]),
  "Chronic days only" = unname(outcome_group_colours[["Chronic Days"]])
)

g121_measure_distribution <- ds0 %>%
  filter(outcome_group == "Chronic Days") %>%
  select(days_absent_total, days_absent_chronic) %>%
  tidyr::pivot_longer(
    cols = everything(),
    names_to = "measure_column",
    values_to = "day_value"
  ) %>%
  mutate(
    measure = factor(
      if_else(
        measure_column == "days_absent_total",
        g121_measure_levels[1],
        g121_measure_levels[2]
      ),
      levels = g121_measure_levels
    ),
    hybrid_index = hybrid_bin_index(day_value)
  ) %>%
  count(measure, hybrid_index, name = "n_raw") %>%
  tidyr::complete(
    measure,
    hybrid_index = seq_len(hybrid_index_max),
    fill = list(n_raw = 0L)
  ) %>%
  hybrid_panel_frame()

stopifnot(sum(g121_measure_distribution$n_raw) == 2L * n_chronic_days)

g121_measure_means <- ds0 %>%
  filter(outcome_group == "Chronic Days") %>%
  summarise(
    mean_total = weighted_mean(days_absent_total, weight_value),
    mean_chronic = weighted_mean(days_absent_chronic, weight_value)
  )

# ---- g121 --------------------------------------------------------------------
g121_left_partition <- build_partition_panel(g12_partition_summary, "g121")

g121_right_measure_distribution <- g121_measure_distribution %>%
  ggplot(aes(x = bin_label, y = n_raw, fill = measure)) +
  geom_col(width = 0.82) +
  facet_grid(
    measure ~ scale_panel,
    scales = "free",
    space = "free_x"
  ) +
  scale_fill_manual(values = g121_measure_colours, guide = "none") +
  scale_y_continuous(labels = scales::label_comma(), expand = expansion(mult = c(0, 0.08))) +
  labs(
    title = "Graph g121: Two Measures on the Same Respondents",
    subtitle = paste0(
      "Chronic Days group only (n = ", scales::comma(n_chronic_days),
      "), counted twice: by all days absent and by the chronic component of those days.\n",
      "Weighted means: ", sprintf("%.1f", g121_measure_means$mean_total),
      " days absent, of which ", sprintf("%.1f", g121_measure_means$mean_chronic),
      " are chronic. Days 1-5 stay exact; the tail is grouped into five-day work weeks."
    ),
    x = "Exact day within week 1, or work-week number",
    y = "Respondent count"
  ) +
  theme_minimal(base_size = 10) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold"),
    axis.text.x = element_text(size = 7),
    plot.title.position = "plot"
  )

g121_measure_hybrid_distribution <- compose_two_panel_grob(
  g121_left_partition,
  g121_right_measure_distribution,
  left_width = 0.22,
  right_width = 0.78
)

grid::grid.draw(g121_measure_hybrid_distribution)
ggsave(
  paste0(prints_folder, "g121_measure_hybrid_distribution.png"),
  g121_measure_hybrid_distribution,
  width = a4_landscape_width, height = a4_landscape_height, dpi = 300
)

# ---- SECTION: Graph Family g2 ------------------------------------------------
# AN ILLUSTRATION, not a finding.
#
# Family g1 established the outcome groups and the day scale. This family shows
# one way a set of variables can be evaluated against those three groups. The
# predisposing domain is used as the worked example because it is the first
# block of the project's candidate registry; the same displays would serve any
# other domain unchanged.
#
# Read g2, g20, g21, g211, and g212 as composition contrasts across groups, and
# g22 through g24 as the numeric outcome conditioned on predictor level. The
# latter use days_absent_chronic and are labelled as the chronic component.

# ---- g2-data-prep ------------------------------------------------------------
g2_composition_all <- predictor_long %>%
  filter(outcome_group %in% outcome_group_levels, !is.na(level)) %>%
  group_by(outcome_group, variable, variable_label, level) %>%
  summarise(
    n_raw = n(),
    weight_sum = sum(weight_value, na.rm = TRUE),
    .groups = "drop_last"
  ) %>%
  mutate(
    pct_raw = n_raw / sum(n_raw) * 100,
    pct_weighted = weight_sum / sum(weight_sum) * 100
  ) %>%
  ungroup() %>%
  mutate(outcome_group = factor(outcome_group, levels = outcome_group_levels)) %>%
  add_facet_level()

g2_composition <- g2_composition_all %>%
  filter(outcome_group %in% comparison_group_levels) %>%
  mutate(outcome_group = factor(outcome_group, levels = comparison_group_levels))

g2_difference <- g2_composition %>%
  select(variable, variable_label, level, outcome_group, pct_weighted, facet_level) %>%
  tidyr::pivot_wider(names_from = outcome_group, values_from = pct_weighted) %>%
  mutate(difference_pp = `Chronic Days` - `No Days`)

g2_pairwise_differences <- g2_composition_all %>%
  select(variable, variable_label, level, outcome_group, pct_weighted, facet_level) %>%
  tidyr::pivot_wider(names_from = outcome_group, values_from = pct_weighted) %>%
  mutate(
    non_chronic_minus_no_days = `Non-Chronic Days` - `No Days`,
    chronic_minus_non_chronic = `Chronic Days` - `Non-Chronic Days`
  )

g2_intensity <- predictor_long %>%
  filter(outcome_group == "Chronic Days", !is.na(level)) %>%
  group_by(variable, variable_label, level) %>%
  summarise(
    n_raw = n(),
    mean_chronic_days = weighted_mean(days_absent_chronic, weight_value),
    .groups = "drop"
  ) %>%
  add_facet_level()

g2_exact_distribution <- predictor_long %>%
  filter(outcome_group == "Chronic Days", !is.na(level)) %>%
  group_by(variable, variable_label, level, days_absent_chronic) %>%
  summarise(weight_sum = sum(weight_value, na.rm = TRUE), .groups = "drop_last") %>%
  tidyr::complete(days_absent_chronic = 1:31, fill = list(weight_sum = 0)) %>%
  mutate(pct_within_level = weight_sum / sum(weight_sum) * 100) %>%
  ungroup() %>%
  add_facet_level()

# ---- g2 ----------------------------------------------------------------------
g2_group_composition <- g2_composition %>%
  ggplot(aes(x = pct_weighted, y = facet_level, colour = outcome_group)) +
  geom_line(
    aes(group = interaction(variable, level)),
    colour = "#C8C8C8",
    linewidth = 0.45
  ) +
  geom_point(size = 1.8) +
  facet_wrap(~ variable_label, scales = "free_y", ncol = 3) +
  scale_colour_manual(values = comparison_group_colours) +
  scale_x_continuous(labels = scales::label_percent(scale = 1)) +
  scale_y_discrete(labels = strip_facet_level) +
  labs(
    title = "Graph g2: Predisposition Composition in No Days and Chronic Days",
    subtitle = paste0(
      "No Days (n = ", scales::comma(n_no_days), ") vs Chronic (>=1 chronic day; n = ",
      scales::comma(n_chronic_days), "); pooled survey-weighted shares"
    ),
    x = "Weighted share within group",
    y = NULL,
    colour = NULL
  ) +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    legend.position = "top",
    strip.text = element_text(face = "bold")
  )

print(g2_group_composition)
ggsave(
  paste0(prints_folder, "g2_group_composition.png"),
  g2_group_composition, width = 11.69, height = 8.27, dpi = 300
)

# ---- g20 ---------------------------------------------------------------------
g20_three_group_composition <- g2_composition_all %>%
  ggplot(aes(x = pct_weighted, y = facet_level, colour = outcome_group)) +
  geom_line(
    aes(group = interaction(variable, level)),
    colour = "#C8C8C8",
    linewidth = 0.45
  ) +
  geom_point(size = 1.8) +
  facet_wrap(~ variable_label, scales = "free_y", ncol = 3) +
  scale_colour_manual(values = comparison_group_colours) +
  scale_x_continuous(labels = scales::label_percent(scale = 1)) +
  scale_y_discrete(labels = strip_facet_level) +
  labs(
    title = "Graph g20: Predisposition Composition Across All Outcome Groups",
    subtitle = paste0(
      "No Days (n = ", scales::comma(n_no_days), "), Chronic (>=1 chronic day; n = ",
      scales::comma(n_chronic_days), "), Non-Chronic (>0 missed days & 0 chronic days; n = ",
      scales::comma(n_non_chronic_days), ")"
    ),
    x = "Weighted share within group",
    y = NULL,
    colour = NULL
  ) +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    legend.position = "top",
    strip.text = element_text(face = "bold")
  )

print(g20_three_group_composition)
ggsave(
  paste0(prints_folder, "g20_three_group_composition.png"),
  g20_three_group_composition, width = 11.69, height = 8.27, dpi = 300
)

# ---- g21 ---------------------------------------------------------------------
g21_composition_difference <- g2_difference %>%
  ggplot(aes(x = difference_pp, y = facet_level)) +
  geom_vline(xintercept = 0, colour = abcol[["grey"]], linewidth = 0.4) +
  geom_segment(
    aes(x = 0, xend = difference_pp, yend = facet_level),
    colour = "#B9B9B9",
    linewidth = 0.6
  ) +
  geom_point(aes(colour = difference_pp >= 0), size = 1.8) +
  facet_wrap(~ variable_label, scales = "free_y", ncol = 3) +
  scale_colour_manual(values = c("TRUE" = abcol[["brown"]], "FALSE" = abcol[["blue"]]), guide = "none") +
  scale_x_continuous(labels = function(x) paste0(x, " pp")) +
  scale_y_discrete(labels = strip_facet_level) +
  labs(
    title = "Graph g21: Chronic Minus No Days Composition Difference",
    subtitle = paste0(
      "Chronic (>=1 chronic day; n = ", scales::comma(n_chronic_days), ") minus No Days (n = ",
      scales::comma(n_no_days), "); positive values indicate larger Chronic share"
    ),
    x = "Percentage-point difference",
    y = NULL
  ) +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold")
  )

print(g21_composition_difference)
ggsave(
  paste0(prints_folder, "g21_composition_difference.png"),
  g21_composition_difference, width = 11.69, height = 8.27, dpi = 300
)

# ---- g211 --------------------------------------------------------------------
g211_non_chronic_minus_no_days <- g2_pairwise_differences %>%
  ggplot(aes(x = non_chronic_minus_no_days, y = facet_level)) +
  geom_vline(xintercept = 0, colour = abcol[["grey"]], linewidth = 0.4) +
  geom_segment(
    aes(x = 0, xend = non_chronic_minus_no_days, yend = facet_level),
    colour = "#B9B9B9",
    linewidth = 0.6
  ) +
  geom_point(aes(colour = non_chronic_minus_no_days >= 0), size = 1.8) +
  facet_wrap(~ variable_label, scales = "free_y", ncol = 3) +
  scale_colour_manual(values = c("TRUE" = abcol[["blue"]], "FALSE" = abcol[["grey"]]), guide = "none") +
  scale_x_continuous(labels = function(x) paste0(x, " pp")) +
  scale_y_discrete(labels = strip_facet_level) +
  labs(
    title = "Graph g211: Non-Chronic Minus No Days Composition Difference",
    subtitle = paste0(
      "Non-Chronic (>0 missed days & 0 chronic days; n = ", scales::comma(n_non_chronic_days),
      ") minus No Days (n = ", scales::comma(n_no_days), ")"
    ),
    x = "Percentage-point difference",
    y = NULL
  ) +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold")
  )

print(g211_non_chronic_minus_no_days)
ggsave(
  paste0(prints_folder, "g211_non_chronic_minus_no_days.png"),
  g211_non_chronic_minus_no_days, width = 11.69, height = 8.27, dpi = 300
)

# ---- g212 --------------------------------------------------------------------
g212_chronic_minus_non_chronic <- g2_pairwise_differences %>%
  ggplot(aes(x = chronic_minus_non_chronic, y = facet_level)) +
  geom_vline(xintercept = 0, colour = abcol[["grey"]], linewidth = 0.4) +
  geom_segment(
    aes(x = 0, xend = chronic_minus_non_chronic, yend = facet_level),
    colour = "#B9B9B9",
    linewidth = 0.6
  ) +
  geom_point(aes(colour = chronic_minus_non_chronic >= 0), size = 1.8) +
  facet_wrap(~ variable_label, scales = "free_y", ncol = 3) +
  scale_colour_manual(values = c("TRUE" = abcol[["brown"]], "FALSE" = abcol[["blue"]]), guide = "none") +
  scale_x_continuous(labels = function(x) paste0(x, " pp")) +
  scale_y_discrete(labels = strip_facet_level) +
  labs(
    title = "Graph g212: Chronic Minus Non-Chronic Composition Difference",
    subtitle = paste0(
      "Chronic (>=1 chronic day; n = ", scales::comma(n_chronic_days), ") minus Non-Chronic (n = ",
      scales::comma(n_non_chronic_days), ")"
    ),
    x = "Percentage-point difference",
    y = NULL
  ) +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold")
  )

print(g212_chronic_minus_non_chronic)
ggsave(
  paste0(prints_folder, "g212_chronic_minus_non_chronic.png"),
  g212_chronic_minus_non_chronic, width = 11.69, height = 8.27, dpi = 300
)

# ---- g22 ---------------------------------------------------------------------
g22_chronic_day_intensity <- g2_intensity %>%
  ggplot(aes(x = mean_chronic_days, y = facet_level, size = n_raw)) +
  geom_point(colour = abcol[["brown"]], alpha = 0.85) +
  facet_wrap(~ variable_label, scales = "free_y", ncol = 3) +
  scale_x_continuous(limits = c(0, NA)) +
  scale_y_discrete(labels = strip_facet_level) +
  scale_size_area(max_size = 5, labels = scales::label_comma()) +
  labs(
    title = "Graph g22: Mean Chronic Days by Predisposition Level",
    subtitle = paste0(
      "Chronic group only (>=1 chronic day), n = ", scales::comma(n_chronic_days),
      "; means use pooled survey weights"
    ),
    x = "Weighted mean chronic-absence days",
    y = NULL,
    size = "Raw n"
  ) +
  theme_minimal(base_size = 9) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold")
  )

print(g22_chronic_day_intensity)
ggsave(
  paste0(prints_folder, "g22_chronic_day_intensity.png"),
  g22_chronic_day_intensity, width = 11.69, height = 8.27, dpi = 300
)

# ---- g23 ---------------------------------------------------------------------
g23_exact_chronic_distribution <- g2_exact_distribution %>%
  ggplot(aes(x = days_absent_chronic, y = facet_level, fill = pct_within_level)) +
  geom_tile(height = 0.82) +
  facet_grid(variable_label ~ ., scales = "free_y", space = "free_y") +
  scale_fill_gradient(low = "#F2F2F2", high = abcol[["brown"]], labels = scales::label_percent(scale = 1)) +
  scale_x_continuous(breaks = c(1:5, seq(10, 30, 5), 31), expand = c(0, 0)) +
  scale_y_discrete(labels = strip_facet_level) +
  labs(
    title = "Graph g23: Exact Chronic-Day Distribution by Predisposition Level",
    subtitle = paste0(
      "Chronic group only (>=1 chronic day), n = ", scales::comma(n_chronic_days),
      "; each row sums to 100%"
    ),
    x = "Exact chronic-absence days among Chronic Days respondents",
    y = NULL,
    fill = "Weighted share"
  ) +
  theme_minimal(base_size = 8) +
  theme(
    panel.grid = element_blank(),
    strip.text.y = element_text(face = "bold", angle = 0),
    axis.text.y = element_text(size = 6),
    legend.position = "top",
    plot.title.position = "plot"
  )

print(g23_exact_chronic_distribution)
ggsave(
  paste0(prints_folder, "g23_exact_chronic_distribution.png"),
  g23_exact_chronic_distribution,
  width = a4_landscape_width, height = a4_landscape_height, dpi = 300
)

# ---- g24-data-prep -----------------------------------------------------------
g24_composition_tiles <- g2_composition_all %>%
  filter(outcome_group == "Chronic Days") %>%
  select(variable, variable_label, facet_level, pct_raw, pct_weighted) %>%
  tidyr::pivot_longer(
    cols = c(pct_raw, pct_weighted),
    names_to = "measure",
    values_to = "share"
  ) %>%
  mutate(
    measure = factor(
      measure,
      levels = c("pct_raw", "pct_weighted"),
      labels = c("Respondent\nshare", "Weighted\nshare")
    )
  )

stopifnot(
  all(
    abs(
      g24_composition_tiles %>%
        group_by(variable, measure) %>%
        summarise(total = sum(share), .groups = "drop") %>%
        pull(total) - 100
    ) < 1e-8
  )
)

# ---- g24 ---------------------------------------------------------------------
g24_left_exact_distribution <- g2_exact_distribution %>%
  ggplot(aes(x = days_absent_chronic, y = facet_level, fill = pct_within_level)) +
  geom_tile(height = 0.82) +
  facet_grid(variable_label ~ ., scales = "free_y", space = "free_y") +
  scale_fill_gradient(low = "#F2F2F2", high = abcol[["brown"]], labels = scales::label_percent(scale = 1)) +
  scale_x_continuous(breaks = c(1:5, seq(10, 30, 5), 31), expand = c(0, 0)) +
  scale_y_discrete(labels = strip_facet_level) +
  labs(
    title = "Graph g24: Chronic-Day Distribution and Predisposition Composition",
    subtitle = "Distribution rows and right-side composition columns each sum to 100%",
    x = "Exact chronic-absence days among Chronic Days respondents",
    y = NULL,
    fill = "Within-row share"
  ) +
  theme_minimal(base_size = 8) +
  theme(
    panel.grid = element_blank(),
    strip.text.y = element_text(face = "bold", angle = 0),
    axis.text.y = element_text(size = 6),
    legend.position = "left",
    plot.title.position = "plot"
  )

g24_right_composition <- g24_composition_tiles %>%
  ggplot(aes(x = measure, y = facet_level, fill = share)) +
  geom_tile(height = 0.82, width = 0.9) +
  geom_text(aes(label = sprintf("%.1f%%", share)), size = 1.8) +
  facet_grid(variable_label ~ ., scales = "free_y", space = "free_y") +
  scale_fill_gradient(
    low = "#F2F2F2",
    high = abcol[["blue"]],
    labels = scales::label_percent(scale = 1),
    name = "Column share"
  ) +
  scale_y_discrete(labels = strip_facet_level) +
  labs(
    x = NULL,
    y = NULL,
    title = NULL,
    subtitle = NULL
  ) +
  theme_minimal(base_size = 8) +
  theme(
    panel.grid = element_blank(),
    strip.text.y = element_blank(),
    axis.text.y = element_text(size = 6),
    axis.text.x = element_text(size = 6, angle = 0, hjust = 0.5, vjust = 0.5, lineheight = 0.9),
    axis.ticks.y = element_blank(),
    legend.position = "right",
    plot.margin = margin(5.5, 5.5, 5.5, 0)
  )

g24_distribution_with_composition <- grid::grid.grabExpr({
  grid::grid.newpage()
  grid::pushViewport(
    grid::viewport(
      layout = grid::grid.layout(
        nrow = 1, ncol = 2,
        widths = grid::unit(c(0.70, 0.30), "npc")
      )
    )
  )
  grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
  grid::grid.draw(ggplot2::ggplotGrob(g24_left_exact_distribution))
  grid::upViewport()
  grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
  grid::grid.draw(ggplot2::ggplotGrob(g24_right_composition))
  grid::upViewport(2)
}, wrap.grobs = TRUE)

grid::grid.draw(g24_distribution_with_composition)
ggsave(
  paste0(prints_folder, "g24_distribution_with_composition.png"),
  g24_distribution_with_composition,
  width = a4_landscape_width, height = a4_landscape_height, dpi = 300
)

# ---- SECTION: Graph Family g3 ------------------------------------------------
# REFERENCE, not argument.
#
# Formerly numbered g0 and placed first. It is a lookup profile of the largest
# outcome group, the 45,006 respondents with No Days, and it answers "what does
# this group look like" rather than "how do the groups differ". It now sits
# after the two substantive families. The retired IDs g0 and g01 are not reused.

# ---- g3-data-prep ------------------------------------------------------------
g3_data <- predictor_long %>%
  filter(outcome_group == "No Days", !is.na(level)) %>%
  group_by(variable, variable_label, level) %>%
  summarise(
    n_raw = n(),
    weight_sum = sum(weight_value, na.rm = TRUE),
    .groups = "drop_last"
  ) %>%
  mutate(
    pct_weighted = weight_sum / sum(weight_sum) * 100,
    label = sprintf("%.1f%%", pct_weighted)
  ) %>%
  ungroup() %>%
  add_facet_level()

# ---- g3 ----------------------------------------------------------------------
g3_no_days_predisposition <- g3_data %>%
  ggplot(aes(x = pct_weighted, y = facet_level)) +
  geom_col(fill = outcome_group_colours[["Non-Chronic Days"]], width = 0.72) +
  facet_wrap(~ variable_label, scales = "free_y", ncol = 4) +
  scale_x_continuous(
    labels = scales::label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.16))
  ) +
  scale_y_discrete(labels = strip_facet_level) +
  labs(
    title = "Graph g3: Predisposition Profile Among Respondents With No Days",
    subtitle = paste0(
      "Reference profile of the largest outcome group. Weighted within each variable; unweighted n = ",
      scales::comma(n_no_days)
    ),
    x = "Weighted share within variable",
    y = NULL
  ) +
  theme_minimal(base_size = 8) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold", size = 7),
    axis.text.y = element_text(size = 6),
    plot.title.position = "plot"
  )

print(g3_no_days_predisposition)
ggsave(
  paste0(prints_folder, "g3_no_days_predisposition.png"),
  g3_no_days_predisposition, width = 8.5, height = 5.5, dpi = 300
)

# ---- g31 ---------------------------------------------------------------------
g31_no_days_predisposition_a4 <- g3_no_days_predisposition +
  geom_text(
    aes(label = label),
    hjust = -0.08,
    size = 2.6,
    colour = abcol[["grey"]]
  ) +
  facet_wrap(~ variable_label, scales = "free_y", ncol = 3) +
  labs(
    title = "Graph g31: A4 Predisposition Profile Among Respondents With No Days",
    subtitle = paste0(
      "A4 landscape layout; weighted percentages within each variable (n = ",
      scales::comma(n_no_days), ")"
    )
  ) +
  theme(
    strip.text = element_text(face = "bold", size = 9),
    axis.text.x = element_text(size = 8),
    axis.text.y = element_text(size = 7),
    axis.title.x = element_text(size = 9),
    plot.title = element_text(size = 15),
    plot.subtitle = element_text(size = 10),
    plot.margin = margin(10, 18, 10, 10)
  )

print(g31_no_days_predisposition_a4)
ggsave(
  paste0(prints_folder, "g31_no_days_predisposition_a4.png"),
  g31_no_days_predisposition_a4,
  width = a4_landscape_width, height = a4_landscape_height, dpi = 300
)

# ---- save-to-disk ------------------------------------------------------------
saveRDS(
  list(
    outcome_group_summary = outcome_group_summary,
    g1_scale_mapping = g1_scale_mapping,
    g11_days_absent_exact = g11_days_absent_exact,
    g111_chronic_exact = g111_chronic_exact,
    g12_hybrid_distribution = g12_hybrid_distribution,
    g121_measure_distribution = g121_measure_distribution,
    g2_composition = g2_composition_all,
    g2_intensity = g2_intensity,
    g3_data = g3_data
  ),
  paste0(local_data, "eda-72-summaries.rds")
)