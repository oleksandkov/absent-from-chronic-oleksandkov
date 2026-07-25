---
name: update-frontend
description: 'Propagate analyst edits from RAW repository sources through EDITED content/ into the PRINTED _site/ of a selected _frontend-N, choosing the correct lane (scripts, Writer, or Interviewer) per changed source. Use when: refreshing a frontend after editing a .md document, an analysis report, or a page that feeds the Pipeline Guide/Home/Site Map, or after a site structure change.'
argument-hint: 'Provide one frontend path (for example _frontend-1). Optional: name the changed source(s) to scope the update.'
user-invocable: true
---

# Update Frontend After Source Changes

Rebuilds one `_frontend-N` so its PRINTED site reflects the current RAW sources,
without breaking the reproducible contract handoff.

Edits flow one direction only:

```text
RAW (repo sources)  ->  EDITED (content/)  ->  PRINTED (_site/)
   analyst edits         assembled copies       rendered HTML
```

The conceptual source of truth for this workflow is
[`_frontend-N/UPDATE-GUIDE.md`](../../../_frontend-1/UPDATE-GUIDE.md). This skill
operationalizes it: it detects what changed, classifies each change against the
contract, and routes it to the correct lane.

## When to Use

- An analyst edited a RAW source and the frontend must be rebuilt to match.
- You want a repeatable, self-verifying update rather than manual step-picking.
- You are unsure whether a change needs only scripts, the Writer, or the
  Interviewer.

Do **not** use this to design a new frontend from scratch — start with
`@publishing-interviewer` and `.github/prompts/publishing-new.prompt.md`.

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| Frontend root path | CLI/arg (for example `_frontend-1`) | Yes |
| Publishing contract | `_frontend-N/publishing-contract.prompt.md` | Yes (the classifier) |
| Changed RAW sources | `git diff` or user-named files | Yes |
| Assembly / audit scripts | `_frontend-N/scripts/*.R` | Yes (generated per frontend) |

## Procedure

Run every command from the **repository root**. Substitute the target frontend
path for `_frontend-N` throughout.

### Step 1 - Resolve The Frontend And What Changed

Confirm the frontend path exists. Discover changed RAW sources:

```powershell
git diff --name-only
git diff --name-only --staged
```

If the user named the changed source(s) explicitly, use that list instead. Never
inspect `content/` or `_site/` to decide what to do — they are generated
outputs.

### Step 2 - Classify Each Changed Source Against The Contract

Open `_frontend-N/publishing-contract.prompt.md` and locate each changed source.
The row that names it gives its page and **protocol**; the protocol selects the
lane in the routing table below. A source absent from the contract is not
published — flag it and stop.

### Step 3 - Execute The Lane For Each Change

| Protocol / change | Lane | Action |
|-------------------|------|--------|
| VERBATIM (`.md` body) | Scripts | Refresh EDITED copy (Step 3a) |
| REDIRECT (`.R`/`.qmd` -> `.html`) | Scripts | Re-render the report (Step 3b) |
| ADAPTED / COMPOSED (feeds Pipeline Guide, Home, Site Map) | Writer | `@publishing-writer` (Step 3c) |
| Site structure or intent (new/moved/renamed page, new audience) | Interviewer -> Writer | `@publishing-interviewer`, then Writer (Step 3d) |

**The boundary is fixed:** scripts reproduce deterministic pages exactly; the
Writer re-authors page *content* against an unchanged contract; the Interviewer
re-plans the contract when *structure or intent* changes. The Writer never
invents structure — routing a structural change straight to it skips the
editorial planning the Interviewer owns.

#### Step 3a - VERBATIM

```powershell
Rscript "_frontend-N/scripts/assemble-verbatim.R" "_frontend-N"
```

#### Step 3b - REDIRECT

Re-render the changed report so its standalone HTML is current (the site copies
it in during Step 4; it never re-runs the analysis):

```powershell
quarto render analysis/<report>/<report>.qmd
```

#### Step 3c - ADAPTED / COMPOSED (content only)

```text
@publishing-writer update the site from the contract
```

The Writer re-reads the contract, reassembles VERBATIM pages, re-authors ADAPTED
and COMPOSED pages, and regenerates `_quarto.yml`.

#### Step 3d - Structure / intent

```text
@publishing-interviewer revise the contract for <the structural change>
```

Then hand off to `@publishing-writer` as in Step 3c.

### Step 4 - Render The PRINTED Site

```powershell
quarto render _frontend-N
```

This renders all contracted pages and runs the registered hooks (images,
redirect-target HTML, and asset copies).

### Step 5 - Verify The Reproducibility Gate

```powershell
Rscript "_frontend-N/scripts/audit-fidelity.R" "_frontend-N"
```

Read `_frontend-N/FIDELITY_REPORT.md`. Interpret the overall status:

- **PASS** — everything reconciles; done.
- **WARN** — advisories only; safe to share.
- **FAIL** — real drift (a VERBATIM copy no longer matches its source, or a page
  is missing). Stop, fix the cause, and rebuild. Do not publish a FAIL.

### Step 6 - Report

Summarize: the frontend targeted, each changed source and the lane it took, the
render outcome, and the fidelity status. Point the user at
`Start-Process "_frontend-N/_site/index.html"` to inspect locally.

## Decision Points

- Multiple sources changed across lanes? Run every applicable Step 3 branch,
  then Steps 4-6 once.
- Changed source not found in the contract? It is unpublished — surface it; do
  not invent a page.
- Both a report's `.qmd` and its contract entry changed? Treat it as a structure
  change (Step 3d), then re-render (Step 3b) before Step 4.

## Related Files

| File | Role |
|------|------|
| `_frontend-N/UPDATE-GUIDE.md` | Human-facing rationale and lane definitions |
| `_frontend-N/publishing-contract.prompt.md` | Source -> page -> protocol map (the classifier) |
| `.github/agents/publishing-writer.agent.md` | Executes content lanes |
| `.github/agents/publishing-interviewer.agent.md` | Re-plans the contract for structure changes |
| `.github/skills/publishing-fidelity-audit/SKILL.md` | Deeper fidelity analysis |
| `.github/publishing-orchestra.md` | Two-agent architecture reference |
