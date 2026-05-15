# Purpose: Prepare self-contained edited content assets and verbatim source copies before render.
# Registered as: pre-render
# Why needed: Direct Line and Narrative pages depend on source files and binary assets that must be co-located in edited_content/.

frontend_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
repo_root <- normalizePath(file.path(frontend_dir, ".."), winslash = "/", mustWork = TRUE)
edited_dir <- file.path(frontend_dir, "edited_content")

copy_file_safe <- function(src, dst) {
  if (!file.exists(src)) {
    message("[pre-render] Missing source: ", src)
    return(FALSE)
  }
  dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
  ok <- file.copy(src, dst, overwrite = TRUE)
  if (!ok) {
    message("[pre-render] Failed to copy: ", src, " -> ", dst)
  }
  ok
}

# Narrative hero image
copy_file_safe(
  file.path(repo_root, "analysis", "eda-5", "prints", "g01_lop_days_histogram.png"),
  file.path(edited_dir, "images", "g01_lop_days_histogram.png")
)

# Verbatim source includes
copy_file_safe(
  file.path(repo_root, "data-private", "raw", "2026-02-19", "stats_instructions_v3.md"),
  file.path(edited_dir, "project", "statistical-instructions-source.md")
)

copy_file_safe(
  file.path(repo_root, "data-public", "metadata", "CACHE-manifest.md"),
  file.path(edited_dir, "pipeline", "cache-manifest-source.md")
)

copy_file_safe(
  file.path(repo_root, "data-public", "metadata", "INPUT-manifest.md"),
  file.path(edited_dir, "pipeline", "input-manifest-source.md")
)

# Variable Inclusion: keep as direct line with requested YAML cleanup
src_var_inc <- file.path(repo_root, "analysis", "data-primer-1", "variable-inclusion.qmd")
dst_var_inc <- file.path(edited_dir, "data-primer", "variable-inclusion.qmd")

if (file.exists(src_var_inc)) {
  lines <- readLines(src_var_inc, warn = FALSE, encoding = "UTF-8")
  if (length(lines) >= 2 && trimws(lines[1]) == "---") {
    end_idx <- which(trimws(lines[-1]) == "---")[1] + 1
    if (!is.na(end_idx) && end_idx > 1) {
      frontmatter <- lines[1:end_idx]
      body <- lines[(end_idx + 1):length(lines)]
      frontmatter <- frontmatter[!grepl("^\\s*embed-resources\\s*:", frontmatter)]
      frontmatter <- frontmatter[!grepl("^\\s*theme\\s*:\\s*flatly\\s*$", frontmatter)]
      out <- c(frontmatter, body)
      dir.create(dirname(dst_var_inc), recursive = TRUE, showWarnings = FALSE)
      writeLines(out, dst_var_inc, useBytes = TRUE)
    }
  }
}
