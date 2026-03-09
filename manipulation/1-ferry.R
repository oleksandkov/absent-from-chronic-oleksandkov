# nolint  start  # TODO: oleksandkov, read up on linting errors and learn to manage in VSC
#' ---
#' title: "Ferry Lane 1: CCHS Data Transport (2010-2011 & 2013-2014)"
#' author: "Andriy Koval"
#' date: "2026-02-19"
#' ---
#'
#' ============================================================================
#' FERRY PATTERN: Multi-Source Data Transport — Zero Semantic Transformation
#' ============================================================================
#'
#' **Purpose**: Transport raw CCHS PUMF microdata from SPSS (.sav) files into
#' a local SQLite staging database with NO semantic transformation.
#'
#' **Sources**:
#' 1. CCHS 2010-2011 Annual Component PUMF: ./data-private/raw/2026-02-19/CCHS2010_LOP.sav
#' 2. CCHS 2013-2014 Annual Component PUMF: ./data-private/raw/2026-02-19/CCHS_2014_EN_PUMF.sav
#'
#' **Permitted Operations** (technical transport only):
#' - Read SPSS file via haven::read_sav()
#' - Strip SPSS value labels (haven::zap_labels()) for SQLite compatibility
#' - Column name sanitization with janitor::clean_names()
#' - Write to SQLite staging; write Parquet backup
#'
#' **Forbidden** (deferred to Ellis):
#' - Variable selection / white-listing
#' - Column renaming (beyond clean_names sanitization)
#' - Factor recoding or value standardization
#' - Sample exclusions
#' - Derived variable construction
#'
#' **Output**: ./data-private/derived/cchs-1.sqlite
#'   - Table: cchs_2010_raw  (CCHS 2010-2011 annual component, all columns)
#'   - Table: cchs_2014_raw  (CCHS 2013-2014 annual component, all columns)
#'
#' **Next Step**: Ellis lane (manipulation/2-ellis.R) — white-list selection,
#' variable harmonization, factor recoding, outcome construction, sample exclusions
#'
#' ============================================================================


#+ echo=F
# rmarkdown::render(input = "./manipulation/1-ferry.R") # run to knit
# ---- setup -------------------------------------------------------------------
rm(list = ls(all.names = TRUE))
cat("\014")

library(magrittr)
library(dplyr)
requireNamespace("haven")
requireNamespace("janitor")
requireNamespace("DBI")
requireNamespace("RSQLite")
requireNamespace("arrow")
requireNamespace("fs")

script_start <- Sys.time()

# ---- load-sources ------------------------------------------------------------
project_root <- if (dir.exists("scripts") && dir.exists("manipulation")) {
  "."
} else if (dir.exists("../scripts") && dir.exists("../manipulation")) {
  ".."
} else {
  stop("Cannot locate project root. Run from project root or from manipulation/.")
}

# ---- declare-globals ---------------------------------------------------------

# Source files (CCHS PUMF SPSS format)
path_sav_2010 <- file.path(project_root, "data-private", "raw", "2026-02-19", "CCHS2010_LOP.sav")
path_sav_2014 <- file.path(project_root, "data-private", "raw", "2026-02-19", "CCHS_2014_EN_PUMF.sav")

# Output — SQLite (primary staging)
output_sqlite  <- file.path(project_root, "data-private", "derived", "cchs-1.sqlite")
output_dir     <- dirname(output_sqlite)
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Output — Parquet backup
output_parquet_dir <- file.path(project_root, "data-private", "derived", "cchs-1-raw")
if (!fs::dir_exists(output_parquet_dir)) fs::dir_create(output_parquet_dir, recurse = TRUE)

# Table names in SQLite
table_2010 <- "cchs_2010_raw"
table_2014 <- "cchs_2014_raw"

cat("Ferry Lane 1: CCHS Data Transport\n")
cat(strrep("=", 70), "\n")
cat("Source 1:", path_sav_2010, "\n")
cat("Source 2:", path_sav_2014, "\n")
cat("Output:  ", output_sqlite, "\n\n")

# ==============================================================================
# SECTION 1: LOAD FROM SOURCES
# ==============================================================================

# ---- load-from-sav-2010 ------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 1A: LOAD CCHS 2010-2011\n")
cat(strrep("=", 70), "\n")

if (!file.exists(path_sav_2010)) {
  stop("Source file not found: ", path_sav_2010,
  "\nExpected at project path: ",
  file.path(project_root, "data-private", "raw", "2026-02-19", "CCHS2010_LOP.sav"))
}

cat("Reading SPSS file...\n")
ds_2010_raw <- haven::read_sav(path_sav_2010)

# Permitted ferry operations only:
# 1. Strip SPSS value/variable labels (for SQLite compatibility and clean storage)
# 2. Sanitize column names (snake_case, no spaces/special chars)
ds_2010 <- ds_2010_raw %>%
  haven::zap_labels() %>%
  haven::zap_label() %>%
  janitor::clean_names()

cat(sprintf("✓ CCHS 2010-2011 loaded: %s rows, %s columns\n",
            format(nrow(ds_2010), big.mark = ","),
            format(ncol(ds_2010), big.mark = ",")))

# ---- load-from-sav-2014 ------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 1B: LOAD CCHS 2013-2014\n")
cat(strrep("=", 70), "\n")

use_2014_placeholder <- FALSE

if (!file.exists(path_sav_2014)) {
  warning(
    "Source file not found: ", path_sav_2014,
    "\nProceeding with a 0-row placeholder for 2014 using the 2010 schema.",
    "\nExpected at project path: ",
    file.path(project_root, "data-private", "raw", "2026-02-19", "CCHS_2014_EN_PUMF.sav")
  )
  ds_2014 <- ds_2010[0, , drop = FALSE]
  use_2014_placeholder <- TRUE
} else {
  cat("Reading SPSS file...\n")
  ds_2014_raw <- haven::read_sav(path_sav_2014)

  ds_2014 <- ds_2014_raw %>%
    haven::zap_labels() %>%
    haven::zap_label() %>%
    janitor::clean_names()
}

cat(sprintf("✓ CCHS 2013-2014 loaded: %s rows, %s columns\n",
            format(nrow(ds_2014), big.mark = ","),
            format(ncol(ds_2014), big.mark = ",")))
if (use_2014_placeholder) {
  cat("⚠ Using 2014 placeholder (0 rows). Add CCHS_2014_EN_PUMF.sav for full two-cycle processing.\n")
}

# ==============================================================================
# SECTION 2: VALIDATE STRUCTURE
# ==============================================================================

# ---- validate-structure ------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 2: VALIDATE STRUCTURE\n")
cat(strrep("=", 70), "\n")

cols_2010 <- names(ds_2010)
cols_2014 <- names(ds_2014)

cols_common  <- intersect(cols_2010, cols_2014)
cols_2010_only <- setdiff(cols_2010, cols_2014)
cols_2014_only <- setdiff(cols_2014, cols_2010)

cat(sprintf("\nColumn inventory:\n"))
cat(sprintf("  CCHS 2010-2011:  %4d columns\n", length(cols_2010)))
cat(sprintf("  CCHS 2013-2014:  %4d columns\n", length(cols_2014)))
cat(sprintf("  Common (shared): %4d columns\n", length(cols_common)))
cat(sprintf("  2010-only:       %4d columns\n", length(cols_2010_only)))
cat(sprintf("  2014-only:       %4d columns\n", length(cols_2014_only)))

if (length(cols_2010_only) > 0) {
  cat("\n  Columns in 2010 only:\n")
  cat("   ", paste(sort(cols_2010_only), collapse = ", "), "\n")
}

if (length(cols_2014_only) > 0) {
  cat("\n  Columns in 2014 only:\n")
  cat("   ", paste(sort(cols_2014_only), collapse = ", "), "\n")
}

# Check that the variables documented in required-variables-and-sample.md
# are present in both cycles (CONFIRMED variables only)
confirmed_vars <- c(
  # Outcome: LOP module
  "lopg040", "lopg070", "lopg082", "lopg083", "lopg084",
  "lopg085", "lopg086", "lopg100",
  # Sample construction
  "lop_015", "dhhgage", "adm_prx",
  # Survey design
  "wts_m", "geodpmf"
)

cat("\n  Checking CONFIRMED required variables:\n")
for (v in confirmed_vars) {
  in_2010 <- v %in% cols_2010
  in_2014 <- v %in% cols_2014
  status <- if (in_2010 && in_2014) "✓ both" else if (in_2010) "⚠ 2010 only" else if (in_2014) "⚠ 2014 only" else "✗ MISSING"
  cat(sprintf("    %-12s  %s\n", v, status))
}

# ==============================================================================
# SECTION 3: WRITE TO OUTPUT
# ==============================================================================

# ---- save-to-sqlite ----------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 3A: SAVE TO SQLITE\n")
cat(strrep("=", 70), "\n")

# Remove existing file for clean state
if (file.exists(output_sqlite)) {
  file.remove(output_sqlite)
  cat("✓ Removed existing SQLite file\n")
}

cnn <- DBI::dbConnect(RSQLite::SQLite(), output_sqlite)

DBI::dbWriteTable(cnn, table_2010, ds_2010, overwrite = TRUE)
DBI::dbWriteTable(cnn, table_2014, ds_2014, overwrite = TRUE)

# Verify
n_2010_db <- DBI::dbGetQuery(cnn, sprintf("SELECT COUNT(*) AS n FROM %s", table_2010))$n
n_2014_db <- DBI::dbGetQuery(cnn, sprintf("SELECT COUNT(*) AS n FROM %s", table_2014))$n
tables_in_db <- DBI::dbListTables(cnn)
DBI::dbDisconnect(cnn)

cat(sprintf("✓ Table '%s': %s rows written\n",  table_2010, format(n_2010_db, big.mark = ",")))
cat(sprintf("✓ Table '%s': %s rows written\n", table_2014, format(n_2014_db, big.mark = ",")))
cat(sprintf("✓ SQLite file: %s\n", output_sqlite))

# ---- save-to-parquet ---------------------------------------------------------
cat("\n", strrep("=", 70), "\n")
cat("SECTION 3B: SAVE TO PARQUET (Backup)\n")
cat(strrep("=", 70), "\n")

arrow::write_parquet(ds_2010, file.path(output_parquet_dir, "cchs_2010_raw.parquet"))
cat(sprintf("✓ cchs_2010_raw.parquet (%s rows)\n", format(nrow(ds_2010), big.mark = ",")))

arrow::write_parquet(ds_2014, file.path(output_parquet_dir, "cchs_2014_raw.parquet"))
cat(sprintf("✓ cchs_2014_raw.parquet (%s rows)\n", format(nrow(ds_2014), big.mark = ",")))

cat(sprintf("✓ Parquet backup: %s\n", output_parquet_dir))

# ==============================================================================
# SECTION 4: SUMMARY
# ==============================================================================

# ---- summary -----------------------------------------------------------------
duration <- difftime(Sys.time(), script_start, units = "secs")

cat("\n", strrep("=", 70), "\n")
cat("✓ FERRY COMPLETE\n")
cat(strrep("=", 70), "\n\n")

cat("Sources:\n")
cat(sprintf("  CCHS 2010-2011: %s  (%s rows, %s cols)\n",
            basename(path_sav_2010),
            format(nrow(ds_2010), big.mark = ","),
            ncol(ds_2010)))
cat(sprintf("  CCHS 2013-2014: %s  (%s rows, %s cols)\n",
            basename(path_sav_2014),
            format(nrow(ds_2014), big.mark = ","),
            ncol(ds_2014)))

cat(sprintf("\nColumn overlap: %d shared, %d 2010-only, %d 2014-only\n",
            length(cols_common), length(cols_2010_only), length(cols_2014_only)))

cat("\nOutputs:\n")
cat(sprintf("  SQLite:  %s  (%d tables)\n", output_sqlite, length(tables_in_db)))
cat(sprintf("  Parquet: %s  (2 files)\n", output_parquet_dir))

cat(sprintf("\nDuration: %.1f seconds\n", as.numeric(duration)))
cat("\nNext step: Ellis lane (manipulation/2-ellis.R)\n")
cat("  - White-list variable selection\n")
cat("  - Variable harmonization between cycles\n")
cat("  - Outcome construction (days_absent_total, days_absent_chronic)\n")
cat("  - Sequential sample exclusions with flow tracking\n")
cat("  - Factor recoding for all categorical predictors\n")
cat("  - Survey weight adjustment for pooling (÷2)\n")
# nolint end
