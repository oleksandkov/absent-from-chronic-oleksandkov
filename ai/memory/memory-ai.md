# AI Memory

AI system status and technical briefings.

---

# 2026-03-01

Built `analysis/eda-3/eda-3.R`, `analysis/eda-3/eda-3.qmd`, and `analysis/eda-3/README.md` as a direct structural replica of EDA-2, substituting `absence_days_chronic` (days absent due to a chronic health condition) for `absence_days_total`. Source: same `cchs_employed` table from `cchs-3.sqlite` (64,248 rows). Variable `absence_days_chronic` originates from Lane 3 rename `days_absent_chronic→absence_days_chronic`. Data pipeline: `ds0` (raw) → `ds1` (filter `absence_days_chronic >= 1`, not NA) → per-variable subsets `ds5`/`ds6`/`ds7` (drop NAs for `education_level` / `marital_status_label` / `immigration_status_label`). Seven graph families produced: g1 (overall scatter + histogram), g2 (by `sex_label`), g3 (by `age_group_3`, stats saved to CSV), g4 (by `survey_cycle_label`, scatter + histogram), g5 (by `education_level`, ds5), g6 (by `marital_status_label`, ds6), g7 (by `immigration_status_label`, ds7). Two analytic tables: `chronic_ratio_tbl` (overall 0-day vs. 1+ ratio) and `sex_ratio_tbl` (per-sex ratio). All conventions identical to EDA-2: `coord_cartesian(xlim=c(1,40))` zoom, 5-day bins/breaks, firebrick dashed median + darkorange dotted mean lines, `geom_label(data=stats_df, inherit.aes=FALSE)` for faceted reference labels. Session logged in `ai/memory/log/2026-03-01-analysing.md`.

---

# 2026-02-23

Built `analysis/eda-2/eda-2.R` and `analysis/eda-2/eda-2.qmd` from scratch using the R + Quarto dual-file pattern (R = development layer with `# ---- chunk-name ----` sections; qmd calls `read_chunk()` and references labels). Source: `cchs_employed` table from `cchs-3.sqlite` (64,248 rows). Data pipeline: `ds0` (raw) → `ds1` (filter absence_days_total ≥ 1, not NA) → per-variable subsets `ds5`/`ds6`/`ds7` (drop NAs for education_level / marital_status_label / immigration_status_label respectively) to avoid blank facet panels. Seven graph families produced: g1 (overall scatter + histogram), g2 (by sex_label), g3 (by age_group_3, stats saved to CSV), g4 (by survey_cycle_label, scatter + histogram), g5 (by education_level, ds5), g6 (by marital_status_label, ds6), g7 (by immigration_status_label, ds7). All graphs: `coord_cartesian(xlim = c(1,40))` zoom, 5-day bins/breaks, firebrick dashed median + darkorange dotted mean lines; faceted graphs use `geom_label(data=stats_df, inherit.aes=FALSE)` instead of `annotate()` because `annotate()` ignores facets. Two analytic tables: `absence_ratio_tbl` (overall 0-day vs. 1+ ratio) and `sex_ratio_tbl` (per-sex 0-day vs. 1+ ratio). Full session logged in `ai/memory/log/2025-02-23-analysing.md`.

---

# 2026-02-22

Updated `manipulation/2-ellis.R` to retain the full pooled CCHS sample by default (including employed and unemployed), matching raw ferry-scale output instead of legacy employed-only filtering (~64k). Added configurable switch `apply_sample_exclusions` (default `FALSE`) so legacy Section 3.1 exclusions remain available when explicitly enabled. Validated end-to-end run: pooled analytical output now `126,431` rows in both `data-private/derived/cchs-2.sqlite` (`cchs_analytical`) and `data-private/derived/cchs-2-tables/cchs_analytical.parquet`; sample flow updated to reflect full-sample mode. Aligned with human memory + session objective in `ai/memory/log/2026-02-22-cchs.md`, including next planned task: create `manipulation/3-ellis.R` to produce clearer outputs in `data-private/derived/cchs-3.sqlite` and `data-private/derived/cchs-3-tables/`.

Completed `manipulation/3-ellis.R` using `2-ellis.R` structure and Ellis pattern conventions: reads Lane 2 output, preserves full-sample context, adds clearer renamed analyst fields (e.g., `survey_cycle`, `employment_status`, `proxy_status`, `absence_days_total`), removes less useful columns in curated outputs, and splits into two dedicated tables (`cchs_employed`, `cchs_unemployed`). New artifacts are targeted in `data-private/derived/cchs-3.sqlite` and `data-private/derived/cchs-3-tables/` (`cchs_analytical`, split tables, `sample_flow`, and `data_dictionary`). Script also produces `manipulation/3-ellis.html` via `rmarkdown::render` with fallback HTML generation when Pandoc is unavailable. Updated `manipulation/pipeline.md` to include Lane 3 in flow, script list, run options, and outputs.

Refined Lane 3 to output a single renamed analytical table `cchs_analytical` (no dual all/v2 naming), excluding requested columns (`adm_rno`, `income_5cat`, `employment_type`, `work_schedule`, `alcohol_type`, `bmi_category`, `dhhgage`) and applying rename mapping (`cycle→survey_cycle_id`, `lop_015→employment_code`, `adm_prx→proxy_code`, `days_absent_total→absence_days_total`, `days_absent_chronic→absence_days_chronic`, `wts_m_pooled→weight_pooled`, `wts_m_original→weight_original`, `geodpmf→geo_region_id`). Split tables are now `cchs_employed` and `cchs_unemployed`.

Expanded Lane 3 renaming to cover most remaining retained columns with short English labels (including LOP components and chronic-condition flags, e.g., `lopg040→abs_chronic_days`, `cc_arthritis→chronic_arthritis`). Finalized split logic so `cchs_unemployed` is the full not-employed remainder (`employment_code != 1` or `NA`), guaranteeing partition completeness. Verified rerun: `cchs_analytical=126,431`, `cchs_employed=64,248`, `cchs_unemployed=62,183` and `cchs_employed + cchs_unemployed = cchs_analytical`. Synchronized documentation pointers so downstream users can trace naming via `data_dictionary.parquet` and `data-public/metadata/cchs-3-column-dictionary-uk.md`.

---

# 2026-02-19

Built complete CCHS data pipeline: `manipulation/1-ferry.R` (zero-transform .sav → SQLite), `manipulation/2-ellis.R` (white-list + harmonize + factor recode + pool weights → Parquet primary + SQLite secondary), `manipulation/2-test-ellis-cache.R` (5-section alignment test), updated `flow.R` Phase 1, populated `INPUT-manifest.md`, created `manipulation/pipeline.md`. Two-tier white-list: 13 CONFIRMED vars (hard error) + ~60 INFERRED vars (warn+drop). Survey-weight pooling: `wts_m / 2`. See `ai/memory/log/2026-02-19-cchs-pipeline.md`.

---

# 2025-11-08

System successfully updated to use config-driven memory paths 

---

# 2025-11-08

Removed all hardcoded paths - memory system now fully configuration-driven using config.yml and ai-support-config.yml with intelligent fallbacks 

---

# 2025-11-08

Created comprehensive AI configuration system: ai-config-utils.R provides unified config reading for all AI scripts. Supports config.yml, ai-support-config.yml, and intelligent fallbacks. All hardcoded paths now configurable. 

---

# 2025-11-08

Refactored ai-memory-functions.R: Removed redundant inline config reader, removed unused export_memory_logic() and context_refresh() functions, improved quick_intent_scan() with directory exclusions (.git, node_modules, data-private) and file size limits, standardized error handling patterns across all functions, removed all emojis from R script output (keeping ASCII-only for cross-platform compatibility), updated initialization message. Script now cleaner, more efficient, and follows project standards. 

---

# 2025-11-11

Major refactoring complete: Split monolithic ai_memory_check() into focused single-purpose functions (check_memory_system, show_memory_help). Simplified detect_memory_system() by removing unused return values. Streamlined memory_status() removing redundant calls and persona checking. Removed system_type parameter from initialize_memory_system(). Result: 377 lines reduced to 312 lines (17% reduction), cleaner architecture, better separation of concerns. 
