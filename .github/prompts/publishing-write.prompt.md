---
description: "Start Publishing Writer from chat using an approved publishing contract, then report execution status and next artifact path."
---

# Run Publishing Writer

Use this prompt to initiate Publishing Writer execution for a frontend workspace.

## What This Does

1. Selects a target frontend workspace (`_frontend-N/`).
2. Verifies the publishing contract exists.
3. Invokes `@publishing-writer` with a deterministic execution prompt.
4. Reports what was launched and what output path to check next.

## Instructions

When this prompt is invoked:

1. Determine target frontend:
   - If the user specifies `_frontend-N`, use it.
   - Otherwise, select the highest-numbered existing `_frontend-N/` directory.
2. Verify required input:
   - `_frontend-N/publishing-contract.prompt.md`
3. If the contract is missing, stop and report:
   - Missing file path.
   - A short action list to generate/approve the contract first (typically via Publishing Interviewer).
4. If the contract exists, invoke `@publishing-writer` with this prompt text:

```text
Use _frontend-N/publishing-contract.prompt.md and execute Phase 2-3 for that frontend: assemble content/, generate _quarto.yml, render _site/, reconcile outputs, run fidelity checks, and report the site entry path.
```

1. Return a concise launch summary:
   - Target frontend
   - Contract path
   - Writer invocation prompt used
   - Expected output entry point (`_frontend-N/_site/index.html`)

## Notes

- This command initiates Writer work; it does not replace Publishing Interviewer contract planning.
- If multiple frontends are plausible and intent is ambiguous, ask the human to choose before invoking Writer.
