# frontend-1 — Human Intent

## Original Intent

I need a research documentation site for the study *"Predictors of Work Absenteeism Associated
with Chronic Conditions Among Canadian Workers"*. The site is for Marc-Andre Blanchette — the PI
and lead researcher — who needs a single place to verify that every requirement in
`stats_instructions_v3.md` has been addressed by the analytical work.

This is not a public-facing site. The audience is one expert reader. Tone should be professional
and direct, not promotional. Show the work; don't sell it.

## What This Site Should Do

The site should allow Marc-Andre to navigate from "what was asked" to "what was done" without
needing access to the repository itself. Each section should correspond to a layer of the
analytical pipeline:

- How the raw SPSS files became the analysis-ready dataset (pipeline documentation)
- What variables were selected and why (data primer)
- What the analytical datasets look like and what patterns emerged (EDA reports)

The organizing principle is **evidence of coverage**: every section should answer to a specific
section of `stats_instructions_v3.md`.

## Audience

Marc-Andre Blanchette, research scientist. Single reader. Expert in the subject matter — does not
need background on the CCHS or on work absenteeism. Needs to verify analytical decisions, not
understand them from scratch.

## Content to Include

The index should host g01 from eda-5.

### Project documentation

- Statistical Instruction - `stats_instructions_v3.md` — show as-is, but strip the "AI system" references and
  instructions (these are internal to the repository and not relevant to the site visitor)

### Pipeline documentation

- The pipeline guide from `manipulation/pipeline.md` — include the ASCII flow diagram and scripts
  table, but strip developer-facing content (R console blocks, PowerShell commands, private paths).
  Replace the note about the missing `3-ellis.R` with a neutral statement.
- CACHE manifest from `data-public/metadata/CACHE-manifest.md` — show as-is
- INPUT manifest from `data-public/metadata/INPUT-manifest.md` — show as-is

### Data Primer (pre-rendered HTML reports)

- Variable inclusion rationale from `analysis/data-primer-1/variable-inclusion.qmd` — transfer
  the QMD to `edited_content/` and render as a site page (strip `embed-resources` and `theme`
  from YAML; these are standalone-only settings overridden by the site's `_quarto.yml`)
- Univariate distributions from `analysis/data-primer-1/univariate-distributions.html` — redirect
  (pre-rendered; too large / plot-heavy to re-render inside the frontend build)

### Analysis (pre-rendered HTML reports)

- EDA-2 from `analysis/eda-2/eda-2.html` — a pipeline observation report (ferry + ellis
  diagnostics, row counts, output verification)
- EDA-5 from `analysis/eda-5/eda-5.html` — outcome variable decomposition: LOP reason-category
  prevalence, relative contribution, and co-occurrence

### Binder-2

- The four notebooks from `analysis/binder-2/` — redirect (pre-rendered; too large / plot-heavy to
  re-render inside the frontend build)

### Docs

- A sanitized version of `README.md` — strip run instructions, AI system references, data-private
  paths. Keep the project overview and data location table.
- A site map page that lists every page, its content type, and which stats instruction section it
  covers.

## What to Exclude

- `data-private/` — never publish
- `analysis/eda-1/` — mtcars scaffold, not an analytical product
- R source scripts and cache directories
- Developer-facing content (installation, renv setup, PowerShell commands)
- Internal AI tooling references

## Tone and Style

The home page (index) should lead with the study title and a brief narrative about what this site
contains: three-sentence summary covering pipeline → data primer → EDA. End with a short
"How to use this site" section mapping each navbar section to what question it answers.

No marketing language. No hypothetical future work. Show what exists.

## Theme and Format

Use Quarto static website with flatly theme. Include TOC on content pages. Use the post-render
hook pattern to copy pre-rendered HTML into `_site/redirects/` (this project has large,
self-contained report HTML files that cannot be re-rendered inside the frontend).
