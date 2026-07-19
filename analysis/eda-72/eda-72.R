# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# EDA-72: Predisposition profiles for chronic-absence outcome groups.
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

# ---- declare-functions -------------------------------------------------------
make_predictor_long <- function(data, specifications) {
  purrr::map2_dfr(
    specifications$variable,
    specifications$variable_label,
    function(variable_name, display_name) {
      source_value <- data[[variable_name]]
      value_levels <- if (is.factor(source_value)) {
        levels(source_value)
      } else {
        sort(unique(stats::na.omit(source_value))) |> as.character()
      }

      tibble::tibble(
        respondent_id = data$.respondent_id,
        outcome_group = data$outcome_group,
        weight_value = data$weight_value,
        days_absent_chronic = data$days_absent_chronic,
        variable = variable_name,
        variable_label = display_name,
        level = factor(as.character(source_value), levels = value_levels)
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
stopifnot(max(ds0$days_absent_chronic, na.rm = TRUE) == 31L)

# ---- inspect-data-0 ----------------------------------------------------------
cat("Analytical rows:", scales::comma(nrow(ds0)), "\n")
print(outcome_group_summary %>% select(-expected_n))

# ---- inspect-data-1 ----------------------------------------------------------
cat("Predisposition variables retained after dropping student status:\n")
print(predisposition_specs)

# ---- data-context-tables -----------------------------------------------------
cat("This analysis uses cchs_analytic.parquet at one row per CCHS respondent.\n")
cat("Variables: 11 non-student predisposing fields, days_absent_total,\n")
cat("days_absent_chronic, and wts_m_pooled.\n")

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

# ---- SECTION: Graph Family g0 ------------------------------------------------
# Predisposition distributions among the 45,006 respondents with No Days.

# ---- g0-data-prep ------------------------------------------------------------
g0_data <- predictor_long %>%
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

# ---- g0 ----------------------------------------------------------------------
g0_no_days_predisposition <- g0_data %>%
  ggplot(aes(x = pct_weighted, y = facet_level)) +
  geom_col(fill = abcol[["blue"]], width = 0.72) +
  facet_wrap(~ variable_label, scales = "free_y", ncol = 4) +
  scale_x_continuous(
    labels = scales::label_percent(scale = 1),
    expand = expansion(mult = c(0, 0.16))
  ) +
  scale_y_discrete(labels = strip_facet_level) +
  labs(
    title = "Graph g0: Predisposition Profile Among Respondents With No Days",
    subtitle = "Weighted within each variable; unweighted n = 45,006",
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

print(g0_no_days_predisposition)
ggsave(
  paste0(prints_folder, "g0_no_days_predisposition.png"),
  g0_no_days_predisposition, width = 8.5, height = 5.5, dpi = 300
)

# ---- g01 ---------------------------------------------------------------------
g01_no_days_predisposition_a4 <- g0_no_days_predisposition +
  geom_text(
    aes(label = label),
    hjust = -0.08,
    size = 2.6,
    colour = abcol[["grey"]]
  ) +
  facet_wrap(~ variable_label, scales = "free_y", ncol = 3) +
  labs(
    title = "Graph g01: A4 Predisposition Profile Among Respondents With No Days",
    subtitle = "A4 landscape layout; weighted percentages within each variable (n = 45,006)"
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

print(g01_no_days_predisposition_a4)
ggsave(
  paste0(prints_folder, "g01_no_days_predisposition_a4.png"),
  g01_no_days_predisposition_a4,
  width = a4_landscape_width, height = a4_landscape_height, dpi = 300
)

# ---- SECTION: Graph Family g1 ------------------------------------------------
# Map exact positive chronic days to both proposed coarsened display scales.

# ---- g1-data-prep ------------------------------------------------------------
g1_scale_mapping <- tidyr::crossing(
  days_absent_chronic = 1:31,
  scale = factor(
    c("Exact reported days", "Five-day work weeks", "First week exact; tail coarsened"),
    levels = c("Exact reported days", "First week exact; tail coarsened", "Five-day work weeks")
  )
) %>%
  mutate(
    bin_index = case_when(
      scale == "Exact reported days" ~ days_absent_chronic,
      scale == "Five-day work weeks" ~ ceiling(days_absent_chronic / 5),
      days_absent_chronic <= 5 ~ days_absent_chronic,
      TRUE ~ 5 + ceiling((days_absent_chronic - 5) / 5)
    ),
    bin_label = case_when(
      scale == "Exact reported days" ~ as.character(days_absent_chronic),
      scale == "Five-day work weeks" & days_absent_chronic == 31 ~ "7+ weeks",
      scale == "Five-day work weeks" ~ paste0(ceiling(days_absent_chronic / 5), " week", if_else(ceiling(days_absent_chronic / 5) == 1, "", "s")),
      days_absent_chronic <= 5 ~ paste0(days_absent_chronic, " day", if_else(days_absent_chronic == 1, "", "s")),
      days_absent_chronic == 31 ~ "31 days",
      TRUE ~ paste0((ceiling((days_absent_chronic - 5) / 5) - 1) * 5 + 6, "-", ceiling((days_absent_chronic - 5) / 5) * 5 + 5, " days")
    ),
    band = factor(bin_index %% 2)
  )

g1_scale_labels <- g1_scale_mapping %>%
  group_by(scale, bin_index, bin_label) %>%
  summarise(label_x = mean(days_absent_chronic), .groups = "drop")

# ---- g1 ----------------------------------------------------------------------
g1_coarsening_map <- g1_scale_mapping %>%
  ggplot(aes(x = days_absent_chronic, y = scale, fill = band)) +
  geom_tile(colour = "white", linewidth = 0.25, height = 0.78) +
  geom_text(
    data = g1_scale_labels,
    aes(x = label_x, y = scale, label = bin_label),
    inherit.aes = FALSE,
    size = 2.5
  ) +
  scale_fill_manual(values = c("0" = "#D9EDF2", "1" = "#FCE2CF"), guide = "none") +
  scale_x_continuous(breaks = c(1:5, seq(10, 30, 5), 31), expand = c(0, 0)) +
  labs(
    title = "Graph g1: Mapping Exact Chronic Days to Coarser Work-Week Scales",
    subtitle = "Five reported workdays are treated as one display week; this is a coarsening rule, not elapsed time",
    x = "Exact reported chronic-absence days",
    y = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(
    panel.grid = element_blank(),
    axis.text.y = element_text(face = "bold"),
    plot.title.position = "plot"
  )

print(g1_coarsening_map)
ggsave(
  paste0(prints_folder, "g1_chronic_day_coarsening_map.png"),
  g1_coarsening_map, width = 11.69, height = 4.2, dpi = 300
)

# ---- g11-data-prep -----------------------------------------------------------
# Extend the EDA-71 G22 composition: the unchanged three-way respondent partition
# sits at left, while the chronic-reporter distribution is shown at three scales.
g11_partition_summary <- ds0 %>%
  filter(!is.na(outcome_group)) %>%
  count(outcome_group, name = "n_raw") %>%
  mutate(
    pct_raw = n_raw / sum(n_raw) * 100,
    outcome_group = factor(outcome_group, levels = outcome_group_levels)
  )

g11_chronic_exact <- ds0 %>%
  filter(outcome_group == "Chronic Days") %>%
  count(days_absent_chronic, name = "n_raw") %>%
  tidyr::complete(days_absent_chronic = 1:31, fill = list(n_raw = 0L)) %>%
  mutate(
    exact_day = factor(days_absent_chronic, levels = 1:31),
    work_week = pmin(ceiling(days_absent_chronic / 5), 7L),
    work_week_label = factor(
      case_when(
        work_week == 1 ~ "1-5 days (1 week)",
        work_week == 2 ~ "6-10 days (2 weeks)",
        work_week == 3 ~ "11-15 days (3 weeks)",
        work_week == 4 ~ "16-20 days (4 weeks)",
        work_week == 5 ~ "21-25 days (5 weeks)",
        work_week == 6 ~ "26-30 days (6 weeks)",
        TRUE ~ "31 days (7+ weeks)"
      ),
      levels = c(
        "1-5 days (1 week)", "6-10 days (2 weeks)",
        "11-15 days (3 weeks)", "16-20 days (4 weeks)",
        "21-25 days (5 weeks)", "26-30 days (6 weeks)",
        "31 days (7+ weeks)"
      )
    ),
    hybrid_label = factor(
      case_when(
        days_absent_chronic <= 5 ~ paste0(days_absent_chronic, " day", if_else(days_absent_chronic == 1, "", "s")),
        days_absent_chronic <= 10 ~ "6-10 days",
        days_absent_chronic <= 15 ~ "11-15 days",
        days_absent_chronic <= 20 ~ "16-20 days",
        days_absent_chronic <= 25 ~ "21-25 days",
        days_absent_chronic <= 30 ~ "26-30 days",
        TRUE ~ "31 days"
      ),
      levels = c("1 day", "2 days", "3 days", "4 days", "5 days", "6-10 days",
                 "11-15 days", "16-20 days", "21-25 days", "26-30 days", "31 days")
    )
  )

g11_weekly <- g11_chronic_exact %>%
  group_by(work_week, work_week_label) %>%
  summarise(n_raw = sum(n_raw), .groups = "drop")

g11_hybrid <- g11_chronic_exact %>%
  group_by(hybrid_label, work_week_label) %>%
  summarise(n_raw = sum(n_raw), .groups = "drop")

g11_partition_colours <- c(
  "No Days" = "#D9D9D9",
  "Chronic Days" = "#D08C60",
  "Non-Chronic Days" = "#0B4F6C"
)
g11_exact_colours <- stats::setNames(grDevices::hcl.colors(31, "YlOrRd", rev = TRUE), as.character(1:31))
g11_week_colours <- stats::setNames(
  grDevices::hcl.colors(7, "YlOrRd", rev = TRUE),
  levels(g11_chronic_exact$work_week_label)
)

# ---- g11 ---------------------------------------------------------------------
g11_left_partition <- g11_partition_summary %>%
  ggplot(aes(x = "Analytic sample", y = pct_raw, fill = outcome_group)) +
  geom_col(width = 0.48, colour = "white", linewidth = 0.3) +
  geom_text(
    aes(label = paste0(scales::comma(n_raw), "\n", sprintf("%.1f%%", pct_raw))),
    position = position_stack(vjust = 0.5), size = 2.8, lineheight = 0.95
  ) +
  scale_fill_manual(values = g11_partition_colours, guide = "none") +
  scale_y_continuous(
    labels = scales::label_percent(scale = 1), limits = c(0, 100),
    expand = expansion(mult = c(0, 0))
  ) +
  labs(x = NULL, y = "Share of sample") +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x = element_blank(), panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(), plot.margin = margin(5.5, 0, 5.5, 5.5)
  )

g11_top_exact <- g11_chronic_exact %>%
  ggplot(aes(x = days_absent_chronic, y = n_raw, fill = exact_day)) +
  geom_col(width = 0.9) +
  scale_fill_manual(values = g11_exact_colours, guide = "none") +
  scale_x_continuous(breaks = c(1:5, seq(10, 30, 5), 31), limits = c(0.5, 31.5)) +
  scale_y_continuous(labels = scales::label_comma(), expand = expansion(mult = c(0, 0.08))) +
  labs(
    title = "Exact reported days", subtitle = "One-day bars, 1 through 31; colour identifies the exact-day category",
    x = "Chronic-absence days", y = "Respondent count"
  ) +
  theme_minimal(base_size = 8) +
  theme(panel.grid.major.x = element_blank(), panel.grid.minor = element_blank(), plot.margin = margin(5.5, 5.5, 1, 6))

g11_middle_weekly <- g11_weekly %>%
  ggplot(aes(x = work_week_label, y = n_raw, fill = work_week_label)) +
  geom_col(width = 0.78) +
  geom_text(aes(label = scales::comma(n_raw)), vjust = -0.3, size = 2.5) +
  scale_fill_manual(values = g11_week_colours, guide = "none") +
  scale_y_continuous(labels = scales::label_comma(), expand = expansion(mult = c(0, 0.14))) +
  labs(
    title = "Five-day work-week bins", subtitle = "1-5, 6-10, ..., 26-30, and 31 days",
    x = NULL, y = "Respondent count"
  ) +
  theme_minimal(base_size = 8) +
  theme(panel.grid.major.x = element_blank(), panel.grid.minor = element_blank(), axis.text.x = element_text(size = 7), plot.margin = margin(1, 5.5, 1, 6))

g11_bottom_hybrid <- g11_hybrid %>%
  ggplot(aes(x = hybrid_label, y = n_raw, fill = work_week_label)) +
  geom_col(width = 0.78) +
  scale_fill_manual(values = g11_week_colours, name = "Five-day colour band") +
  scale_y_continuous(labels = scales::label_comma(), expand = expansion(mult = c(0, 0.08))) +
  labs(
    title = "First week exact; tail coarsened", subtitle = "Days 1-5 remain separate; tail bins retain their five-day colour band",
    x = NULL, y = "Respondent count"
  ) +
  theme_minimal(base_size = 8) +
  theme(
    panel.grid.major.x = element_blank(), panel.grid.minor = element_blank(),
    axis.text.x = element_text(size = 6.5, angle = 25, hjust = 1),
    legend.position = c(0.99, 0.99), legend.justification = c(1, 1),
    legend.background = element_rect(fill = "#FFFFFFDD", colour = "#D0D0D0"),
    legend.key.size = grid::unit(0.28, "cm"), legend.title = element_text(size = 6),
    legend.text = element_text(size = 5.5), plot.margin = margin(1, 5.5, 5.5, 6)
  )

g11_chronic_day_scales <- grid::grid.grabExpr({
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
  grid::grid.draw(ggplot2::ggplotGrob(g11_left_partition))
  grid::upViewport()
  grid::pushViewport(grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
  grid::grid.draw(ggplot2::ggplotGrob(g11_top_exact))
  grid::upViewport()
  grid::pushViewport(grid::viewport(layout.pos.row = 2, layout.pos.col = 2))
  grid::grid.draw(ggplot2::ggplotGrob(g11_middle_weekly))
  grid::upViewport()
  grid::pushViewport(grid::viewport(layout.pos.row = 3, layout.pos.col = 2))
  grid::grid.draw(ggplot2::ggplotGrob(g11_bottom_hybrid))
  grid::upViewport(2)
}, wrap.grobs = TRUE)

grid::grid.draw(g11_chronic_day_scales)
ggsave(
  paste0(prints_folder, "g11_chronic_day_scales.png"),
  g11_chronic_day_scales, width = a4_landscape_width, height = a4_landscape_height, dpi = 300
)

# ---- g12-data-prep -----------------------------------------------------------
# Compare the hybrid missed-day distribution for the two positive-day groups.
g12_hybrid_distribution <- ds0 %>%
  filter(outcome_group %in% c("Chronic Days", "Non-Chronic Days")) %>%
  transmute(
    outcome_group,
    missed_days = if_else(
      outcome_group == "Chronic Days",
      days_absent_chronic,
      as.integer(days_absent_total)
    )
  ) %>%
  mutate(
    bin_index = case_when(
      missed_days <= 5 ~ missed_days,
      missed_days <= 10 ~ 6L,
      missed_days <= 15 ~ 7L,
      missed_days <= 20 ~ 8L,
      missed_days <= 25 ~ 9L,
      missed_days <= 30 ~ 10L,
      TRUE ~ 11L
    )
  ) %>%
  count(outcome_group, bin_index, name = "n_raw") %>%
  tidyr::complete(
    outcome_group = factor(
      c("Chronic Days", "Non-Chronic Days"),
      levels = c("Chronic Days", "Non-Chronic Days")
    ),
    bin_index = 1:11,
    fill = list(n_raw = 0L)
  ) %>%
  mutate(
    scale_panel = factor(
      if_else(bin_index <= 5, "A Week or Less", "More than a Week"),
      levels = c("A Week or Less", "More than a Week")
    ),
    bin_label = factor(
      case_when(
        bin_index <= 5 ~ as.character(bin_index),
        bin_index == 6 ~ "2",
        bin_index == 7 ~ "3",
        bin_index == 8 ~ "4",
        bin_index == 9 ~ "5",
        bin_index == 10 ~ "6",
        TRUE ~ "7+"
      ),
      levels = c("1", "2", "3", "4", "5", "6", "7+")
    ),
    work_week = factor(
      if_else(bin_index <= 5, 1L, bin_index - 4L),
      levels = 1:7
    )
  )

# ---- g12 ---------------------------------------------------------------------
g12_group_hybrid_distribution <- g12_hybrid_distribution %>%
  ggplot(aes(x = bin_label, y = n_raw, fill = work_week)) +
  geom_col(width = 0.82) +
  facet_grid(
    outcome_group ~ scale_panel,
    scales = "free",
    space = "free_x"
  ) +
  scale_fill_manual(
    values = stats::setNames(unname(g11_week_colours), as.character(1:7)),
    guide = "none"
  ) +
  scale_y_continuous(labels = scales::label_comma(), expand = expansion(mult = c(0, 0.08))) +
  labs(
    title = "Graph g12: Missed-Day Distributions on the Hybrid Work-Week Scale",
    subtitle = "Days 1-5 remain exact; values above day 5 are grouped into work-week bins",
    x = "Exact day within week 1 or work-week bin",
    y = "Respondent count"
  ) +
  theme_minimal(base_size = 10) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold"),
    plot.title.position = "plot"
  )

print(g12_group_hybrid_distribution)
ggsave(
  paste0(prints_folder, "g12_group_hybrid_distribution.png"),
  g12_group_hybrid_distribution,
  width = 8.5, height = 5.5, dpi = 300
)

# ---- SECTION: Graph Family g2 ------------------------------------------------
# Compare No Days with Chronic Days, then add positive chronic-day intensity.

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
    subtitle = "Pooled survey-weighted percentages within each outcome group and variable",
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
    subtitle = "Pooled survey-weighted percentages; colours match EDA-71 graph g2",
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
    subtitle = "Positive values indicate a larger weighted share among Chronic Days respondents",
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
    subtitle = "Positive values indicate a larger weighted share among Non-Chronic Days respondents",
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
    subtitle = "Positive values indicate a larger weighted share among Chronic Days respondents",
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
    subtitle = "Chronic Days respondents only (n = 3,626); means use pooled survey weights",
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
    subtitle = "Each row sums to 100%; darker cells mark more common exact values within that level",
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
      labels = c("Respondent count", "Weighted share")
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
    subtitle = "Distribution rows sum to 100%; each composition column also sums to 100% within predictor",
    x = "Exact chronic-absence days among Chronic Days respondents",
    y = NULL,
    fill = "Within-row share"
  ) +
  theme_minimal(base_size = 8) +
  theme(
    panel.grid = element_blank(),
    strip.text.y = element_text(face = "bold", angle = 0),
    axis.text.y = element_text(size = 6),
    legend.position = "top",
    plot.title.position = "plot"
  )

g24_right_composition <- g24_composition_tiles %>%
  ggplot(aes(x = measure, y = facet_level, fill = share)) +
  geom_tile(height = 0.82, width = 0.9) +
  geom_text(aes(label = sprintf("%.1f%%", share)), size = 1.8) +
  facet_grid(variable_label ~ ., scales = "free_y", space = "free_y") +
  scale_fill_gradient(low = "#F2F2F2", high = abcol[["blue"]], guide = "none") +
  scale_y_discrete(labels = NULL) +
  labs(x = NULL, y = NULL) +
  theme_minimal(base_size = 8) +
  theme(
    panel.grid = element_blank(),
    strip.text.y = element_blank(),
    axis.text.x = element_text(size = 7, angle = 25, hjust = 1),
    axis.ticks.y = element_blank(),
    plot.margin = margin(5.5, 5.5, 5.5, 0)
  )

g24_distribution_with_composition <- grid::grid.grabExpr({
  grid::grid.newpage()
  grid::pushViewport(
    grid::viewport(
      layout = grid::grid.layout(
        nrow = 1, ncol = 2,
        widths = grid::unit(c(0.78, 0.22), "npc")
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

# ---- save-to-disk ------------------------------------------------------------
saveRDS(
  list(
    outcome_group_summary = outcome_group_summary,
    g0_data = g0_data,
    g1_scale_mapping = g1_scale_mapping,
    g2_composition = g2_composition_all,
    g2_intensity = g2_intensity
  ),
  paste0(local_data, "eda-72-summaries.rds")
)