rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014") # Clear the console
cat("Working directory: ", getwd()) # Must be set to Project Directory

# ---- load-packages -----------------------------------------------------------
if (!requireNamespace("tools", quietly = TRUE)) {
  stop("Package 'tools' is required.")
}

# ---- declare-globals ---------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
frontend_path <- if (length(args) >= 1) args[[1]] else "."
contract_path <- file.path(frontend_path, "publishing-contract.prompt.md")
content_path <- file.path(frontend_path, "content")
site_path <- file.path(frontend_path, "_site")
transform_log_path <- file.path(frontend_path, "TRANSFORM_LOG.md")
report_path <- file.path(frontend_path, "FIDELITY_REPORT.md")

# ---- declare-functions -------------------------------------------------------
status_rank <- function(status) {
  if (identical(status, "fail")) {
    return(3L)
  }
  if (identical(status, "warn")) {
    return(2L)
  }
  1L
}

merge_status <- function(current_status, new_status) {
  if (status_rank(new_status) > status_rank(current_status)) {
    return(new_status)
  }
  current_status
}

check_condition <- function(ok, pass_message, fail_message, fail_is_warn = FALSE) {
  if (isTRUE(ok)) {
    return(list(status = "pass", message = pass_message))
  }
  if (isTRUE(fail_is_warn)) {
    return(list(status = "warn", message = fail_message))
  }
  list(status = "fail", message = fail_message)
}

count_matches <- function(path, pattern) {
  if (!file.exists(path)) {
    return(0L)
  }
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  sum(grepl(pattern, lines, perl = TRUE))
}

# ---- load-data ---------------------------------------------------------------
has_contract <- file.exists(contract_path)
has_content <- dir.exists(content_path)
has_site <- dir.exists(site_path)
has_transform_log <- file.exists(transform_log_path)

protocol_mode_output_mapping <- list(
  VERBATIM = "Direct Line \\(VERBATIM\\)",
  REDIRECT = "Direct Line \\(REDIRECTED\\)",
  ADAPTED = "Technical Bridge",
  COMPOSED = "Narrative Bridge"
)

output_type_counts <- lapply(protocol_mode_output_mapping, function(pattern) {
  count_matches(contract_path, pattern)
})

verbatim_count <- output_type_counts$VERBATIM
redirect_count <- output_type_counts$REDIRECT
adapted_count <- output_type_counts$ADAPTED
composed_count <- output_type_counts$COMPOSED
source_hash_count <- count_matches(contract_path, "source_sha256")
allowed_transform_count <- count_matches(contract_path, "allowed_transforms")

# ---- validate-protocols ------------------------------------------------------
overall_status <- "pass"
checks <- list()

checks[[length(checks) + 1L]] <- check_condition(
  has_contract,
  "Contract file found.",
  "Contract file missing: publishing-contract.prompt.md"
)

checks[[length(checks) + 1L]] <- check_condition(
  has_content,
  "content/ exists.",
  "content/ missing."
)

checks[[length(checks) + 1L]] <- check_condition(
  has_site,
  "_site/ exists.",
  "_site/ missing."
)

checks[[length(checks) + 1L]] <- check_condition(
  !(adapted_count > 0L) || has_transform_log,
  "Transform log requirement satisfied.",
  "TRANSFORM_LOG.md is required when Technical Bridge pages are present."
)

checks[[length(checks) + 1L]] <- check_condition(
  source_hash_count > 0L,
  "Contract includes source_sha256 metadata.",
  "No source_sha256 fields found in contract (recommended for deterministic drift checks).",
  fail_is_warn = TRUE
)

checks[[length(checks) + 1L]] <- check_condition(
  !(adapted_count > 0L) || allowed_transform_count > 0L,
  "allowed_transforms metadata present for Technical Bridge pages.",
  "Technical Bridge pages detected but allowed_transforms metadata was not found.",
  fail_is_warn = TRUE
)

for (chk in checks) {
  overall_status <- merge_status(overall_status, chk$status)
}

# ---- write-report ------------------------------------------------------------
report_lines <- c(
  "# Fidelity Report",
  "",
  paste0("- Overall Status: **", toupper(overall_status), "**"),
  paste0("- Frontend Path: `", normalizePath(frontend_path, winslash = "/", mustWork = FALSE), "`"),
  "- Taxonomy Source: `.github/instructions/publishing-rules.instructions.md` (Section \"Taxonomy and Mapping Registry\" — designates Protocol, Mode, Output Type concepts)",
  "",
  "## Contract Protocol Counts",
  "",
  paste0("- VERBATIM pages: ", verbatim_count),
  paste0("- REDIRECTED pages: ", redirect_count),
  paste0("- ADAPTED pages: ", adapted_count),
  paste0("- COMPOSED pages: ", composed_count),
  "",
  "## Check Results",
  ""
)

for (i in seq_along(checks)) {
  chk <- checks[[i]]
  report_lines <- c(
    report_lines,
    paste0(i, ". [", toupper(chk$status), "] ", chk$message)
  )
}

report_lines <- c(
  report_lines,
  "",
  "## Notes",
  "",
  "- This template script provides baseline structural and metadata checks.",
  "- Extend with page-level hash and transform-diff checks for strict enforcement."
)

writeLines(report_lines, report_path, useBytes = TRUE)

message("FIDELITY_REPORT.md written: ", report_path)
if (identical(overall_status, "fail")) {
  stop("Fidelity audit failed. See FIDELITY_REPORT.md for details.")
}
