# Purpose: Copy redirect target HTML reports into the rendered _site output.
# Registered as: post-render
# Why needed: REDIRECTED pages forward to standalone HTML artifacts that are outside edited_content.

frontend_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
project_root <- normalizePath(file.path(frontend_root, ".."), winslash = "/", mustWork = TRUE)
site_root <- file.path(frontend_root, "_site")

copy_dir_recursive <- function(src_dir, dst_dir) {
  if (!dir.exists(src_dir)) {
    return(FALSE)
  }
  dir.create(dirname(dst_dir), recursive = TRUE, showWarnings = FALSE)
  if (dir.exists(dst_dir)) {
    unlink(dst_dir, recursive = TRUE, force = TRUE)
  }
  dir.create(dst_dir, recursive = TRUE, showWarnings = FALSE)
  files <- list.files(src_dir, all.files = TRUE, full.names = TRUE, no.. = TRUE)
  if (length(files) == 0) {
    return(TRUE)
  }
  ok <- file.copy(files, dst_dir, recursive = TRUE, overwrite = TRUE)
  all(ok)
}

write_placeholder_html <- function(dest_path, page_label, expected_source) {
  dir.create(dirname(dest_path), recursive = TRUE, showWarnings = FALSE)
  html <- c(
    "<!doctype html>",
    "<html lang=\"en\">",
    "<head>",
    "  <meta charset=\"utf-8\" />",
    paste0("  <title>", page_label, "</title>"),
    "</head>",
    "<body>",
    paste0("  <h1>", page_label, "</h1>"),
    "  <p>The expected standalone HTML source was not found during post-render assembly.</p>",
    paste0("  <p>Expected source: <code>", expected_source, "</code></p>"),
    "  <p>This placeholder was generated to keep site navigation and redirects resolvable.</p>",
    "</body>",
    "</html>"
  )
  writeLines(html, dest_path, useBytes = TRUE)
}

redirect_targets <- list(
  list(
    label = "Univariate Distributions",
    dest_rel = "analysis/data-primer-1/univariate-distributions.html",
    source_candidates = c(
      "analysis/data-primer-1/univariate-distributions.html"
    )
  ),
  list(
    label = "EDA-2",
    dest_rel = "analysis/eda-2/eda-2.html",
    source_candidates = c(
      "analysis/eda-2/eda-2.html",
      "_site/analysis/eda-2/eda-2.html"
    )
  ),
  list(
    label = "EDA-5",
    dest_rel = "analysis/eda-5/eda-5.html",
    source_candidates = c(
      "analysis/eda-5/eda-5.html",
      "_site/analysis/eda-5/eda-5.html"
    )
  ),
  list(
    label = "Binder-2: Table Anatomy",
    dest_rel = "analysis/binder-2/1-table-anatomy.html",
    source_candidates = c(
      "analysis/binder-2/1-table-anatomy.html"
    )
  ),
  list(
    label = "Binder-2: Sociodemographic Fabric",
    dest_rel = "analysis/binder-2/2-sociodemographic-fabric.html",
    source_candidates = c(
      "analysis/binder-2/2-sociodemographic-fabric.html"
    )
  ),
  list(
    label = "Binder-2: Outcome Anatomy",
    dest_rel = "analysis/binder-2/3-outcome-anatomy.html",
    source_candidates = c(
      "analysis/binder-2/3-outcome-anatomy.html"
    )
  ),
  list(
    label = "Binder-2: Raw to Analytical",
    dest_rel = "analysis/binder-2/4-raw-to-analytical.html",
    source_candidates = c(
      "analysis/binder-2/4-raw-to-analytical.html"
    )
  )
)

missing_sources <- character(0)

for (target in redirect_targets) {
  source_abs <- NA_character_

  for (cand in target$source_candidates) {
    cand_abs <- file.path(project_root, cand)
    if (file.exists(cand_abs)) {
      source_abs <- cand_abs
      break
    }
  }

  dest_abs <- file.path(site_root, target$dest_rel)
  dir.create(dirname(dest_abs), recursive = TRUE, showWarnings = FALSE)

  if (is.na(source_abs)) {
    write_placeholder_html(dest_abs, target$label, target$source_candidates[1])
    missing_sources <- c(missing_sources, paste0(target$label, " -> ", target$source_candidates[1]))
    next
  }

  file.copy(source_abs, dest_abs, overwrite = TRUE)

  src_dir <- dirname(source_abs)
  base_name <- tools::file_path_sans_ext(basename(source_abs))

  dep_dir_1 <- file.path(src_dir, paste0(base_name, "_files"))
  dep_dir_1_dest <- file.path(dirname(dest_abs), paste0(base_name, "_files"))
  copy_dir_recursive(dep_dir_1, dep_dir_1_dest)

  dep_dir_2 <- file.path(src_dir, "figure-png-iso")
  dep_dir_2_dest <- file.path(dirname(dest_abs), "figure-png-iso")
  copy_dir_recursive(dep_dir_2, dep_dir_2_dest)
}

# Ensure hero image exists in rendered output if available in edited_content.
hero_src <- file.path(frontend_root, "edited_content", "images", "g01_lop_days_histogram.png")
hero_dest <- file.path(site_root, "edited_content", "images", "g01_lop_days_histogram.png")
if (file.exists(hero_src)) {
  dir.create(dirname(hero_dest), recursive = TRUE, showWarnings = FALSE)
  file.copy(hero_src, hero_dest, overwrite = TRUE)
}

# Emit BUILD_REPORT when redirect sources are missing.
if (length(missing_sources) > 0) {
  report_path <- file.path(frontend_root, "BUILD_REPORT.md")
  report_lines <- c(
    "# Build Report",
    "",
    "## Missing redirect sources",
    "",
    "The following REDIRECTED source HTML files were not found at post-render time.",
    "Placeholder pages were generated in `_site/` to keep navigation resolvable.",
    "",
    paste0("- ", missing_sources),
    "",
    "## Recommended resolution",
    "",
    "- Render missing source HTML reports from their corresponding `.qmd` files, or",
    "- Update the publishing contract to point to available rendered artifacts."
  )
  writeLines(report_lines, report_path, useBytes = TRUE)
}

message("copy-redirect-targets.R: redirect targets processed.")