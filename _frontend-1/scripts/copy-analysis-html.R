# Purpose: Copy redirect target HTML files into _site/ so that meta-refresh stubs resolve
# Registered as: post-render
# Why needed: REDIRECTED pages point to standalone HTML reports that live outside
#   content/. The self-containment rule applies to content/ as a source
#   tree; the rendered _site/ needs these HTML targets placed alongside the stubs.

# Determine project root (this script runs from _frontend-1/)
project_root <- normalizePath(file.path(getwd(), ".."), winslash = "/")
site_dir <- file.path(getwd(), "_site")

# Helper: copy HTML to _site at the correct relative path
copy_html <- function(source_rel, dest_subdir, dest_filename) {
  src <- file.path(project_root, source_rel)
  dest_dir <- file.path(site_dir, "content", dest_subdir)
  if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE)
  dest <- file.path(dest_dir, dest_filename)
  if (file.exists(src)) {
    file.copy(src, dest, overwrite = TRUE)
    message("Copied: ", src, " -> ", dest)
  } else {
    warning("Source not found: ", src)
  }
}

# Data Primer
copy_html(
  "analysis/data-primer-1/univariate-distributions.html",
  "data-primer",
  "univariate-distributions.html"
)

# Outcome reports
copy_html("analysis/eda-5/eda-5.html", "outcome", "eda-5.html")
copy_html("analysis/eda-71/eda-71.html", "outcome", "eda-71.html")
copy_html("analysis/eda-72/eda-72.html", "outcome", "eda-72.html")

# Predictor reports
copy_html("analysis/eda-61/eda-61.html", "predictors", "eda-61.html")
copy_html("analysis/eda-62/eda-62.html", "predictors", "eda-62.html")
copy_html("analysis/eda-63/eda-63.html", "predictors", "eda-63.html")
copy_html("analysis/eda-64/eda-64.html", "predictors", "eda-64.html")
copy_html("analysis/eda-65/eda-65.html", "predictors", "eda-65.html")

# Model reports
copy_html("analysis/model-00/model-00.html", "model", "model-00.html")
copy_html("analysis/model-0/model-0.html", "model", "model-0.html")
copy_html("analysis/model-1/model-1.html", "model", "model-1.html")

message("Post-render hook complete: all redirect targets copied to _site/")
