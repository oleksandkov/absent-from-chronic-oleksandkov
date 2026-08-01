# Frontend 1 Intent Record

## 2026-07-18 — Add Predictors Section

- **Audience and use case**: Preserve the existing PI-facing research documentation site and add access to predictor analysis.
- **Messaging goal and tone**: Keep the existing professional, direct, evidence-oriented presentation.
- **Required navigation change**: Add a `Predictors` dropdown to the navbar. Its first entry is `Predisposing`.
- **Protocol assignment**: Publish `Predisposing` through Direct Line (REDIRECTED), targeting `analysis/eda-72/eda-72.html`.
- **Dependencies**: Update the composed site map so its navigation tree and proposal coverage include the new section and page.
- **Exclusions and caveats**: Retain the existing `Analysis > Predisposing` page backed by EDA-62; this revision does not replace or remove it.

## 2026-07-19 — Refresh EDA-72 Predisposing Analysis

- **Audience and use case**: Preserve the existing PI-facing frontend while refreshing the published Predisposing analysis.
- **Messaging goal and tone**: Retain the current professional, direct, evidence-oriented presentation without editorial changes.
- **Required publishing action**: Re-run the existing Direct Line (REDIRECTED) page for `Predisposing` so the printed site receives the latest `analysis/eda-72/eda-72.html`.
- **Included additions**: Publish graphs g12, g20, g211, g212, and g24 from the updated EDA-72 report.
- **Protocol and transform constraints**: Keep the existing contract, redirect stub, navigation, and copy hook unchanged; this is a source refresh only.
- **Exclusions and caveats**: Do not modify the EDA-72 source during publishing and do not replace the separate `Analysis > Predisposing` page backed by EDA-62.

## 2026-07-31 — Add Model Section

- **Audience and use case**: Same single expert reader (the PI). Extend the site from descriptive
  evidence into the modelling layer so that Project Proposal §5.3–§5.4 have visible, traceable
  deliverables.
- **Messaging goal and tone**: Unchanged — professional, direct, evidence-oriented. No editorial
  rewriting of the modelling reports.
- **Required navigation change**: Add a `Model` dropdown to the navbar, placed after `Predictors`
  and before `Site Map`. Three entries, in this order:
  1. Bivariate Models (`model-00`)
  2. Lasso Rehearsal with Predisposing (`model-0`)
  3. Variable Selection with Lasso (`model-1`)
- **Protocol assignment**: All three pages are Direct Line (REDIRECTED), targeting the rendered
  `.html` half of each `.qmd`/`.html` document pair in `analysis/model-00/`, `analysis/model-0/`,
  and `analysis/model-1/`.
- **Label convention**: Each label carries its report ID in parentheses, matching the convention
  already used by the `Outcome` and `Predictors` sections.
- **Dependencies**: Extend the post-render copy hook (`scripts/copy-analysis-html.R`) to place the
  three model HTML targets under `_site/content/model/`. Update the composed Site Map so its
  navigation tree and proposal coverage table include the new section and its three pages.
- **Exclusions and caveats**: Do not modify the model sources during publishing. `model-0_cache/`
  and `data-local/` under the model folders remain excluded.
- **Site map decision**: Continue from the existing `content/site-map.qmd` draft. Additive edits
  only — add the `Model` branch to the navigation tree and three rows to the proposal coverage
  table; leave all existing content unchanged.
- **Navbar reordering**: Analytical sections now run `Predictors` → `Outcome` → `Model`,
  reflecting the analytical reading order (what predicts, what is predicted, how it is modelled).
  The site map navigation tree and proposal coverage table follow the same order.
