#' ---
#' title: "Ellis Lane 2: CCHS Data Transformation — White-List Analytical Dataset"
#' author: "Andriy Koval"
#' date: "2026-02-19"
#' ---
#'
#' ============================================================================
#' ELLIS PATTERN: Transform Ferry Output into Analysis-Ready Dataset
#' ============================================================================
#'
#' **Purpose**: Select, harmonize, recode, and validate CCHS microdata from
#' two survey cycles (2010-2011, 2013-2014) into a single pooled analytical
#' dataset containing only the variables required by stats_instructions_v3.md.
#'
#' **White-List Philosophy**: This Ellis script explicitly selects ~60-80
#' analysis-relevant variables from the hundreds in the raw SPSS files.
#' Variables are grouped by conceptual category. Unrecognized white-list names
#' trigger WARNINGS (not errors) so the analyst can verify against data
#' dictionaries in ./data-private/raw/2026-02-19/ and update this script.
#'
#' **Input**: ./data-private/derived/cchs-1.sqlite
#'   - Table: cchs_2010_raw  (CCHS 2010-2011, all columns)
#'   - Table: cchs_2014_raw  (CCHS 2013-2014, all columns)
#'
#' **Output**:
#'   Primary: ./data-private/derived/cchs-2-tables/  (Parquet — preserves factors)
#'     - cchs_analytical.parquet  : pooled white-listed analytical dataset
#'     - sample_flow.parquet      : sequential exclusion counts (flowchart data)
#'   Secondary: ./data-private/derived/cchs-2.sqlite  (for ad-hoc SQL exploration)
#'     - cchs_analytical  : same data, factors stored as character
#'     - sample_flow      : same data
#'
#' **Required Variables** (see ./data-public/derived/required-variables-and-sample.md):
#'   Confirmed: LOPG040, LOPG070, LOPG082-086, LOPG100, LOP_015, DHHGAGE,
#'              ADM_PRX, WTS_M, GEODPMF
#'   Inferred:  CCC module (19 conditions), DHH demographics, INC, GEN, ALC,
#'              SMK, HWT, PAC, HCU, LBF, FVC, RAC, INJ modules
#'              (Verify against PDF data dictionaries in data-private/raw/)
#'
#' **References**:
#'   - stats_instructions_v3.md   (analysis plan)
#'   - required-variables-and-sample.md  (confirmed variable names)
#'   - CCHS_2010_DataDictionary_Freqs-ver2.pdf  (verify INFERRED names)
#'   - CCHS_2014_DataDictionary_Freqs.pdf       (verify INFERRED names)
#'
#' ============================================================================

#+ echo=F
# rmarkdown::render(input = "./manipulation/2-ellis.R") # run to knit
# ---- setup -------------------------------------------------------------------
rm(list = ls(all.names = TRUE))
cat("\014")

# ============================================================
# PIPELINE FLAGS  —  Edit these or let run-interactive-flow.ps1 manage them
# ============================================================
#
# strict_cycle_integrity
#   Controls what happens when one of the two CCHS survey cycles (2010-2011
#   or 2013-2014) loads as an empty table from cchs-1.sqlite.
#   Affects rows: acts as a guard — does NOT exclude rows, only prevents a
#   silent single-cycle run when both cycles are required for valid analysis.
#     FALSE = emit a warning and continue with available cycle(s);
#             useful during development or when only one dataset is present.
#     TRUE  = stop with an error if any cycle is empty (strict pooled mode).
#
# apply_sample_exclusions
#   Applies the inclusion/exclusion criteria from stats_instructions_v3.md §3.1:
#     – Keep only respondents employed in the past 3 months  (lop_015 == 1)
#     – Keep only ages 15–75                                 (dhhgage in range)
#     – Exclude proxy respondents                            (adm_prx == 1)
#   Affects rows: removes out-of-scope respondents; reduces analytic sample.
#     FALSE = skip these filters; retain full pooled sample.
#     TRUE  = apply the three filters above (recommended for analysis).
#
# apply_completeness_exclusion  (§3.1 criterion 4b)
#   After the above filters, also drops any respondent with NA on ANY of the
#   19 CCC chronic-condition indicators OR on any key predictor variable.
#   Affects rows: drops incomplete cases from cchs_analytical.parquet / SQLite.
#   Affects columns: none (columns are kept; only rows with NA in CCC/predictors
#                   are removed when TRUE).
#     FALSE = do NOT drop incomplete cases here; handle missingness downstream
#             (e.g., multiple imputation, complete-case sensitivity analysis).
#     TRUE  = enforce full §3.1 compliance by removing incomplete cases now.
#
strict_cycle_integrity       <- FALSE
apply_sample_exclusions      <- TRUE
apply_completeness_exclusion <- FALSE

script_start <- Sys.time()
verbose      <- FALSE   # set FALSE to suppress progress output; key results always print
vcat         <- function(...) if (verbose) cat(...)

# ---- load-packages -----------------------------------------------------------
library(magrittr)
library(dplyr)
library(tidyr)
library(stringr)
library(janitor)
requireNamespace("DBI")
requireNamespace("RSQLite")
requireNamespace("checkmate")
requireNamespace("arrow")
requireNamespace("fs")

# ---- load-sources ------------------------------------------------------------
project_root <- if (dir.exists("scripts") && dir.exists("manipulation")) {
  "."
} else if (dir.exists("../scripts") && dir.exists("../manipulation")) {
  ".."
} else {
  stop("Cannot locate project root. Run from project root or from manipulation/.")
}

base::source(file.path(project_root, "scripts", "common-functions.R"))

# ---- declare-globals ---------------------------------------------------------

# Input (ferry output)
input_sqlite_candidates <- unique(c(
  file.path(project_root, "data-private", "derived", "cchs-1.sqlite"),
  file.path(".", "data-private", "derived", "cchs-1.sqlite"),
  file.path("..", "data-private", "derived", "cchs-1.sqlite")
))
input_sqlite <- input_sqlite_candidates[file.exists(input_sqlite_candidates)][1]
if (is.na(input_sqlite)) input_sqlite <- input_sqlite_candidates[1]
table_2010    <- "cchs_2010_raw"
table_2014    <- "cchs_2014_raw"

# Output — SQLite (secondary: ad-hoc SQL exploration; factors as character)
output_sqlite <- file.path(project_root, "data-private", "derived", "cchs-2.sqlite")
output_dir    <- dirname(output_sqlite)
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Output — Parquet (primary: preserves R factor types, levels, and order)
output_parquet_dir <- file.path(project_root, "data-private", "derived", "cchs-2-tables")
if (!fs::dir_exists(output_parquet_dir)) fs::dir_create(output_parquet_dir, recurse = TRUE)

# --------------------------------------------------------------------------
# WHITE-LIST: Variables selected for the analytical dataset
# --------------------------------------------------------------------------
#
# CONFIRMED = explicitly named in required-variables-and-sample.md
# INFERRED  = derived from CCHS PUMF naming conventions
#             MUST BE VERIFIED against PDF data dictionaries:
#             ./data-private/raw/2026-02-19/CCHS_2010_DataDictionary_Freqs-ver2.pdf
#             ./data-private/raw/2026-02-19/CCHS_2014_DataDictionary_Freqs.pdf
#
# Variable names below are AFTER janitor::clean_names() (lowercase, snake_case).
# Original CCHS names: LOPG040 → lopg040, CCC_015 → ccc_015, DHH_SEX → dhh_sex
# --------------------------------------------------------------------------

vars_confirmed <- c(
  # --- LOP module: outcome components (8 variables) ---
  "lopg040",   # CONFIRMED: days lost – chronic condition (also: sensitivity outcome)
  "lopg070",   # CONFIRMED: days lost – injury
  "lopg082",   # CONFIRMED: days lost – cold
  "lopg083",   # CONFIRMED: days lost – flu/influenza
  "lopg084",   # CONFIRMED: days lost – stomach flu (gastroenteritis)
  "lopg085",   # CONFIRMED: days lost – respiratory infection
  "lopg086",   # CONFIRMED: days lost – other infectious disease
  "lopg100",   # CONFIRMED: days lost – other physical/mental health

  # --- Sample construction filters ---
  "lop_015",   # CONFIRMED: employed in past 3 months (1=Yes; inclusion criterion)
  "dhhgage",   # CONFIRMED: age group (inclusion: 15-75; recoded to 3-cat predictor)
  "adm_prx",   # CONFIRMED: proxy indicator (1=Proxy; exclusion criterion)

  # --- Survey design ---
  "wts_m",     # CONFIRMED: master survey weight (labelled WGHT_FINAL in instructions)
  "geodpmf"    # CONFIRMED: health region / strata identifier
)

vars_inferred_ccc <- c(
  # --- CCC module: 19 chronic conditions (binary Yes/No each) ---
  # Codes 1=Yes, 2=No; special NAs: 6=Not applicable, 7=DK, 8=Refusal, 9=Not stated
  #
  # METADATA STATUS per cchs_variable_labels.csv (extract-metadata.R):
  #   VERIFIED  = variable and label confirmed in both SAV cycles
  #   NOT FOUND = absent from both SAV files; verify against PDF data dictionaries
  #
  "ccc_031",   # VERIFIED: asthma                                   (CCC_031; both cycles)
  "ccc_041",   # VERIFIED: fibromyalgia                             (CCC_041; both cycles)
  "ccc_051",   # VERIFIED: arthritis (excl. fibromyalgia)           (CCC_051; both cycles)
  "ccc_061",   # VERIFIED: back problems (excl. fibro/arthritis)    (CCC_061; both cycles)
  "ccc_071",   # VERIFIED: hypertension (high blood pressure)       (CCC_071; both cycles)
  "ccc_081",   # VERIFIED: migraine headaches                       (CCC_081; both cycles)
  "ccc_091",   # VERIFIED: COPD / chronic bronchitis / emphysema    (CCC_091; both cycles)
  "ccc_101",   # VERIFIED: diabetes                                 (CCC_101; both cycles)
  "ccc_121",   # VERIFIED: heart disease                            (CCC_121; both cycles)
  "ccc_131",   # VERIFIED: cancer (any type)                        (CCC_131; both cycles)
  "ccc_141",   # VERIFIED: intestinal / stomach ulcer               (CCC_141; both cycles)
  "ccc_151",   # VERIFIED: effects of stroke                        (CCC_151; both cycles)
  "ccc_171",   # VERIFIED: bowel disorder (Crohn's/colitis/IBS)     (CCC_171; both cycles)
  "ccc_251",   # VERIFIED: chronic fatigue syndrome (CFS)           (CCC_251; both cycles)
  "ccc_261",   # VERIFIED: multiple chemical sensitivities (MCS)    (CCC_261; both cycles)
  "ccc_280",   # VERIFIED: mood disorder (depression/bipolar/etc.)  (CCC_280; both cycles)
  "ccc_290",   # VERIFIED: anxiety disorder (phobia/OCD/panic)      (CCC_290; both cycles)
  "ccc_300",   # NOT FOUND in SAV metadata — NEEDS EXTERNAL DICT VERIFICATION
                #   Intended: other mental illness (schizophrenia etc.)
                #   Verify against CCHS_2010_DataDictionary_Freqs-ver2.pdf
  "ccc_185"    # NOT FOUND in SAV metadata — NEEDS EXTERNAL DICT VERIFICATION
                #   Intended: digestive diseases (other than ulcer/bowel disorder)
                #   Verify against CCHS_2010_DataDictionary_Freqs-ver2.pdf
)

vars_inferred_predisposing <- c(
  # --- Predisposing variables ---
  # Codes below are standard CCHS PUMF; verify against data dictionaries
  "dhh_sex",    # INFERRED: sex (1=Male, 2=Female)
  "dhhgms",     # INFERRED: marital status (1=Married, 2=Common-law,
                #            3=Widowed/Divorced/Separated, 4=Single)
  "dhhdghsz",   # VERIFIED: household size — alias resolves to dhhghsz (DHHGHSZ in SAV)
  "edudh04",    # INFERRED: education level (derived; 4 categories)
                #            Alt candidate: "edudr04"
  "sdcfimm",    # VERIFIED: immigrant flag — SDCFIMM; codes 1=YES (immigrant), 2=NO
                #   NOTE: SAV has only 2 codes; no code 3 in data (code 3 recode is dead)
  "sdcdgcb",    # VERIFIED: visible minority — alias resolves to sdcgcgt (SDCGCGT in SAV)
                #   codes: 1=WHITE, 2=VISIBLE MINORITY
  "dhhdglvg",   # NOT FOUND in SAV metadata — NEEDS EXTERNAL DICT VERIFICATION
                #   Intended: homeownership / living arrangements
                #   Verify against CCHS_2010_DataDictionary_Freqs-ver2.pdf
  # --- Children in household by age group (§2.2 predisposing) ---
  # VERIFY exact variable names against CCHS data dictionaries;
  # standard CCHS PUMF may use a single derived variable or separate counts
  "dhhdfc5",    # NOT FOUND in SAV metadata — NEEDS EXTERNAL DICT VERIFICATION
                #   Intended: number of children < 5 yrs in household
  "dhhdfc11",   # NOT FOUND in SAV metadata — NEEDS EXTERNAL DICT VERIFICATION
                #   Intended: number of children 6–11 yrs in household
  "dhhdfc12p",  # NOT FOUND in SAV metadata — NEEDS EXTERNAL DICT VERIFICATION
                #   Intended: number of children ≥ 12 yrs in household
  # --- Student status (§2.2 predisposing) ---
  "sdcdgstud"   # NOT FOUND in SAV metadata — NEEDS EXTERNAL DICT VERIFICATION
                #   Intended: student status (full-time / part-time / not a student)
)

vars_inferred_facilitating <- c(
  # --- Facilitating variables ---
  "incdghh",   # VERIFIED: household income 5-category — alias resolves to incghh (INCGHH in SAV)
                #   codes: 1=<$20k, 2=$20k-$39.9k, 3=$40k-$59.9k, 4=$60k-$79.9k, 5=$80k+
  "geodgprv",  # VERIFIED: province — alias resolves to geogprv (GEOGPRV in SAV)
               #   codes: 10=NL, 11=PEI, 12=NS, 13=NB, 24=QC, 35=ON, 46=MB, 47=SK, 48=AB, 59=BC, 60=YT/NT/NU
  "hcu_1aa",   # VERIFIED: has regular family doctor — HCU_1AA in SAV; codes 1=YES, 2=NO
  "lbfdghp",   # VERIFIED: employment type — alias resolves to lbsg31 (LBSG31 in SAV)
               #   codes: 1=EMPLOYEE, 2=SELF-EMPLOYED  (no code 3 in data; unpaid worker recode is dead)
  "lbfdgft",   # VERIFIED: work schedule — alias resolves to lbsdpft (LBSDPFT in SAV)
               #   codes: 1=FULL-TIME, 2=PART-TIME
  "fvcdgtot",  # VERIFIED: fruit & veg intake — alias resolves to fvcgtot (FVCGTOT in SAV)
               #   NOTE: FVCGTOT is a 3-category derived variable (1=<5/day, 2=5-10/day, 3=>10/day)
               #   NOT a continuous count; treat as ordinal/categorical in analysis
  "alcdgtyp",  # NOT FOUND in SAV metadata — NEEDS EXTERNAL DICT VERIFICATION
               #   Intended: type of drinker (regular/occasional/former/never)
               #   Verify against CCHS_2010_DataDictionary_Freqs-ver2.pdf
  "smkdsty",   # VERIFIED: smoking status derived — SMKDSTY in SAV
               #   codes: 1=DAILY, 2=OCCASIONAL (current), 3=ALWAYS OCCASIONAL (former),
               #          4=FORMER DAILY, 5=FORMER OCCASIONAL, 6=NEVER SMOKED
               #   special NAs: 96=NOT APPLICABLE, 97=DK, 98=REFUSAL, 99=NOT STATED
  "hwtdgbmi",  # NOT FOUND in SAV metadata — NEEDS EXTERNAL DICT VERIFICATION
               #   Intended: 4-category derived BMI (underweight/normal/overweight/obese)
               #   SAV contains HWTGBMI (continuous BMI); derived categories not found
               #   Verify HWTDGBMI against CCHS_2014_DataDictionary_Freqs.pdf
  "pacdpai",   # VERIFIED: physical activity index — PACDPAI in SAV
               #   codes: 1=ACTIVE, 2=MODERATE ACTIVE, 3=INACTIVE
  "gen_07",    # VERIFIED: perceived life stress — GEN_07 in SAV
               #   codes: 1=NOT AT ALL, 2=NOT VERY, 3=A BIT, 4=QUITE A BIT, 5=EXTREMELY
               #   NOTE: GEN_07 = perceived LIFE stress; GEN_09 = perceived WORK stress
               #   Confirm which is intended as 'job_stress' against stats_instructions
  # --- Occupation category (§2.2 facilitating) ---
  "noc_31"     # NOT FOUND in SAV metadata — NEEDS EXTERNAL DICT VERIFICATION
               #   LBSGSOC (in SAV) is a 5-cat occupation group (1=Mgmt/Art/Education,
               #   2=Business/Finance, 3=Sales/Service, 4=Trades/Transport, 5=Prim.Ind./Processing)
               #   This does NOT match the 10-category NOC structure coded in Ellis.
               #   Verify whether noc_31 exists or lbsgsoc should be used with revised categories.
)

vars_inferred_needs <- c(
  # --- Needs variables ---
  "gen_01",    # VERIFIED: self-perceived general health — GEN_01 in SAV
               #   codes: 1=EXCELLENT, 2=VERY GOOD, 3=GOOD, 4=FAIR, 5=POOR
  "gen_02a",   # VERIFIED: self-perceived mental health — alias resolves to gen_02b (GEN_02B in SAV)
               #   codes: 1=EXCELLENT, 2=VERY GOOD, 3=GOOD, 4=FAIR, 5=POOR
               #   WARNING: GEN_02 is "health compared to 1 yr ago" (NOT mental health);
               #            GEN_02A2 is "life satisfaction" 0-10 scale (NOT mental health)
  "gen_02",    # VERIFIED: self-perceived health compared to 1 year ago — GEN_02 in SAV
               #   codes: 1=MUCH BETTER, 2=SOMEWHAT BETTER, 3=ABOUT THE SAME,
               #          4=SOMEWHAT WORSE, 5=MUCH WORSE
  "rac_1",     # VERIFIED: activity limitations — RAC_1 in SAV
               #   ACTUAL CODES (3-category): 1=SOMETIMES, 2=OFTEN, 3=NEVER
               #   WARNING: prior recode used binary (1=Yes, 2=No) — WRONG; corrected below
  "inj_01"     # VERIFIED: injury in past 12 months — INJ_01 in SAV; 1=YES, 2=NO
)

vars_inferred_id <- c(
  # --- Identifiers / metadata (exceptions for data quality checks) ---
  "adm_rno"    # INFERRED: respondent sequence number (deduplication check)
)

# Combine all white-listed variables
vars_whitelist_all <- c(
  vars_confirmed,
  vars_inferred_ccc,
  vars_inferred_predisposing,
  vars_inferred_facilitating,
  vars_inferred_needs,
  vars_inferred_id
)

# Bootstrap weight pattern (500 variables: bsw001 through bsw500 or similar)
# Selected via grepl pattern after loading — NOT listed individually here
bootstrap_pattern <- "^bsw"   # matches bsw001, bsw002, ..., bsw500

# ---- declare-functions -------------------------------------------------------

# Attempt to select white-listed variables from a data frame.
# CONFIRMED variables trigger an error if missing.
# INFERRED variables trigger a warning if missing and are silently dropped.
select_whitelist <- function(data, confirmed, inferred, bootstrap_pat,
                             cycle_label = "") {
  all_cols <- names(data)

  # Confirmed: must be present
  missing_confirmed <- setdiff(confirmed, all_cols)
  if (length(missing_confirmed) > 0) {
    stop(sprintf(
      "[%s] MISSING CONFIRMED variables (%d): %s\n%s",
      cycle_label, length(missing_confirmed),
      paste(missing_confirmed, collapse = ", "),
      "Check ferry output: did 1-ferry.R run successfully?"
    ))
  }

  # Inferred: warn if missing, skip silently
  missing_inferred <- setdiff(inferred, all_cols)
  found_inferred   <- intersect(inferred, all_cols)
  if (length(missing_inferred) > 0) {
    warning(sprintf(
      "[%s] %d INFERRED variable(s) NOT found — dropped from white-list:\n  %s\n  Verify names against PDF data dictionaries in data-private/raw/2026-02-19/",
      cycle_label, length(missing_inferred),
      paste(missing_inferred, collapse = ", ")
    ))
  }

  # Bootstrap weights: pattern-matched
  boot_cols <- grep(bootstrap_pat, all_cols, value = TRUE)
  if (length(boot_cols) == 0) {
    warning(sprintf("[%s] No bootstrap weight columns found matching pattern '%s'",
                    cycle_label, bootstrap_pat))
  } else {
    vcat(sprintf("  Bootstrap weights found: %d columns (%s ... %s)\n",
                length(boot_cols), boot_cols[1], utils::tail(boot_cols, 1)))
  }

  keep_cols <- c(confirmed, found_inferred, boot_cols)
  data[, keep_cols, drop = FALSE]
}

# Harmonize known cross-cycle alias names to canonical white-list names.
# If canonical is missing and an alias exists, copy alias into canonical.
harmonize_aliases <- function(data, alias_map, cycle_label = "") {
  for (canonical in names(alias_map)) {
    if (canonical %in% names(data)) next

    aliases <- alias_map[[canonical]]
    found <- intersect(aliases, names(data))
    if (length(found) > 0) {
      data[[canonical]] <- data[[found[1]]]
      vcat(sprintf("  [%s] harmonized alias: %s <- %s\n",
                  cycle_label, canonical, found[1]))
    }
  }
  data
}

# Ensure columns exist before recoding; add as NA when absent.
ensure_columns <- function(data, cols, context_label = "") {
  missing_cols <- setdiff(cols, names(data))
  if (length(missing_cols) > 0) {
    for (col in missing_cols) {
      data[[col]] <- NA
    }
    warning(sprintf(
      "[%s] Added %d missing column(s) as NA for downstream compatibility: %s",
      context_label, length(missing_cols), paste(missing_cols, collapse = ", ")
    ))
  }
  data
}

# Safely recode a numeric vector into a factor.
# Returns NA (with a warning) for any values not in the code map.
safe_recode_factor <- function(x, code_map, ordered = FALSE) {
  result <- code_map[as.character(x)]
  n_unmatched <- sum(is.na(result) & !is.na(x))
  if (n_unmatched > 0) {
    warning(sprintf("%d value(s) not in code map — set to NA", n_unmatched))
  }
  factor(result, levels = unique(code_map), ordered = ordered)
}

# ==============================================================================
# SECTION 1: DATA IMPORT
# ==============================================================================

# ---- load-data ---------------------------------------------------------------
vcat("\n", strrep("=", 70), "\n")
vcat("SECTION 1: DATA IMPORT\n")
vcat(strrep("=", 70), "\n")

if (!file.exists(input_sqlite)) {
  stop("Ferry output not found: ", input_sqlite,
  "\nSearched: ", paste(input_sqlite_candidates, collapse = "; "),
  "\nRun manipulation/1-ferry.R first.")
}

cnn <- DBI::dbConnect(RSQLite::SQLite(), input_sqlite)
ds_2010_raw <- DBI::dbGetQuery(cnn, sprintf("SELECT * FROM %s", table_2010))
ds_2014_raw <- DBI::dbGetQuery(cnn, sprintf("SELECT * FROM %s", table_2014))
DBI::dbDisconnect(cnn)

# Input guardrails for cycle availability
if (nrow(ds_2010_raw) == 0L && nrow(ds_2014_raw) == 0L) {
  stop(
    sprintf(
      paste0(
        "Both ferry input tables are empty in %s.\\n",
        "- %s rows: %s\\n",
        "- %s rows: %s\\n",
        "Cannot proceed: run 1-ferry.R with valid raw inputs."
      ),
      input_sqlite,
      table_2010, format(nrow(ds_2010_raw), big.mark = ","),
      table_2014, format(nrow(ds_2014_raw), big.mark = ",")
    )
  )
}

if (nrow(ds_2010_raw) == 0L || nrow(ds_2014_raw) == 0L) {
  msg <- sprintf(
    paste0(
      "One ferry input table is empty in %s.\\n",
      "- %s rows: %s\\n",
      "- %s rows: %s\\n",
      "Likely cause: missing raw .sav file or failed ingest in 1-ferry.R."
    ),
    input_sqlite,
    table_2010, format(nrow(ds_2010_raw), big.mark = ","),
    table_2014, format(nrow(ds_2014_raw), big.mark = ",")
  )

  if (strict_cycle_integrity) {
    stop(msg, "\\nstrict_cycle_integrity=TRUE: stopping.")
  } else {
    warning(msg, "\\nContinuing with available cycle(s) because strict_cycle_integrity=FALSE.")
  }
}

# Harmonize known alias names before white-list selection.
# Entries verified against cchs_value_labels.csv (extract-metadata.R).
alias_map <- list(
  edudh04  = c("edudr04"),          # EDUDR04 present in both SAV cycles
  sdcdgcb  = c("sdcgcgt"),          # VERIFIED: SDCGCGT = visible minority (1=White, 2=Visible minority)
  geodgprv = c("geogprv"),          # VERIFIED: GEOGPRV = province of residence
  hcu_1aa  = c("hcu_1a", "hcudgmd"),# VERIFIED: HCU_1AA in SAV (1=YES, 2=NO)
  lbfdghp  = c("lbsg31"),           # VERIFIED: LBSG31 in SAV (1=EMPLOYEE, 2=SELF-EMPLOYED; no code 3)
  lbfdgft  = c("lbsdpft"),          # VERIFIED: LBSDPFT in SAV (1=FULL-TIME, 2=PART-TIME)
  incdghh  = c("incghh"),           # VERIFIED: INCGHH in SAV (5-category household income)
  fvcdgtot = c("fvcgtot"),          # VERIFIED: FVCGTOT in SAV (3-cat: <5/5-10/>10 per day)
  dhhdghsz = c("dhhghsz"),          # VERIFIED: DHHGHSZ in SAV (household size 1-5+)
  gen_02a  = c("gen_02b"),          # VERIFIED: GEN_02B = self-perceived mental health
                                    #   (GEN_02 = health vs. 1 yr ago — NOT mental health)
  inj_01   = c("injdgyrs")          # VERIFIED: INJ_01 in SAV (1=YES, 2=NO)
)

ds_2010_raw <- harmonize_aliases(ds_2010_raw, alias_map, cycle_label = "CCHS2010")
ds_2014_raw <- harmonize_aliases(ds_2014_raw, alias_map, cycle_label = "CCHS2014")

vcat(sprintf("📥 Loaded CCHS 2010-2011: %s rows, %s columns\n",
            format(nrow(ds_2010_raw), big.mark = ","),
            format(ncol(ds_2010_raw), big.mark = ",")))
vcat(sprintf("📥 Loaded CCHS 2013-2014: %s rows, %s columns\n",
            format(nrow(ds_2014_raw), big.mark = ","),
            format(ncol(ds_2014_raw), big.mark = ",")))

# ---- apply-whitelist ---------------------------------------------------------
vcat("\n📋 Applying white-list variable selection...\n")

vars_inferred_all <- c(vars_inferred_ccc, vars_inferred_predisposing,
                       vars_inferred_facilitating, vars_inferred_needs,
                       vars_inferred_id)

ds_2010_wl <- select_whitelist(ds_2010_raw, vars_confirmed, vars_inferred_all,
                                bootstrap_pattern, cycle_label = "CCHS2010")
ds_2014_wl <- select_whitelist(ds_2014_raw, vars_confirmed, vars_inferred_all,
                                bootstrap_pattern, cycle_label = "CCHS2014")

vcat(sprintf("  CCHS 2010-2011 after white-list: %s rows, %s columns\n",
            format(nrow(ds_2010_wl), big.mark = ","),
            format(ncol(ds_2010_wl), big.mark = ",")))
vcat(sprintf("  CCHS 2013-2014 after white-list: %s rows, %s columns\n",
            format(nrow(ds_2014_wl), big.mark = ","),
            format(ncol(ds_2014_wl), big.mark = ",")))

# ---- add-cycle-indicator -----------------------------------------------------
vcat("\n🔢 Adding cycle indicator variable...\n")

ds_2010_wl <- ds_2010_wl %>% mutate(cycle = 0L)   # 0 = CCHS 2010-2011
ds_2014_wl <- ds_2014_wl %>% mutate(cycle = 1L)   # 1 = CCHS 2013-2014

vcat("  cycle = 0: CCHS 2010-2011\n")
vcat("  cycle = 1: CCHS 2013-2014\n")

# ---- harmonize-and-stack -----------------------------------------------------
vcat("\n🔗 Harmonizing variable names between cycles and stacking...\n")
#
# If variable names differ between 2010 and 2014 cycles, rename to a common
# schema here. Common CCHS harmonization issues:
#   - Some derived variables changed names between cycles
#   - Verify using CCHS_2010_Alpha_Index.pdf vs CCHS_2014_Alpha_Index.pdf
#
# Currently: column names are assumed identical after clean_names().
# If differences are found during execution, add rename() steps below.
#
# Example template (uncomment and adjust):
# ds_2014_wl <- ds_2014_wl %>%
#   rename(
#     old_2014_name_1 = new_common_name_1,
#     old_2014_name_2 = new_common_name_2
#   )

# Align columns: use union; fill missing columns with NA
all_cols <- union(names(ds_2010_wl), names(ds_2014_wl))
ds_2010_aligned <- ds_2010_wl[, intersect(all_cols, names(ds_2010_wl)), drop = FALSE]
ds_2014_aligned <- ds_2014_wl[, intersect(all_cols, names(ds_2014_wl)), drop = FALSE]

# Add missing columns as NA in each cycle's dataset
for (col in setdiff(all_cols, names(ds_2010_aligned))) {
  ds_2010_aligned[[col]] <- NA
}
for (col in setdiff(all_cols, names(ds_2014_aligned))) {
  ds_2014_aligned[[col]] <- NA
}

ds0 <- bind_rows(ds_2010_aligned, ds_2014_aligned) %>%
  select(cycle, everything())   # cycle first

vcat(sprintf("  ✓ Pooled (both cycles): %s rows, %s columns\n",
            format(nrow(ds0), big.mark = ","),
            format(ncol(ds0), big.mark = ",")))
vcat(sprintf("  ✓ CCHS 2010-2011: %s rows\n", format(sum(ds0$cycle == 0L), big.mark = ",")))
vcat(sprintf("  ✓ CCHS 2013-2014: %s rows\n", format(sum(ds0$cycle == 1L), big.mark = ",")))

if (sum(ds0$cycle == 0L, na.rm = TRUE) == 0L || sum(ds0$cycle == 1L, na.rm = TRUE) == 0L) {
  msg <- paste0(
    "Cycle integrity check before transformations: one cycle has 0 rows in pooled ds0.\n",
    "Inspect white-list/alias mappings and upstream ferry input tables."
  )
  if (strict_cycle_integrity) {
    stop(msg)
  } else {
    warning(msg)
  }
}

# ==============================================================================
# SECTION 2: ELLIS TRANSFORMATIONS
# ==============================================================================

vcat("\n", strrep("=", 70), "\n")
vcat("SECTION 2: ELLIS TRANSFORMATIONS\n")
vcat(strrep("=", 70), "\n")

# ---- tweak-data-1-outcomes ---------------------------------------------------
vcat("\n🔧 Step 1: Construct outcome variables\n")
#
# Primary outcome: days_absent_total
#   Sum of all 8 LOP reason variables. NA treated as 0 when at least one
#   non-NA value exists across the 8 components. When ALL are NA, treat as 0
#   (no reported absence reasons) to preserve structural zeros.
#
# Sensitivity outcome: days_absent_chronic
#   Single variable lopg040 (days lost due to chronic condition only).
#
# NOTE: The prior analysis capped the range at 0–90 days. Values outside
#       this range should be treated as data quality issues and flagged.

lop_vars <- c("lopg040", "lopg070", "lopg082", "lopg083",
              "lopg084", "lopg085", "lopg086", "lopg100")

ds1 <- ds0 %>%
  mutate(
    # Primary outcome: rowwise sum (NA-safe: at least one component must be non-NA)
    days_absent_total = rowSums(
      across(all_of(lop_vars), ~ as.numeric(.x)),
      na.rm = TRUE
    ),
    # Flag respondents where ALL 8 LOP components are NA.
    # In CCHS skip-patterns this generally indicates no absences (structural zero).
    outcome_all_na = rowSums(is.na(across(all_of(lop_vars)))) == length(lop_vars),
    days_absent_total = if_else(outcome_all_na, 0, days_absent_total),

    # Sensitivity outcome: chronic condition days only
    days_absent_chronic = as.numeric(lopg040)
  )

# Enforce valid range for primary outcome (0-90 days).
# Values outside this range are treated as data quality issues and set to NA.
invalid_total <- !is.na(ds1$days_absent_total) &
  (ds1$days_absent_total < 0 | ds1$days_absent_total > 90)
n_invalid_total <- sum(invalid_total)
if (n_invalid_total > 0) {
  warning(sprintf(
    "%d respondents have days_absent_total outside 0-90 and were set to NA",
    n_invalid_total
  ))
  ds1$days_absent_total[invalid_total] <- NA_real_
}

vcat(sprintf("   ✓ days_absent_total range: %g – %g (n non-NA: %s)\n",
            min(ds1$days_absent_total, na.rm = TRUE),
            max(ds1$days_absent_total, na.rm = TRUE),
            format(sum(!is.na(ds1$days_absent_total)), big.mark = ",")))
vcat(sprintf("   ✓ days_absent_chronic range: %g – %g (n non-NA: %s)\n",
            min(ds1$days_absent_chronic, na.rm = TRUE),
            max(ds1$days_absent_chronic, na.rm = TRUE),
            format(sum(!is.na(ds1$days_absent_chronic)), big.mark = ",")))

# ---- tweak-data-2-exclusions -------------------------------------------------
vcat("\n🔧 Step 2: Sample inclusion mode\n")
#
# If apply_sample_exclusions=TRUE, apply legacy exclusions (Section 3.1):
#   1. Age outside 15-75 (dhhgage)
#   2. Not employed in past 3 months (lop_015 != 1)
#   3. Proxy respondent (adm_prx == 1)
#   4. Incomplete outcome or predictor data
#
# If apply_sample_exclusions=FALSE (default), retain full pooled sample
# from ferry output (employed + unemployed + not stated), after white-listing.
#
# CCHS DHHGAGE codes (VERIFIED: extracted from attr(DHHGAGE, 'labels') in both SAV files;
#   identical across 2010-2011 and 2013-2014 cycles):
#   1=12-14yrs, 2=15-17yrs, 3=18-19yrs, 4=20-24yrs, 5=25-29yrs, 6=30-34yrs,
#   7=35-39yrs, 8=40-44yrs, 9=45-49yrs, 10=50-54yrs, 11=55-59yrs, 12=60-64yrs,
#   13=65-69yrs, 14=70-74yrs, 15=75-79yrs, 16=80+yrs
# Include: codes 2-15 (15-79 yrs). Age 75 is in code 15 (75-79); code 15 is kept
# since data cannot distinguish 75 from 76-79 in the PUMF grouped variable.
#
# LOP_015: 1=Yes (employed), 2=No, 6=Not applicable, 9=Not stated
# ADM_PRX: 1=Proxy, 2=Not proxy

# Identify predictor variables (non-structural white-listed columns)
predictor_cols <- setdiff(
  names(ds1),
  c("cycle", lop_vars, "days_absent_total", "days_absent_chronic",
    "outcome_all_na", "lop_015", "dhhgage", "adm_prx",
    "wts_m", "geodpmf",
    grep(bootstrap_pattern, names(ds1), value = TRUE))
)

# Track sample sizes at each step
n_step <- integer(0)
n_step["n_start"] <- nrow(ds1)

# Apply sequential filters only when explicitly requested
if (isTRUE(apply_sample_exclusions)) {
  vcat("   Mode: legacy exclusions enabled (employment filter applied)\n")

  ds2 <- ds1

  # Step 1: Age 15–75
  # DHHGAGE codes 2–15 correspond to ages 15–79.
  # Code 15 = 75-79 yrs (grouped; no single-year resolution in PUMF).
  # The instruction says exclude >75, but since ages 75-79 share one code,
  # code 15 is RETAINED to capture 75-year-olds — ages 76-79 in code 15
  # are an unavoidable inclusion given the grouped derived variable.
  # VERIFY if a single-year age variable is available in the restricted-access file.
  in_age_range <- ds2$dhhgage %in% 2:15   # codes 2=15-17 through 15=75-79
  n_step["n_after_age"] <- sum(in_age_range, na.rm = TRUE)
  ds2 <- ds2 %>% filter(dhhgage %in% 2:15)

  # Step 2: Employed in past 3 months
  in_employed <- ds2$lop_015 == 1
  n_step["n_after_employment"] <- sum(in_employed, na.rm = TRUE)
  ds2 <- ds2 %>% filter(lop_015 == 1)

  # Step 3: Exclude proxy respondents
  not_proxy <- ds2$adm_prx != 1 | is.na(ds2$adm_prx)
  n_step["n_after_proxy"] <- sum(not_proxy, na.rm = TRUE)
  ds2 <- ds2 %>% filter(adm_prx != 1 | is.na(adm_prx))

  # Step 4: Complete outcome (days_absent_total must be non-NA)
  complete_outcome <- !is.na(ds2$days_absent_total)
  n_step["n_after_complete_outcome"] <- sum(complete_outcome, na.rm = TRUE)
  ds2 <- ds2 %>% filter(!is.na(days_absent_total))

  vcat(sprintf("   ✓ Starting pool:             %s\n", format(n_step["n_start"], big.mark = ",")))
  vcat(sprintf("   ✓ After age 15-75:           %s  (-%s excluded)\n",
              format(n_step["n_after_age"], big.mark = ","),
              format(n_step["n_start"] - n_step["n_after_age"], big.mark = ",")))
  vcat(sprintf("   ✓ After employed filter:     %s  (-%s excluded)\n",
              format(n_step["n_after_employment"], big.mark = ","),
              format(n_step["n_after_age"] - n_step["n_after_employment"], big.mark = ",")))
  vcat(sprintf("   ✓ After proxy exclusion:     %s  (-%s excluded)\n",
              format(n_step["n_after_proxy"], big.mark = ","),
              format(n_step["n_after_employment"] - n_step["n_after_proxy"], big.mark = ",")))
  vcat(sprintf("   ✓ After complete outcome:    %s  (-%s excluded)\n",
              format(n_step["n_after_complete_outcome"], big.mark = ","),
              format(n_step["n_after_proxy"] - n_step["n_after_complete_outcome"], big.mark = ",")))
} else {
  vcat("   Mode: full pooled sample (no exclusions applied)\n")

  ds2 <- ds1
  n_step["n_after_age"] <- n_step["n_start"]
  n_step["n_after_employment"] <- n_step["n_start"]
  n_step["n_after_proxy"] <- n_step["n_start"]
  n_step["n_after_complete_outcome"] <- n_step["n_start"]

  vcat(sprintf("   ✓ Starting pool:             %s\n", format(n_step["n_start"], big.mark = ",")))
  vcat(sprintf("   ✓ Full pooled retained:      %s  (-0 excluded)\n",
              format(n_step["n_after_complete_outcome"], big.mark = ",")))

  if (verbose) {
  cat("\n   Employment distribution retained (lop_015):\n")
  print(ds2 %>%
          count(lop_015, name = "n") %>%
          arrange(lop_015))
  }
}

# Step 5b (optional): CCC + predictor completeness (§3.1 criterion 4b)
# Controlled by `apply_completeness_exclusion` in the globals section.
# NOTE: ds2 is still pre-recode at this point — only structural NAs from
#       import are detected here. CCHS special codes (6/7/8/9) become NA
#       only after Step 3 factor recoding. For full §3.1 compliance, verify
#       that recode order matches the intended exclusion timing.
if (isTRUE(apply_completeness_exclusion)) {
  vcat("\n   Step 5b: CCC + predictor completeness exclusion\n")
  ccc_cols_found      <- intersect(vars_inferred_ccc, names(ds2))
  predictor_cols_full <- intersect(c(ccc_cols_found, predictor_cols), names(ds2))
  complete_predictors <- apply(
    ds2[, predictor_cols_full, drop = FALSE], 1,
    function(row) !any(is.na(row))
  )
  n_step["n_after_complete_predictors"] <- sum(complete_predictors, na.rm = TRUE)
  n_before_step5b <- nrow(ds2)
  ds2 <- ds2[complete_predictors, ]
  vcat(sprintf("   ✓ After CCC + predictor completeness: %s  (-%s excluded)\n",
              format(n_step["n_after_complete_predictors"], big.mark = ","),
              format(n_before_step5b - n_step["n_after_complete_predictors"], big.mark = ",")))
}

if (verbose) {
  cat("\n   Cycle counts after exclusions:\n")
  print(ds2 %>%
          count(cycle, name = "n") %>%
          arrange(cycle))
}

if (sum(ds2$cycle == 0L, na.rm = TRUE) == 0L || sum(ds2$cycle == 1L, na.rm = TRUE) == 0L) {
  msg <- paste0(
    "Cycle integrity check after exclusions: one cycle has 0 rows.\n",
    "Verify variable coding consistency across cycles (especially dhhgage, lop_015, adm_prx, LOP outcomes)."
  )
  if (strict_cycle_integrity) {
    stop(msg)
  } else {
    warning(msg)
  }
}

n_final <- nrow(ds2)
cat(sprintf("\n   Final analytical sample: %s\n", format(n_final, big.mark = ",")))
if (isTRUE(apply_sample_exclusions)) {
  vcat(sprintf("   Reference (legacy exclusions): 64,141\n"))
  if (abs(n_final - 64141) > 5000) {
    warning(sprintf(
      "Final sample size (%d) differs from reference (64,141) by >5,000.\nVerify exclusion variable codes against data dictionaries.",
      n_final
    ))
  }
} else {
  vcat(sprintf("   Reference mode: full pooled sample from ferry output (employment not filtered)\n"))
}

# Build sample_flow table (for reproducing Figure 1 flowchart)
sample_flow <- tibble::tibble(
  step = c(
    "1_start",
    "2_after_age_15_75",
    "3_after_employed",
    "4_after_no_proxy",
    "5_after_complete_outcome"
  ),
  description = c(
    "Starting pool (both CCHS cycles pooled)",
    if (isTRUE(apply_sample_exclusions)) "Exclude respondents outside age 15-75" else "No exclusion applied (full pooled sample mode)",
    if (isTRUE(apply_sample_exclusions)) "Exclude respondents not employed (past 3 months)" else "No exclusion applied (employment retained)",
    if (isTRUE(apply_sample_exclusions)) "Exclude proxy respondents" else "No exclusion applied (proxy retained)",
    if (isTRUE(apply_sample_exclusions)) "Exclude respondents with missing outcome (days absent)" else "No exclusion applied (outcome missingness retained)"
  ),
  n_remaining = as.integer(c(
    n_step["n_start"],
    n_step["n_after_age"],
    n_step["n_after_employment"],
    n_step["n_after_proxy"],
    n_step["n_after_complete_outcome"]
  )),
  n_excluded  = as.integer(c(
    0L,
    n_step["n_start"]            - n_step["n_after_age"],
    n_step["n_after_age"]        - n_step["n_after_employment"],
    n_step["n_after_employment"] - n_step["n_after_proxy"],
    n_step["n_after_proxy"]      - n_step["n_after_complete_outcome"]
  )),
  pct_remaining = round(n_remaining / n_step["n_start"] * 100, 1)
)

# Conditionally append step 6 (CCC + predictor completeness)
if (isTRUE(apply_completeness_exclusion) && "n_after_complete_predictors" %in% names(n_step)) {
  sample_flow <- rbind(sample_flow, tibble::tibble(
    step          = "6_after_complete_ccc_predictors",
    description   = "Exclude respondents with missing values on any CCC condition or predictor variable (§3.1)",
    n_remaining   = as.integer(n_step["n_after_complete_predictors"]),
    n_excluded    = as.integer(n_step["n_after_complete_outcome"] - n_step["n_after_complete_predictors"]),
    pct_remaining = round(n_step["n_after_complete_predictors"] / n_step["n_start"] * 100, 1)
  ))
}

if (verbose) {
  cat("\n   Sample flow table:\n")
  print(as.data.frame(sample_flow[, c("step", "n_remaining", "n_excluded")]))
}

# ---- tweak-data-3-factors ----------------------------------------------------
vcat("\n🔧 Step 3: Factor recoding\n")
#
# All CCHS numeric codes below are based on standard PUMF documentation.
# VERIFY each recode against:
#   CCHS_2010_DataDictionary_Freqs-ver2.pdf
#   CCHS_2014_DataDictionary_Freqs.pdf
#
# Pattern: original raw numeric column → recoded factor column
# Labelling convention: Human-readable ordered factor where meaningful
#
# NOTE ON CCHS CODES: Special codes 6=Not applicable, 7=Don't know,
#   8=Refusal, 9=Not stated are mapped to NA throughout.

special_na_codes <- c(6, 7, 8, 9, 96, 97, 98, 99)

# Inferred recode source variables may be absent in one/both cycles.
# Ensure they exist as NA columns so mutate()/case_when() never fails.
recode_source_vars <- c(
  "dhhgage", "dhh_sex", "dhhgms", "edudh04", "sdcfimm", "sdcdgcb",
  "incdghh", "hcu_1aa", "lbfdghp", "lbfdgft", "alcdgtyp", "smkdsty",
  "hwtdgbmi", "pacdpai", "gen_01", "gen_02a", "gen_02", "rac_1", "inj_01",
  # Added: previously missing from recode pipeline
  "dhhdglvg",   # homeownership
  "gen_07",     # job stress level
  "sdcdgstud",  # student status
  "noc_31"      # occupation category
)

ds2 <- ensure_columns(ds2, recode_source_vars, context_label = "factor recoding inputs")

ds3 <- ds2 %>%
  mutate(

    # --- Age group (3 categories per stats_instructions_v3) ---
    # DHHGAGE codes: 2=15-17, 3=18-19, 4=20-24, 5=25-29, 6=30-34, 7=35-39,
    #   8=40-44, 9=45-49, 10=50-54, 11=55-59, 12=60-64, 13=65-69, 14=70-74,
    #   15=75-79  (VERIFIED: identical in both cycles; extracted from SAV metadata)
    age_group = factor(
      case_when(
        dhhgage %in% 2:4  ~ "15-24",       # 15-24 yrs
        dhhgage %in% 5:10 ~ "25-54",       # 25-54 yrs
        dhhgage %in% 11:15 ~ "55-75",      # 55-75 yrs
        TRUE ~ NA_character_
      ),
      levels = c("15-24", "25-54", "55-75"),
      ordered = TRUE
    ),

    # --- Sex ---
    # DHH_SEX: 1=Male, 2=Female
    sex = factor(
      case_when(
        dhh_sex == 1 ~ "Male",
        dhh_sex == 2 ~ "Female",
        dhh_sex %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Male", "Female")
    ),

    # --- Marital status ---
    # DHHGMS: 1=Married, 2=Common-law, 3=Widowed/Divorced/Separated, 4=Single
    marital_status = factor(
      case_when(
        dhhgms == 1 ~ "Married",
        dhhgms == 2 ~ "Common-law",
        dhhgms == 3 ~ "Widowed/Divorced/Separated",
        dhhgms == 4 ~ "Single",
        dhhgms %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Single", "Married", "Common-law", "Widowed/Divorced/Separated")
    ),

    # --- Education (derived 4-category, EDUDH04 or EDUDR04) ---
    # Numeric codes are consistent across cycles; label wording differs:
    #   Code | 2010-2011 label          | 2013-2014 label
    #   -----+--------------------------+---------------------------
    #     1  | < THAN SECONDARY         | < SEC. SCHOOL GR       (cosmetic)
    #     2  | SECONDARY GRAD.          | SEC. SCHOOL. GR.       (cosmetic)
    #     3  | OTHER POST-SEC.          | SOME POST-SEC ED        *** CONCEPTUAL ***
    #     4  | POST-SEC. GRAD.          | POST-SEC CERT          (cosmetic)
    #
    # ⚠️  CROSS-CYCLE DISCREPANCY — Code 3 decision:
    #   2010: "Other post-secondary" implies incomplete/non-degree programs
    #         (certificates, diplomas, vocational) but NOT "some college".
    #   2014: "Some post-secondary" implies partial post-secondary attendance.
    #   These are plausibly the same population (non-graduate post-secondary
    #   participants), but there is conceptual ambiguity. The label "Some
    #   post-secondary" is adopted here as the common denominator.
    #   ► This decision must be flagged in the Methods section and treated
    #     as a limitation for the education predictor interpretation.
    #     See cchs_value_label_diffs.csv (EDUDR04) for the source comparison.
    education = factor(
      case_when(
        edudh04 == 1 ~ "Less than secondary",
        edudh04 == 2 ~ "Secondary graduate",
        edudh04 == 3 ~ "Some post-secondary",   # see note above re: cross-cycle ambiguity
        edudh04 == 4 ~ "Post-secondary graduate",
        edudh04 %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Less than secondary", "Secondary graduate",
                 "Some post-secondary", "Post-secondary graduate"),
      ordered = TRUE
    ),

    # --- Immigration status ---
    # SDCFIMM: 1=Immigrant, 2=Non-immigrant; 3=Non-permanent resident
    immigration_status = factor(
      case_when(
        sdcfimm == 1 ~ "Immigrant",
        sdcfimm == 2 ~ "Non-immigrant",
        sdcfimm == 3 ~ "Non-permanent resident",
        sdcfimm %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Non-immigrant", "Immigrant", "Non-permanent resident")
    ),

    # --- Visible minority / ethnic origin ---
    # SDCDGCB: 1=White (not visible min), 2=Visible minority
    visible_minority = factor(
      case_when(
        sdcdgcb == 1 ~ "White",
        sdcdgcb == 2 ~ "Visible minority",
        sdcdgcb %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("White", "Visible minority")
    ),

    # --- Household income (5 categories) ---
    # INCDGHH: 1=<$20k, 2=$20k-$39.9k, 3=$40k-$59.9k, 4=$60k-$79.9k, 5=$80k+
    income_5cat = factor(
      case_when(
        incdghh == 1 ~ "< $20k",
        incdghh == 2 ~ "$20k - $39.9k",
        incdghh == 3 ~ "$40k - $59.9k",
        incdghh == 4 ~ "$60k - $79.9k",
        incdghh == 5 ~ "$80k+",
        incdghh %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("< $20k", "$20k - $39.9k", "$40k - $59.9k",
                 "$60k - $79.9k", "$80k+"),
      ordered = TRUE
    ),

    # --- Has regular family doctor ---
    # HCU_1AA: 1=Yes, 2=No
    has_family_doctor = factor(
      case_when(
        hcu_1aa == 1 ~ "Yes",
        hcu_1aa == 2 ~ "No",
        hcu_1aa %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Yes", "No")
    ),

    # --- Employment type (self-employed vs employee) ---
    # LBFDGHP: 1=Employee, 2=Self-employed, 3=Unpaid family worker
    employment_type = factor(
      case_when(
        lbfdghp == 1 ~ "Employee",
        lbfdghp == 2 ~ "Self-employed",
        lbfdghp == 3 ~ "Unpaid family worker",
        lbfdghp %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Employee", "Self-employed", "Unpaid family worker")
    ),

    # --- Work schedule (full-time vs part-time) ---
    # LBFDGFT: 1=Full-time, 2=Part-time
    work_schedule = factor(
      case_when(
        lbfdgft == 1 ~ "Full-time",
        lbfdgft == 2 ~ "Part-time",
        lbfdgft %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Full-time", "Part-time")
    ),

    # --- Alcohol use (derived type of drinker) ---
    # ALCDGTYP: 1=Regular drinker, 2=Occasional drinker, 3=Former drinker,
    #           4=Never drinker (lifetime abstainer)
    alcohol_type = factor(
      case_when(
        alcdgtyp == 1 ~ "Regular drinker",
        alcdgtyp == 2 ~ "Occasional drinker",
        alcdgtyp == 3 ~ "Former drinker",
        alcdgtyp == 4 ~ "Never drinker",
        alcdgtyp %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Never drinker", "Former drinker",
                 "Occasional drinker", "Regular drinker")
    ),

    # --- Smoking status (derived) ---
    # SMKDSTY — VERIFIED: both SAV cycles.
    #   Actual codes: 1=DAILY, 2=OCCASIONAL (current), 3=ALWAYS OCCASIONAL (former),
    #                 4=FORMER DAILY, 5=FORMER OCCASIONAL, 6=NEVER SMOKED
    #   Special NAs: 96/97/98/99 (NOT 6/7/8/9 — code 6=Never must come before special_na_codes)
    #   → Collapsed: Daily / Occasional / Former (3+4+5) / Never
    smoking_status = factor(
      case_when(
        smkdsty == 1 ~ "Daily",
        smkdsty == 2 ~ "Occasional",
        smkdsty %in% 3:5 ~ "Former",
        smkdsty == 6 ~ "Never",
        smkdsty %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Never", "Former", "Occasional", "Daily"),
      ordered = TRUE
    ),

    # --- BMI category (derived) ---
    # HWTDGBMI: 1=Underweight (<18.5), 2=Normal (18.5-24.9),
    #           3=Overweight (25-29.9), 4=Obese (30+)
    bmi_category = factor(
      case_when(
        hwtdgbmi == 1 ~ "Underweight",
        hwtdgbmi == 2 ~ "Normal weight",
        hwtdgbmi == 3 ~ "Overweight",
        hwtdgbmi == 4 ~ "Obese",
        hwtdgbmi %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Underweight", "Normal weight", "Overweight", "Obese"),
      ordered = TRUE
    ),

    # --- Physical activity index (derived) ---
    # PACDPAI: 1=Active, 2=Moderately active, 3=Inactive
    physical_activity = factor(
      case_when(
        pacdpai == 1 ~ "Active",
        pacdpai == 2 ~ "Moderately active",
        pacdpai == 3 ~ "Inactive",
        pacdpai %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Active", "Moderately active", "Inactive"),
      ordered = TRUE
    ),

    # --- Self-perceived general health ---
    # GEN_01: 1=Excellent, 2=Very good, 3=Good, 4=Fair, 5=Poor
    self_health_general = factor(
      case_when(
        gen_01 == 1 ~ "Excellent",
        gen_01 == 2 ~ "Very good",
        gen_01 == 3 ~ "Good",
        gen_01 == 4 ~ "Fair",
        gen_01 == 5 ~ "Poor",
        gen_01 %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Excellent", "Very good", "Good", "Fair", "Poor"),
      ordered = TRUE
    ),

    # --- Self-perceived mental health ---
    # GEN_02B: 1=Excellent, 2=Very good, 3=Good, 4=Fair, 5=Poor
    # VERIFIED: GEN_02B label = "Self-perceived mental health" in both SAV cycles.
    # alias_map resolves gen_02a → gen_02b when gen_02a is absent from raw data.
    # ALERT: GEN_02 is "health compared to 1 yr ago" (NOT mental health);
    #        GEN_02A2 is "satisfaction with life" 0-10 scale (NOT mental health).
    self_health_mental = factor(
      case_when(
        gen_02a == 1 ~ "Excellent",
        gen_02a == 2 ~ "Very good",
        gen_02a == 3 ~ "Good",
        gen_02a == 4 ~ "Fair",
        gen_02a == 5 ~ "Poor",
        gen_02a %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Excellent", "Very good", "Good", "Fair", "Poor"),
      ordered = TRUE
    ),

    # --- Health compared to 1 year ago ---
    # GEN_02: 1=Much better, 2=Somewhat better, 3=About the same,
    #         4=Somewhat worse, 5=Much worse
    # VERIFIED: GEN_02 label = "Self-perceived hlth - compared 1 yr ago" in both SAV cycles.
    health_vs_lastyear = factor(
      case_when(
        gen_02 == 1 ~ "Much better",
        gen_02 == 2 ~ "Somewhat better",
        gen_02 == 3 ~ "About the same",
        gen_02 == 4 ~ "Somewhat worse",
        gen_02 == 5 ~ "Much worse",
        gen_02 %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Much better", "Somewhat better", "About the same",
                 "Somewhat worse", "Much worse"),
      ordered = TRUE
    ),

    # --- Functional limitations / activity limitations ---
    # RAC_1 — VERIFIED: 3-category variable in both SAV cycles.
    #   Actual codes: 1=SOMETIMES (limited), 2=OFTEN (limited), 3=NEVER (limited)
    #   Codes 1 and 2 are both affirmative (limited), code 3 = not limited.
    #   Former binary recode (1=Yes, 2=No) was WRONG — code 2=OFTEN was silently
    #   mapped to NA, losing all "often limited" respondents.
    activity_limitation = factor(
      case_when(
        rac_1 %in% c(1, 2) ~ "Yes",   # 1=SOMETIMES or 2=OFTEN → limited
        rac_1 == 3          ~ "No",    # 3=NEVER → not limited
        rac_1 %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Yes", "No")
    ),

    # --- Injury status ---
    # INJ_01: 1=Yes, 2=No
    injury_past_year = factor(
      case_when(
        inj_01 == 1 ~ "Yes",
        inj_01 == 2 ~ "No",
        inj_01 %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Yes", "No")
    ),

    # --- Homeownership / living arrangements (§2.2 predisposing) ---
    # DHHDGLVG: typical CCHS codes — VERIFY against data dictionary
    # Common coding: 1=Owner, 2=Renter/other
    homeownership = factor(
      case_when(
        dhhdglvg == 1 ~ "Owner",
        dhhdglvg == 2 ~ "Renter/other",
        dhhdglvg %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Owner", "Renter/other")
    ),

    # --- Job stress level (§2.2 facilitating) ---
    # GEN_07: 1=Not at all stressful, 2=Not very stressful, 3=A bit stressful,
    #          4=Quite a bit stressful, 5=Extremely stressful  — VERIFY codes
    job_stress = factor(
      case_when(
        gen_07 == 1 ~ "Not at all stressful",
        gen_07 == 2 ~ "Not very stressful",
        gen_07 == 3 ~ "A bit stressful",
        gen_07 == 4 ~ "Quite a bit stressful",
        gen_07 == 5 ~ "Extremely stressful",
        gen_07 %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Not at all stressful", "Not very stressful",
                 "A bit stressful", "Quite a bit stressful", "Extremely stressful"),
      ordered = TRUE
    ),

    # --- Student status (§2.2 predisposing) ---
    # SDCDGSTUD: 1=Full-time student, 2=Part-time student, 3=Not a student — VERIFY
    student_status = factor(
      case_when(
        sdcdgstud == 1 ~ "Full-time student",
        sdcdgstud == 2 ~ "Part-time student",
        sdcdgstud == 3 ~ "Not a student",
        sdcdgstud %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Not a student", "Part-time student", "Full-time student")
    ),

    # --- Occupation category (§2.2 facilitating) ---
    # NOC_31: National Occupation Classification major group — VERIFY codes
    # Typical NOC major groups: 0=Management, 1=Business/finance, 2=Natural sciences,
    #   3=Health, 4=Education, 5=Art/culture, 6=Sales/service, 7=Trades,
    #   8=Primary industries, 9=Manufacturing/utilities
    occupation_category = factor(
      case_when(
        noc_31 == 0  ~ "Management",
        noc_31 == 1  ~ "Business/finance/admin",
        noc_31 == 2  ~ "Natural/applied sciences",
        noc_31 == 3  ~ "Health",
        noc_31 == 4  ~ "Education/law/social",
        noc_31 == 5  ~ "Art/culture/sport",
        noc_31 == 6  ~ "Sales/service",
        noc_31 == 7  ~ "Trades/transport",
        noc_31 == 8  ~ "Primary industries",
        noc_31 == 9  ~ "Manufacturing/utilities",
        noc_31 %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Management", "Business/finance/admin", "Natural/applied sciences",
                 "Health", "Education/law/social", "Art/culture/sport",
                 "Sales/service", "Trades/transport", "Primary industries",
                 "Manufacturing/utilities")
    ),

    # --- Cycle as factor for models ---
    cycle_f = factor(
      case_when(
        cycle == 0L ~ "CCHS 2010-2011",
        cycle == 1L ~ "CCHS 2013-2014"
      ),
      levels = c("CCHS 2010-2011", "CCHS 2013-2014")
    )
  )

# Factor recoding for 19 chronic condition variables
# CCC variables: 1=Yes, 2=No, 6=Not applicable, 7=DK, 8=Refusal, 9=Not stated
ccc_vars_found <- intersect(vars_inferred_ccc, names(ds3))
# CCC label map — VERIFIED against cchs_variable_labels.csv (extract-metadata.R)
# Maps clean white-list variable name → short analytical label (used as cc_<label>).
# Prior version had wrong assignments: ccc_015/ccc_011/ccc_051/ccc_061 were
# mis-numbered. Corrected below based on SAV metadata.
ccc_labels <- c(
  ccc_031 = "asthma",           # VERIFIED: CCC_031 = "Has asthma" (both cycles)
  ccc_041 = "fibromyalgia",     # VERIFIED: CCC_041 = "Has fibromyalgia" (both cycles)
  ccc_051 = "arthritis",        # VERIFIED: CCC_051 = "Has arthritis" (both cycles)
  ccc_061 = "back_problems",    # VERIFIED: CCC_061 = "Has back problems/excl. fibro/arthritis"
  ccc_071 = "hypertension",     # VERIFIED: CCC_071 = "Has high blood pressure"
  ccc_081 = "migraine",         # VERIFIED: CCC_081 = "Has migraine headaches"
  ccc_091 = "copd",             # VERIFIED: CCC_091 = "Has a COPD"
  ccc_101 = "diabetes",         # VERIFIED: CCC_101 = "Has diabetes"
  ccc_121 = "heart_disease",    # VERIFIED: CCC_121 = "Has heart disease"
  ccc_131 = "cancer",           # VERIFIED: CCC_131 = "Has cancer"
  ccc_141 = "ulcer",            # VERIFIED: CCC_141 = "Has stomach or intestinal ulcers"
  ccc_151 = "stroke",           # VERIFIED: CCC_151 = "Suffers from the effects of a stroke"
  ccc_171 = "bowel_disorder",   # VERIFIED: CCC_171 = "Has bowel disorder"
  ccc_251 = "chronic_fatigue",  # VERIFIED: CCC_251 = "Has chronic fatigue syndrome"
  ccc_261 = "chemical_sensitiv",# VERIFIED: CCC_261 = "Suffers multiple chemical sensitivities"
  ccc_280 = "mood_disorder",    # VERIFIED: CCC_280 = "Has a mood disorder"
  ccc_290 = "anxiety_disorder", # VERIFIED: CCC_290 = "Has an anxiety disorder"
  ccc_300 = "other_mental_ill", # NOT FOUND in SAV — NEEDS EXTERNAL DICT VERIFICATION
  ccc_185 = "digestive_disease" # NOT FOUND in SAV — NEEDS EXTERNAL DICT VERIFICATION
)

if (verbose) {
  cat("\n  Recoding chronic condition flags:\n")
  for (v in ccc_vars_found) {
    label <- if (v %in% names(ccc_labels)) ccc_labels[v] else v
    new_name <- paste0("cc_", label)
    ds3[[new_name]] <- factor(
      case_when(
        ds3[[v]] == 1L ~ "Yes",
        ds3[[v]] == 2L ~ "No",
        ds3[[v]] %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Yes", "No")
    )
    cat(sprintf("    %-18s → %-22s : Yes=%d, No=%d, NA=%d\n",
                v, new_name,
                sum(ds3[[new_name]] == "Yes", na.rm = TRUE),
                sum(ds3[[new_name]] == "No",  na.rm = TRUE),
                sum(is.na(ds3[[new_name]]))))
  }
} else {
  for (v in ccc_vars_found) {
    label <- if (v %in% names(ccc_labels)) ccc_labels[v] else v
    new_name <- paste0("cc_", label)
    ds3[[new_name]] <- factor(
      case_when(
        ds3[[v]] == 1L ~ "Yes",
        ds3[[v]] == 2L ~ "No",
        ds3[[v]] %in% special_na_codes ~ NA_character_,
        TRUE ~ NA_character_
      ),
      levels = c("Yes", "No")
    )
  }
}

vcat(sprintf("   ✓ Factor recoding complete. Columns after recoding: %d\n", ncol(ds3)))

# ---- tweak-data-4-weights ----------------------------------------------------
vcat("\n🔧 Step 4: Survey weight adjustment for pooling\n")
#
# Statistics Canada guideline: when pooling two CCHS annual cycles, divide
# each respondent's original survey weight by the number of cycles pooled (2).
# This maintains the correct total weighted population size.
# Bootstrap weights are adjusted identically.

boot_cols <- grep(bootstrap_pattern, names(ds3), value = TRUE)

ds4 <- ds3 %>%
  mutate(
    wts_m_original = wts_m,          # preserve original for reference
    wts_m_pooled   = wts_m / 2       # pooled weight: divide by 2
  )

# Adjust bootstrap weights
if (length(boot_cols) > 0) {
  ds4 <- ds4 %>%
    mutate(across(all_of(boot_cols), ~ .x / 2))
  vcat(sprintf("   ✓ Original weight (wts_m) preserved in wts_m_original\n"))
  vcat(sprintf("   ✓ Pooled weight (wts_m / 2) → wts_m_pooled\n"))
  vcat(sprintf("   ✓ %d bootstrap weights divided by 2\n", length(boot_cols)))
} else {
  cat("   ⚠ No bootstrap weight columns found — weight adjustment incomplete\n")
  cat("   Bootstrap weights are required for correct variance estimation.\n")
}

vcat(sprintf("   ✓ Mean original weight: %.1f\n", mean(ds4$wts_m_original, na.rm = TRUE)))
vcat(sprintf("   ✓ Mean pooled weight:   %.1f\n", mean(ds4$wts_m_pooled, na.rm = TRUE)))

# ---- tweak-data-5-types ------------------------------------------------------
vcat("\n🔧 Step 5: Final data type standardization\n")

# Build the final analytical column set:
# outcomes | predictors (factors + continuous) | weights | design vars | identifiers
cc_factor_cols  <- grep("^cc_", names(ds4), value = TRUE)
factor_cols     <- c(
  "age_group", "sex", "marital_status", "education", "immigration_status",
  "visible_minority", "income_5cat", "has_family_doctor", "employment_type",
  "work_schedule", "alcohol_type", "smoking_status", "bmi_category",
  "physical_activity", "self_health_general", "self_health_mental",
  "health_vs_lastyear", "activity_limitation", "injury_past_year",
  # Added: previously dropped from output (Fix #2)
  "homeownership", "job_stress", "student_status", "occupation_category",
  "cycle_f",
  cc_factor_cols
)
factor_cols_found <- intersect(factor_cols, names(ds4))

# Continuous / integer columns to keep
keep_numeric <- c(
  # Outcomes
  "days_absent_total", "days_absent_chronic",
  lop_vars,                                      # raw LOP components (kept for transparency)
  # Survey design
  "wts_m_pooled", "wts_m_original", "geodpmf",
  # Province/territory (§2.2 facilitating) — added: previously dropped (Fix #2)
  if ("geodgprv" %in% names(ds4)) "geodgprv",
  # Raw sample construction vars (kept for audit trail)
  "dhhgage", "lop_015", "adm_prx",
  # Cycle indicator
  "cycle",
  # Continuous predictors
  "dhhdghsz",                                    # household size
  if ("fvcdgtot" %in% names(ds4)) "fvcdgtot",   # fruit/veg servings
  # Children by age group (§2.2 predisposing) — added: previously absent (Fix #1)
  if ("dhhdfc5"   %in% names(ds4)) "dhhdfc5",   # children < 5 yrs
  if ("dhhdfc11"  %in% names(ds4)) "dhhdfc11",  # children 6-11 yrs
  if ("dhhdfc12p" %in% names(ds4)) "dhhdfc12p", # children >= 12 yrs
  if ("adm_rno"  %in% names(ds4)) "adm_rno",    # respondent ID
  boot_cols
)
keep_numeric_found <- intersect(keep_numeric, names(ds4))

ds_long <- ds4 %>%
  select(all_of(c(keep_numeric_found, factor_cols_found))) %>%
  mutate(
    cycle           = as.integer(cycle),
    days_absent_total   = as.numeric(days_absent_total),
    days_absent_chronic = as.numeric(days_absent_chronic),
    wts_m_pooled    = as.numeric(wts_m_pooled),
    wts_m_original  = as.numeric(wts_m_original),
    geodpmf         = as.character(geodpmf),    # strata: treat as character ID
    dhhgage         = as.integer(dhhgage),
    lop_015         = as.integer(lop_015),
    adm_prx         = as.integer(adm_prx)
  )

vcat(sprintf("   ✓ Final analytical dataset: %s rows, %d columns\n",
            format(nrow(ds_long), big.mark = ","),
            ncol(ds_long)))
vcat(sprintf("   ✓ Factor columns: %d  |  Numeric columns: %d\n",
            sum(sapply(ds_long, is.factor)),
            sum(sapply(ds_long, is.numeric))))

# ==============================================================================
# SECTION 3: VALIDATION
# ==============================================================================

# ---- verify-values -----------------------------------------------------------
vcat("\n", strrep("=", 70), "\n")
vcat("SECTION 3: DATA VALIDATION\n")
vcat(strrep("=", 70), "\n")

vcat("\n🔍 Running checkmate assertions...\n")

checkmate::assert_integer(ds_long$cycle, any.missing = FALSE, lower = 0L, upper = 1L)
vcat("   ✓ cycle: integer in {0, 1}\n")

checkmate::assert_numeric(ds_long$wts_m_pooled, any.missing = FALSE, lower = 0)
vcat("   ✓ wts_m_pooled: numeric, non-negative\n")

checkmate::assert_numeric(ds_long$days_absent_total, lower = 0, upper = 90)
vcat("   ✓ days_absent_total: numeric, 0–90 range\n")

for (fct_col in intersect(factor_cols_found, names(ds_long))) {
  checkmate::assert_factor(ds_long[[fct_col]], any.missing = TRUE)
}
vcat(sprintf("   ✓ All %d factor columns have valid factor type\n", length(factor_cols_found)))

# Composite key: no duplicate respondents within a cycle
# (adm_rno unique within cycle if present)
if ("adm_rno" %in% names(ds_long)) {
  dupes <- ds_long %>%
    count(cycle, adm_rno) %>%
    filter(n > 1L)
  if (nrow(dupes) > 0) {
    warning(sprintf("%d duplicate respondent IDs found within cycle — investigate", nrow(dupes)))
  } else {
    vcat("   ✓ No duplicate respondent IDs within cycle\n")
  }
}

vcat("\n✅ Core validation checks passed\n")

# ---- outcome-diagnostics -----------------------------------------------------
vcat("\n📊 Outcome distribution (reference: mean≈1.35, 70.59% zeros):\n")

n_total    <- sum(!is.na(ds_long$days_absent_total))
n_zeros    <- sum(ds_long$days_absent_total == 0, na.rm = TRUE)
mean_out   <- weighted.mean(ds_long$days_absent_total,
                            w = ds_long$wts_m_pooled, na.rm = TRUE)
var_out    <- sum(ds_long$wts_m_pooled * (ds_long$days_absent_total - mean_out)^2,
                  na.rm = TRUE) / sum(ds_long$wts_m_pooled, na.rm = TRUE)

vcat(sprintf("   Unweighted n:       %s\n", format(n_total, big.mark = ",")))
vcat(sprintf("   Weighted mean:      %.2f  (reference: 1.35)\n", mean_out))
vcat(sprintf("   Weighted variance:  %.1f  (reference: 17.7)\n", var_out))
vcat(sprintf("   Dispersion (var/mean): %.1f  (>1 → overdispersion → NB model)\n", var_out / mean_out))
vcat(sprintf("   Zeroes:             %.1f%%  (reference: 70.59%%)\n",
            n_zeros / n_total * 100))
vcat(sprintf("   Maximum:            %g\n", max(ds_long$days_absent_total, na.rm = TRUE)))

# ==============================================================================
# SECTION 4: BUILD ANALYSIS-READY TABLES
# ==============================================================================

# ---- build-cchs-analytical ---------------------------------------------------
vcat("\n", strrep("=", 70), "\n")
vcat("SECTION 4: BUILD ANALYSIS-READY TABLES\n")
vcat(strrep("=", 70), "\n")

vcat("\n📊 Table 1: cchs_analytical (pooled white-list dataset)\n")

cchs_analytical <- ds_long   # already the final dataset

vcat(sprintf("   ✓ Rows:    %s\n", format(nrow(cchs_analytical), big.mark = ",")))
vcat(sprintf("   ✓ Columns: %d\n", ncol(cchs_analytical)))
vcat(sprintf("   ✓ Factors: %d\n", sum(sapply(cchs_analytical, is.factor))))
vcat(sprintf("   ✓ CCHS 2010-2011: %s\n", format(sum(cchs_analytical$cycle == 0L), big.mark = ",")))
vcat(sprintf("   ✓ CCHS 2013-2014: %s\n", format(sum(cchs_analytical$cycle == 1L), big.mark = ",")))

vcat("\n📊 Table 2: sample_flow (exclusion flowchart data)\n")
vcat(sprintf("   ✓ Rows: %d (one per exclusion step)\n", nrow(sample_flow)))
if (verbose) print(as.data.frame(sample_flow))

# ==============================================================================
# SECTION 5: SAVE TO OUTPUT
# ==============================================================================

vcat("\n", strrep("=", 70), "\n")
vcat("SECTION 5A: SAVE TO PARQUET (Primary — preserves factor types & levels)\n")
vcat(strrep("=", 70), "\n")

arrow::write_parquet(cchs_analytical,
                     file.path(output_parquet_dir, "cchs_analytical.parquet"))
cat(sprintf("   ✓ cchs_analytical.parquet  (%s rows, %d cols)\n",
            format(nrow(cchs_analytical), big.mark = ","),
            ncol(cchs_analytical)))

arrow::write_parquet(sample_flow,
                     file.path(output_parquet_dir, "sample_flow.parquet"))
cat(sprintf("   ✓ sample_flow.parquet      (%d rows)\n", nrow(sample_flow)))

cat(sprintf("\n✅ Parquet files saved to: %s\n", output_parquet_dir))

# ---- save-to-sqlite ----------------------------------------------------------
vcat("\n", strrep("=", 70), "\n")
vcat("SECTION 5B: SAVE TO SQLITE (Secondary — factors as character)\n")
vcat(strrep("=", 70), "\n")

# SQLite does not natively store R factor types.
# Convert factors to character strings; factor level ORDER is lost in SQLite
# (use Parquet as primary if factor ordering matters).
cchs_analytical_sql <- cchs_analytical %>%
  mutate(across(where(is.factor), as.character))

sample_flow_sql <- sample_flow

if (file.exists(output_sqlite)) {
  file.remove(output_sqlite)
  vcat("   ✓ Removed existing SQLite file\n")
}

cnn_out <- DBI::dbConnect(RSQLite::SQLite(), output_sqlite)
DBI::dbWriteTable(cnn_out, "cchs_analytical", cchs_analytical_sql, overwrite = TRUE)
DBI::dbWriteTable(cnn_out, "sample_flow",     sample_flow_sql,     overwrite = TRUE)

tables_out <- DBI::dbListTables(cnn_out)
for (tbl in tables_out) {
  n_rows <- DBI::dbGetQuery(cnn_out, sprintf("SELECT COUNT(*) AS n FROM %s", tbl))$n
  vcat(sprintf("   ✓ table '%s': %s rows\n", tbl, format(n_rows, big.mark = ",")))
}
DBI::dbDisconnect(cnn_out)

cat(sprintf("\n✅ SQLite saved to: %s\n", output_sqlite))

# ==============================================================================
# SECTION 6: SESSION INFO
# ==============================================================================

# ---- session-info ------------------------------------------------------------
duration <- difftime(Sys.time(), script_start, units = "secs")

vcat("\n", strrep("=", 70), "\n")
vcat("SESSION INFO\n")
vcat(strrep("=", 70), "\n")

vcat(sprintf("\n⏱️  Ellis completed in %.1f seconds\n", as.numeric(duration)))
vcat(sprintf("📅 Executed: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
vcat(sprintf("👤 User: %s\n", Sys.info()["user"]))

cat("\n📊 Output summary:\n")
vcat(sprintf("   Parquet dir:      %s  (2 files, primary)\n", output_parquet_dir))
vcat(sprintf("   SQLite database:  %s  (2 tables, secondary)\n", output_sqlite))
cat(sprintf("   Analytical rows:  %s\n", format(nrow(cchs_analytical), big.mark = ",")))
cat(sprintf("   Analytical cols:  %d  (white-listed subset)\n", ncol(cchs_analytical)))
vcat(sprintf("   Factor columns:   %d  (with levels preserved in Parquet)\n",
            sum(sapply(cchs_analytical, is.factor))))
vcat(sprintf("   Bootstrap weights: %d  (÷2 for pooling)\n", length(boot_cols)))
vcat(sprintf("   Cycles pooled:    2 (CCHS 2010-2011 + 2013-2014)\n"))

vcat("\n⚠️  VERIFICATION CHECKLIST:\n")
vcat("   1. Review white-list miss warnings above (if any)\n")
vcat("      → Open PDF data dictionaries in ./data-private/raw/2026-02-19/\n")
vcat("      → Update INFERRED variable names in declare-globals section\n")
vcat("   2. Confirm DHHGAGE age codes match your data dictionary (currently 2-15)\n")
vcat("   3. Confirm LOP_015 employment coding (retained as raw; no employment exclusion in default mode)\n")
vcat("   4. Confirm ADM_PRX proxy coding (retained as raw; proxy exclusion only when apply_sample_exclusions=TRUE)\n")
vcat("   5. Verify CCC variable names match the 19 conditions in thesis Appendix 3\n")
vcat("   6. Check outcome distribution vs reference (mean≈1.35, 70.59% zeros)\n")

if (verbose) sessionInfo()
