---
description: "Export a selected frontend _site tree into per-page PDFs under _pdf and summarize rerunnable conversion results."
---

# Export Frontend Site To PDF

Use this prompt to export one frontend's rendered `_site/` HTML pages into mirrored per-page PDFs under `_pdf/`.

## What This Does

1. Selects one target frontend directory (`_frontend-N/`).
2. Verifies `_frontend-N/_site/` exists.
3. Runs the PDF export skill script.
4. Reads `_frontend-N/_pdf/export-report.md`.
5. Returns a structured run summary.

## Instructions

When this prompt is invoked:

1. Determine target frontend:
   - If the user specifies `_frontend-N`, use it.
   - Otherwise, ask the user to provide the exact frontend path.
2. Verify required paths:
   - `_frontend-N/`
   - `_frontend-N/_site/`
3. Run export:

```powershell
Rscript .github/skills/export-frontend-site-pdfs/scripts/export-frontend-site-pdfs.R _frontend-N
```

1. Read `_frontend-N/_pdf/export-report.md` and summarize:
   - HTML pages found
   - PDFs converted
   - PDFs skipped
   - stale PDFs deleted
   - conversion failures
2. If failures are greater than zero, include exact failure items and remediation guidance.

## Output Format

- **Target**: `_frontend-N`
- **Status**: `PASS | WARN | FAIL`
- **Findings**: bullet list of conversion outcomes
- **Actions**: numbered list of required next steps when failures exist
- **Evidence**: path to `_frontend-N/_pdf/export-report.md`

## Notes

- This workflow is rerunnable and idempotent by design.
- By default, stale PDFs are cleaned to mirror current `_site/` state.
- Use script flags manually when needed:
  - `--force` to regenerate all pages
  - `--no-clean` to preserve stale PDFs
