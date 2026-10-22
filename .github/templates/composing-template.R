# nolint start
# AI agents must consult ./analysis/eda-1/eda-style-guide.md before making changes to this file.
# Composing Orchestra template — customize all {PLACEHOLDERS} before use.
# Mode: {TYPE} (EDA = explore with open mind | Report = synthesize prior findings)
rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014") # Clear the console
# verify root location
cat("Working directory: ", getwd()) # Must be set to Project Directory
# ---- load-packages -----------------------------------------------------------
library(magrittr)    # pipes
library(ggplot2)     # graphs
library(forcats)     # factors
library(stringr)     # strings
library(lubridate)   # dates
library(labelled)    # labels
library(dplyr)       # data wrangling
library(tidyr)       # data reshaping
library(scales)      # format
library(janitor)     # tidy data
library(testit)      # assertions
library(fs)          # file system
library(arrow)       # parquet I/O

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
base::source("./scripts/common-functions.R")      # project-level
base::source("./scripts/operational-functions.R")  # project-level
# base::source("./scripts/graphing/graph-presets.R") # Alberta Corporate Visual Identity colors

# ---- declare-globals ---------------------------------------------------------

local_root <- "./analysis/{NAME}/"
local_data <- paste0(local_root, "data-local/")

if (!fs::dir_exists(local_data)) { fs::dir_create(local_data) }

data_private_derived <- "./data-private/derived/{NAME}/"
if (!fs::dir_exists(data_private_derived)) { fs::dir_create(data_private_derived) }

prints_folder <- paste0(local_root, "prints/")
if (!fs::dir_exists(prints_folder)) { fs::dir_create(prints_folder) }

# ---- declare-functions -------------------------------------------------------
# base::source(paste0(local_root, "local-functions.R")) # uncomment when needed

# ---- load-data ---------------------------------------------------------------
# Load Ellis parquet outputs
# Adjust paths based on which tables your report-contract.prompt.md specifies

# ds_client <- arrow::read_parquet("./data-private/derived/manipulation/client_roster.parquet")
# ds_support <- arrow::read_parquet("./data-private/derived/manipulation/support_by_year.parquet")
# ds_training <- arrow::read_parquet("./data-private/derived/manipulation/training_by_year.parquet")
# ds_assessment <- arrow::read_parquet("./data-private/derived/manipulation/assessment_by_year.parquet")

message("Data loaded. Uncomment the tables needed for this analysis.")

# ---- tweak-data-0 -----------------------------------------------------------
# General data transformations shared across all graph families

# ---- inspect-data-0 ---------------------------------------------------------
# Basic structure of loaded datasets
# ds_support %>% glimpse()
# ds_support %>% dim()

# ---- inspect-data-1 ---------------------------------------------------------
# Grain verification: confirm the unit of analysis
# ds_support %>%
#   group_by(person_oid, year) %>%
#   summarise(n = n(), .groups = "drop") %>%
#   filter(n > 1) %>%
#   nrow() # should be 0 if grain is person-year

# ---- data-context-tables -----------------------------------------------------
# Which tables and variables this analysis uses (MANDATORY — populate during interview)
# References: contract Data Sources (Primary + Supporting tables)
# Example:
# cat("This analysis uses:\n")
# cat("  - support_by_year.parquet: person-year of financial support (grain: person × year)\n")
# cat("  - client_roster.parquet: person-level demographics and enrollment history\n")

# ---- data-context-person -----------------------------------------------------
# What the data looks like for a representative individual (MANDATORY)
# Show 1-2 people whose data exemplifies the grain of analysis
# Example:
# example_oid <- ds_support %>% count(person_oid) %>% filter(n >= 3, n <= 8) %>% slice_sample(n = 1) %>% pull(person_oid)
# cat("Example person_oid:", example_oid, "\n\n")
# ds_support %>% filter(person_oid == example_oid)
# ds_client %>% filter(person_oid == example_oid)

# ---- data-context-distributions ----------------------------------------------
# Distributions of key variables relevant to this analysis (MANDATORY)
# Show only variables that appear in this report's graphs and tables
# Example:
# ds_support %>% count(program_class1) %>% arrange(desc(n))
# ds_client %>% summarise(age_mean = mean(age), age_sd = sd(age))

# ---- SECTION: Graph Family g1 ------------------------------------------------
# Artifact ID: g1 | Type: Graph | Research Question: {RQ1 from contract}
# Numbering is nominal (creation order); see artifact-naming.instructions.md

# ---- g1-data-prep -----------------------------------------------------------
# Data preparation for first graph family (g1 and any g1* members)
# Research question: {RQ1 from contract}

# g1_data <- ds_support %>%
#   # your data prep here

# ---- g1 --------------------------------------------------------------------
# Level-1 graph: g1 {descriptive title}
# g1_primary <- g1_data %>%
#   ggplot(aes(x = , y = )) +
#   geom_point() +
#   labs(
#     title = "Graph g1: {Descriptive Title}",
#     subtitle = "Data source: {table_name}",
#     x = "",
#     y = ""
#   ) +
#   theme_minimal()
#
# ggsave(paste0(prints_folder, "g1_descriptive_name.png"),
#        g1_primary, width = 8.5, height = 5.5, dpi = 300)
# print(g1_primary)

# ---- SECTION: Graph Family g2 ------------------------------------------------
# Artifact ID: g2 | Type: Graph | Research Question: {RQ2 from contract}
# Hierarchy: g2 (level 1) -> g21, g22 (level 2) -> g211 (level 3 micro-variant)

# ---- g2-data-prep -----------------------------------------------------------
# Data preparation shared by the g2 family
# Research question: {RQ2 from contract}

# ---- g2 --------------------------------------------------------------------
# Level-1 graph: g2 {descriptive title}

# ---- g21 -------------------------------------------------------------------
# Level-2 variant: alternative facet of the g2 family
# g21_plot <- g2_data %>% ggplot(...) + labs(title = "Graph g21: {Descriptive Title}")
# ggsave(paste0(prints_folder, "g21_descriptive_name.png"), g21_plot, width = 8.5, height = 5.5, dpi = 300)
# print(g21_plot)

# ---- g211 ------------------------------------------------------------------
# Level-3 micro-variant: aesthetic test of g21 (e.g., alternative palette)
# Use a micro-variant instead of renumbering when testing a minor change
# g211_plot <- g21_plot + scale_color_brewer(palette = "Set2") +
#   labs(title = "Graph g211: {Descriptive Title} (palette test)")
# ggsave(paste0(prints_folder, "g211_descriptive_name.png"), g211_plot, width = 8.5, height = 5.5, dpi = 300)
# print(g211_plot)

# ---- SECTION: Table Family t1 ------------------------------------------------
# Artifact ID: t1 | Type: Table | {Description}
# Tables are enhanced displays (kable/gt/DT) and form their own families,
# independent of graphs. A raw text print belongs in an Output (out*) instead.

# ---- t1-data-prep -----------------------------------------------------------
# Data preparation for the t1 table family
# t1_summary <- ds_support %>%
#   group_by(program_class1) %>%
#   summarise(n = n(), mean_support = mean(annual_support), sd_support = sd(annual_support))

# ---- t1 --------------------------------------------------------------------
# Level-1 table: summary statistics rendered through an enhanced display
# t1_summary %>%
#   knitr::kable(caption = "Table t1: Summary Statistics by Program Type")

# ---- t11 -------------------------------------------------------------------
# Level-2 table: same family, stratified subset
# t1_summary_sub <- ds_support %>% filter(<subset>) %>%
#   group_by(program_class1) %>% summarise(n = n(), mean_support = mean(annual_support))
# t1_summary_sub %>%
#   knitr::kable(caption = "Table t11: Summary Statistics — {Subset}")

# ---- SECTION: Outputs --------------------------------------------------------
# Artifact ID: out1 | Type: Output | Raw text-based blocks
# Outputs establish understanding relative to the CACHE-manifest, the data
# primer, or method.md. They are RAW TEXT by definition. If you render the same
# content through an enhanced display (kable), classify it as a Table (t*).

# ---- out1 ------------------------------------------------------------------
# Level-1 output: grain proof for the primary table (should print 0)
# cat("Output out1: Grain proof for support_by_year (person x year)\n")
# ds_support %>%
#   group_by(person_oid, year) %>%
#   summarise(n = n(), .groups = "drop") %>%
#   filter(n > 1) %>%
#   nrow()

# ---- out11 -----------------------------------------------------------------
# Level-2 output: structure dump for the same table
# cat("Output out11: Structure of support_by_year\n")
# ds_support %>% dplyr::glimpse()

# ---- save-to-disk -----------------------------------------------------------
# Save any derived datasets for downstream use
# arrow::write_parquet(derived_data, paste0(data_private_derived, "descriptive_name.parquet"))
