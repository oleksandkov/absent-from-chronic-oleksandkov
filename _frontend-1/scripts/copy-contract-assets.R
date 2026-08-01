# Purpose: Copy contract-referenced static assets into content/ before render.
# Registered as: pre-render
# Why needed: Ensures content/ is self-contained and contract image sources are
#   refreshed from canonical repository locations each run.

project_root <- normalizePath(file.path(getwd(), ".."), winslash = "/")
content_images <- file.path(getwd(), "content", "images")
if (!dir.exists(content_images)) dir.create(content_images, recursive = TRUE)

copy_asset <- function(source_rel, dest_name) {
  src <- file.path(project_root, source_rel)
  dest <- file.path(content_images, dest_name)
  if (file.exists(src)) {
    file.copy(src, dest, overwrite = TRUE)
    message("Copied: ", src, " -> ", dest)
  } else {
    warning("Asset not found: ", src)
  }
}

copy_asset(
  "analysis/eda-5/prints/g01_lop_days_histogram.png",
  "g01_lop_days_histogram.png"
)
copy_asset(
  "analysis/eda-71/prints/g23_chronic_vs_other_only_raw_split_distribution.png",
  "g23_chronic_vs_other_only_raw_split_distribution.png"
)
copy_asset(
  "libs/images/pipeline-architecture.jpg",
  "pipeline-architecture.jpg"
)

message("Pre-render asset hook complete.")
