#' ---
#' title: "Test: Ellis Lane 2 ↔ CACHE-Manifest Alignment (CCHS)"
#' author: "Andriy Koval"
#' date: "2026-02-19"
#' ---
#'
#' ============================================================================
#' PURPOSE: Verify that CACHE-manifest.md accurately describes the artifacts
#' actually produced by manipulation/2-ellis.R (CCHS analytical dataset)
#' ============================================================================
#'
#' THREE-WAY ALIGNMENT CHECK:
#'   1. Ellis script (2-ellis.R)         — the code that produces the artifacts
#'   2. Artifacts on disk                — Parquet files + SQLite database
#'   3. CACHE-manifest.md                — the human-readable documentation
#'
#' Run this after any change to 2-ellis.R or CACHE-manifest.md to ensure
#' the documentation still matches reality.
#'
#' ============================================================================

#+ echo=F
# rmarkdown::render(input = "./manipulation/2-test-ellis-cache.R") # run to knit
# ---- setup -------------------------------------------------------------------
rm(list = ls(all.names = TRUE))
cat("\014")

script_start <- Sys.time()

# ---- load-packages -----------------------------------------------------------
library(magrittr)
library(dplyr)
library(stringr)
requireNamespace("DBI")
requireNamespace("RSQLite")
requireNamespace("arrow")
requireNamespace("checkmate")
requireNamespace("fs")

# ---- declare-globals ---------------------------------------------------------
parquet_dir   <- "./data-private/derived/cchs-2-tables/"
sqlite_path   <- "./data-private/derived/cchs-2.sqlite"
manifest_path <- "./data-public/metadata/CACHE-manifest.md"
ellis_script  <- "./manipulation/2-ellis.R"

# Expected file inventory
expected_parquet_files <- sort(c(
  "cchs_analytical.parquet",
  "sample_flow.parquet"
))

expected_sqlite_tables <- sort(c(
  "cchs_analytical",
  "sample_flow"
))

# Test counters
tests_passed  <- 0L
tests_failed  <- 0L
tests_skipped <- 0L
failures      <- character(0)

# ---- declare-functions -------------------------------------------------------
run_test <- function(test_name, expr, skip_reason = NULL) {
  if (!is.null(skip_reason)) {
    tests_skipped <<- tests_skipped + 1L
    cat("   ⏭️  SKIP:", test_name, "-", skip_reason, "\n")
    return(invisible(FALSE))
  }
  result <- tryCatch({
    eval(expr)
    TRUE
  }, error = function(e) e$message)

  if (isTRUE(result)) {
    tests_passed <<- tests_passed + 1L
    cat("   ✅ PASS:", test_name, "\n")
    invisible(TRUE)
  } else {
    tests_failed <<- tests_failed + 1L
    msg <- if (is.character(result)) result else "Assertion failed"
    failures <<- c(failures, paste0(test_name, ": ", msg))
    cat("   ❌ FAIL:", test_name, "\n")
    cat("         ", msg, "\n")
    invisible(FALSE)
  }
}

# ==============================================================================
cat("\n", strrep("=", 70), "\n")
cat("ELLIS ↔ CACHE-MANIFEST ALIGNMENT TESTS (CCHS)\n")
cat(strrep("=", 70), "\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# ==============================================================================
# SECTION 1: ARTIFACT EXISTENCE
# ==============================================================================

cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("SECTION 1: ARTIFACT EXISTENCE\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n")

run_test("Ellis script exists",   quote(checkmate::assert_file_exists(ellis_script)))
run_test("CACHE-manifest exists", quote(checkmate::assert_file_exists(manifest_path)))
run_test("SQLite database exists",quote(checkmate::assert_file_exists(sqlite_path)))
run_test("Parquet dir exists",    quote(checkmate::assert_directory_exists(parquet_dir)))

actual_parquet_files <- sort(list.files(parquet_dir, pattern = "\\.parquet$"))

run_test("Parquet file count = 2", quote(
  checkmate::assert_true(length(actual_parquet_files) == 2L)
))

run_test("Expected Parquet files present", quote(
  checkmate::assert_set_equal(actual_parquet_files, expected_parquet_files)
))

extra_parquet <- setdiff(actual_parquet_files, expected_parquet_files)
run_test("No unexpected Parquet files", quote(
  checkmate::assert_true(length(extra_parquet) == 0L)
))

# ==============================================================================
# SECTION 2: SQLITE ↔ PARQUET PARITY
# ==============================================================================

cat("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("SECTION 2: SQLITE ↔ PARQUET PARITY\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n")

sqlite_ok <- file.exists(sqlite_path)

if (sqlite_ok) {
  cnn <- DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
  sqlite_tables <- sort(DBI::dbListTables(cnn))

  run_test("SQLite table count = 2", quote(
    checkmate::assert_true(length(sqlite_tables) == 2L)
  ))
  run_test("SQLite table names match expected", quote(
    checkmate::assert_set_equal(sqlite_tables, expected_sqlite_tables)
  ))

  cat("\n   Row parity (SQLite ↔ Parquet):\n")
  for (tbl_name in expected_sqlite_tables) {
    parquet_path <- file.path(parquet_dir, paste0(tbl_name, ".parquet"))
    if (!file.exists(parquet_path)) {
      run_test(paste0("Parity: ", tbl_name, " (Parquet missing)"),
               quote(stop("Parquet file does not exist")))
      next
    }
    sqlite_n  <- DBI::dbGetQuery(cnn, sprintf("SELECT COUNT(*) AS n FROM %s", tbl_name))$n
    parquet_n <- nrow(arrow::read_parquet(parquet_path))
    run_test(
      paste0("Row parity: ", tbl_name,
             " (SQLite=", format(sqlite_n, big.mark=","),
             " ↔ Parquet=", format(parquet_n, big.mark=","), ")"),
      bquote(checkmate::assert_true(.(sqlite_n) == .(parquet_n)))
    )
  }

  cat("\n   Column parity (SQLite ↔ Parquet):\n")
  for (tbl_name in expected_sqlite_tables) {
    parquet_path <- file.path(parquet_dir, paste0(tbl_name, ".parquet"))
    if (!file.exists(parquet_path)) next
    sqlite_cols  <- sort(DBI::dbListFields(cnn, tbl_name))
    parquet_cols <- sort(names(arrow::read_parquet(parquet_path, as_data_frame = FALSE)))
    run_test(
      paste0("Column names: ", tbl_name),
      bquote(checkmate::assert_set_equal(.(sqlite_cols), .(parquet_cols)))
    )
  }

  DBI::dbDisconnect(cnn)
} else {
  run_test("SQLite readable", NULL, skip_reason = "SQLite file missing — run 2-ellis.R first")
}

# ==============================================================================
# SECTION 3: DATA QUALITY CHECKS (cchs_analytical)
# ==============================================================================

cat("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("SECTION 3: DATA QUALITY — cchs_analytical\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n")

parquet_analytical <- file.path(parquet_dir, "cchs_analytical.parquet")

if (file.exists(parquet_analytical)) {
  ds <- arrow::read_parquet(parquet_analytical)

  # Row counts
  n_total  <- nrow(ds)
  n_cycle0 <- sum(ds$cycle == 0L, na.rm = TRUE)
  n_cycle1 <- sum(ds$cycle == 1L, na.rm = TRUE)

  cat(sprintf("   Total rows: %s  (CCHS 2010: %s, CCHS 2014: %s)\n",
              format(n_total, big.mark=","),
              format(n_cycle0, big.mark=","),
              format(n_cycle1, big.mark=",")))

  run_test("Both cycles present", quote(
    checkmate::assert_true(n_cycle0 > 0L && n_cycle1 > 0L)
  ))

  # Final sample size plausibility (reference: ~63,843)
  run_test("Sample size plausible (40k–90k)", quote(
    checkmate::assert_true(n_total >= 40000L && n_total <= 90000L)
  ))

  # Required columns (structural + key predictors)
  required_cols <- c("cycle", "days_absent_total", "days_absent_chronic",
                     "wts_m_pooled", "wts_m_original", "geodpmf",
                     "living_arrangements", "alcohol_type", "bmi_category",
                     "occupation_category", "dhhgle5", "dhhg611")
  run_test("Required columns present", quote(
    checkmate::assert_names(names(ds), must.include = required_cols)
  ))

  # Outcome range
  run_test("days_absent_total: non-negative", quote(
    checkmate::assert_numeric(ds$days_absent_total, lower = 0)
  ))
  run_test("days_absent_total: max ≤ 90", quote(
    checkmate::assert_true(max(ds$days_absent_total, na.rm = TRUE) <= 90)
  ))

  # Weights positive
  run_test("wts_m_pooled: all positive", quote(
    checkmate::assert_numeric(ds$wts_m_pooled, any.missing = FALSE, lower = 0.001)
  ))

  # Weight adjustment: pooled should be exactly half of original
  wt_ratio <- mean(ds$wts_m_pooled, na.rm = TRUE) /
              mean(ds$wts_m_original, na.rm = TRUE)
  run_test("wts_m_pooled = wts_m_original / 2 (ratio ≈ 0.5)", quote(
    checkmate::assert_true(abs(wt_ratio - 0.5) < 0.001)
  ))

  # Factor columns: check critical ones (including formerly-ALL-NA columns now populated)
  factor_check <- c("age_group", "sex", "cycle_f",
                    "living_arrangements", "alcohol_type", "bmi_category",
                    "occupation_category")
  for (fc in intersect(factor_check, names(ds))) {
    run_test(paste0("'", fc, "' is factor with levels"), quote(
      checkmate::assert_factor(ds[[fc]], any.missing = TRUE)
    ))
  }

  # Verify formerly-ALL-NA factors now have non-NA values
  populated_factors <- c("living_arrangements", "alcohol_type", "bmi_category",
                         "occupation_category")
  for (pf in intersect(populated_factors, names(ds))) {
    n_non_na <- sum(!is.na(ds[[pf]]))
    run_test(paste0("'", pf, "' has non-NA values (n=", format(n_non_na, big.mark=","), ")"), 
             bquote(checkmate::assert_true(.(n_non_na) > 0L)))
  }

  # Outcome distribution (soft check: warn if far from reference)
  mean_out <- weighted.mean(ds$days_absent_total, w = ds$wts_m_pooled, na.rm = TRUE)
  pct_zero <- mean(ds$days_absent_total == 0, na.rm = TRUE) * 100
  cat(sprintf("   Weighted mean outcome: %.2f  (reference: ≈1.25)\n", mean_out))
  cat(sprintf("   Percent zeros:         %.1f%%  (reference: ≈70.5%%)\n", pct_zero))
  run_test("Outcome mean plausible (0.5–5.0)", quote(
    checkmate::assert_true(mean_out >= 0.5 && mean_out <= 5.0)
  ))

} else {
  run_test("cchs_analytical.parquet readable", NULL,
           skip_reason = "Parquet file missing — run 2-ellis.R first")
}

# ==============================================================================
# SECTION 4: DATA QUALITY CHECKS (sample_flow)
# ==============================================================================

cat("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("SECTION 4: DATA QUALITY — sample_flow\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n")

parquet_flow <- file.path(parquet_dir, "sample_flow.parquet")

if (file.exists(parquet_flow)) {
  sf <- arrow::read_parquet(parquet_flow)

  run_test("sample_flow has 5 rows (one per exclusion step)", quote(
    checkmate::assert_true(nrow(sf) == 5L)
  ))

  expected_flow_cols <- c("step", "description", "n_remaining", "n_excluded", "pct_remaining")
  run_test("sample_flow has expected columns", quote(
    checkmate::assert_names(names(sf), must.include = expected_flow_cols)
  ))

  # n_remaining should be monotonically decreasing
  run_test("n_remaining is non-increasing", quote(
    checkmate::assert_true(all(diff(sf$n_remaining) <= 0L))
  ))

  # Final n_remaining should match nrow(cchs_analytical)
  if (file.exists(parquet_analytical)) {
    n_analytical <- nrow(arrow::read_parquet(parquet_analytical))
    n_flow_final <- sf$n_remaining[nrow(sf)]
    run_test(
      paste0("sample_flow final n matches cchs_analytical rows (",
             format(n_flow_final, big.mark=","), " = ", format(n_analytical, big.mark=","), ")"),
      bquote(checkmate::assert_true(.(n_flow_final) == .(n_analytical)))
    )
  }

  cat("\n   Sample flow summary:\n")
  print(as.data.frame(sf[, c("step", "n_remaining", "n_excluded")]))

} else {
  run_test("sample_flow.parquet readable", NULL,
           skip_reason = "Parquet file missing — run 2-ellis.R first")
}

# ==============================================================================
# SECTION 5: MANIFEST ALIGNMENT
# ==============================================================================

cat("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("SECTION 5: MANIFEST ↔ ARTIFACTS (CACHE-manifest.md vs disk)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n")

manifest_ok <- file.exists(manifest_path)

if (manifest_ok) {
  manifest_lines <- readLines(manifest_path, warn = FALSE)

  # Check manifest has been populated (not just the empty template)
  is_populated <- any(str_detect(manifest_lines, "cchs_analytical|CCHS"))
  run_test("CACHE-manifest.md has been populated with CCHS content", quote(
    checkmate::assert_true(is_populated)
  ))

  # Check manifest references both tables
  run_test("Manifest references cchs_analytical", quote(
    checkmate::assert_true(any(str_detect(manifest_lines, "cchs_analytical")))
  ))
  run_test("Manifest references sample_flow", quote(
    checkmate::assert_true(any(str_detect(manifest_lines, "sample_flow")))
  ))

} else {
  run_test("CACHE-manifest.md populated",
           NULL,
           skip_reason = "Manifest missing or empty — populate data-public/metadata/CACHE-manifest.md")
}

# ==============================================================================
# SUMMARY
# ==============================================================================

duration <- difftime(Sys.time(), script_start, units = "secs")

cat("\n", strrep("=", 70), "\n")
cat("TEST SUMMARY\n")
cat(strrep("=", 70), "\n\n")

total_run <- tests_passed + tests_failed
cat(sprintf("  ✅ Passed:  %d\n", tests_passed))
cat(sprintf("  ❌ Failed:  %d\n", tests_failed))
cat(sprintf("  ⏭️  Skipped: %d\n", tests_skipped))
cat(sprintf("  Total run: %d\n", total_run))
cat(sprintf("  Duration:  %.1f seconds\n\n", as.numeric(duration)))

if (tests_failed > 0L) {
  cat("  FAILURES:\n")
  for (f in failures) {
    cat("   ❌", f, "\n")
  }
  cat("\n")
  message("⚠️  ", tests_failed, " test(s) FAILED — see output above for details")
} else if (total_run > 0L) {
  cat("  🎉 All tests passed — Ellis output aligns with CACHE-manifest\n")
}
