# EDA-71 Session Context — Report Development Log

**Date**: 2026-06-19  
**Session Focus**: Opening Lens design, interpretation tables, HTML formatting, 9-facet g11 with total outcome  
**Status**: Core opening sections (g0, chronic interpretation, Bridge tables) complete and rendering

---

## Key Editorial Decisions

### 1. Opening Lens Strategy (Before G1)

**Purpose**: Clarify what `days_absent_total` measures and establish denominator logic for all downstream graphs before readers see frequency distributions.

**Components**:
- **g0 duality map**: Single scatterplot encoding two complementary perspectives simultaneously:
  - X-axis: weighted prevalence (% workers with ≥1 day)
  - Y-axis: weighted mean days **among reporters** (>0)
  - Point size: absolute burden (days per 100 workers)
  - Point color: relative share of total days_absent_total
  - **Key insight**: Separates "how common is it?" from "how severe is it among those affected?"

- **Chronic-condition concrete interpretation table**: 5 metrics with plain-language definition + source corroboration:
  - Prevalence (%)
  - Mean days per worker
  - Mean days among reporters
  - Burden per 100 workers
  - Share of total
  - Each row cites exact survey documentation source (CCHS DataDictionary + Record Layout)

- **Total-reference row**: Every table now includes "Total outcome" row so readers have benchmark for the composite criterion

### 2. Interpretation Framework

**Two required perspectives**:
1. **Population burden perspective**: How much each reason contributes to overall productivity loss (denominator = all workers)
2. **Reporter intensity perspective**: Among workers with ≥1 day for a reason, typical severity (denominator = reporters only)

**Why both matter**: 
- Chronic condition may be rare but long-duration → high intensity
- Cold may be common but brief → high prevalence, low intensity
- Both matter for modeling zero-inflation and tail behavior separately

**Avoid in later graphs**: Don't mix denominators; always make denominator explicit in caption

### 3. HTML Table Formatting (knitr::kable)

**Convention adopted**:
- All section tables render via `knitr::kable(..., format = "html")` when in Quarto
- Fallback to `print()` for standalone `.R` execution
- Use `ifelse(isTRUE(getOption("knitr.in.progress")), knitr::kable(...), print(...))`

**Table improvements**:
- Human-readable column names (not variable codes)
- Right-aligned numeric columns
- Clear captions explaining table purpose
- Wrapped text in interpretation columns (width ≈ 92 characters)

**Tables with total row**:
- Opening Lens table (`g0-data-prep`)
- Bridge: transformation assumptions (`t1-modeling-assumptions`)
- Bridge: shape diagnostics (`g15-data-prep` + `g15_shape_table`)

---

## Source Documentation References

**Key survey constructs** (for future editing/validation):

| Construct | Variable(s) | Source |
|-----------|-----------|--------|
| Employment gate (3 months) | `LOP_015` | [CCHS_2014_DataDictionary_Freqs.txt line 18957](file://data-private/derived/2026-02-19/CCHS_2014_DataDictionary_Freqs.txt#L18957) |
| Chronic: missed work days | `LOPG040` (derived) | [CCHS_2014_DataDictionary_Freqs.txt line 19019](file://data-private/derived/2026-02-19/CCHS_2014_DataDictionary_Freqs.txt#L19019) |
| Chronic: record layout | `LOPG040` position | [CCHS_2010_Record_Layout.txt line 1539](file://data-private/derived/2026-02-19/CCHS_2010_Record_Layout.txt#L1539) |
| Master weight | `WTS_M` | [CCHS_2014_Record_Layout.txt line 1391](file://data-private/derived/2026-02-19/CCHS_2014_Record_Layout.txt#L1391) |
| Pooled weight adjustment | `wts_m_pooled = wts_m / 2` | [manipulation/2-ellis.R line 263](file://manipulation/2-ellis.R#L263) |
| Outcome construction | `days_absent_total = lopg040 + ... + lopg100` | [manipulation/2-ellis.R line 406](file://manipulation/2-ellis.R#L406) |

**Key datasets**:
- Input PUMF: `data-private/raw/2026-02-19/CCHS_2010_EN_PUMF.sav` + `CCHS2010_LOP.sav`
- Analytical: `data-private/derived/cchs-2-tables/cchs_analytic.parquet` (n=63,843)

---

## G0 and G11 Design Details

### G0: Duality Map
- **Data prep**: `g0-data-prep` chunk computes all 6 metrics per reason + total
- **Total row**: computed separately via direct `days_absent_total` aggregation
- **Labels**: "Chronic condition", "Injury", "Cold", "Flu / influenza", "Gastroenteritis", "Respiratory infection", "Other infectious disease", "Other physical / mental health"
- **Color scale**: `scale_color_gradient(low="#9BC6D9", high="#0B4F6C")` (blue)
- **Readability**: `check_overlap=TRUE` for label avoidance; nudge_y=0.06 for vertical spacing

### G11: 3×3 Faceted Shape Comparison (8 LOP + Total)
- **9th facet added**: "Total outcome" as a focal LOP facet alongside the 8 components
- **Purpose**: See how composite outcome distributes relative to individual reasons
- **Normalization**: Y-axis is within-positive normalized (% of positive-day mass per reason)
  - This isolates **shape** (front-loaded vs tail-heavy) from **prevalence**
  - Chronic benchmark omitted in chronic facet (redundant)
  - Total benchmark omitted in total facet (redundant)
- **Colors**: Focal = blue solid + area fill; chronic benchmark = orange dashed; total benchmark = gray dotted
- **Grid**: 3 columns (so 9 panels wrap to 3 rows)

---

## Integration with EDA-5

**Principle**: EDA-5 does the full decomposition (prevalence, contribution, co-occurrence, correlation). EDA-71 uses compact orientation to support distribution modeling.

**Reference pattern**: "For full decomposition details, see [EDA-5](../eda-5/eda-5.qmd)."

**What EDA-71 adds**:
- Dual-perspective visual (g0 duality map)
- Transformation diagnostics (g15 ECDF, g16 density-vs-Gaussian)
- Shape benchmarking with facets (g11)
- Zero-inflation profiling (g2 stub)

---

## Common Conventions (For Consistency)

1. **Weight column**: Always reference `weight_col <- "wts_m_pooled"` global (not raw `wts_m`)
2. **Outcome variable**: Use `days_absent_total` (capped 90 days) unless explicitly modeling `days_absent_chronic` as sensitivity
3. **Recall window**: Always state "past 3 months" in captions and interpretation text
4. **Population frame**: "Employed workers" (LOP_015 = 1); filters applied in Ellis lane 2
5. **Denominators**: Always make explicit in table captions and graph subtitles
6. **Bin levels**: Use canonical ordered factor `bin_levels` (9 bins from "1 day" to "31+ days")
7. **LOP component names**: Use `lop_components` named vector with readable labels

---

## Future Editing Checklist

- [ ] If adding new figures, update g0 duality map to highlight relevant reason(s)
- [ ] All weighted quantities must use `wts_m_pooled`, not `wts_m`
- [ ] Document any new metrics with source reference (Ellis derivation, CCHS codebook)
- [ ] Tables with numeric comparisons should include total-outcome reference row
- [ ] Faceted plots should use 3-column layout for readability
- [ ] Captions must specify denominator (all workers vs reporters)
- [ ] Links to source documentation: use line-number references when possible

---

## Known Limitations & Notes

- **Bootstrap weights**: Not available for CCHS PUMF 2010 & 2014 cycles. Variance estimation must rely on master weight only (documented in CACHE-manifest).
- **Pooled sample**: Two-year cycles combined; each respondent's weight divided by 2 per Statistics Canada guidance.
- **Zero handling**: 405 respondents with any missing LOP component excluded at Ellis step 4; zeros preserved as valid integer values in analytical sample, not stored as NA.
- **Chronic condition**: `days_absent_chronic = pmin(lopg040, 90)` uses only chronic component; kept separate for sensitivity analysis.

---

## Report Navigation

1. **Opening Lens** (before G1): g0-data-prep → g0-chronic-interpretation → g0 duality map
2. **G1 family**: g1-data-prep → g1 frequency distribution curves (marginal prevalence by bin)
3. **G11 family**: g11-data-prep → g11 faceted shape comparison (3×3 with benchmarks)
4. **Bridge to G2**: t1-modeling-assumptions → g15-data-prep + g15 ECDF → g16 density vs Gaussian
5. **G2+ family** (stubs): Zero-inflation profiling, composite outcome distribution, correlation structure

---

**Last Updated**: 2026-06-19  
**Files Modified**: `analysis/eda-71/eda-71.R`, `analysis/eda-71/eda-71.qmd`  
**Report Build**: Successful; rendered to `analysis/eda-71/eda-71.html`
