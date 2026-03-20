# `./analysis/` Directory

Contains reproducible reports narrating the engagement with the data of choice. See `./scripts/templates/` for report templates.

# Rules

1.  A folder contains a monothematic engagement with an Analysis-Ready Rectangle

2.  Until it can be rendered into a report, a script is but a scratch pad.

3.  If you want a report to exist for the public - add a link in this README.

---

# EDA Scripts

Each EDA folder contains an `.R` script (data loading, analysis, and plots) and a `.qmd` Quarto document (rendering the report). Run the `.R` script first, then render the `.qmd`.

## `eda-1/` — Broad Exploratory Analysis

**Purpose**: Comprehensive exploration of the `cchs_analytical.parquet` dataset produced by `manipulation/2-ellis.R`. Covers sample composition, chronic condition prevalence, work-absenteeism outcome distributions, and key predictor relationships.

**Input**: `data-private/derived/cchs-2-tables/cchs_analytical.parquet`

**Output**: Static plots in `analysis/eda-1/figure-png-iso/`, intermediate objects in `analysis/eda-1/data-local/`, rendered report `analysis/eda-1/eda-1.html` (after `quarto render`).

**How to run**:
```r
source("analysis/eda-1/eda-1.R")        # run analysis
```
```powershell
quarto render analysis/eda-1/eda-1.qmd  # render report
# or use the dedicated script:
powershell -ExecutionPolicy Bypass -File scripts/ps1/run-eda-1.ps1
```

See `analysis/eda-1/eda-style-guide.md` for visual and code conventions that apply to plots in this project.

## `eda-2/` — Ferry and Ellis Observation

**Purpose**: Focused observation of the ferry (`cchs-1.sqlite`) and ellis (`cchs-2-tables/`) outputs. Documents column counts, sample sizes across both CCHS cycles, white-list variable coverage, and exclusion-criterion effects.

**Input**: `data-private/derived/cchs-1.sqlite`, `data-private/derived/cchs-2-tables/`

**Output**: Plots and prints in `analysis/eda-2/prints/` and `analysis/eda-2/figure-png-iso/`, rendered report `analysis/eda-2/eda-2.html`.

**How to run**:
```r
source("analysis/eda-2/eda-2.R")        # run analysis
```
```powershell
quarto render analysis/eda-2/eda-2.qmd  # render report
# or use the dedicated script:
powershell -ExecutionPolicy Bypass -File scripts/ps1/run-eda-2.ps1
```

> **Note**: The EDA scripts depend on the manipulation pipeline having been run first.
> Run `source("flow.R")` or `source("manipulation/2-ellis.R")` before running any EDA.
