#' ---
#' title: "Metadata Extraction: CCHS SAV Variable & Value Labels"
#' author: "Andriy Koval"
#' date: "2026-03-20"
#' ---
#'
#' ============================================================================
#' PURPOSE: Extract authoritative variable and value label metadata from the
#'   raw CCHS SPSS (.sav) files. Output is the source-of-truth codebook for
#'   variable coding decisions in Ellis (2-ellis.R) and downstream analysis.
#'
#'   SPSS .sav files embed two kinds of metadata:
#'     - Variable label  : attr(col, "label")   — human description of what the
#'                         variable measures (e.g. "Age - (G)")
#'     - Value labels    : attr(col, "labels")  — named numeric vector mapping
#'                         integer codes to text categories (e.g. 2 = "15 TO 17 YEARS")
#'
#'   This script reads both CCHS cycles WITHOUT stripping labels (no zap_labels),
#'   harvests all label metadata, and writes structured CSVs that can be:
#'     - Inspected in Excel / R to look up any variable's coding scheme
#'     - Diffed across cycles to find where codes changed between 2010 and 2014
#'     - Referenced in comments of 2-ellis.R to cite verified code mappings
#'
#' ============================================================================
#'
#' **Input**:
#'   ./data-private/raw/2026-02-19/CCHS2010_LOP.sav       (2010-2011 cycle)
#'   ./data-private/raw/2026-02-19/CCHS_2014_EN_PUMF.sav  (2013-2014 cycle)
#'
#' **Output** (data-public/derived/cchs-metadata/):
#'   cchs_variable_labels.csv  — one row per (cycle × variable);
#'                               columns: cycle, variable_name, variable_label,
#'                               has_value_labels, n_value_labels
#'
#'   cchs_value_labels.csv     — one row per (cycle × variable × value code);
#'                               columns: cycle, variable_name, value_code,
#'                               value_label
#'
#'   cchs_value_label_diffs.csv — value label differences between cycles;
#'                                empty if labels are identical for a variable
#'
#' **Reference**:
#'   Extract labels for a single variable interactively:
#'     library(haven)
#'     d <- read_sav("data-private/raw/2026-02-19/CCHS2010_LOP.sav", n_max = 1)
#'     attr(d[["DHHGAGE"]], "labels")   # value labels
#'     attr(d[["DHHGAGE"]], "label")    # variable label
#'
#' ============================================================================

#+ echo=F
# rmarkdown::render(input = "./manipulation/extract-metadata.R") # run to knit
# ---- setup -------------------------------------------------------------------
rm(list = ls(all.names = TRUE))
cat("\014")

library(magrittr)
library(dplyr)
requireNamespace("haven")
requireNamespace("fs")

script_start <- Sys.time()
verbose      <- TRUE
vcat         <- function(...) if (verbose) cat(...)

# ---- load-sources ------------------------------------------------------------
project_root <- if (dir.exists("scripts") && dir.exists("manipulation")) {
  "."
} else if (dir.exists("../scripts") && dir.exists("../manipulation")) {
  ".."
} else {
  stop("Cannot locate project root. Run from project root or from manipulation/.")
}

# ---- declare-globals ---------------------------------------------------------

path_sav_2010 <- file.path(project_root, "data-private", "raw", "2026-02-19", "CCHS2010_LOP.sav")
path_sav_2014 <- file.path(project_root, "data-private", "raw", "2026-02-19", "CCHS_2014_EN_PUMF.sav")

output_dir <- file.path(project_root, "data-public", "derived", "cchs-metadata")
if (!fs::dir_exists(output_dir)) fs::dir_create(output_dir, recurse = TRUE)

path_out_variable_labels <- file.path(output_dir, "cchs_variable_labels.csv")
path_out_value_labels    <- file.path(output_dir, "cchs_value_labels.csv")
path_out_diffs           <- file.path(output_dir, "cchs_value_label_diffs.csv")

# ---- declare-functions -------------------------------------------------------

# Extract variable labels (one row per variable) from a haven-labelled data frame.
extract_variable_labels <- function(data, cycle_label) {
  purrr::map_dfr(names(data), function(var) {
    col   <- data[[var]]
    vlabs <- attr(col, "labels")
    tibble::tibble(
      cycle            = cycle_label,
      variable_name    = var,
      variable_label   = attr(col, "label") %||% NA_character_,
      has_value_labels = !is.null(vlabs),
      n_value_labels   = if (!is.null(vlabs)) length(vlabs) else 0L
    )
  })
}

# Extract value labels (one row per variable × code) from a haven-labelled data frame.
extract_value_labels <- function(data, cycle_label) {
  purrr::map_dfr(names(data), function(var) {
    vlabs <- attr(data[[var]], "labels")
    if (is.null(vlabs) || length(vlabs) == 0L) return(NULL)
    tibble::tibble(
      cycle         = cycle_label,
      variable_name = var,
      value_code    = as.numeric(vlabs),
      value_label   = names(vlabs)
    )
  })
}

# Null-coalescing helper (base R analogue of rlang::`%||%`)
`%||%` <- function(x, y) if (!is.null(x) && length(x) > 0L) x else y

# ==============================================================================
# SECTION 1: READ SAV FILES (LABELS PRESERVED)
# ==============================================================================

vcat("\n", strrep("=", 70), "\n")
vcat("SECTION 1: Reading SAV files (labels preserved)\n")
vcat(strrep("=", 70), "\n")

for (path in c(path_sav_2010, path_sav_2014)) {
  if (!file.exists(path)) {
    stop("Source file not found: ", path)
  }
}

vcat("  Loading CCHS 2010-2011 (n_max=1 for metadata only)...\n")
ds_2010_meta <- haven::read_sav(path_sav_2010, n_max = 1L)

vcat("  Loading CCHS 2013-2014 (n_max=1 for metadata only)...\n")
ds_2014_meta <- haven::read_sav(path_sav_2014, n_max = 1L)

vcat(sprintf("  CCHS 2010-2011: %d variables\n", ncol(ds_2010_meta)))
vcat(sprintf("  CCHS 2013-2014: %d variables\n", ncol(ds_2014_meta)))

# ==============================================================================
# SECTION 2: EXTRACT METADATA
# ==============================================================================

vcat("\n", strrep("=", 70), "\n")
vcat("SECTION 2: Extracting metadata\n")
vcat(strrep("=", 70), "\n")

# -- Variable labels -----------------------------------------------------------
vcat("  Extracting variable labels...\n")

var_labels_2010 <- extract_variable_labels(ds_2010_meta, cycle_label = "2010-2011")
var_labels_2014 <- extract_variable_labels(ds_2014_meta, cycle_label = "2013-2014")

var_labels_all <- dplyr::bind_rows(var_labels_2010, var_labels_2014) %>%
  dplyr::arrange(variable_name, cycle)

vcat(sprintf("  Variable label rows: %d (both cycles)\n", nrow(var_labels_all)))

# -- Value labels --------------------------------------------------------------
vcat("  Extracting value labels...\n")

val_labels_2010 <- extract_value_labels(ds_2010_meta, cycle_label = "2010-2011")
val_labels_2014 <- extract_value_labels(ds_2014_meta, cycle_label = "2013-2014")

val_labels_all <- dplyr::bind_rows(val_labels_2010, val_labels_2014) %>%
  dplyr::arrange(variable_name, cycle, value_code)

vcat(sprintf("  Value label rows: %d (both cycles)\n", nrow(val_labels_all)))

# -- Cross-cycle diffs ---------------------------------------------------------
vcat("  Computing cross-cycle value label differences...\n")

# Variables present in both cycles
vars_in_both <- intersect(
  val_labels_2010$variable_name,
  val_labels_2014$variable_name
)

# For each shared variable, compare value label sets between cycles
val_2010_wide <- val_labels_2010 %>%
  dplyr::filter(variable_name %in% vars_in_both) %>%
  dplyr::rename(value_label_2010 = value_label)

val_2014_wide <- val_labels_2014 %>%
  dplyr::filter(variable_name %in% vars_in_both) %>%
  dplyr::rename(value_label_2014 = value_label)

val_diffs <- dplyr::full_join(
  val_2010_wide %>% dplyr::select(-cycle),
  val_2014_wide %>% dplyr::select(-cycle),
  by = c("variable_name", "value_code")
) %>%
  dplyr::filter(
    is.na(value_label_2010) | is.na(value_label_2014) |
    value_label_2010 != value_label_2014
  ) %>%
  dplyr::arrange(variable_name, value_code)

n_diff_vars <- dplyr::n_distinct(val_diffs$variable_name)
vcat(sprintf("  Variables with differing value labels across cycles: %d\n", n_diff_vars))
if (n_diff_vars > 0L) {
  vcat("  ⚠ Differing variables:\n")
  for (v in unique(val_diffs$variable_name)) {
    vcat(sprintf("    - %s\n", v))
  }
}

# Variables only in one cycle
vars_only_2010 <- setdiff(val_labels_2010$variable_name, val_labels_2014$variable_name)
vars_only_2014 <- setdiff(val_labels_2014$variable_name, val_labels_2010$variable_name)

if (length(vars_only_2010) > 0L) {
  vcat(sprintf("  Variables with value labels only in 2010-2011 (%d): %s\n",
    length(vars_only_2010), paste(head(vars_only_2010, 10), collapse = ", ")))
}
if (length(vars_only_2014) > 0L) {
  vcat(sprintf("  Variables with value labels only in 2013-2014 (%d): %s\n",
    length(vars_only_2014), paste(head(vars_only_2014, 10), collapse = ", ")))
}

# ==============================================================================
# SECTION 3: WRITE OUTPUTS
# ==============================================================================

vcat("\n", strrep("=", 70), "\n")
vcat("SECTION 3: Writing output files\n")
vcat(strrep("=", 70), "\n")

utils::write.csv(var_labels_all, path_out_variable_labels, row.names = FALSE)
vcat(sprintf("  ✓ cchs_variable_labels.csv  (%d rows)\n", nrow(var_labels_all)))

utils::write.csv(val_labels_all, path_out_value_labels, row.names = FALSE)
vcat(sprintf("  ✓ cchs_value_labels.csv     (%d rows)\n", nrow(val_labels_all)))

utils::write.csv(val_diffs, path_out_diffs, row.names = FALSE)
vcat(sprintf("  ✓ cchs_value_label_diffs.csv (%d differing rows across %d variables)\n",
             nrow(val_diffs), n_diff_vars))

# ==============================================================================
# SECTION 4: SUMMARY
# ==============================================================================

cat("\n")
cat(strrep("=", 70), "\n")
cat("Metadata extraction complete\n")
cat(strrep("-", 70), "\n")
cat(sprintf("  Variables documented (2010-2011): %d\n", ncol(ds_2010_meta)))
cat(sprintf("  Variables documented (2013-2014): %d\n", ncol(ds_2014_meta)))
cat(sprintf("  Value-labelled variables (2010-2011): %d\n",
    sum(var_labels_2010$has_value_labels)))
cat(sprintf("  Value-labelled variables (2013-2014): %d\n",
    sum(var_labels_2014$has_value_labels)))
cat(sprintf("  Variables with cross-cycle label diffs: %d\n", n_diff_vars))
cat(sprintf("  Outputs written to: %s\n", output_dir))
cat(strrep("=", 70), "\n")

cat(sprintf("\nScript completed in %.1f seconds.\n",
            as.numeric(difftime(Sys.time(), script_start, units = "secs"))))

# ============================================================================
# USAGE NOTE
# ============================================================================
# To look up the coding for any variable during Ellis development:
#
#   library(readr)
#   vals <- read_csv("data-public/derived/cchs-metadata/cchs_value_labels.csv")
#
#   # Look up DHHGAGE in 2010 cycle:
#   vals |> filter(variable_name == "DHHGAGE", cycle == "2010-2011")
#
#   # Check if codes differ between cycles:
#   diffs <- read_csv("data-public/derived/cchs-metadata/cchs_value_label_diffs.csv")
#   diffs |> filter(variable_name == "DHHGAGE")
#
#   # Search by variable label text:
#   read_csv("data-public/derived/cchs-metadata/cchs_variable_labels.csv") |>
#     filter(grepl("age", variable_label, ignore.case = TRUE))
# ============================================================================
