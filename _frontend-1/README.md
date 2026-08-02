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

## 2026-08-02 — Navbar Restructure, Docs Section, Analysis Section

- **Audience and use case**: Unchanged — a single expert reader (the PI) verifying that every
  Project Proposal requirement has visible, traceable evidence. This revision is structural: it
  removes navbar redundancy and gives the interpretation layer its own home.
- **Messaging goal and tone**: Unchanged — professional, direct, evidence-oriented.
- **Drop `Home` from the navbar**: The site title in the navbar brand already links to `index`,
  so a separate `Home` entry is redundant. `index` remains in `content/` as the home page but is
  absent from the navbar.
- **Drop `Project` from the navbar**: The section held a single page (`Project Proposal`), which
  does not justify a dedicated dropdown.
- **New `Docs` section (last in the navbar)**: Houses two pages, in this order:
  1. Site Map
  2. Project Proposal
  The `Project Proposal` page moves from `content/project/project-proposal.qmd` to
  `content/docs/project-proposal.qmd`; `content/project/` is removed. `content/site-map.qmd`
  stays where it is so that its existing relative links remain valid.
- **New `Analysis` section**: One entry, labelled `Story 1`, published through Direct Line
  (REDIRECTED) and targeting `analysis/eda-81/eda-81.html` — the interpretation layer that reads
  `model-00` and `model-1` side by side.
- **Navbar order**: `Data Primer` → `Predictors` → `Outcome` → `Model` → `Analysis` → `Pipeline`
  → `Docs`. Evidence first, then interpretation, then infrastructure, then documentation.
- **Landing page change**: Immediately below the study title and author line — and above
  **Outcome in Focus** — add a short section that links to the Project Proposal page and states
  why it is the authoritative reference for the rest of the site.
- **Dependencies**: Extend `scripts/copy-analysis-html.R` to copy `analysis/eda-81/eda-81.html`
  into `_site/content/analysis/`. Update the composed Site Map so its navigation tree and
  proposal coverage table reflect the new sections, the new order, and the relocated
  `Project Proposal` link (`docs/project-proposal.html`). Update the **About This Site** prose on
  `index` so it no longer refers to a `Project` navbar section and does mention `Analysis`
  and `Docs`.
- **Exclusions and caveats**: Do not modify `analysis/eda-81/` during publishing. Its
  `data-local/`, `prints/`, and `figure-png-iso/` folders remain excluded, as does
  `report-contract.prompt.md`.
- **Site map decision**: CONTINUE FROM EXISTING DRAFT. Additive and structural edits only —
  reorder branches, add the `Analysis` and `Docs` branches, retarget the Project Proposal link,
  and append one coverage row for `Story 1`. Leave the **Content Type** table and all existing
  coverage row text unchanged.
