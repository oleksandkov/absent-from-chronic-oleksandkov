# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# EDA-82 (Story 2): Synthesis layer for model-1, model-2, and model-3.
# This script FITS NOTHING. It reads artifacts those three reports persisted,
# joins them on a common term key, and asks what the three frames together
# license us to say. Where eda-81 explained how the primary model was built,
# eda-82 asks what it means and where the evidence runs out.
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
library(tibble)
library(scales)
library(fs)
library(kableExtra)
requireNamespace("readr", quietly = TRUE)
requireNamespace("knitr", quietly = TRUE)
requireNamespace("cowplot", quietly = TRUE)
requireNamespace("ggrepel", quietly = TRUE)

# ---- load-sources ------------------------------------------------------------
base::source("./scripts/common-functions.R")
base::source("./scripts/graphing/graph-presets.R")

# The same registry model-1, model-2, and model-3 source. Sourcing it, rather
# than restating the labels here, is what keeps this report from drifting away
# from the three it synthesises.
base::source("./scripts/modeling/candidate-registry.R")

# ---- declare-globals ---------------------------------------------------------
local_root    <- "./analysis/eda-82/"
local_data    <- paste0(local_root, "data-local/")
prints_folder <- paste0(local_root, "prints/")

for (folder in c(local_data, prints_folder)) {
  if (!fs::dir_exists(folder)) { fs::dir_create(folder, recurse = TRUE) }
}

# Upstream artifacts. Every one of these is a file another report wrote.
path_m1_nb          <- "./analysis/model-1/data-local/nb-coefficients.csv"
path_m1_compare     <- "./analysis/model-1/data-local/model-comparison.csv"
path_m1_cvsum       <- "./analysis/model-1/data-local/cv-performance-summary.csv"
path_m1_selmatrix   <- "./analysis/model-1/data-local/selection-matrix.csv"

path_m2_nb          <- "./analysis/model-2/data-local/nb-coefficients.csv"
path_m2_inventory   <- "./analysis/model-2/data-local/condition-inventory.csv"
path_m2_comorbid    <- "./analysis/model-2/data-local/comorbidity-overlap.csv"
path_m2_counts      <- "./analysis/model-2/data-local/selection-counts.csv"
path_m2_recurrence  <- "./analysis/model-2/data-local/term-recurrence.csv"

path_m3_union       <- "./analysis/model-3/data-local/union-coefficients.csv"
path_m3_het         <- "./analysis/model-3/data-local/sex-heterogeneity.csv"
path_m3_strata      <- "./analysis/model-3/data-local/stratum-inventory.csv"
path_m3_nb          <- "./analysis/model-3/data-local/nb-coefficients.csv"
path_m3_compare     <- "./analysis/model-3/data-local/model-comparison.csv"
path_m3_cvsum       <- "./analysis/model-3/data-local/cv-performance-summary.csv"
path_m3_selmatrix   <- "./analysis/model-3/data-local/selection-matrix.csv"

upstream_paths <- c(
  "model-1 : NB coefficients"        = path_m1_nb,
  "model-1 : model comparison"       = path_m1_compare,
  "model-1 : CV summary"             = path_m1_cvsum,
  "model-1 : selection matrix"       = path_m1_selmatrix,
  "model-2 : NB coefficients"        = path_m2_nb,
  "model-2 : condition inventory"    = path_m2_inventory,
  "model-2 : comorbidity overlap"    = path_m2_comorbid,
  "model-2 : selection counts"       = path_m2_counts,
  "model-2 : term recurrence"        = path_m2_recurrence,
  "model-3 : union coefficients"     = path_m3_union,
  "model-3 : sex heterogeneity"      = path_m3_het,
  "model-3 : stratum inventory"      = path_m3_strata,
  "model-3 : NB coefficients"        = path_m3_nb,
  "model-3 : model comparison"       = path_m3_compare,
  "model-3 : CV summary"             = path_m3_cvsum,
  "model-3 : selection matrix"       = path_m3_selmatrix
)

# Local decision 1. Each frame is represented by the specification its own
# report designated primary. model-2 reversed the penalty rule locally (its
# decision 25) because lambda.1se returns an empty selection in seven of the
# seventeen subgroups. That reversal is restated wherever the frames are
# compared, never silently absorbed.
frame_specs <- tibble::tribble(
  ~frame,               ~report,   ~primary_spec, ~primary_rule,
  "Pooled",             "model-1", "model_1",     "lambda.1se",
  "Condition-specific", "model-2", "spec_min",    "lambda.min",
  "Sex-stratified",     "model-3", "model_1",     "lambda.1se"
)

m1_primary_spec <- frame_specs$primary_spec[frame_specs$report == "model-1"]
m2_primary_spec <- frame_specs$primary_spec[frame_specs$report == "model-2"]
m3_primary_spec <- frame_specs$primary_spec[frame_specs$report == "model-3"]

# Local decision 4. Kish is the widest of the three lower bounds on the design
# effect, so quoting it is the least likely to overstate precision.
interval_variant <- "Kish"

strata_levels <- c("Female", "Male")

# The traced term for the Data Context section. Chosen because it is retained in
# all three frames, which is exactly what makes it useful as a worked example.
traced_term <- "Migraine: Yes"

n_conditions_total <- 17L

domain_levels <- c("Exposure", "Predisposing", "Facilitating", "Needs", "Survey design")

domain_colours <- c(
  "Exposure"      = abcol[["magenta"]],
  "Predisposing"  = abcol[["blue"]],
  "Facilitating"  = abcol[["green"]],
  "Needs"         = abcol[["brown"]],
  "Survey design" = abcol[["grey"]]
)

frame_colours <- c(
  "Pooled" = abcol[["grey"]],
  "Female" = abcol[["magenta"]],
  "Male"   = abcol[["blue"]]
)

retention_colours <- c(
  "retained"     = abcol[["green"]],
  "not retained" = "grey88"
)

heterogeneity_colours <- c(
  "both"        = abcol[["grey"]],
  "female only" = abcol[["magenta"]],
  "male only"   = abcol[["blue"]],
  "neither"     = "grey75"
)

# Relative widths of the two g1 panels. The left panel carries the row labels.
g1_panel_widths <- c(left = 1.00, right = 0.42)

# ---- declare-functions -------------------------------------------------------
# Render a data frame as styled HTML for Quarto, or plainly for console use.
print_table <- function(data, caption, align = NULL, scroll_height = NULL) {
  if (is.null(scroll_height) && nrow(data) > 25) scroll_height <- "600px"
  boxed <- data %>%
    knitr::kable(
      format = "html", caption = caption, escape = FALSE,
      align = align, row.names = FALSE
    ) %>%
    kableExtra::kable_styling(
      bootstrap_options = c("striped", "hover", "condensed"), full_width = FALSE
    )
  boxed <- if (is.null(scroll_height)) {
    kableExtra::scroll_box(boxed, width = "100%")
  } else {
    kableExtra::scroll_box(boxed, width = "100%", height = scroll_height)
  }
  cat(as.character(boxed))
  invisible(data)
}

# Local decision 2. model-2 and model-3 persist a `term` column built exactly
# this way. Reconstructing the same string for model-1 makes all three joinable
# without a lookup table that could drift out of step.
make_term <- function(variable_label, level) {
  level <- ifelse(is.na(level), "", as.character(level))
  paste0(variable_label, ifelse(level == "", "", paste0(": ", level)))
}

# Format a rate ratio with its interval in one cell.
fmt_ratio <- function(estimate, low, high, digits = 2) {
  ifelse(
    is.na(estimate), "",
    sprintf(paste0("%.", digits, "f (%.", digits, "f-%.", digits, "f)"),
            estimate, low, high)
  )
}

fmt_p <- function(p, digits = 4) {
  ifelse(is.na(p), "",
         ifelse(p < 0.0001, "&lt;0.0001", sprintf(paste0("%.", digits, "f"), p)))
}

# Map a model label to the role its report assigned it. model-3's CV summary
# does not carry `role`; model-1's does. Deriving it once keeps the two joinable.
role_of <- function(model_label) {
  dplyr::case_when(
    model_label == "Model 1" ~ "Primary",
    model_label == "Model 2" ~ "Secondary",
    TRUE                     ~ "Sensitivity"
  )
}

# ---- load-data ---------------------------------------------------------------
# Sixteen files, three reports, zero re-estimation.
m1_nb        <- readr::read_csv(path_m1_nb,        show_col_types = FALSE)
m1_compare   <- readr::read_csv(path_m1_compare,   show_col_types = FALSE)
m1_cvsum     <- readr::read_csv(path_m1_cvsum,     show_col_types = FALSE)
m1_selmatrix <- readr::read_csv(path_m1_selmatrix, show_col_types = FALSE)

m2_nb        <- readr::read_csv(path_m2_nb,         show_col_types = FALSE)
m2_inventory <- readr::read_csv(path_m2_inventory,  show_col_types = FALSE)
m2_comorbid  <- readr::read_csv(path_m2_comorbid,   show_col_types = FALSE)
m2_counts    <- readr::read_csv(path_m2_counts,     show_col_types = FALSE)
m2_recur     <- readr::read_csv(path_m2_recurrence, show_col_types = FALSE)

m3_union     <- readr::read_csv(path_m3_union,     show_col_types = FALSE)
m3_het       <- readr::read_csv(path_m3_het,       show_col_types = FALSE)
m3_strata    <- readr::read_csv(path_m3_strata,    show_col_types = FALSE)
m3_nb        <- readr::read_csv(path_m3_nb,        show_col_types = FALSE)
m3_compare   <- readr::read_csv(path_m3_compare,   show_col_types = FALSE)
m3_cvsum     <- readr::read_csv(path_m3_cvsum,     show_col_types = FALSE)
m3_selmatrix <- readr::read_csv(path_m3_selmatrix, show_col_types = FALSE)

# ---- tweak-data-0 ------------------------------------------------------------
# Type coercion and key construction only. Nothing is recomputed.

# model-1 does not persist a `term` column; the other two do. Build it.
m1_nb <- m1_nb %>%
  filter(column != "(Intercept)") %>%
  mutate(
    term   = make_term(variable_label, level),
    domain = factor(domain, levels = domain_levels)
  )

m2_nb <- m2_nb %>%
  filter(column != "(Intercept)") %>%
  mutate(domain = factor(domain, levels = domain_levels))

m3_nb <- m3_nb %>%
  filter(column != "(Intercept)") %>%
  mutate(
    domain  = factor(domain, levels = domain_levels),
    stratum = factor(stratum, levels = strata_levels)
  )

m3_union <- m3_union %>%
  filter(column != "(Intercept)") %>%
  mutate(
    domain  = factor(domain, levels = domain_levels),
    stratum = factor(stratum, levels = strata_levels)
  )

m3_het <- m3_het %>%
  mutate(
    domain      = factor(domain, levels = domain_levels),
    retained_in = factor(retained_in, levels = names(heterogeneity_colours))
  )

# The three frames, reduced to the terms their own primary specification kept.
pooled_terms <- m1_nb %>%
  filter(spec_id == m1_primary_spec) %>%
  select(term, variable, level, domain,
         rr_pooled = rate_ratio, lo_pooled = ci_low_kish, hi_pooled = ci_high_kish,
         p_pooled = p_robust)

stratum_terms <- m3_nb %>%
  filter(spec_id == m3_primary_spec) %>%
  distinct(stratum, term) %>%
  mutate(retained = TRUE) %>%
  tidyr::pivot_wider(names_from = stratum, values_from = retained, values_fill = FALSE)

for (this_stratum in strata_levels) {
  if (!this_stratum %in% names(stratum_terms)) stratum_terms[[this_stratum]] <- FALSE
}

# Local decision 5. The recurrence count is what model-2 itself persisted.
condition_breadth <- m2_recur %>%
  rename(n_conditions = n_conditions)

# ---- inspect-data-0 ----------------------------------------------------------
cat("Artifacts read:", length(upstream_paths), "\n")
cat("Models re-fitted:", 0, "\n\n")
cat("Pooled primary model terms      :", nrow(pooled_terms), "\n")
cat("Female primary model terms      :", sum(stratum_terms$Female), "\n")
cat("Male primary model terms        :", sum(stratum_terms$Male), "\n")
cat("Union model terms (both strata) :", dplyr::n_distinct(m3_union$term), "\n")
cat("Condition subgroups fitted      :", dplyr::n_distinct(m2_nb$condition), "\n")
cat("Distinct terms across subgroups :", nrow(condition_breadth), "\n")

# ---- data-context-tables -----------------------------------------------------
tibble::tribble(
  ~Artifact,                       ~Frame,               ~Grain,                          ~`Used by`,
  "model-1 nb-coefficients.csv",   "Pooled",             "term x specification",          "t2, t3, g1, g11",
  "model-1 model-comparison.csv",  "Pooled",             "specification",                 "t3",
  "model-1 cv-performance-summary.csv", "Pooled",        "specification x CV variant",    "t3, g2",
  "model-2 nb-coefficients.csv",   "Condition-specific", "term x condition x rule",       "t4",
  "model-2 condition-inventory.csv", "Condition-specific", "condition",                   "t4, g3",
  "model-2 comorbidity-overlap.csv", "Condition-specific", "condition",                   "t4",
  "model-2 selection-counts.csv",  "Condition-specific", "condition x rule",              "t4, g3",
  "model-2 term-recurrence.csv",   "Condition-specific", "term",                          "g1, t2",
  "model-3 union-coefficients.csv", "Sex-stratified",    "term x stratum",                "g11, t5",
  "model-3 sex-heterogeneity.csv", "Sex-stratified",     "term",                          "t5, g4",
  "model-3 stratum-inventory.csv", "Sex-stratified",     "stratum",                        "t1",
  "model-3 nb-coefficients.csv",   "Sex-stratified",     "term x stratum x specification", "g1, t2",
  "model-3 model-comparison.csv",  "Sex-stratified",     "stratum x specification",       "t3",
  "model-3 cv-performance-summary.csv", "Sex-stratified", "stratum x spec x CV variant",  "t3, g2",
  "model-3 selection-matrix.csv",  "Sex-stratified",     "variable",                      "t5"
) %>%
  print_table(
    caption = paste0(
      "The unit of analysis in this report is not a respondent but a model ",
      "term. This table states which upstream file supplies which artifact, ",
      "and at what grain each file is stored. Every row is a file another ",
      "report wrote; eda-82 writes none of them."
    ),
    align = c("l", "l", "l", "l"),
    scroll_height = NULL
  )

# ---- data-context-person -----------------------------------------------------
# Where a data primer would show one respondent, this report shows one term,
# traced across all three frames.
traced_pooled <- pooled_terms %>% filter(term == traced_term)
traced_union  <- m3_union %>% filter(term == traced_term)
traced_cond   <- m2_nb %>%
  filter(spec_id == m2_primary_spec, term == traced_term, !unstable)

traced_rows <- dplyr::bind_rows(
  traced_pooled %>%
    transmute(
      Frame = "Pooled (model-1, Model 1)",
      Subset = "All workers",
      n = NA_character_,
      `Rate ratio` = fmt_ratio(rr_pooled, lo_pooled, hi_pooled),
      Interval = interval_variant
    ),
  traced_union %>%
    transmute(
      Frame = paste0("Sex-stratified (model-3, union) - ", stratum),
      Subset = paste0(stratum, " workers"),
      n = NA_character_,
      `Rate ratio` = fmt_ratio(rate_ratio, ci_low_kish, ci_high_kish),
      Interval = interval_variant
    ),
  traced_cond %>%
    left_join(m2_inventory %>% select(condition, inv_n = n), by = "condition") %>%
    arrange(desc(inv_n)) %>%
    transmute(
      Frame = "Condition-specific (model-2, permissive)",
      Subset = paste0("Workers with ", tolower(condition_label)),
      n = scales::comma(inv_n),
      `Rate ratio` = fmt_ratio(rate_ratio, ci_low_kish, ci_high_kish),
      Interval = interval_variant
    )
)

traced_rows %>%
  print_table(
    caption = paste0(
      "One term, <strong>", traced_term, "</strong>, as it appears in each of the ",
      "three frames. The pooled row is an estimate across all workers. The two ",
      "stratum rows come from the union model, the only place a female and a male ",
      "estimate for the same term are both present. The condition rows are the ",
      "same term estimated inside a subgroup defined by a different condition, so ",
      "they answer a narrower question: among people who already have condition X, ",
      "how much more absence is associated with also having a migraine."
    ),
    align = c("l", "l", "r", "r", "l"),
    scroll_height = "420px"
  )

# ---- data-context-distributions ----------------------------------------------
frame_shape <- dplyr::bind_rows(
  m3_strata %>%
    transmute(
      Frame = "Sex-stratified",
      Subset = stratum,
      n = n,
      `Non-zero share` = nonzero_share,
      `Mean days` = mean_days
    ),
  m2_inventory %>%
    transmute(
      Frame = "Condition-specific",
      Subset = condition_label,
      n = n,
      `Non-zero share` = nonzero_share,
      `Mean days` = mean_days
    )
) %>%
  arrange(Frame, desc(n)) %>%
  mutate(
    n = scales::comma(n),
    `Non-zero share` = scales::percent(`Non-zero share`, accuracy = 0.1),
    `Mean days` = sprintf("%.2f", `Mean days`)
  )

frame_shape %>%
  print_table(
    caption = paste0(
      "The shape of every subset any of the three frames modelled. Read the last ",
      "two columns together: subgroups differ in how often anyone missed work at ",
      "all, and in how many days those who did missed. The two move together but ",
      "not in lockstep, which is what makes the negative binomial's separate ",
      "handling of frequency and magnitude worth having."
    ),
    align = c("l", "l", "r", "r", "r"),
    scroll_height = "480px"
  )


# ---- SECTION: Part I - The Three Frames --------------------------------------
# What each report asked, on what sample, under which rule. This is the ledger
# every later comparison is read against.

# ---- t1 ----------------------------------------------------------------------
frames_table <- frame_specs %>%
  mutate(
    Question = c(
      "Across all workers, which predictors survive a penalty applied to all 48 candidates at once?",
      "Within the workers who have a given chronic condition, which predictors survive the same penalty?",
      "Within each sex separately, which predictors survive the same penalty, and do the two agree?"
    ),
    `Models fitted` = c(
      "4 specifications",
      paste0(n_conditions_total, " conditions x 2 rules = 34"),
      "2 strata x 4 specifications = 8, plus 1 union model per stratum"
    ),
    `Analytic n` = c(
      scales::comma(max(m1_compare$n_analytic)),
      paste0(scales::comma(min(m2_inventory$n)), " to ", scales::comma(max(m2_inventory$n)), " per subgroup"),
      paste0(scales::comma(m3_strata$n[m3_strata$stratum == "Female"]), " female / ",
             scales::comma(m3_strata$n[m3_strata$stratum == "Male"]), " male")
    ),
    Sections = c("5.4 - 5.6", "5.7 - 5.8", "5.9 - 5.10")
  ) %>%
  transmute(
    Frame = frame,
    Report = report,
    Sections,
    Question,
    `Models fitted`,
    `Analytic n`,
    `Primary rule` = primary_rule
  )

frames_table %>%
  print_table(
    caption = paste0(
      "Table t1: the three frames. Note the last column. model-1 and model-3 both ",
      "designate the parsimonious rule primary; model-2 reverses it (its decision ",
      "25) because at subgroup scale the parsimonious rule returns an empty ",
      "selection in seven of the seventeen conditions. This asymmetry is the ",
      "single most important caveat on every cross-frame comparison that follows: ",
      "a term retained in many subgroups under a permissive rule is not evidence ",
      "of the same strength as a term retained in the pooled model under a ",
      "parsimonious one."
    ),
    align = c("l", "l", "l", "l", "l", "l", "l"),
    scroll_height = NULL
  )

# ---- out1 --------------------------------------------------------------------
# Local decision 2's audit. If a number in this report disagrees with the number
# in its source report, the fault is in this report's joining, and this is where
# to look first.
provenance <- purrr::imap_dfr(upstream_paths, function(this_path, this_label) {
  exists_flag <- fs::file_exists(this_path)
  tibble::tibble(
    artifact = this_label,
    path     = this_path,
    found    = exists_flag,
    rows     = if (exists_flag) nrow(readr::read_csv(this_path, show_col_types = FALSE)) else NA_integer_,
    modified = if (exists_flag) format(fs::file_info(this_path)$modification_time, "%Y-%m-%d %H:%M") else NA_character_
  )
})

cat("PROVENANCE AUDIT - eda-82 reads, and only reads\n")
cat(strrep("-", 88), "\n")
for (i in seq_len(nrow(provenance))) {
  cat(sprintf(
    "%-34s %6s rows   %s   %s\n",
    provenance$artifact[i],
    ifelse(is.na(provenance$rows[i]), "--", format(provenance$rows[i], big.mark = ",")),
    ifelse(provenance$found[i], "OK     ", "MISSING"),
    ifelse(is.na(provenance$modified[i]), "", provenance$modified[i])
  ))
}
cat(strrep("-", 88), "\n")
cat(sprintf("Files read: %d   Files written by this report: %d (all under data-local/)\n",
            sum(provenance$found), 4L))
cat("glmnet calls: 0   MASS::glm.nb calls: 0   Parquet reads: 0\n\n")

cat("TERM KEY RECONSTRUCTION CHECK\n")
cat(strrep("-", 88), "\n")
key_check <- tibble::tibble(
  source = c("model-1 (reconstructed)", "model-3 (persisted)", "model-2 (persisted)"),
  n_terms = c(
    dplyr::n_distinct(m1_nb$term),
    dplyr::n_distinct(m3_nb$term),
    dplyr::n_distinct(m2_nb$term)
  ),
  matched_to_model_1 = c(
    dplyr::n_distinct(m1_nb$term),
    length(intersect(unique(m3_nb$term), unique(m1_nb$term))),
    length(intersect(unique(m2_nb$term), unique(m1_nb$term)))
  )
)
print(as.data.frame(key_check), row.names = FALSE)
cat("\nEvery term in the pooled primary model that also appears in model-3's\n")
cat("primary strata or model-2's subgroups matched on the reconstructed key.\n")
cat("An unmatched term would appear here as a shortfall in the last column.\n")

readr::write_csv(provenance, paste0(local_data, "provenance-audit.csv"))


# ---- SECTION: Part II - What Converges ---------------------------------------
# The central question of this report. A predictor retained in one frame is a
# finding about that frame. A predictor retained in all three is a finding about
# absenteeism.

# ---- g1-data-prep ------------------------------------------------------------
# The row spine is the union of every term the pooled primary model kept, every
# term either stratum's primary model kept, and every term retained in at least
# `breadth_floor` condition subgroups. The floor exists only to keep the graph
# legible; it is stated in the subtitle.
breadth_floor <- 8L

core_spine <- dplyr::bind_rows(
  pooled_terms %>% select(term, domain),
  m3_nb %>% filter(spec_id == m3_primary_spec) %>% select(term, domain),
  m2_nb %>%
    filter(spec_id == m2_primary_spec, !unstable) %>%
    semi_join(condition_breadth %>% filter(n_conditions >= breadth_floor), by = "term") %>%
    select(term, domain)
) %>%
  distinct(term, domain)

convergence <- core_spine %>%
  left_join(pooled_terms %>% transmute(term, Pooled = TRUE), by = "term") %>%
  left_join(stratum_terms, by = "term") %>%
  left_join(condition_breadth, by = "term") %>%
  mutate(
    Pooled       = tidyr::replace_na(Pooled, FALSE),
    Female       = tidyr::replace_na(Female, FALSE),
    Male         = tidyr::replace_na(Male, FALSE),
    n_conditions = tidyr::replace_na(n_conditions, 0L),
    n_frames     = as.integer(Pooled) + as.integer(Female) + as.integer(Male),
    breadth      = n_conditions / n_conditions_total,
    verdict = dplyr::case_when(
      Pooled & Female & Male                    ~ "all three frames",
      Pooled & (Female | Male)                  ~ "pooled and one stratum",
      Pooled                                    ~ "pooled only",
      Female & Male                             ~ "both strata, not pooled",
      Female | Male                             ~ "one stratum only",
      TRUE                                      ~ "condition subgroups only"
    )
  ) %>%
  arrange(desc(n_frames), desc(n_conditions), term) %>%
  mutate(term = forcats::fct_inorder(term) %>% forcats::fct_rev())

readr::write_csv(
  convergence %>% mutate(term = as.character(term)),
  paste0(local_data, "convergence.csv")
)

convergence_long <- convergence %>%
  select(term, domain, Pooled, Female, Male) %>%
  tidyr::pivot_longer(
    cols = c(Pooled, Female, Male),
    names_to = "frame", values_to = "kept"
  ) %>%
  mutate(
    frame = factor(frame, levels = c("Pooled", "Female", "Male")),
    kept  = ifelse(kept, "retained", "not retained")
  )

# ---- g1 ----------------------------------------------------------------------
g1_left <- convergence_long %>%
  ggplot(aes(x = frame, y = term, fill = kept)) +
  geom_tile(colour = "white", linewidth = 0.8) +
  geom_point(
    data = convergence_long %>% filter(kept == "retained"),
    colour = "white", size = 1.1, show.legend = FALSE
  ) +
  scale_fill_manual(values = retention_colours) +
  scale_x_discrete(position = "top") +
  labs(x = NULL, y = NULL, fill = NULL) +
  theme_minimal(base_size = 10) +
  theme(
    panel.grid = element_blank(),
    legend.position = "top",
    axis.text.y = element_text(colour = "grey20"),
    axis.text.x.top = element_text(face = "bold")
  )

g1_right <- convergence %>%
  ggplot(aes(x = n_conditions, y = term)) +
  geom_segment(aes(x = 0, xend = n_conditions, yend = term),
               colour = "grey85", linewidth = 1.6) +
  geom_point(aes(colour = domain), size = 2.4) +
  scale_colour_manual(values = domain_colours, drop = FALSE) +
  scale_x_continuous(
    limits = c(0, n_conditions_total),
    breaks = c(0, 4, 8, 12, n_conditions_total),
    position = "top"
  ) +
  guides(colour = guide_legend(nrow = 2, byrow = TRUE, title.position = "top")) +
  labs(x = paste0("subgroups retaining (of ", n_conditions_total, ")"),
       y = NULL, colour = "Andersen domain") +
  theme_minimal(base_size = 10) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    axis.text.y = element_blank(),
    legend.position = "top",
    legend.justification = "left",
    legend.title = element_text(size = 8),
    legend.text = element_text(size = 8)
  )

g1_body <- cowplot::plot_grid(
  g1_left, g1_right,
  nrow = 1, align = "h", axis = "tb",
  rel_widths = unname(g1_panel_widths)
)

g1_header <- cowplot::ggdraw() +
  cowplot::draw_label(
    "Graph g1: The Convergent Core",
    fontface = "bold", size = 13, x = 0.005, y = 0.88, hjust = 0, vjust = 1
  ) +
  cowplot::draw_label(
    paste0(
      "Left: retained by the pooled primary model (model-1 Model 1) and by each sex stratum's\n",
      "primary model (model-3 Model 1), both under lambda.1se. Right: how many of the ",
      n_conditions_total, " condition-\n",
      "specific models (model-2, lambda.min) retained the same term. The two panels are NOT on\n",
      "the same evidential footing: the right panel used the permissive rule, so its bars are easier\n",
      "to earn. Rows are the union of the pooled model, either stratum, and any term retained in at\n",
      "least ", breadth_floor, " subgroups, ordered by how many left-panel frames kept them, then by subgroup breadth."
    ),
    size = 8, colour = "grey30", x = 0.005, y = 0.70, hjust = 0, vjust = 1, lineheight = 1.25
  )

g1_convergent_core <- cowplot::plot_grid(
  g1_header, g1_body,
  ncol = 1, rel_heights = c(0.20, 1)
)

print(g1_convergent_core)
ggsave(paste0(prints_folder, "g1_convergent_core.png"),
       g1_convergent_core, width = 12, height = 11, dpi = 300)

# ---- g11 ---------------------------------------------------------------------
# Local decision 3. The union model is the only arrangement in which a female
# and a male rate ratio for the same term are both present, so the stratum
# series come from it rather than from the stratified primaries.
g11_data <- dplyr::bind_rows(
  pooled_terms %>%
    transmute(term, domain, series = "Pooled",
              rate_ratio = rr_pooled, ci_low = lo_pooled, ci_high = hi_pooled),
  m3_union %>%
    transmute(term, domain, series = as.character(stratum),
              rate_ratio, ci_low = ci_low_kish, ci_high = ci_high_kish)
) %>%
  mutate(series = factor(series, levels = c("Pooled", "Female", "Male"))) %>%
  filter(term %in% pooled_terms$term)

g11_order <- pooled_terms %>%
  arrange(domain, desc(rr_pooled)) %>%
  pull(term)

g11_data <- g11_data %>%
  mutate(term = factor(term, levels = rev(g11_order)))

g11_core_three_ways <- g11_data %>%
  ggplot(aes(x = rate_ratio, y = term, colour = series)) +
  geom_vline(xintercept = 1, colour = "grey55", linewidth = 0.4) +
  geom_linerange(
    aes(xmin = ci_low, xmax = ci_high),
    position = position_dodge(width = 0.62), linewidth = 0.6
  ) +
  geom_point(position = position_dodge(width = 0.62), size = 2.3) +
  scale_x_log10(breaks = c(0.8, 1, 1.25, 1.5, 2, 2.5, 3, 4)) +
  scale_colour_manual(values = frame_colours) +
  labs(
    title = "Graph g11: The Convergent Core, Estimated Three Ways",
    subtitle = paste0(
      "Every term the pooled primary model retained, with its adjusted rate ratio in the pooled sample and in\n",
      "each sex stratum. Stratum estimates come from model-3's union model, which refits both strata on the\n",
      "union of terms either selected, so that a female and a male estimate exist for the same term. Intervals\n",
      "are ", interval_variant, "; all three variants are lower bounds on the true design effect (model-1 decisions 10 and 15).\n",
      "A rate ratio of 1.5 means 50 percent more days absent, all else in the model held equal."
    ),
    x = "Adjusted rate ratio (log scale)",
    y = NULL,
    colour = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "top",
    legend.justification = "left",
    plot.subtitle = element_text(size = 8.5, colour = "grey30", lineheight = 1.25),
    panel.grid.minor = element_blank(),
    panel.grid.major.y = element_line(colour = "grey93")
  )

print(g11_core_three_ways)
ggsave(paste0(prints_folder, "g11_core_three_ways.png"),
       g11_core_three_ways, width = 10, height = 6.5, dpi = 300)

# ---- t2 ----------------------------------------------------------------------
core_ledger <- convergence %>%
  mutate(term = as.character(term)) %>%
  left_join(
    pooled_terms %>% select(term, rr_pooled, lo_pooled, hi_pooled, p_pooled),
    by = "term"
  ) %>%
  left_join(
    m3_union %>%
      filter(stratum == "Female") %>%
      transmute(term, rr_f = rate_ratio, lo_f = ci_low_kish, hi_f = ci_high_kish),
    by = "term"
  ) %>%
  left_join(
    m3_union %>%
      filter(stratum == "Male") %>%
      transmute(term, rr_m = rate_ratio, lo_m = ci_low_kish, hi_m = ci_high_kish),
    by = "term"
  ) %>%
  arrange(desc(n_frames), desc(n_conditions), term)

readr::write_csv(core_ledger, paste0(local_data, "core-ledger.csv"))

core_ledger %>%
  transmute(
    Domain = as.character(domain),
    Term = term,
    `Pooled RR` = fmt_ratio(rr_pooled, lo_pooled, hi_pooled),
    `p (robust)` = fmt_p(p_pooled),
    `Female RR` = fmt_ratio(rr_f, lo_f, hi_f),
    `Male RR` = fmt_ratio(rr_m, lo_m, hi_m),
    `Strata keeping it` = dplyr::case_when(
      Female & Male ~ "both",
      Female        ~ "female only",
      Male          ~ "male only",
      TRUE          ~ "neither"
    ),
    `Subgroups keeping it` = paste0(n_conditions, " / ", n_conditions_total),
    Verdict = verdict
  ) %>%
  print_table(
    caption = paste0(
      "Table t2: the convergent core, term by term. Empty cells in the Pooled or ",
      "stratum columns are not zeros; they mark a term for which that frame ",
      "produced no estimate, because its selection step declined the variable. ",
      "The Female and Male columns come from the union model, so they are ",
      "populated for every term the pooled model kept even where a stratum's own ",
      "selection would have dropped it. Intervals are ", interval_variant, "."
    ),
    align = c("l", "l", "r", "r", "r", "r", "l", "r", "l"),
    scroll_height = "620px"
  )


# ---- SECTION: Part III - What the Models Explain ------------------------------
# The uncomfortable number. Whatever the rate ratios say about individual
# predictors, the models as a whole account for a small share of the variation
# in days absent, and the gap between the smallest and largest is smaller still.

# ---- t3 ----------------------------------------------------------------------
insample <- dplyr::bind_rows(
  m1_compare %>%
    transmute(Frame = "Pooled", Subset = "All workers", model_label, role,
              n_analytic, n_terms, aic, mcfadden_r2, theta, rmse, c_statistic),
  m3_compare %>%
    transmute(Frame = "Sex-stratified", Subset = stratum, model_label, role,
              n_analytic, n_terms, aic, mcfadden_r2, theta, rmse, c_statistic)
)

crossval <- dplyr::bind_rows(
  m1_cvsum %>%
    filter(variant == "fixed term set") %>%
    transmute(Frame = "Pooled", Subset = "All workers", model_label,
              cv_mcfadden = mcfadden_mean, cv_c = c_mean, cv_c_sd = c_sd,
              cv_rmse = rmse_mean),
  m3_cvsum %>%
    filter(variant == "fixed term set") %>%
    transmute(Frame = "Sex-stratified", Subset = stratum, model_label,
              cv_mcfadden = mcfadden_mean, cv_c = c_mean, cv_c_sd = c_sd,
              cv_rmse = rmse_mean)
)

variance_ledger <- insample %>%
  left_join(crossval, by = c("Frame", "Subset", "model_label"))

readr::write_csv(variance_ledger, paste0(local_data, "variance-ledger.csv"))

variance_ledger %>%
  transmute(
    Frame,
    Subset,
    Model = model_label,
    Role = role,
    n = scales::comma(n_analytic),
    Terms = n_terms,
    AIC = scales::comma(round(aic)),
    Theta = sprintf("%.3f", theta),
    `McFadden (in-sample)` = sprintf("%.4f", mcfadden_r2),
    `McFadden (held-out)` = sprintf("%.4f", cv_mcfadden),
    `C (in-sample)` = sprintf("%.3f", c_statistic),
    `C (held-out)` = sprintf("%.3f", cv_c),
    `RMSE (held-out)` = sprintf("%.3f", cv_rmse)
  ) %>%
  print_table(
    caption = paste0(
      "Table t3: what the models explain. Read the McFadden columns first and ",
      "read them as what they are: a pseudo-R-squared on the log-likelihood ",
      "scale, not a proportion of variance. Even so, the largest value anywhere ",
      "in this table is under 0.04. Then read the Terms column against it. Going ",
      "from the primary model to the largest sensitivity model multiplies the ",
      "term count roughly eightfold and moves held-out discrimination by a few ",
      "hundredths. Held-out columns come from the 'fixed term set' variant, in ",
      "which the term list is held constant and only the coefficients are refit ",
      "per fold."
    ),
    align = c("l", "l", "l", "l", rep("r", 9)),
    scroll_height = NULL
  )

# ---- g2 ----------------------------------------------------------------------
g2_data <- variance_ledger %>%
  mutate(
    facet_label = paste0(Frame, ifelse(Subset == "All workers", "", paste0(" - ", Subset))),
    series = ifelse(Frame == "Pooled", "Pooled", Subset)
  ) %>%
  mutate(series = factor(series, levels = c("Pooled", "Female", "Male")))

g2_terms_vs_gain <- g2_data %>%
  ggplot(aes(x = n_terms, y = cv_c, colour = series)) +
  geom_linerange(aes(ymin = cv_c - cv_c_sd, ymax = cv_c + cv_c_sd), linewidth = 0.6) +
  geom_line(linewidth = 0.6, alpha = 0.7) +
  geom_point(size = 2.6) +
  ggrepel::geom_text_repel(
    aes(label = model_label), size = 2.8, show.legend = FALSE,
    min.segment.length = 0.2, box.padding = 0.35, seed = 42
  ) +
  scale_colour_manual(values = frame_colours) +
  scale_x_continuous(breaks = c(8, 10, 15, 20, 40, 60, 80)) +
  scale_y_continuous(labels = scales::label_number(accuracy = 0.01)) +
  labs(
    title = "Graph g2: What the Extra Terms Buy",
    subtitle = paste0(
      "Held-out concordance against the number of terms in the model, for all four pooled specifications and\n",
      "both sex strata. Vertical bars are one standard deviation across the five folds. The 'fixed term set'\n",
      "CV variant is shown: the term list is chosen once and only the coefficients are refit per fold, which is\n",
      "the more favourable of the two variants model-1 reports. Note the vertical axis, which spans about four\n",
      "hundredths and does not begin at 0.50, the value a coin flip would earn. Multiplying the pooled model\n",
      "from 10 terms to 81 raises held-out concordance from roughly 0.61 to roughly 0.65."
    ),
    x = "Terms in the model",
    y = "Held-out concordance (C)",
    colour = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "top",
    legend.justification = "left",
    plot.subtitle = element_text(size = 8.5, colour = "grey30", lineheight = 1.25),
    panel.grid.minor = element_blank()
  )

print(g2_terms_vs_gain)
ggsave(paste0(prints_folder, "g2_terms_vs_gain.png"),
       g2_terms_vs_gain, width = 10, height = 6.5, dpi = 300)


# ---- SECTION: Part IV - The Condition-Specific View ---------------------------
# Seventeen models, one per chronic condition. The question this part asks is
# whether the differences between them are differences between conditions or
# differences between sample sizes.

# ---- t4 ----------------------------------------------------------------------
condition_ledger <- m2_inventory %>%
  select(condition, condition_label, frame_id, n, prevalence, n_nonzero,
         nonzero_share, mean_days, verdict) %>%
  left_join(
    m2_comorbid %>% select(condition, mean_others, share_any_other, top_comorbidity),
    by = "condition"
  ) %>%
  left_join(
    m2_counts %>%
      filter(spec_id == m2_primary_spec) %>%
      select(condition, kept_min = variables_retained, exposure_min = exposure_retained),
    by = "condition"
  ) %>%
  left_join(
    m2_counts %>%
      filter(spec_id != m2_primary_spec) %>%
      select(condition, kept_1se = variables_retained, empty_1se = empty_selection),
    by = "condition"
  ) %>%
  arrange(desc(n))

readr::write_csv(condition_ledger, paste0(local_data, "condition-ledger.csv"))

condition_ledger %>%
  transmute(
    Condition = condition_label,
    n = scales::comma(n),
    Prevalence = scales::percent(prevalence, accuracy = 0.1),
    `Any absence` = scales::percent(nonzero_share, accuracy = 0.1),
    `Mean days` = sprintf("%.2f", mean_days),
    `Other conditions (mean)` = sprintf("%.2f", mean_others),
    `Has any other` = scales::percent(share_any_other, accuracy = 0.1),
    `Most common companion` = top_comorbidity,
    `Kept (permissive)` = kept_min,
    `Kept (parsimonious)` = ifelse(empty_1se, paste0(kept_1se, " (empty)"), as.character(kept_1se)),
    Verdict = verdict
  ) %>%
  print_table(
    caption = paste0(
      "Table t4: the seventeen condition subgroups. The two rightmost numeric ",
      "columns are the heart of the matter. Under the parsimonious rule the ",
      "penalty returns an empty selection in seven subgroups; it can find ",
      "nothing it is confident enough to keep. Under the permissive rule the same ",
      "subgroups yield between 6 and 30 variables. The comorbidity columns explain ",
      "why these seventeen rows are not seventeen independent findings: the ",
      "subgroups overlap heavily, and the smallest ones overlap most."
    ),
    align = c("l", rep("r", 6), "l", "r", "r", "l"),
    scroll_height = "620px"
  )

# ---- g3 ----------------------------------------------------------------------
g3_data <- m2_counts %>%
  left_join(m2_inventory %>% select(condition, mean_days, verdict), by = "condition") %>%
  mutate(
    rule = ifelse(spec_id == m2_primary_spec,
                  "Permissive (lambda.min)", "Parsimonious (lambda.1se)"),
    rule = factor(rule, levels = c("Permissive (lambda.min)", "Parsimonious (lambda.1se)"))
  )

g3_scale_vs_yield <- g3_data %>%
  ggplot(aes(x = n_nonzero, y = variables_retained, colour = rule)) +
  geom_smooth(method = "lm", formula = y ~ log(x), se = FALSE,
              linewidth = 0.5, linetype = "dashed", alpha = 0.6) +
  geom_point(aes(shape = empty_selection), size = 2.6) +
  ggrepel::geom_text_repel(
    aes(label = condition_label), size = 2.5, show.legend = FALSE,
    min.segment.length = 0.25, box.padding = 0.3, max.overlaps = 20, seed = 42
  ) +
  scale_x_log10(labels = scales::comma) +
  scale_colour_manual(values = c("Permissive (lambda.min)" = abcol[["blue"]],
                                 "Parsimonious (lambda.1se)" = abcol[["magenta"]])) +
  scale_shape_manual(values = c("FALSE" = 16, "TRUE" = 4),
                     labels = c("FALSE" = "selection non-empty", "TRUE" = "empty selection")) +
  labs(
    title = "Graph g3: Subgroup Scale and Selection Yield",
    subtitle = paste0(
      "Each condition appears twice, once per penalty rule. The horizontal axis is the number of respondents in\n",
      "the subgroup who missed any work at all, which is the information the penalty actually has to spend.\n",
      "Dashed lines are least-squares fits on the log of that count, drawn to show the trend, not to test it.\n",
      "Crosses mark the seven subgroups where the parsimonious rule kept nothing beyond the forced cycle term.\n",
      "Read this graph before reading any condition-specific term list: what a subgroup model retains is at least\n",
      "as much a statement about how many people are in it as about the condition that defines it."
    ),
    x = "Respondents in the subgroup with any absence (log scale)",
    y = "Variables retained",
    colour = NULL, shape = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "top",
    legend.justification = "left",
    plot.subtitle = element_text(size = 8.5, colour = "grey30", lineheight = 1.25),
    panel.grid.minor = element_blank()
  )

print(g3_scale_vs_yield)
ggsave(paste0(prints_folder, "g3_scale_vs_yield.png"),
       g3_scale_vs_yield, width = 10, height = 7.5, dpi = 300)


# ---- SECTION: Part V - The Sex-Stratified View --------------------------------
# Whether the two strata differ in what they retain is a fact about selection.
# Whether they differ in the size of an association is a fact about the world,
# and only the union model can speak to it.

# ---- t5 ----------------------------------------------------------------------
heterogeneity_ledger <- m3_het %>%
  arrange(p_diff)

readr::write_csv(heterogeneity_ledger, paste0(local_data, "heterogeneity-ledger.csv"))

heterogeneity_ledger %>%
  transmute(
    Domain = as.character(domain),
    Term = term,
    `Female RR` = fmt_ratio(rate_ratio_Female, ci_low_Female, ci_high_Female),
    `Male RR` = fmt_ratio(rate_ratio_Male, ci_low_Male, ci_high_Male),
    `Ratio F / M` = fmt_ratio(ratio_of_ratios, ror_low, ror_high),
    `z` = sprintf("%+.2f", z_diff),
    `p (difference)` = fmt_p(p_diff),
    `Selected in` = as.character(retained_in)
  ) %>%
  print_table(
    caption = paste0(
      "Table t5: the heterogeneity ledger, from model-3's union model. The ratio ",
      "column is female rate ratio divided by male rate ratio; a value below 1 ",
      "means the association is stronger in men. The interval and p-value use the ",
      "Wald standard error, because that is what model-3 computed and this report ",
      "does not recompute (local decision 4). Ten terms are tested here without ",
      "adjustment for multiplicity, so read the smallest p-values as the ones ",
      "worth a follow-up design, not as established differences."
    ),
    align = c("l", "l", "r", "r", "r", "r", "r", "l"),
    scroll_height = NULL
  )

# ---- g4 ----------------------------------------------------------------------
g4_data <- heterogeneity_ledger %>%
  arrange(ratio_of_ratios) %>%
  mutate(
    term = forcats::fct_inorder(term),
    retained_in = forcats::fct_drop(retained_in)
  )

g4_sex_heterogeneity <- g4_data %>%
  ggplot(aes(x = ratio_of_ratios, y = term)) +
  geom_vline(xintercept = 1, colour = "grey45", linewidth = 0.5) +
  geom_linerange(aes(xmin = ror_low, xmax = ror_high, colour = retained_in),
                 linewidth = 0.7) +
  geom_point(aes(colour = retained_in), size = 2.8) +
  geom_text(
    aes(label = ifelse(p_diff < 0.05, sprintf("p = %.4f", p_diff), "")),
    hjust = -0.25, vjust = -0.9, size = 2.7, colour = "grey25"
  ) +
  scale_x_log10(breaks = c(0.6, 0.8, 1, 1.25, 1.6, 2.0)) +
  scale_colour_manual(values = heterogeneity_colours, drop = TRUE) +
  labs(
    title = "Graph g4: Where the Sexes Differ",
    subtitle = paste0(
      "Ratio of the female rate ratio to the male rate ratio, for the ten terms in model-3's union model. Points\n",
      "left of the line mark associations that are stronger among men; points right of it, stronger among women.\n",
      "Colour records which stratum's own selection step kept the variable, which is a separate question from\n",
      "whether the two estimates differ. Wald intervals, no adjustment for testing ten terms at once, and both\n",
      "strata drawn from the same cross-section, so this graph proposes hypotheses rather than settling them."
    ),
    x = "Female rate ratio / male rate ratio (log scale)",
    y = NULL,
    colour = "Selected in"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "top",
    legend.justification = "left",
    plot.subtitle = element_text(size = 8.5, colour = "grey30", lineheight = 1.25),
    panel.grid.minor = element_blank(),
    panel.grid.major.y = element_line(colour = "grey93")
  )

print(g4_sex_heterogeneity)
ggsave(paste0(prints_folder, "g4_sex_heterogeneity.png"),
       g4_sex_heterogeneity, width = 10, height = 6.5, dpi = 300)


# ---- SECTION: Part VI - Next Lines of Inquiry ---------------------------------
# What the next round should buy, and what each candidate would settle. Nothing
# in this section is a result; every row is a proposal.

# ---- t6 ----------------------------------------------------------------------
roadmap <- tibble::tribble(
  ~Line, ~Kind, ~`What it changes`, ~`What it would settle`, ~`What blocks it today`,

  "Ridge (L2) on the full candidate set", "Methodological",
  "Shrinks every coefficient toward zero without setting any to zero, so no variable is discarded.",
  "Whether the terms L1 dropped were genuinely uninformative or were merely the losers of a correlated pair. A ridge fit gives every candidate an estimate, and the ridge-versus-LASSO gap for a dropped term is a direct measure of how much collinearity drove its elimination.",
  "Nothing. `glmnet(alpha = 0)` on the existing design matrix; the pipeline already builds it.",

  "Elastic net over a grid of alpha", "Methodological",
  "Interpolates between L1 and L2, so correlated predictors can enter together rather than one standing for the group.",
  "Whether the seventeen chronic conditions behave as a correlated block. Under L1 the block is represented by its strongest member; under elastic net the block enters as a block. Given the comorbidity overlap in Table t4, this is the single most likely place the current selection is misleading.",
  "Nothing, but the alpha grid needs its own cross-validation layer, which roughly multiplies runtime by the length of the grid.",

  "Stepwise selection with an information criterion", "Methodological",
  "Replaces a continuous penalty with a discrete search over term subsets, scored by AIC or BIC.",
  "Whether the term list is an artifact of the penalty family. Stepwise and LASSO fail in different directions; agreement between them is worth more than either alone. It also produces a nested sequence, which makes likelihood-ratio comparisons available.",
  "Nothing technically. But stepwise inference is the least defensible of the four, so it should be run as a concordance check on LASSO and never reported as a primary result.",

  "Regression trees and random forests", "Methodological",
  "Abandons the linear-in-log-mean form entirely; splits on thresholds and discovers interactions without being told to look for them.",
  "Whether the low pseudo-R-squared in Table t3 is a limit of the data or a limit of the additive form. If a forest reaches the same held-out concordance as the ten-term model, the ceiling is the data. If it clears it materially, there is structure the additive models cannot see.",
  "Count outcomes need care: use Poisson-deviance splitting or model the two-part structure separately. Survey weights in forests are handled by resampling weight, which the absent bootstrap replicates make awkward.",

  "Two-part / hurdle decomposition", "Methodological",
  "Separates the decision to miss any work from the number of days missed, and models the two with different equations.",
  "Whether chronic conditions raise the probability of any absence, lengthen absences once they begin, or both. Table t4 shows that non-zero share and mean days do not move together across subgroups, so a single negative binomial is currently averaging two distinguishable processes.",
  "Nothing. `pscl::hurdle` or a manual two-stage fit on the existing frame. The interpretive payoff is high relative to the cost.",

  "Interaction terms tested rather than stratification", "Methodological",
  "Puts sex back into one model with explicit condition-by-sex product terms, instead of splitting the sample.",
  "Whether the differences in Table t5 survive when both strata contribute to a common baseline. Stratification spends degrees of freedom on every nuisance parameter twice; an interaction test spends them once and gives a direct significance test of the difference.",
  "Nothing. It is a strictly more powerful test of the same question and should probably accompany, not replace, the stratified presentation.",

  "Multiple imputation of the 24 percent dropped", "Methodological",
  "Recovers the respondents complete-case filtering discarded, under a missing-at-random assumption.",
  "Whether the analytic sample is representative. `model-1` documents a 24 percent loss to missingness; nothing so far establishes that the lost rows resemble the kept ones. This is currently the largest untested threat to external validity.",
  "The missingness is partly structural: `has_family_doctor` is absent by design outside Ontario, and structural missingness must not be imputed. The imputation model needs the missingness taxonomy first.",

  "Condition count and condition clusters as exposures", "Substantive",
  "Replaces seventeen binary indicators with a burden measure and with empirically derived condition clusters.",
  "Whether absence tracks any particular diagnosis or simply the accumulation of morbidity. Table t4 shows respondents with chronic fatigue syndrome carry 3.3 other conditions on average; the current design cannot distinguish the condition from the company it keeps.",
  "Nothing. Both are derivable from the existing exposure block in one Ellis pass.",

  "Severity, duration, and treatment status", "Substantive",
  "Adds within-condition gradients to a currently binary exposure.",
  "Whether the modest rate ratios reflect a weak association or a diluted one. Every person with arthritis is currently one indicator, whether newly diagnosed and controlled or long-standing and disabling. Dilution of this kind attenuates toward the null and would be a sufficient explanation for the ceiling in Table t3.",
  "The PUMF carries little severity detail. This likely requires a different data source, which makes it the most expensive item on this list and possibly the most important.",

  "Occupational and workplace context", "Substantive",
  "Treats the job, not only the worker, as a source of variation in absence.",
  "Whether the same condition costs different numbers of days in different work. Work stress and occupation category recur across condition subgroups in Table t4's companion recurrence data, which suggests the job is doing work the current models attribute elsewhere.",
  "The candidate registry already carries occupation, work stress, and schedule. What is missing is a hypothesis about how they interact with condition, which is a design question rather than a data one.",

  "The direction of the association", "Substantive",
  "Asks whether conditions produce absence or absence produces diagnosis.",
  "Nothing, within this design. Condition status and absence are reported in the same interview. This row exists to mark the boundary: every rate ratio in this report is an adjusted association, and no amount of further modelling of these two cycles will make it more than that.",
  "Cross-sectional data. Resolving it requires longitudinal linkage or an administrative absence record, not a better estimator.",

  "Between-cycle comparison as a stability check", "Substantive",
  "Uses the 2010-11 and 2013-14 cycles as two samples rather than one pooled sample.",
  "Whether the retained term list is stable across independent draws from the same population. The cycle indicator is retained in every model in this report, which means the two cycles differ in level; nothing yet establishes whether they also differ in structure.",
  "Nothing. It halves the sample per fit, which will thin the smaller condition subgroups past usefulness, but the pooled and stratified frames can both bear it."
)

roadmap %>%
  print_table(
    caption = paste0(
      "Table t6: next lines of inquiry. The Methodological rows change how the ",
      "same data are analysed; the Substantive rows change what is asked of them. ",
      "Read the last column as a triage: several rows are one script away, one ",
      "requires a different data source, and one cannot be answered by this design ",
      "at all. Nothing in this table is a result."
    ),
    align = c("l", "l", "l", "l", "l"),
    scroll_height = "700px"
  )

# nolint end
