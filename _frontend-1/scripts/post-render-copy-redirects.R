# Purpose: Copy standalone HTML analysis artifacts (and local dependency folders) into _site targets used by REDIRECT pages.
# Registered as: post-render
# Why needed: REDIRECTED pages route to external rendered HTML files that are not built from edited_content/ directly.

frontend_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
repo_root <- normalizePath(file.path(frontend_dir, ".."), winslash = "/", mustWork = TRUE)
site_dir <- file.path(frontend_dir, "_site")

dir.create(site_dir, recursive = TRUE, showWarnings = FALSE)

copy_dir_safe <- function(src_dir, dst_dir) {
  if (!dir.exists(src_dir)) {
    return(FALSE)
  }
  if (dir.exists(dst_dir)) {
    unlink(dst_dir, recursive = TRUE, force = TRUE)
  }
  dir.create(dst_dir, recursive = TRUE, showWarnings = FALSE)

  entries <- list.files(
    src_dir,
    recursive = TRUE,
    all.files = TRUE,
    include.dirs = TRUE,
    no.. = TRUE
  )

  if (length(entries) == 0) {
    return(TRUE)
  }

  for (entry in entries) {
    src_path <- file.path(src_dir, entry)
    dst_path <- file.path(dst_dir, entry)
    if (dir.exists(src_path)) {
      dir.create(dst_path, recursive = TRUE, showWarnings = FALSE)
    } else {
      dir.create(dirname(dst_path), recursive = TRUE, showWarnings = FALSE)
      file.copy(src_path, dst_path, overwrite = TRUE)
    }
  }

  TRUE
}

copy_html_bundle <- function(src_html, dst_html, rewrite = NULL) {
  if (!file.exists(src_html)) {
    message("[post-render] Missing source HTML: ", src_html)
    return(FALSE)
  }

  dir.create(dirname(dst_html), recursive = TRUE, showWarnings = FALSE)

  if (is.null(rewrite)) {
    file.copy(src_html, dst_html, overwrite = TRUE)
  } else {
    txt <- readLines(src_html, warn = FALSE, encoding = "UTF-8")
    txt <- rewrite(txt)
    writeLines(txt, dst_html, useBytes = TRUE)
  }

  src_dir <- dirname(src_html)
  dst_dir <- dirname(dst_html)
  stem <- tools::file_path_sans_ext(basename(src_html))
  assets <- unique(c(paste0(stem, "_files"), paste0(stem, "_cache"), "figure-png-iso", "prints"))

  for (asset in assets) {
    copy_dir_safe(file.path(src_dir, asset), file.path(dst_dir, asset))
  }

  TRUE
}

# Data Primer redirect target
copy_html_bundle(
  file.path(repo_root, "analysis", "data-primer-1", "univariate-distributions.html"),
  file.path(site_dir, "data-primer", "univariate-distributions.html")
)

# Analysis redirect targets
copy_html_bundle(
  file.path(repo_root, "analysis", "eda-2", "eda-2.html"),
  file.path(site_dir, "analysis", "eda-2.html")
)

# EDA-5: contract expects eda-5.html; use fallback if needed
src_eda5 <- file.path(repo_root, "analysis", "eda-5", "eda-5.html")
fallback_eda5 <- file.path(repo_root, "analysis", "eda-5", "eda-5-fixed.html")
dst_eda5 <- file.path(site_dir, "analysis", "eda-5.html")

if (file.exists(src_eda5)) {
  copy_html_bundle(src_eda5, dst_eda5)
} else if (file.exists(fallback_eda5)) {
  copy_html_bundle(fallback_eda5, dst_eda5)

  # If expected dependency folder is missing, provide compatible libs fallback.
  dst_analysis <- dirname(dst_eda5)
  expected_bundle <- file.path(dst_analysis, "eda-5-fixed_files")
  if (!dir.exists(expected_bundle)) {
    src_fallback_libs <- file.path(repo_root, "analysis", "eda-2", "eda-2_files", "libs")
    if (dir.exists(src_fallback_libs)) {
      copy_dir_safe(src_fallback_libs, file.path(expected_bundle, "libs"))
    }
  }
}

copy_html_bundle(
  file.path(repo_root, "analysis", "binder-2", "1-table-anatomy.html"),
  file.path(site_dir, "analysis", "1-table-anatomy.html")
)

copy_html_bundle(
  file.path(repo_root, "analysis", "binder-2", "2-sociodemographic-fabric.html"),
  file.path(site_dir, "analysis", "2-sociodemographic-fabric.html")
)

copy_html_bundle(
  file.path(repo_root, "analysis", "binder-2", "3-outcome-anatomy.html"),
  file.path(site_dir, "analysis", "3-outcome-anatomy.html")
)

copy_html_bundle(
  file.path(repo_root, "analysis", "binder-2", "4-raw-to-analytical.html"),
  file.path(site_dir, "analysis", "4-raw-to-analytical.html")
)
