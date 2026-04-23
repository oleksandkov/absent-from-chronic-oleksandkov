# AI Memory

AI system status and technical briefings.

---

## 2026-03-21 (documentation alignment sprint)

Ran Ellis (`apply_sample_exclusions = TRUE`) producing 63,843 rows × 62 columns (Cycle 0:
32,621; Cycle 1: 31,222) in `cchs_analytical.parquet` + `cchs-2.sqlite`. Verified actual
output schema: 41 factors, ~20 numeric, 1 character (`geodpmf`), 1 logical
(`outcome_all_na`). 17 cc_* binary factors present (not 19 — `ccc_300`, `ccc_185` absent
from PUMF). 5 all-NA factor columns: `homeownership`, `student_status`,
`occupation_category`, `alcohol_type`, `bmi_category` (source variables absent from PUMF;
columns created by `ensure_columns()` for downstream recode stubs). 6 variables previously
thought broken are actually populated via alias resolution: `income_5cat` (incghh→incdghh),
`employment_type` (lbsg31→lbfdghp), `work_schedule` (lbsdpft→lbfdgft), `dhhdghsz`
(dhhghsz), `fvcdgtot` (fvcgtot), `geodgprv` (geogprv).

**Correction to prior entries**: CCC code mappings in 2026-03-20 entries were wrong.
Correct: `ccc_015→ccc_031` (asthma), `ccc_011→ccc_041` (fibromyalgia). NOT ccc_035/ccc_036
as previously stated. The full verified CCC map is: ccc_031=asthma, ccc_041=fibromyalgia,
ccc_051=arthritis, ccc_061=back_problems, ccc_071=hypertension, ccc_081=migraine,
ccc_091=copd, ccc_101=diabetes, ccc_121=heart_disease, ccc_131=cancer, ccc_141=ulcer,
ccc_151=stroke, ccc_171=bowel_disorder, ccc_251=chronic_fatigue, ccc_261=chemical_sensitiv,
ccc_280=mood_disorder, ccc_290=anxiety_disorder.

Files updated to match actual Ellis output:

- `manipulation/pipeline.md` — column count 58→62, CCC codes fixed, white-list miss 17→10
- `data-public/metadata/CACHE-manifest.md` — major overhaul: column counts, cycle splits,
  removed nonexistent cc_other_mental_ill/cc_digestive_disease, fixed factor level strings,
  rewrote alias table and Known Limitations
- `manipulation/2-test-ellis-cache.R` — no changes needed; 31/31 tests pass
- `analysis/data-primer-1/variable-inclusion.qmd` — rewrote CCC table (7 of 17 mappings
  were wrong), corrected predisposing/facilitating tables (many vars marked absent are
  actually populated), updated Summary of Gaps
- `analysis/data-primer-1/univariate-distributions.R` — added cc_asthma, cc_fibromyalgia
  to cc_vars (were missing from list)
- `analysis/data-primer-1/univariate-distributions.qmd` — removed incorrect all-NA guards
  for income/employment/work_schedule, fixed condition counts and section descriptions

Education cross-cycle discrepancy documented in Ellis: EDUDH04 code 3 is "Other
post-secondary" in 2010 vs "Some post-secondary" in 2014; both mapped to "Some
post-secondary" with in-code documentation.

Round 2 dictionary-verified corrections to 2-ellis.R remain UNAPPLIED — plan saved in
`/memories/session/plan.md`. These include: 10 variable name fixes, homeownership→living
arrangement (8-cat), job_stress split into life_stress + job_stress, alcohol_type fix to
3-cat, bmi_category source fix, occupation_category to 5-cat lbsgsoc.

Session log: `ai/memory/log/2026-03-21-documentation-alignment.md`.

---

## 2026-03-20

Authored `analysis/data-primer-1/variable-inclusion.md` — a five-column traceability table
(Requested / 2011 / 2014 / In Study / Note) linking every §2.2 variable from
`stats_instructions_v3.md` to its concrete PUMF source name and analytical-dataset column
name in `cchs_analytical.parquet`. Organised into 7 sections matching the §2.2 table rows.
PUMF column presence verified by querying ferry parquet files directly. Ellis "In Study"
names traced from factor-recoding steps in `manipulation/2-ellis.R`. Key findings: 17/19
CCC vars available (2 PUMF-suppressed: `ccc_300`, `ccc_185`); 13 INFERRED white-list codes
need alias fixes (wrong DG-infix); student status and occupation absent from PUMF;
bootstrap weights absent (critical blocker — separate Statistics Canada supplement file).
Session log: `ai/memory/log/2026-03-20-variable-inclusion.md`.

---

## 2026-03-20 (pipeline validation)

Ran 1-ferry.R (62,909 + 63,522 rows → cchs-1.sqlite) and 2-ellis.R (63,843 rows, 58 cols →
cchs-2-tables/). Corrected pipeline.md (7 edits), INPUT-manifest.md (4 edits), and populated
CACHE-manifest.md from stub. Root-caused 17 missing INFERRED variables: 2 wrong CCC codes
(ccc_015→ccc_035, ccc_011→ccc_036), 11 DG-infix mismatches, 2 absent from PUMF, 2 absent
entirely. Fixed renv.lock version pins (fs 1.6.7, later 1.4.8, httpuv 1.6.17) to allow
binary install without Rtools.

---

## 2026-03-01

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
