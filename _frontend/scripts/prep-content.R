# Purpose: Assemble edited_content pages before Quarto render.
# Registered as: pre-render
# Why needed: Contract-driven page assembly with protocol-specific transforms and verbatim copies.

frontend_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
project_root <- normalizePath(file.path(frontend_root, ".."), winslash = "/", mustWork = TRUE)
edited_root <- file.path(frontend_root, "edited_content")

dir.create(edited_root, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(edited_root, "project"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(edited_root, "pipeline"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(edited_root, "data-primer"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(edited_root, "analysis"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(edited_root, "docs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(edited_root, "images"), recursive = TRUE, showWarnings = FALSE)

read_lines <- function(rel_path) {
	readLines(file.path(project_root, rel_path), warn = FALSE, encoding = "UTF-8")
}

write_lines <- function(path, lines) {
	dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
	writeLines(lines, path, useBytes = TRUE)
}

derive_title <- function(lines, fallback) {
	idx <- grep("^#\\s+.+", lines)
	if (length(idx) > 0) {
		sub("^#\\s+", "", lines[idx[1]])
	} else {
		fallback
	}
}

to_qmd_with_frontmatter <- function(lines, title) {
	c(
		"---",
		paste0("title: \"", title, "\""),
		"---",
		"",
		lines
	)
}

strip_fence_blocks <- function(lines, strip_langs = c("r", "powershell", "bash", "sh", "ps1")) {
	out <- character(0)
	in_fence <- FALSE
	drop_current <- FALSE

	for (ln in lines) {
		if (!in_fence && grepl("^```", ln)) {
			in_fence <- TRUE
			lang <- tolower(trimws(sub("^```", "", ln)))
			lang <- strsplit(lang, "[[:space:]]+")[[1]][1]
			drop_current <- nzchar(lang) && (lang %in% strip_langs)
			if (!drop_current) {
				out <- c(out, ln)
			}
			next
		}

		if (in_fence && grepl("^```\\s*$", ln)) {
			if (!drop_current) {
				out <- c(out, ln)
			}
			in_fence <- FALSE
			drop_current <- FALSE
			next
		}

		if (!drop_current) {
			out <- c(out, ln)
		}
	}

	out
}

remove_data_private_refs <- function(lines) {
	gsub("`?data-private/[^` )]*`?", "private data storage", lines, perl = TRUE)
}

remove_markdown_links <- function(lines) {
	gsub("\\[([^\\]]+)\\]\\(([^)]+)\\)", "\\1", lines, perl = TRUE)
}

normalize_variable_inclusion <- function(lines) {
	if (length(lines) < 3 || trimws(lines[1]) != "---") {
		return(lines)
	}

end_rel <- which(trimws(lines[-1]) == "---")
if (length(end_rel) == 0) {
		return(lines)
	}

	end_idx <- end_rel[1] + 1
	yaml <- lines[1:end_idx]
	body <- lines[(end_idx + 1):length(lines)]

	yaml <- yaml[!grepl("^\\s*embed-resources\\s*:", yaml)]
	yaml <- yaml[!grepl("^\\s*theme\\s*:\\s*flatly\\s*$", yaml, ignore.case = TRUE)]

	c(yaml, body)
}

replace_lane3_note <- function(lines) {
	start_idx <- grep("^> \\*\\*Note on Ellis Lane 3\\*\\*", lines)
	if (length(start_idx) == 0) {
		return(lines)
	}

	s <- start_idx[1]
	e <- s
	while (e <= length(lines) && grepl("^>", lines[e])) {
		e <- e + 1
	}

	replacement <- c(
		"A third Ellis lane produced additional derived outputs; documentation is in the CACHE Manifest.",
		""
	)

	prefix <- if (s > 1) lines[1:(s - 1)] else character(0)
	suffix <- if (e <= length(lines)) lines[e:length(lines)] else character(0)

	c(prefix, replacement, suffix)
}

# --- Narrative Bridge: index.qmd ---
hero_src <- file.path(project_root, "analysis", "eda-5", "prints", "g01_lop_days_histogram.png")
hero_dest <- file.path(edited_root, "images", "g01_lop_days_histogram.png")
hero_available <- file.exists(hero_src)

if (hero_available) {
	file.copy(hero_src, hero_dest, overwrite = TRUE)
}

index_lines <- c(
	"---",
	"title: \"Absent from Chronic — Research Documentation\"",
	"---",
	"",
	"This site documents the statistical analysis workflow for *Predictors of Work Absenteeism Associated with Chronic Conditions Among Canadian Workers*.",
	"",
	if (hero_available) "![Distribution of total missed workdays among respondents with at least one missed day.](images/g01_lop_days_histogram.png)" else "**Hero figure unavailable:** `analysis/eda-5/prints/g01_lop_days_histogram.png` was not found at build time.",
	"",
	"The documentation is organized as a verification path from statistical instructions to implemented analysis artifacts. It is intended for direct review by the principal investigator.",
	"",
	"The analytical dataset currently documented in the CACHE Manifest contains **63,843 rows** and **62 columns**, pooling two CCHS cycles (2010–2011 and 2013–2014).",
	"",
	"Source grounding: `README.md`; `data-public/metadata/CACHE-manifest.md`.",
	"",
	"## How to use this site",
	"",
	"- **Project**: the original statistical instructions that define required outputs.",
	"- **Pipeline**: the transport-and-transformation documentation, plus manifest references.",
	"- **Data Primer**: variable inclusion traceability and univariate profile access.",
	"- **Analysis**: EDA and binder report outputs used to inspect outcome structure and sample composition.",
	"- **Docs**: project synopsis and site map for navigation and requirement coverage."
)

write_lines(file.path(edited_root, "index.qmd"), index_lines)

# --- Narrative Bridge: site-map.qmd ---
site_map_lines <- c(
	"---",
	"title: \"Site Map\"",
	"---",
	"",
	"## Content Types",
	"",
	"| Type | Meaning |",
	"|------|----------|",
	"| **VERBATIM** | Source content copied with minimal formatting changes (frontmatter only) |",
	"| **REDIRECTED** | Transit page that forwards to a standalone HTML report |",
	"| **TECHNICAL BRIDGE** | Source document adapted for web readability and PI-focused context |",
	"| **NARRATIVE BRIDGE** | Authored synthesis page grounded in repository sources |",
	"",
	"## Navigation Structure",
	"",
	"- **Home**",
	"  - `index` — NARRATIVE BRIDGE ← `README.md`, `data-public/metadata/CACHE-manifest.md`",
	"- **Project**",
	"  - `Statistical Instructions` — TECHNICAL BRIDGE ← `data-private/raw/2026-02-19/stats_instructions_v3.md`",
	"- **Pipeline**",
	"  - `Pipeline Guide` — TECHNICAL BRIDGE ← `manipulation/pipeline.md`",
	"  - `CACHE Manifest` — VERBATIM ← `data-public/metadata/CACHE-manifest.md`",
	"  - `INPUT Manifest` — VERBATIM ← `data-public/metadata/INPUT-manifest.md`",
	"- **Data Primer**",
	"  - `Variable Inclusion` — VERBATIM ← `analysis/data-primer-1/variable-inclusion.qmd`",
	"  - `Univariate Distributions` — REDIRECTED → `analysis/data-primer-1/univariate-distributions.html`",
	"- **Analysis**",
	"  - `EDA-2` — REDIRECTED → `analysis/eda-2/eda-2.html`",
	"  - `EDA-5` — REDIRECTED → `analysis/eda-5/eda-5.html`",
	"  - `Binder-2: Table Anatomy` — REDIRECTED → `analysis/binder-2/1-table-anatomy.html`",
	"  - `Binder-2: Sociodemographic Fabric` — REDIRECTED → `analysis/binder-2/2-sociodemographic-fabric.html`",
	"  - `Binder-2: Outcome Anatomy` — REDIRECTED → `analysis/binder-2/3-outcome-anatomy.html`",
	"  - `Binder-2: Raw to Analytical` — REDIRECTED → `analysis/binder-2/4-raw-to-analytical.html`",
	"- **Docs**",
	"  - `README` — TECHNICAL BRIDGE ← `README.md`",
	"  - `Site Map` — NARRATIVE BRIDGE ← contract navigation structure",
	"",
	"## Stats Instructions Coverage",
	"",
	"- **§2.2 variable requirements** map to **Data Primer → Variable Inclusion**.",
	"- **§3 sample construction and pooling** map to **Pipeline Guide** and binder/EDA pages.",
	"- **§4 descriptive outcome diagnostics** map to **Analysis (EDA-2, EDA-5)**."
)

write_lines(file.path(edited_root, "docs", "site-map.qmd"), site_map_lines)

# --- Technical Bridge: Statistical Instructions ---
stats_lines <- read_lines("data-private/raw/2026-02-19/stats_instructions_v3.md")
stats_lines <- stats_lines[!grepl("data-private/", stats_lines, fixed = TRUE)]
stats_qmd <- to_qmd_with_frontmatter(stats_lines, "Statistical Instructions")
write_lines(file.path(edited_root, "project", "statistical-instructions.qmd"), stats_qmd)

# --- Technical Bridge: Pipeline Guide ---
pipeline_lines <- read_lines("manipulation/pipeline.md")
pipeline_lines <- replace_lane3_note(pipeline_lines)
pipeline_lines <- strip_fence_blocks(pipeline_lines, c("r", "powershell", "bash", "sh", "ps1"))
pipeline_lines <- remove_data_private_refs(pipeline_lines)
pipeline_lines <- remove_markdown_links(pipeline_lines)
pipeline_qmd <- to_qmd_with_frontmatter(pipeline_lines, "Pipeline Guide")
write_lines(file.path(edited_root, "pipeline", "pipeline-guide.qmd"), pipeline_qmd)

# --- Technical Bridge: README ---
readme_lines <- read_lines("README.md")
idx_about <- grep("^## About This Project", readme_lines)
idx_run <- grep("^### Running the data pipeline", readme_lines)

if (length(idx_about) > 0 && length(idx_run) > 0 && idx_run[1] > idx_about[1]) {
	readme_slice <- readme_lines[idx_about[1]:(idx_run[1] - 1)]
} else {
	readme_slice <- readme_lines
}

readme_slice <- remove_data_private_refs(readme_slice)
readme_slice <- remove_markdown_links(readme_slice)
readme_slice <- gsub(
	"See `?data-public/metadata/CACHE-manifest.md`? for detailed descriptions\\.",
	"See the CACHE Manifest page in the Pipeline section for detailed descriptions.",
	readme_slice
)

readme_qmd <- to_qmd_with_frontmatter(readme_slice, "README")
write_lines(file.path(edited_root, "docs", "readme.qmd"), readme_qmd)

# --- Direct Line VERBATIM: CACHE Manifest ---
cache_lines <- read_lines("data-public/metadata/CACHE-manifest.md")
cache_title <- derive_title(cache_lines, "CACHE Manifest")
cache_qmd <- to_qmd_with_frontmatter(cache_lines, cache_title)
write_lines(file.path(edited_root, "pipeline", "cache-manifest.qmd"), cache_qmd)

# --- Direct Line VERBATIM: INPUT Manifest ---
input_lines <- read_lines("data-public/metadata/INPUT-manifest.md")
input_title <- derive_title(input_lines, "INPUT Manifest")
input_qmd <- to_qmd_with_frontmatter(input_lines, input_title)
write_lines(file.path(edited_root, "pipeline", "input-manifest.qmd"), input_qmd)

# --- Direct Line VERBATIM: Variable Inclusion ---
var_inclusion_lines <- read_lines("analysis/data-primer-1/variable-inclusion.qmd")
var_inclusion_lines <- normalize_variable_inclusion(var_inclusion_lines)
write_lines(file.path(edited_root, "data-primer", "variable-inclusion.qmd"), var_inclusion_lines)

message("prep-content.R: edited_content assembly complete.")
