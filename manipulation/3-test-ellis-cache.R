rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014") # Clear the console
cat("Working directory: ", getwd()) # Must be set to Project Directory

# Three-way alignment test: Ellis code <-> Disk (SQLite + Parquet) <-> CACHE-manifest
# Registered as run_r_soft in flow.R — failures warn but do not halt the pipeline.

# ---- load-packages -----------------------------------------------------------
library(magrittr)
library(dplyr)
requireNamespace("DBI")
requireNamespace("RSQLite")
requireNamespace("arrow")
requireNamespace("config")

# ---- declare-globals ---------------------------------------------------------
config <- config::get()

path_ellis  <- config$database$cchs$ellis_sqlite
parquet_dir <- config$database$cchs$ellis_parquet_dir

pass_count <- 0L
fail_count <- 0L

# Helper: run a named assertion
assert_test <- function(label, expr) {
  result <- tryCatch(
    {
      stopifnot(expr)
      TRUE
    },
    error = function(e) {
      cat("  FAIL:", label, "\n       ", conditionMessage(e), "\n")
      FALSE
    }
  )
  if (result) {
    cat("  PASS:", label, "\n")
    pass_count <<- pass_count + 1L
  } else {
    fail_count <<- fail_count + 1L
  }
  invisible(result)
}

cat("\n---- SECTION 1: Artifact Existence -----------------------------------\n")
# ---- test-artifacts-exist ----------------------------------------------------
assert_test("Ellis SQLite exists",
  file.exists(path_ellis)
)

assert_test("Parquet directory exists",
  dir.exists(parquet_dir)
)

assert_test("cchs_analytic.parquet exists",
  file.exists(file.path(parquet_dir, "cchs_analytic.parquet"))
)

assert_test("sample_flow.parquet exists",
  file.exists(file.path(parquet_dir, "sample_flow.parquet"))
)

cat("\n---- SECTION 2: Cross-Format Parity (SQLite <-> Parquet) ------------\n")
# ---- test-parity -------------------------------------------------------------
if (file.exists(path_ellis) && file.exists(file.path(parquet_dir, "cchs_analytic.parquet"))) {

  con <- DBI::dbConnect(RSQLite::SQLite(), dbname = path_ellis)
  n_sqlite <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM cchs_analytic")$n
  cols_sqlite <- DBI::dbListFields(con, "cchs_analytic")
  DBI::dbDisconnect(con)

  ds_parquet <- arrow::read_parquet(file.path(parquet_dir, "cchs_analytic.parquet"))
  n_parquet   <- nrow(ds_parquet)
  cols_parquet <- names(ds_parquet)

  assert_test("Row count matches: SQLite == Parquet",
    n_sqlite == n_parquet
  )

  assert_test("Column count matches: SQLite == Parquet",
    length(cols_sqlite) == length(cols_parquet)
  )

  cat("  Row count  | SQLite:", n_sqlite, "| Parquet:", n_parquet, "\n")
  cat("  Col count  | SQLite:", length(cols_sqlite), "| Parquet:", length(cols_parquet), "\n")

} else {
  cat("  SKIP: SQLite or Parquet file not found — skipping parity tests.\n")
}

cat("\n---- SECTION 3: Data Quality Checks ---------------------------------\n")
# ---- test-data-quality -------------------------------------------------------
if (exists("ds_parquet") && nrow(ds_parquet) > 0) {

  # Sample size plausibility (prior analysis: n = 64,141)
  assert_test("Sample size within plausible range (40,000 - 90,000)",
    nrow(ds_parquet) >= 40000L && nrow(ds_parquet) <= 90000L
  )

  # Survey weight: all positive
  assert_test("wts_m_pooled: all positive",
    all(ds_parquet$wts_m_pooled > 0, na.rm = TRUE)
  )

  # Survey weight: no NAs
  assert_test("wts_m_pooled: no missing values",
    sum(is.na(ds_parquet$wts_m_pooled)) == 0L
  )

  # Both cycles represented
  assert_test("Both CCHS cycles present",
    all(c(0L, 1L) %in% ds_parquet$cchs_cycle)
  )

  # Outcome variable: within 0-90
  assert_test("days_absent_total: range 0 to 90",
    min(ds_parquet$days_absent_total, na.rm = TRUE) >= 0 &&
    max(ds_parquet$days_absent_total, na.rm = TRUE) <= 90
  )

  # Outcome variable: no NAs
  assert_test("days_absent_total: no missing values",
    sum(is.na(ds_parquet$days_absent_total)) == 0L
  )

  # Zero proportion: should be roughly 50-85% per prior analysis
  pct_zero <- mean(ds_parquet$days_absent_total == 0) * 100
  cat("  Info: days_absent_total zero proportion:", round(pct_zero, 1), "% (expected ~71%)\n")
  assert_test("days_absent_total: zero proportion between 40% and 90%",
    pct_zero >= 40 && pct_zero <= 90
  )

  # Chronic condition columns: logical (no integer codes remaining)
  cc_cols <- names(ds_parquet)[startsWith(names(ds_parquet), "cc_")]
  assert_test("Chronic condition columns present (at least 10)",
    length(cc_cols) >= 10L
  )
  assert_test("Chronic condition columns are logical",
    all(purrr::map_lgl(ds_parquet[cc_cols], is.logical))
  )

  # Age: dhhgage stores CCHS category codes 2-15 (not year values)
  # Code 2 = 15-17 yrs (lower bound set in Ellis), Code 15 = 75-79 yrs (upper bound)
  assert_test("dhhgage: all codes 2 to 15 (CCHS category codes, not year values)",
    all(ds_parquet$dhhgage >= 2L & ds_parquet$dhhgage <= 15L, na.rm = TRUE)
  )

  # Province factor: 13 levels expected
  assert_test("province factor: 13 levels",
    nlevels(ds_parquet$province) == 13L
  )

  # Cycle proportions approximately equal (±15%)
  cycle_pct <- prop.table(table(ds_parquet$cchs_cycle))
  assert_test("Cycle proportions roughly balanced (40-60%)",
    all(cycle_pct >= 0.40 & cycle_pct <= 0.60)
  )

  # immigration_status: 3-level factor; non-immigrants now captured via SDCFIMM
  # After the SDCFIMM fix, non-NA count should be > 50,000 (near-complete coverage)
  if ("immigration_status" %in% names(ds_parquet)) {
    imm_nonNA <- sum(!is.na(ds_parquet$immigration_status))
    imm_levels <- levels(ds_parquet$immigration_status)
    cat("  Info: immigration_status non-NA n =", imm_nonNA,
        "| levels:", paste(imm_levels, collapse = ", "), "\n")
    assert_test("immigration_status: 3 factor levels",
      length(imm_levels) == 3L
    )
    assert_test("immigration_status: non-NA count > 50,000 (non-immigrants captured)",
      imm_nonNA > 50000L
    )
    assert_test("immigration_status: 'Non-immigrant (Canadian-born)' level present",
      "Non-immigrant (Canadian-born)" %in% imm_levels
    )
  } else {
    cat("  SKIP: immigration_status column not found.\n")
  }

} else {
  cat("  SKIP: Parquet data not available — skipping data quality tests.\n")
}

cat("\n---- SECTION 4: Sample Flow Validation ------------------------------\n")
# ---- test-sample-flow --------------------------------------------------------
if (file.exists(file.path(parquet_dir, "sample_flow.parquet"))) {

  sf <- arrow::read_parquet(file.path(parquet_dir, "sample_flow.parquet"))

  assert_test("sample_flow has at least 5 steps",
    nrow(sf) >= 5L
  )

  assert_test("sample_flow n_remaining is monotonically non-increasing",
    all(diff(sf$n_remaining) <= 0)
  )

  assert_test("sample_flow final n > 0",
    dplyr::last(sf$n_remaining) > 0L
  )

  cat("\n  Sample Flow Table:\n")
  print(sf[, c("step","description","n_remaining","n_excluded")], n = Inf)

} else {
  cat("  SKIP: sample_flow.parquet not found.\n")
}

cat("\n---- Test Summary ----------------------------------------------------\n")
cat("  PASSED:", pass_count, "\n")
cat("  FAILED:", fail_count, "\n")

if (fail_count > 0L) {
  warning(fail_count, " test(s) failed — review output above for details.")
} else {
  cat("  All tests passed.\n")
}
