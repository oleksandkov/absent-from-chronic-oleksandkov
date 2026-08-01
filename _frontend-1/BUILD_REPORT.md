# Build Report

## Build Outcome (2026-07-31 — Add Model Section)

The frontend assembled and rendered all 19 contract pages (16 prior + 3 new `Model` pages). The
post-render hook copied all 12 REDIRECT targets, including the three new model reports. Output
reconciliation passed. The fidelity gate returned **WARN** (non-blocking).

### Model Section

Three Direct Line (REDIRECTED) pages were added under `content/model/`:

| Page | Stub | Target |
|---|---|---|
| Bivariate Models (model-00) | `content/model/bivariate-models.qmd` | `analysis/model-00/model-00.html` |
| Lasso Rehearsal with Predisposing (model-0) | `content/model/lasso-rehearsal.qmd` | `analysis/model-0/model-0.html` |
| Variable Selection with Lasso (model-1) | `content/model/variable-selection.qmd` | `analysis/model-1/model-1.html` |

Each rendered stub was verified to carry the correct `meta http-equiv="refresh"` target, and all
three target HTML files are present in `_site/content/model/`. The `Model` navbar dropdown sits
between `Predictors` and `Site Map`, in contract order (`model-00`, `model-0`, `model-1`).

### Site Map

Regenerated in CONTINUE-FROM-DRAFT mode per the contract. Edits were additive only: the `Model`
branch was inserted into the ASCII navigation tree and three rows were appended to the
**Proposal Coverage** table (mapped to §5.3 and §5.4). The **Content Type** table and all prior
tree branches and coverage rows are unchanged.

### Fidelity Warnings (Non-Blocking)

- No `source_sha256` fields in the contract — deterministic drift checks are unavailable.
- Technical Bridge pages present without `allowed_transforms` metadata.

Both warnings pre-date this revision and are contract-metadata gaps, not assembly defects.

---

## Build Outcome (prior run)

The frontend assembled and rendered all 16 contract pages. The post-render hook copied all 9 REDIRECT targets, including the refreshed EDA-72 Predisposing analysis. Output reconciliation passed, but the run did not pass the strict fidelity gate.

## Confirmed EDA-72 Refresh

The printed target at `_site/content/predictors/eda-72.html` is byte-identical to `analysis/eda-72/eda-72.html` and contains graphs g12, g20, g211, g212, and g24.

## Blocking Fidelity Issue

All three pages declared Direct Line (VERBATIM) fail deterministic source-body equivalence:

- `content/pipeline/cache-manifest.qmd` removes the source H1 heading.
- `content/pipeline/input-manifest.qmd` removes the source H1 heading and sanitizes internal-path text.
- `content/data-primer/variable-inclusion.qmd` sanitizes internal-path text.

The body sanitization appears intended to prevent internal paths from being published, but that operation belongs to Technical Bridge (ADAPTED), not Direct Line (VERBATIM).

## Suggested Resolution

Revise the publishing contract to classify pages requiring sanitization as Technical Bridge and explicitly list their allowed transforms. Alternatively, retain Direct Line (VERBATIM) and restore each source body exactly, limiting assembly changes to YAML frontmatter.

No raw repository source files were modified during frontend assembly.
