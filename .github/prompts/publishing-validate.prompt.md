---
description: "Validate a frontend workspace from chat by running the publishing fidelity audit and summarizing pass/warn/fail results with concrete remediation."
---

# Validate Frontend Fidelity

Use this prompt to validate the current frontend workspace from chat in a consistent, repeatable way.

## What This Does

1. Selects a target frontend workspace (`_frontend-N/`).
2. Ensures `_frontend-N/scripts/audit-fidelity.R` exists (bootstrap from `.github/templates/audit-fidelity-template.R` if missing).
3. Runs the fidelity audit script.
4. Reads `_frontend-N/FIDELITY_REPORT.md`.
5. Returns a structured validation summary with required fixes.

## Instructions

When this prompt is invoked:

1. Determine target frontend:
   - If the user specifies `_frontend-N`, use it.
   - Otherwise, pick the highest-numbered existing `_frontend-N/` directory.
2. Verify required files:
   - `_frontend-N/publishing-contract.prompt.md`
   - `_frontend-N/content/`
   - `_frontend-N/_site/`
3. If `_frontend-N/scripts/audit-fidelity.R` is missing, copy from:
   - `.github/templates/audit-fidelity-template.R`
4. Run audit:

```powershell
Rscript _frontend-N/scripts/audit-fidelity.R _frontend-N
```

1. Read `_frontend-N/FIDELITY_REPORT.md` and summarize:
   - Overall status (`PASS`, `WARN`, `FAIL`)
   - Protocol counts (VERBATIM, REDIRECTED, ADAPTED, COMPOSED)
   - Failed checks (if any)
   - Warning checks (if any)
   - Exact remediation actions per failed item
2. If status is `FAIL`, explicitly state that the run is blocked until fixes are applied.

## Output Format

- **Target**: `_frontend-N`
- **Status**: `PASS | WARN | FAIL`
- **Findings**: bullet list of failures/warnings
- **Actions**: numbered list of fixes
- **Evidence**: path to `FIDELITY_REPORT.md`

## Notes

- Do not re-author site content in this step.
- This prompt is for validation and reporting only.
- For deep analysis of drift, use the `publishing-fidelity-audit` skill.
