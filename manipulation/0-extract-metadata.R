rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014") # Clear the console
cat("Working directory: ", getwd()) # Must be set to Project Directory

# ---- load-packages -----------------------------------------------------------
library(magrittr)
library(dplyr)
library(tidyr)
library(readr)
requireNamespace("haven")
requireNamespace("labelled")
requireNamespace("config")
requireNamespace("fs")

# ---- declare-globals ---------------------------------------------------------
config <- config::get()

path_2010 <- config$raw_data$cchs_2010
path_2014 <- config$raw_data$cchs_2014

output_dir <- "./data-private/derived/"
if (!fs::dir_exists(output_dir)) fs::dir_create(output_dir, recursive = TRUE)

# ---- declare-functions -------------------------------------------------------
# Extract variable-level metadata from a labelled data frame
extract_var_labels <- function(ds, cycle_label) {
  var_labels <- labelled::var_label(ds)
  tibble::tibble(
    variable_name  = names(var_labels),
    variable_label = as.character(var_labels),
    cycle          = cycle_label,
    col_type       = purrr::map_chr(ds, ~class(.x)[1])
  )
}

# Extract value-level labels from a labelled data frame
extract_val_labels <- function(ds, cycle_label) {
  val_labels <- labelled::val_labels(ds)
  # Keep only variables that have value labels defined
  has_labels <- purrr::keep(val_labels, ~length(.x) > 0)
  if (length(has_labels) == 0) {
    return(tibble::tibble(
      variable_name = character(),
      value_code    = numeric(),
      value_label   = character(),
      cycle         = character()
    ))
  }
  purrr::imap_dfr(has_labels, function(labels_vec, var_name) {
    tibble::tibble(
      variable_name = var_name,
      value_code    = as.numeric(labels_vec),
      value_label   = names(labels_vec),
      cycle         = cycle_label
    )
  })
}

cat("\n---- SECTION: Load SPSS files ----------------------------------------\n")
cat("Reading CCHS 2010 from:", path_2010, "\n")
ds_2010 <- haven::read_sav(path_2010, user_na = TRUE)
cat("  Rows:", nrow(ds_2010), "  Cols:", ncol(ds_2010), "\n")

cat("Reading CCHS 2014 from:", path_2014, "\n")
ds_2014 <- haven::read_sav(path_2014, user_na = TRUE)
cat("  Rows:", nrow(ds_2014), "  Cols:", ncol(ds_2014), "\n")

# ---- extract-variable-labels -------------------------------------------------
cat("\n---- SECTION: Extract variable labels --------------------------------\n")
ds_var_2010 <- extract_var_labels(ds_2010, "CCHS_2010")
ds_var_2014 <- extract_var_labels(ds_2014, "CCHS_2014")

ds_var_combined <- dplyr::bind_rows(ds_var_2010, ds_var_2014)

readr::write_csv(
  ds_var_combined,
  file.path(output_dir, "codebook-variable-labels.csv")
)
cat("  Written:", file.path(output_dir, "codebook-variable-labels.csv"),
    "(", nrow(ds_var_combined), "rows )\n")

# ---- extract-value-labels ----------------------------------------------------
cat("\n---- SECTION: Extract value labels -----------------------------------\n")
ds_val_2010 <- extract_val_labels(ds_2010, "CCHS_2010")
ds_val_2014 <- extract_val_labels(ds_2014, "CCHS_2014")

ds_val_combined <- dplyr::bind_rows(ds_val_2010, ds_val_2014)

readr::write_csv(
  ds_val_combined,
  file.path(output_dir, "codebook-value-labels.csv")
)
cat("  Written:", file.path(output_dir, "codebook-value-labels.csv"),
    "(", nrow(ds_val_combined), "rows )\n")

# ---- compare-cycles ----------------------------------------------------------
cat("\n---- SECTION: Cross-cycle variable comparison ------------------------\n")

vars_2010 <- unique(ds_var_2010$variable_name)
vars_2014 <- unique(ds_var_2014$variable_name)

# Variables present in 2010 only
only_2010 <- setdiff(vars_2010, vars_2014)
cat("  Variables in 2010 only:", length(only_2010), "\n")

# Variables present in 2014 only
only_2014 <- setdiff(vars_2014, vars_2010)
cat("  Variables in 2014 only:", length(only_2014), "\n")

# Variables present in both
in_both <- intersect(vars_2010, vars_2014)
cat("  Variables in both cycles:", length(in_both), "\n")

ds_comparison <- tibble::tibble(
  variable_name    = unique(c(vars_2010, vars_2014)),
  in_cchs_2010     = variable_name %in% vars_2010,
  in_cchs_2014     = variable_name %in% vars_2014,
  label_2010       = ds_var_2010$variable_label[match(variable_name, ds_var_2010$variable_name)],
  label_2014       = ds_var_2014$variable_label[match(variable_name, ds_var_2014$variable_name)],
  labels_identical = dplyr::coalesce(label_2010, "") == dplyr::coalesce(label_2014, "")
) %>%
  dplyr::arrange(!in_cchs_2010 | !in_cchs_2014, variable_name)

readr::write_csv(
  ds_comparison,
  file.path(output_dir, "codebook-cycle-comparison.csv")
)
cat("  Written:", file.path(output_dir, "codebook-cycle-comparison.csv"),
    "(", nrow(ds_comparison), "rows )\n")

# ---- spot-check-research-vars ------------------------------------------------
cat("\n---- SECTION: Research variable spot-check ---------------------------\n")
# Verify key research variables appear in both cycles

research_vars <- c(
  # Outcome (LOP)
  "LOP_015", "LOPG040", "LOPG070", "LOPG082", "LOPG083",
  "LOPG084", "LOPG085", "LOPG086", "LOPG100",
  # Chronic conditions (CCC)
  "CCC_031", "CCC_041", "CCC_051", "CCC_061", "CCC_071",
  "CCC_081", "CCC_091", "CCC_101", "CCC_121", "CCC_131",
  "CCC_141", "CCC_151", "CCC_171", "CCC_251", "CCC_261",
  "CCC_280", "CCC_290",
  # Demographics
  "DHHGAGE", "DHH_SEX", "DHHGMS", "DHHGHSZ", "DHHGLE5",
  "DHHG611", "DHHGL12", "DHH_OWN", "GEOGPRV",
  # Socioeconomic
  "INCGHH", "EDUDR04", "EDUDH04", "SDCFIMM", "SDCGRES", "SDCGCGT",
  # Health behaviours
  "HWTGISW", "HWTGBMI", "ALCDTTM", "FVCGTOT", "PACDPAI",
  # General health
  "GEN_01", "GEN_02", "GEN_02B", "GEN_09",
  # Functional limitations
  "ADL_01", "ADL_02", "ADL_03", "ADL_04", "ADL_05", "ADL_06",
  # Survey design
  "WTS_M", "ADM_PRX",
  # Employment / schedule
  "LBSDPFT"
)

ds_spot_check <- tibble::tibble(
  variable_name = research_vars,
  in_cchs_2010  = variable_name %in% vars_2010,
  in_cchs_2014  = variable_name %in% vars_2014,
  status        = dplyr::case_when(
    in_cchs_2010 & in_cchs_2014  ~ "BOTH",
    in_cchs_2010 & !in_cchs_2014 ~ "2010 ONLY",
    !in_cchs_2010 & in_cchs_2014 ~ "2014 ONLY",
    TRUE                          ~ "MISSING FROM BOTH"
  )
)

cat(format(ds_spot_check), "\n")

# Flag any missing
missing_any <- dplyr::filter(ds_spot_check, status != "BOTH")
if (nrow(missing_any) > 0) {
  warning(
    nrow(missing_any), " research variable(s) not present in both cycles:\n",
    paste(missing_any$variable_name, missing_any$status, sep = " -> ", collapse = "\n")
  )
} else {
  cat("\n  All ", nrow(ds_spot_check), " research variables confirmed in both cycles.\n")
}

readr::write_csv(
  ds_spot_check,
  file.path(output_dir, "codebook-research-vars-check.csv")
)
cat("  Written:", file.path(output_dir, "codebook-research-vars-check.csv"), "\n")

cat("\n---- SECTION: Session info -------------------------------------------\n")
sessionInfo()
