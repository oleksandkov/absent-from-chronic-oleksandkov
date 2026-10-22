rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014") # Clear the console
cat("Working directory: ", getwd()) # Must be set to Project Directory

# ---- load-packages -----------------------------------------------------------
library(magrittr)
library(dplyr)
requireNamespace("haven")
requireNamespace("DBI")
requireNamespace("RSQLite")
requireNamespace("arrow")
requireNamespace("config")
requireNamespace("fs")

# ---- declare-globals ---------------------------------------------------------
config <- config::get()

path_2010  <- config$raw_data$cchs_2010
path_2014  <- config$raw_data$cchs_2014
path_ferry <- config$database$cchs$ferry_sqlite

# Parquet backup directory (mirrors the SQLite tables for offline inspection)
parquet_dir <- "./data-private/derived/cchs-1-ferry/"

report_render_start_time <- Sys.time()

# ---- declare-functions -------------------------------------------------------
# Log transport counts to confirm import integrity
log_transport <- function(label, ds) {
  cat(sprintf("  [%s]  %d rows x %d cols\n", label, nrow(ds), ncol(ds)))
  invisible(ds)
}

cat("\n---- SECTION: Ferry CCHS 2010 ----------------------------------------\n")
# ---- load-cchs-2010 ----------------------------------------------------------
# Full transport: read all variables from the SPSS file.
# haven::read_sav preserves integer codes; haven::zap_labels strips label
# attributes so SQLite can store the data without type conflicts.
cat("Loading CCHS 2010 from:", path_2010, "\n")
ds_2010 <- haven::read_sav(path_2010, user_na = FALSE) %>%
  haven::zap_labels() %>%     # strip haven_labelled → plain numeric/character
  haven::zap_label() %>%      # strip variable-level labels
  haven::zap_formats() %>%    # strip SPSS display formats
  haven::zap_widths()         # strip SPSS column widths

log_transport("2010 raw", ds_2010)

# Confirm LOP module inclusion flag is present (data validation)
stopifnot(
  "DOLOP not found in 2010 data — LOP module may be absent" =
    "DOLOP" %in% names(ds_2010)
)

cat("  CCHS 2010: LOP module inclusion flag (DOLOP) confirmed present.\n")

cat("\n---- SECTION: Ferry CCHS 2014 ----------------------------------------\n")
# ---- load-cchs-2014 ----------------------------------------------------------
cat("Loading CCHS 2014 from:", path_2014, "\n")
ds_2014 <- haven::read_sav(path_2014, user_na = FALSE) %>%
  haven::zap_labels() %>%
  haven::zap_label() %>%
  haven::zap_formats() %>%
  haven::zap_widths()

log_transport("2014 raw", ds_2014)

stopifnot(
  "DOLOP not found in 2014 data — LOP module may be absent" =
    "DOLOP" %in% names(ds_2014)
)

cat("  CCHS 2014: LOP module inclusion flag (DOLOP) confirmed present.\n")

cat("\n---- SECTION: Write to SQLite ferry database -------------------------\n")
# ---- write-to-sqlite ---------------------------------------------------------
# Ensure parent directory exists
if (!fs::dir_exists(dirname(path_ferry))) {
  fs::dir_create(dirname(path_ferry), recursive = TRUE)
}

con <- DBI::dbConnect(RSQLite::SQLite(), dbname = path_ferry)

# Write 2010 — overwrite if script is re-run
DBI::dbWriteTable(con, "cchs_2010", ds_2010, overwrite = TRUE)
cat("  Written table 'cchs_2010':",
    DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM cchs_2010")$n, "rows\n")

# Write 2014 — overwrite if script is re-run
DBI::dbWriteTable(con, "cchs_2014", ds_2014, overwrite = TRUE)
cat("  Written table 'cchs_2014':",
    DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM cchs_2014")$n, "rows\n")

DBI::dbDisconnect(con)
cat("  SQLite ferry database closed.\n")

cat("\n---- SECTION: Parquet backup -----------------------------------------\n")
# ---- write-parquet-backup ----------------------------------------------------
# Parquet files allow column-level inspection without opening SQLite
if (!fs::dir_exists(parquet_dir)) fs::dir_create(parquet_dir, recursive = TRUE)

arrow::write_parquet(ds_2010, file.path(parquet_dir, "cchs_2010.parquet"))
cat("  Written:", file.path(parquet_dir, "cchs_2010.parquet"), "\n")

arrow::write_parquet(ds_2014, file.path(parquet_dir, "cchs_2014.parquet"))
cat("  Written:", file.path(parquet_dir, "cchs_2014.parquet"), "\n")

cat("\n---- SECTION: Transport summary --------------------------------------\n")
# ---- transport-summary -------------------------------------------------------
cat(
  "\n  FERRY COMPLETE\n",
  "  Source 1: CCHS 2010-2011  |  Table: cchs_2010  |  Rows:", nrow(ds_2010),
  " Cols:", ncol(ds_2010), "\n",
  "  Source 2: CCHS 2013-2014  |  Table: cchs_2014  |  Rows:", nrow(ds_2014),
  " Cols:", ncol(ds_2014), "\n",
  "  Destination:", path_ferry, "\n"
)

elapsed <- as.numeric(difftime(Sys.time(), report_render_start_time, units = "secs"))
cat(sprintf("  Elapsed: %.0f seconds\n", elapsed))
