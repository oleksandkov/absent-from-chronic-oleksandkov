# Transform Log

Records all non-editorial Technical Bridge (ADAPTED) transforms applied during
content assembly for `_frontend-1/`.

Taxonomy source: `.github/instructions/publishing-rules.instructions.md`
(Section "Taxonomy and Mapping Registry").

---

## content/project/project-proposal.qmd

**Source:** `data-private/raw/2026-02-19/stats_instructions_v3.md`

| Transform | Type | Rationale |
|-----------|------|-----------|
| Added YAML frontmatter (`title: "Project Proposal"`) | `frontmatter_add` | Source file has no YAML frontmatter; required for Quarto rendering and navbar integration. |
| Removed reference to `data-private/` path in body | `sanitize` | Source preamble instruction references internal file path; removed to avoid exposing repository internals. No scientific content affected. Source §1–§6 preserved verbatim. |

---

## content/pipeline/pipeline-guide.qmd

**Source:** `manipulation/pipeline.md`

| Transform | Type | Rationale |
|-----------|------|-----------|
| Added YAML frontmatter (`title: "Pipeline Guide"`) | `frontmatter_add` | Source file has no YAML frontmatter; required for Quarto rendering. |
| Replaced fenced mermaid block with `{{< include ../_pipeline-diagram.qmd >}}` | `shortcode_injection` | Quarto shortcode ensures the mermaid renderer processes the diagram correctly in website context. Diagram content extracted to `content/_pipeline-diagram.qmd`. |
| Removed the `![Pipeline Architecture](../libs/images/pipeline-architecture.jpg)` image line | `sanitize` | Image path points outside `content/`; diagram is already shown on the index page. Removing avoids broken relative path in website build. |
| Stripped execution order PowerShell code blocks (`Rscript ...` commands) | `sanitize` | Developer execution commands not relevant to PI audience; removed per contract instruction. |
| Stripped R/SQL diagnostic code blocks (Lane 1 `DBI::dbConnect` example) | `sanitize` | Raw database query examples not relevant to PI audience; retained surrounding descriptive text. |
| Removed "Configuration Reference" section | `sanitize` | Section exposes internal `data-private/` file paths (config key → path mapping). Removed to comply with contract requirement to not reference `data-private/` paths. |
| Sanitized data-private paths in script summary output lists | `sanitize` | Output path references (e.g., `data-private/derived/`) replaced with generic descriptions to avoid exposing internal file system layout. |
| Rewrote local file links to plain text | `link_rewrite` | Cross-references to files not included in the site (e.g., `config.yml`) converted to plain text per contract instruction. |

---

## content/_pipeline-diagram.qmd (mermaid partial)

**Source:** `manipulation/pipeline.md` (mermaid block)

| Transform | Type | Rationale |
|-----------|------|-----------|
| Replaced `data-private/derived/...` node labels with generic names | `sanitize` | Mermaid diagram node labels contained internal file system paths. Replaced with generic descriptions (e.g., "Staging SQLite", "Analytic Parquet") to avoid exposing `data-private/` paths in the rendered diagram. |

---

## content/data-primer/variable-inclusion.qmd

**Source:** `analysis/data-primer-1/variable-inclusion.qmd`

| Transform | Type | Rationale |
|-----------|------|-----------|
| Stripped `embed-resources: true` from YAML frontmatter | `frontmatter_add` | Field causes Quarto to embed all assets inline; incompatible with multi-page website build. Inherited from site `_quarto.yml`. |
| Stripped `theme: flatly` from YAML frontmatter | `frontmatter_add` | Standalone theme declaration conflicts with site-level theme; inherited from `_quarto.yml`. |
| Removed reference to `data-private/raw/2026-02-19/stats_instructions_v3.md` path in body | `sanitize` | Source file path replaced with generic reference ("the statistical analysis instructions") to avoid exposing internal `data-private/` path in rendered page. |
| Replaced `data-public/metadata/CACHE-manifest.md` path with plain text "the CACHE manifest" in the `dhhgl12` row | `link_rewrite` | Cross-reference points at a repository file; the site publishes the same content as the CACHE Manifest page. Added 2026-08-01. |
| Removed `data-public/metadata/cchs_value_label_diffs.csv` reference from the `education` row | `sanitize` | Metadata CSV is not published by this site; the discrepancy itself is retained verbatim. Added 2026-08-01. |

---

## Refresh 2026-08-01 — `home_ownership` admitted, `dhhgl12` disposition ratified

Re-applied Technical Bridge transforms to `content/pipeline/pipeline-guide.qmd` after
`manipulation/pipeline.md` gained the 70-column verification checklist and the `DHH_OWN`
cross-cycle note.

**Source:** `manipulation/pipeline.md`

| Transform | Type | Rationale |
|-----------|------|-----------|
| Carried the two new "After Lane 2" bullets (63,843 × 70 table shape; `home_ownership` non-NA ≈ 63,677) into the guide unchanged | `content_sync` | Source-side verification checklist grew when `home_ownership` was admitted; no sanitization needed because the bullets reference no repository paths. |
| Carried the new "After Lane 3" latest-run bullet (2026-08-01, 0 FAILED, 63,843 × 70) into the guide unchanged | `content_sync` | Keeps the published validation record aligned with the current pipeline run. |
| Carried the `DHH_OWN` paragraph into "Cross-Cycle Harmonization Reference", rewriting the trailing `INPUT-manifest.md` § reference to plain text ("the INPUT Manifest, section Known Cross-Cycle Encoding Differences") | `link_rewrite` | Per contract, local file links are rendered as plain text; the referenced content is published as the INPUT Manifest page. |

