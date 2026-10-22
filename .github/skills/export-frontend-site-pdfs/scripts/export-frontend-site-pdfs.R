rm(list = ls(all.names = TRUE)) # Clear the memory of variables from previous run.
cat("\014") # Clear the console
cat("Working directory: ", getwd()) # Must be set to Project Directory

# ---- load-packages -----------------------------------------------------------
has_webshot2 <- requireNamespace("webshot2", quietly = TRUE)

# ---- declare-functions -------------------------------------------------------
find_browser_binary <- function() {
  cli_candidates <- c(
    Sys.which("msedge"),
    Sys.which("chrome"),
    Sys.which("chromium"),
    Sys.which("chromium-browser")
  )

  path_candidates <- c(
    "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
    "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
    "C:/Program Files/Google/Chrome/Application/chrome.exe",
    "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe"
  )

  all_candidates <- c(cli_candidates, path_candidates)
  all_candidates <- all_candidates[nzchar(all_candidates)]
  all_candidates <- unique(all_candidates)

  existing <- all_candidates[file.exists(all_candidates)]
  if (length(existing) == 0) {
    return("")
  }

  existing[[1]]
}

extract_meta_refresh_target <- function(html_file) {
  if (!file.exists(html_file)) {
    return("")
  }

  lines <- readLines(html_file, warn = FALSE, encoding = "UTF-8")
  if (length(lines) == 0) {
    return("")
  }

  html_text <- paste(lines, collapse = "\n")
  pattern <- "(?i)<meta[^>]+http-equiv\\s*=\\s*['\"]?refresh['\"]?[^>]+content\\s*=\\s*['\"][^'\"]*url\\s*=\\s*([^'\";>]+)"
  matches <- regexec(pattern, html_text, perl = TRUE)
  capture <- regmatches(html_text, matches)

  if (length(capture[[1]]) < 2) {
    return("")
  }

  trimws(capture[[1]][2])
}

resolve_local_print_source <- function(html_file, site_dir_norm, max_hops = 5L) {
  current <- normalizePath(html_file, winslash = "/", mustWork = TRUE)

  for (hop in seq_len(max_hops)) {
    target <- extract_meta_refresh_target(current)
    if (!nzchar(target)) {
      return(current)
    }

    # Only follow local relative redirects. Leave external targets untouched.
    if (grepl("^(?i)https?://", target, perl = TRUE) || startsWith(target, "//")) {
      return(current)
    }

    resolved <- normalizePath(
      file.path(dirname(current), target),
      winslash = "/",
      mustWork = FALSE
    )

    if (!file.exists(resolved)) {
      return(current)
    }

    # Guard rails: keep resolution inside the selected site tree.
    if (!startsWith(resolved, site_dir_norm)) {
      return(current)
    }

    current <- resolved
  }

  current
}

convert_html_to_pdf <- function(html_file, pdf_file, has_webshot2, browser_binary) {
  if (has_webshot2) {
    webshot2::chrome_print(
      input = html_file,
      output = pdf_file,
      wait = 0.5,
      timeout = 60
    )
    return(invisible(TRUE))
  }

  if (!nzchar(browser_binary)) {
    stop(
      "No conversion backend available. Install R package 'webshot2' or install Microsoft Edge/Google Chrome.",
      call. = FALSE
    )
  }

  html_abs <- normalizePath(html_file, winslash = "/", mustWork = TRUE)
  html_url <- paste0("file:///", html_abs)
  pdf_abs <- normalizePath(pdf_file, winslash = "\\", mustWork = FALSE)

  args <- c(
    "--headless",
    "--disable-gpu",
    "--print-to-pdf-no-header",
    sprintf("--print-to-pdf=%s", pdf_abs),
    html_url
  )

  output_lines <- suppressWarnings(system2(browser_binary, args = args, stdout = TRUE, stderr = TRUE))
  exit_status <- attr(output_lines, "status")
  if (is.null(exit_status)) {
    exit_status <- 0L
  }

  # Headless browser export may complete well after process return on heavy pages.
  for (attempt in seq_len(600)) {
    if (file.exists(pdf_file)) {
      file_size <- file.info(pdf_file)$size
      if (!is.na(file_size) && file_size > 0) {
        break
      }
    }
    Sys.sleep(0.1)
  }

  if (!file.exists(pdf_file)) {
    detail <- paste(output_lines, collapse = " ; ")
    stop(
      sprintf(
        "Browser export failed for '%s'. Exit status: %s. %s",
        html_file,
        as.character(exit_status),
        detail
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

# ---- parse-arguments ---------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  stop(
    "Usage: Rscript .github/skills/export-frontend-site-pdfs/scripts/export-frontend-site-pdfs.R _frontend-N [--force] [--no-clean]",
    call. = FALSE
  )
}

force_render <- FALSE
clean_stale <- TRUE
frontend_args <- character()

for (arg in args) {
  if (identical(arg, "--force")) {
    force_render <- TRUE
  } else if (identical(arg, "--no-clean")) {
    clean_stale <- FALSE
  } else {
    frontend_args <- c(frontend_args, arg)
  }
}

if (length(frontend_args) != 1) {
  stop("Provide exactly one frontend path (for example _frontend-1).", call. = FALSE)
}

# ---- declare-globals ---------------------------------------------------------
frontend_dir <- frontend_args[[1]]
site_dir <- file.path(frontend_dir, "_site")
content_dir <- file.path(frontend_dir, "content")
pdf_dir <- file.path(frontend_dir, "_pdf")
report_path <- file.path(pdf_dir, "export-report.md")
run_started <- Sys.time()
browser_binary <- find_browser_binary()

# ---- validate-inputs ---------------------------------------------------------
if (!dir.exists(frontend_dir)) {
  stop(sprintf("Frontend directory not found: %s", frontend_dir), call. = FALSE)
}

if (!dir.exists(site_dir)) {
  stop(sprintf("Rendered site not found: %s", site_dir), call. = FALSE)
}

if (!dir.exists(content_dir)) {
  stop(sprintf("Content directory not found: %s", content_dir), call. = FALSE)
}

if (!dir.exists(pdf_dir)) {
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
}

# ---- discover-html -----------------------------------------------------------
html_files <- list.files(
  path = site_dir,
  pattern = "\\.[Hh][Tt][Mm][Ll]$",
  recursive = TRUE,
  full.names = TRUE
)

html_files <- sort(normalizePath(html_files, winslash = "/", mustWork = FALSE))
site_dir_norm <- normalizePath(site_dir, winslash = "/", mustWork = TRUE)
content_dir_norm <- normalizePath(content_dir, winslash = "/", mustWork = TRUE)
pdf_dir_norm <- normalizePath(pdf_dir, winslash = "/", mustWork = TRUE)

authored_qmd <- list.files(
  path = content_dir,
  pattern = "\\.[Qq][Mm][Dd]$",
  recursive = TRUE,
  full.names = TRUE
)

authored_qmd <- sort(normalizePath(authored_qmd, winslash = "/", mustWork = FALSE))
authored_html_rel <- character()

if (length(authored_qmd) > 0) {
  authored_rel <- substring(authored_qmd, nchar(content_dir_norm) + 2)
  authored_html_rel <- file.path(
    "content",
    sub("\\.[Qq][Mm][Dd]$", ".html", authored_rel)
  )
  authored_html_rel <- gsub("\\\\", "/", authored_html_rel)
}

if (length(html_files) > 0) {
  site_rel_paths <- substring(html_files, nchar(site_dir_norm) + 2)

  if (length(authored_html_rel) > 0) {
    keep_idx <- site_rel_paths %in% authored_html_rel
    html_files <- html_files[keep_idx]
    rel_paths <- site_rel_paths[keep_idx]
  } else {
    rel_paths <- character()
    html_files <- character()
  }

  pdf_targets <- file.path(pdf_dir_norm, sub("\\.[Hh][Tt][Mm][Ll]$", ".pdf", rel_paths))
} else {
  rel_paths <- character()
  pdf_targets <- character()
}

# ---- cleanup-stale -----------------------------------------------------------
deleted_count <- 0L

if (clean_stale) {
  existing_pdfs <- list.files(
    path = pdf_dir_norm,
    pattern = "\\.[Pp][Dd][Ff]$",
    recursive = TRUE,
    full.names = TRUE
  )

  existing_pdfs <- normalizePath(existing_pdfs, winslash = "/", mustWork = FALSE)
  stale_pdfs <- setdiff(existing_pdfs, pdf_targets)

  if (length(stale_pdfs) > 0) {
    deleted_ok <- file.remove(stale_pdfs)
    deleted_count <- sum(deleted_ok)
  }
}

# ---- render-pdfs -------------------------------------------------------------
converted_count <- 0L
skipped_count <- 0L
failed <- data.frame(
  html = character(),
  pdf = character(),
  error = character(),
  stringsAsFactors = FALSE
)

for (i in seq_along(html_files)) {
  html_file <- html_files[[i]]
  pdf_file <- pdf_targets[[i]]

  dir.create(dirname(pdf_file), recursive = TRUE, showWarnings = FALSE)

  should_render <- force_render || !file.exists(pdf_file)
  if (!should_render) {
    html_mtime <- file.info(html_file)$mtime
    pdf_mtime <- file.info(pdf_file)$mtime
    should_render <- isTRUE(html_mtime > pdf_mtime)
  }

  if (!should_render) {
    skipped_count <- skipped_count + 1L
    next
  }

  if (file.exists(pdf_file)) {
    file.remove(pdf_file)
  }

  source_file <- resolve_local_print_source(
    html_file = html_file,
    site_dir_norm = site_dir_norm
  )

  ok <- TRUE
  err_msg <- ""

  tryCatch(
    convert_html_to_pdf(
      html_file = source_file,
      pdf_file = pdf_file,
      has_webshot2 = has_webshot2,
      browser_binary = browser_binary
    ),
    error = function(e) {
      ok <<- FALSE
      err_msg <<- conditionMessage(e)
    }
  )

  if (ok) {
    converted_count <- converted_count + 1L
  } else {
    failed <- rbind(
      failed,
      data.frame(html = html_file, pdf = pdf_file, error = err_msg, stringsAsFactors = FALSE)
    )
  }
}

# ---- write-report ------------------------------------------------------------
run_finished <- Sys.time()
summary_lines <- c(
  "# Frontend Site PDF Export Report",
  "",
  sprintf("- Run started: %s", format(run_started, "%Y-%m-%d %H:%M:%S %Z")),
  sprintf("- Run finished: %s", format(run_finished, "%Y-%m-%d %H:%M:%S %Z")),
  sprintf("- Frontend: `%s`", frontend_dir),
  sprintf("- Source site: `%s`", site_dir),
  sprintf("- PDF output: `%s`", pdf_dir),
  sprintf("- Backend: `%s`", if (has_webshot2) "webshot2::chrome_print" else browser_binary),
  sprintf("- Force render: `%s`", tolower(as.character(force_render))),
  sprintf("- Clean stale PDFs: `%s`", tolower(as.character(clean_stale))),
  "",
  "## Summary",
  "",
  sprintf("- HTML pages found: %d", length(html_files)),
  sprintf("- PDFs converted: %d", converted_count),
  sprintf("- PDFs skipped: %d", skipped_count),
  sprintf("- Stale PDFs deleted: %d", deleted_count),
  sprintf("- Conversion failures: %d", nrow(failed)),
  ""
)

if (nrow(failed) > 0) {
  failure_lines <- c(
    "## Failures",
    "",
    "| HTML | PDF | Error |",
    "|------|-----|-------|"
  )

  for (i in seq_len(nrow(failed))) {
    failure_lines <- c(
      failure_lines,
      sprintf(
        "| `%s` | `%s` | %s |",
        failed$html[[i]],
        failed$pdf[[i]],
        gsub("\\|", "\\\\|", failed$error[[i]])
      )
    )
  }

  summary_lines <- c(summary_lines, "", failure_lines, "")
}

writeLines(summary_lines, con = report_path, useBytes = TRUE)

# ---- return-summary ----------------------------------------------------------
message(sprintf("Frontend: %s", frontend_dir))
message(sprintf("HTML pages found: %d", length(html_files)))
message(sprintf("PDFs converted: %d", converted_count))
message(sprintf("PDFs skipped: %d", skipped_count))
message(sprintf("Stale PDFs deleted: %d", deleted_count))
message(sprintf("Failures: %d", nrow(failed)))
message(sprintf("Report: %s", report_path))

if (nrow(failed) > 0) {
  message("Some conversions failed. Review export-report.md for details.")
}
