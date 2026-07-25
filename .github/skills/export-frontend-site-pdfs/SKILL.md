---
name: export-frontend-site-pdfs
description: 'Export each HTML page from a selected _frontend-N/_site tree into a matching PDF file under _frontend-N/_pdf. Use when: reviewing static site content in a PDF-only viewer, re-exporting after frontend changes, or generating per-page PDFs without modifying publishing assembly.'
argument-hint: 'Provide one frontend path (for example _frontend-1). Optional flags: --force, --no-clean.'
user-invocable: true
---

# Frontend Site PDF Export

Exports one PDF per HTML page for a selected frontend workspace.

Redirect stub pages (for example meta-refresh pages) are resolved to their local target before printing so exported PDFs contain the target page content.

## When to Use

- You need a stand-alone PDF view of a rendered frontend site
- You want rerunnable export after updates to `_site/`
- You want page-level PDFs without changing publishing or rendering logic

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| Frontend root path | CLI arg (for example `_frontend-1`) | Yes |
| Rendered site pages | `_frontend-N/_site/**/*.html` | Yes |
| Export destination | `_frontend-N/_pdf/` | No (created by script) |
| Optional force rerender flag | `--force` | No |
| Optional stale cleanup override | `--no-clean` | No |

## Procedure

### Step 1 - Run Export Script

Run [export-frontend-site-pdfs.R](./scripts/export-frontend-site-pdfs.R) with one frontend target:

```r
source(".github/skills/export-frontend-site-pdfs/scripts/export-frontend-site-pdfs.R")
```

Or via terminal:

```powershell
Rscript .github/skills/export-frontend-site-pdfs/scripts/export-frontend-site-pdfs.R _frontend-1
```

Optional flags:

- `--force`: regenerate all PDFs regardless of timestamps
- `--no-clean`: keep stale PDFs instead of deleting them

### Step 2 - Review Export Report

Read `_frontend-N/_pdf/export-report.md` and summarize:

- scanned page count
- converted page count
- skipped page count
- deleted stale PDF count
- failed conversion count

### Step 3 - Rerun After Site Changes

After rendering `_frontend-N/_site/` again, rerun the same command. The script is idempotent and only reconverts changed pages unless `--force` is set.

## Output Location

- PDF files: `_frontend-N/_pdf/**` mirrored from `_frontend-N/_site/**`
- Run report: `_frontend-N/_pdf/export-report.md`

## Decision Points

- Missing `_site/`? Render the frontend first, then rerun export.
- Browser backend unavailable? Install `webshot2` or ensure Microsoft Edge / Google Chrome is available for headless export.
- Need historical PDFs kept? Run with `--no-clean`.

## Related Files

| File | Role |
|------|------|
| `.github/prompts/publishing-export-site-pdf.prompt.md` | Canonical manual workflow for this export |
| `.claude/commands/publishing-export-site-pdf.md` | Claude slash wrapper delegating to the canonical prompt |
| `_frontend-N/_site/` | HTML source tree |
| `_frontend-N/_pdf/` | Generated PDF output tree |
