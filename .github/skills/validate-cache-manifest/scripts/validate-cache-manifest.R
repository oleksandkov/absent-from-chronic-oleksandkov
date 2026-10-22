# ============================================================================
# validate-cache-manifest.R
# ============================================================================
# Purpose: Extract physical table metadata and compare against CACHE-manifest.md
# Usage: Source this script to produce a validation report
# Dependencies: DBI, odbc, readr, stringr, dplyr, arrow (for parquet mode)
# ============================================================================

# ---- load-packages -----------------------------------------------------------
library(DBI)
library(odbc)
library(readr)
library(stringr)
library(dplyr)

# ---- read-binding ------------------------------------------------------------
config_path <- if (exists("validation_config_path", inherits = FALSE)) {
  validation_config_path
} else {
  file.path(getwd(), "manipulation", "pipeline-validation.dcf")
}

if (!file.exists(config_path)) {
  stop("Validation binding not found: ", config_path)
}

binding <- as.list(read.dcf(config_path, all = TRUE)[1, , drop = FALSE])

get_field <- function(name, default = "") {
  value <- binding[[name]]
  if (is.null(value) || identical(value, "")) default else value
}

dsn <- get_field("dsn")
target_type <- tolower(get_field("target_type", "sqlserver"))
target_path <- get_field("target_path")

is_parquet_target <- identical(target_type, "parquet")

database_label <- if (is_parquet_target) {
  get_field("database_label", "local-filesystem")
} else {
  get_field("database_label", dsn)
}

target_object <- if (exists("target_object_override", inherits = FALSE)) {
  target_object_override
} else {
  get_field("target_object")
}

target_default_label <- if (is_parquet_target) {
  if (target_path == "") "parquet-target" else basename(target_path)
} else {
  target_object
}

target_label <- get_field("target_label", target_default_label)
manifest_path <- file.path(getwd(), get_field("manifest_path", "data-public/metadata/CACHE-manifest.md"))
report_path <- file.path(getwd(), get_field("report_path", "data-private/derived/manifest-validation/validation-report.md"))
exclude_mode <- tolower(get_field("exclude_mode", "none"))
exclude_query <- get_field("exclude_query")
provenance_query <- get_field("provenance_query")

if (is_parquet_target) {
  if (target_path == "") {
    stop("Validation binding must declare target_path when target_type is parquet.")
  }
} else {
  if (dsn == "" || target_object == "") {
    stop("Validation binding must declare both dsn and target_object.")
  }
}

if (!file.exists(manifest_path)) {
  stop("CACHE manifest not found: ", manifest_path)
}

# ---- query-physical-columns --------------------------------------------------
if (is_parquet_target) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Package 'arrow' is required for parquet validation mode.")
  }

  parquet_path <- file.path(getwd(), target_path)
  if (!file.exists(parquet_path)) {
    stop("Parquet target not found: ", parquet_path)
  }

  parquet_dataset <- arrow::open_dataset(parquet_path, format = "parquet")
  parquet_schema <- parquet_dataset$schema

  ds_physical <- data.frame(
    column_name = parquet_schema$names,
    data_type = vapply(parquet_schema$fields, function(f) format(f$type), character(1)),
    max_length = NA_integer_,
    precision = NA_integer_,
    scale = NA_integer_,
    is_nullable = NA_integer_,
    ordinal_position = seq_along(parquet_schema$names),
    stringsAsFactors = FALSE
  )
} else {
  channel <- DBI::dbConnect(odbc::odbc(), dsn = dsn)
  on.exit(DBI::dbDisconnect(channel), add = TRUE)

  sql_columns <- sprintf("
SELECT 
    c.name AS column_name,
    t.name AS data_type,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    c.column_id AS ordinal_position
FROM sys.columns c
JOIN sys.types t ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID('%s')
ORDER BY c.column_id;
", target_object)

  ds_physical <- DBI::dbGetQuery(channel, sql_columns)
}

cat(sprintf("Physical columns: %d\n", nrow(ds_physical)))

# ---- query-excluded-columns --------------------------------------------------
ds_excluded <- data.frame(column_name = character(), stringsAsFactors = FALSE)

if (exclude_mode == "query" && exclude_query != "") {
  if (is_parquet_target) {
    warning("exclude_mode=query is ignored for parquet targets.")
  } else {
    ds_excluded <- DBI::dbGetQuery(channel, exclude_query)
    names(ds_excluded)[1] <- "column_name"
  }
}

cat(sprintf("Excluded columns: %d\n", nrow(ds_excluded)))

# ---- query-provenance --------------------------------------------------------
ds_provenance <- data.frame(
  ellis_version = NA_character_,
  ellis_processed_date = NA_character_,
  source_ferry_date = NA_character_,
  stringsAsFactors = FALSE
)

if (provenance_query != "") {
  if (is_parquet_target) {
    warning("provenance_query is ignored for parquet targets.")
  } else {
    ds_provenance <- tryCatch(
      DBI::dbGetQuery(channel, provenance_query),
      error = function(e) ds_provenance
    )
  }
}

# ---- parse-manifest ----------------------------------------------------------
manifest_text <- readr::read_file(manifest_path)

manifest_lines <- readLines(manifest_path, warn = FALSE)
manifest_columns <- character(0)

i <- 1L
while (i <= length(manifest_lines)) {
  if (grepl("^\\|\\s*Column\\s*\\|", manifest_lines[i], ignore.case = TRUE)) {
    j <- i + 2L
    while (j <= length(manifest_lines) && grepl("^\\|", manifest_lines[j])) {
      parts <- strsplit(manifest_lines[j], "\\|", fixed = FALSE)[[1]]
      if (length(parts) >= 3L) {
        first_cell <- trimws(parts[2])
        token <- stringr::str_extract(first_cell, "[A-Za-z][A-Za-z0-9_]*")
        if (!is.na(token) && nzchar(token)) {
          manifest_columns <- c(manifest_columns, tolower(token))
        }
      }
      j <- j + 1L
    }
    i <- j
  } else {
    i <- i + 1L
  }
}

manifest_columns <- unique(manifest_columns)

cat(sprintf("Documented columns in manifest: %d\n", length(manifest_columns)))

# ---- compute-sets ------------------------------------------------------------
physical_cols <- tolower(ds_physical$column_name)
excluded_cols <- tolower(ds_excluded$column_name)
documentable_cols <- setdiff(physical_cols, excluded_cols)
undocumented <- setdiff(documentable_cols, manifest_columns)
phantom <- setdiff(manifest_columns, documentable_cols)

cat(sprintf("Columns requiring documentation: %d\n", length(documentable_cols)))
cat(sprintf("Undocumented: %d\n", length(undocumented)))
cat(sprintf("Phantom: %d\n", length(phantom)))

# ---- classify-undocumented ---------------------------------------------------
classify_column <- function(col) {
  if (grepl("_flag$|_ind$|_indicator$", col)) return("indicator")
  if (grepl("_date$|_year$|_month$", col)) return("temporal")
  if (grepl("_code$|_oid$|_id$", col)) return("identifier")
  if (grepl("_count$|_cnt$", col)) return("count")
  if (grepl("^source_|^ellis_", col)) return("provenance")
  return("unclassified")
}

ds_undocumented <- data.frame(

  column_name = undocumented,
  data_type = ds_physical$data_type[match(undocumented, physical_cols)],
  classification = vapply(undocumented, classify_column, character(1)),
  stringsAsFactors = FALSE
) |> arrange(classification, column_name)

# ---- build-report -----------------------------------------------------------
coverage <- if (length(documentable_cols) == 0) {
  100
} else {
  round(length(intersect(manifest_columns, documentable_cols)) / length(documentable_cols) * 100, 1)
}

status <- if (length(undocumented) == 0 && length(phantom) == 0) {
  "PASS"
} else if (length(undocumented) + length(phantom) <= 10) {
  "NEEDS ATTENTION"
} else {
  "FAIL"
}

ellis_version <- if ("ellis_version" %in% names(ds_provenance)) ds_provenance$ellis_version[1] else NA_character_
ellis_processed_date <- if ("ellis_processed_date" %in% names(ds_provenance)) ds_provenance$ellis_processed_date[1] else NA_character_
source_ferry_date <- if ("source_ferry_date" %in% names(ds_provenance)) ds_provenance$source_ferry_date[1] else NA_character_

target_reference <- if (is_parquet_target) target_path else target_object
target_reference_label <- if (is_parquet_target) "Path" else "Object"

report_lines <- c(
  "# CACHE Manifest Validation Report",
  "",
  sprintf("**Date**: %s", Sys.Date()),
  sprintf("**Target**: `%s`", target_label),
  sprintf("**Database**: `%s`", database_label),
  sprintf("**%s**: `%s`", target_reference_label, target_reference),
  sprintf("**Ellis Version**: %s", ellis_version),
  sprintf("**Ellis Processed Date**: %s", ellis_processed_date),
  sprintf("**Source Ferry Date**: %s", source_ferry_date),
  "",
  "---",
  "",
  "## Summary",
  "",
  "| Metric | Count |",
  "|---|---|",
  sprintf("| Physical columns (total) | %d |", nrow(ds_physical)),
  sprintf("| Excluded columns | %d |", nrow(ds_excluded)),
  sprintf("| Columns requiring documentation | %d |", length(documentable_cols)),
  sprintf("| Documented in CACHE-manifest | %d |", length(intersect(manifest_columns, documentable_cols))),
  sprintf("| **Coverage** | %s%% |", coverage),
  "",

  sprintf("## Validation Status: **%s**", status),
  "",
  "---",
  "",
  "## Undocumented Columns",
  "",
  sprintf("Count: %d", length(undocumented)),
  ""
)

if (nrow(ds_undocumented) > 0) {
  report_lines <- c(report_lines,
    "| # | Column Name | Data Type | Classification |",
    "|---|-------------|-----------|----------------|"
  )
  for (i in seq_len(nrow(ds_undocumented))) {
    report_lines <- c(report_lines, sprintf(
      "| %d | `%s` | %s | %s |",
      i, ds_undocumented$column_name[i],
      ds_undocumented$data_type[i],
      ds_undocumented$classification[i]
    ))
  }
} else {
  report_lines <- c(report_lines, "*None — all required physical columns are documented.*")
}

report_lines <- c(report_lines, "", "---", "",
  "## Phantom Columns",
  "",
  sprintf("Count: %d", length(phantom)),
  ""
)

if (length(phantom) > 0) {
  report_lines <- c(report_lines,
    "| # | Column Name |",
    "|---|-------------|"
  )
  for (i in seq_along(phantom)) {
    report_lines <- c(report_lines, sprintf("| %d | `%s` |", i, phantom[i]))
  }
} else {
  report_lines <- c(report_lines, "*None — no phantom columns detected.*")
}

report_lines <- c(report_lines, "", "---", "",
  "## Recommended Actions",
  ""
)
if (status == "PASS") {
  report_lines <- c(report_lines, "No action needed. CACHE-manifest is in sync with the bound target.")
} else {
  if (length(undocumented) > 0) {
    report_lines <- c(report_lines, sprintf(
      "1. Add %d undocumented columns to CACHE-manifest.md", length(undocumented)
    ))
  }
  if (length(phantom) > 0) {
    report_lines <- c(report_lines, sprintf(
      "2. Remove %d phantom columns from CACHE-manifest.md", length(phantom)
    ))
  }
  report_lines <- c(report_lines, "3. Re-run validation after manifest edits are complete")
}

# ---- write-report -----------------------------------------------------------
report_dir <- dirname(report_path)
if (!dir.exists(report_dir)) {
  dir.create(report_dir, recursive = TRUE)
}

writeLines(report_lines, report_path)
cat(sprintf("\nReport written to: %s\n", report_path))

# ---- return-results ----------------------------------------------------------
# Return structured results for agent consumption
list(
  status = status,
  coverage_pct = coverage,
  undocumented_count = length(undocumented),
  phantom_count = length(phantom),
  undocumented_columns = ds_undocumented,
  phantom_columns = phantom,
  report_path = report_path,
  target_object = target_reference,
  target_label = target_label
)
