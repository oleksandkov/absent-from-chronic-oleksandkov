---
name: update-frontend
description: 'Propagate analyst edits from RAW repository sources through EDITED content/ into the PRINTED _site/ of the frontend named by the mandatory frontend ID argument, choosing the correct lane (scripts, Writer, or Interviewer) per changed source. Use when: refreshing a frontend after editing a .md document, an analysis report, or a page that feeds the Pipeline Guide/Home/Site Map, or after a site structure change.'
argument-hint: 'Required: the frontend ID (for example `1` for `_frontend-1`). Optional: name the changed source(s) to scope the update.'
user-invocable: true
---

# Update Frontend After Source Changes

Rebuilds the frontend identified by `<ID>` so its PRINTED site reflects the
current RAW sources, without breaking the reproducible contract handoff.

Edits flow one direction only:

```text
RAW (repo sources)  ->  EDITED (content/)  ->  PRINTED (_site/)
   analyst edits         assembled copies       rendered HTML
```

Each frontend owns its update instructions. This skill resolves `<ID>` to a
frontend root, defers to that frontend's own update guide, and falls back to the
generic procedure below when the frontend does not publish one.

## Invocation

```text
/update-frontend <ID>
```

`<ID>` is **mandatory** and is the numeric suffix of the frontend directory:
`/update-frontend 1` targets `_frontend-1`. If the user omits `<ID>`, ask for it
before doing anything else — never guess a default and never assume
`_frontend-1`.

Optionally the user may name changed sources after the ID to scope the update,
for example `/update-frontend 1 manipulation/pipeline.md`.

## When to Use

- An analyst edited a RAW source and a specific frontend must be rebuilt to
  match.
- You want a repeatable, self-verifying update rather than manual step-picking.
- You are unsure whether a change needs only scripts, the Writer, or the
  Interviewer.

Do **not** use this to design a new frontend from scratch — start with
`@publishing-interviewer` and `.github/prompts/publishing-new.prompt.md`.

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| Frontend ID | Slash-command argument (for example `1`) | Yes |
| Frontend update guide | `_frontend-<ID>/UPDATE-GUIDE.md`, else `_frontend-<ID>/README.md` | Yes, if present |
| Publishing contract | `_frontend-<ID>/publishing-contract.prompt.md` | Yes (the classifier) |
| Changed RAW sources | `git diff` or user-named files | Yes |
| Assembly / audit scripts | `_frontend-<ID>/scripts/*.R` | Yes (generated per frontend) |

## Procedure

Run every command from the **repository root**. Substitute the supplied ID for
`<ID>` throughout.

### Step 0 - Resolve The Frontend And Its Own Instructions

Confirm `_frontend-<ID>` exists. If it does not, list the available
`_frontend-*` directories and stop.

Then read the frontend's own update instructions, in this order of precedence:

1. `_frontend-<ID>/UPDATE-GUIDE.md` — the authoritative, frontend-specific
   procedure. If it exists, **follow it**; the steps below supply only the
   shared vocabulary for lanes and verification.
2. `_frontend-<ID>/README.md` — the intent record; read it for audience,
   protocol, and structural constraints that shape the update.

Only when neither document specifies a procedure do you execute Steps 1-6
verbatim.

### Step 1 - Determine What Changed

Discover changed RAW sources:

```powershell
git diff --name-only
git diff --name-only --staged
```

If the user named the changed source(s) explicitly, use that list instead. Never
inspect `content/` or `_site/` to decide what to do — they are generated
outputs.

### Step 2 - Classify Each Changed Source Against The Contract

Open `_frontend-<ID>/publishing-contract.prompt.md` and locate each changed
source. The row that names it gives its page and **protocol**; the protocol
selects the lane in the routing table below. A source absent from the contract
is not published by this frontend — flag it and stop.

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

Script names are generated per frontend. List `_frontend-<ID>/scripts/` and run
the assembly script that copies contracted sources into `content/`, for example:

```powershell
Rscript "_frontend-<ID>/scripts/copy-contract-assets.R" "_frontend-<ID>"
```

#### Step 3b - REDIRECT

Re-render the changed report so its standalone HTML is current (the site copies
it in during Step 4; it never re-runs the analysis):

```powershell
quarto render analysis/<report>/<report>.qmd
```

#### Step 3c - ADAPTED / COMPOSED (content only)

```text
@publishing-writer update _frontend-<ID> from the contract
```

The Writer re-reads the contract, reassembles VERBATIM pages, re-authors ADAPTED
and COMPOSED pages, and regenerates `_quarto.yml`.

#### Step 3d - Structure / intent

```text
@publishing-interviewer revise the _frontend-<ID> contract for <the structural change>
```

Then hand off to `@publishing-writer` as in Step 3c.

### Step 4 - Render The PRINTED Site

```powershell
quarto render _frontend-<ID>
```

This renders all contracted pages and runs the registered hooks (images,
redirect-target HTML, and asset copies).

### Step 5 - Verify The Reproducibility Gate

```powershell
Rscript "_frontend-<ID>/scripts/audit-fidelity.R" "_frontend-<ID>"
```

Read `_frontend-<ID>/FIDELITY_REPORT.md`. Interpret the overall status:

- **PASS** — everything reconciles; done.
- **WARN** — advisories only; safe to share.
- **FAIL** — real drift (a VERBATIM copy no longer matches its source, or a page
  is missing). Stop, fix the cause, and rebuild. Do not publish a FAIL.

### Step 6 - Report

Summarize: the frontend ID targeted, whether its own update guide governed the
run, each changed source and the lane it took, the render outcome, and the
fidelity status. Point the user at
`Start-Process "_frontend-<ID>/_site/index.html"` to inspect locally.

## Decision Points

- No ID supplied? Ask for it; do not default to the first or only frontend.
- `_frontend-<ID>` missing? List existing `_frontend-*` directories and stop.
- Frontend publishes its own `UPDATE-GUIDE.md`? Its steps win over Steps 1-6.
- Multiple sources changed across lanes? Run every applicable Step 3 branch,
  then Steps 4-6 once.
- Changed source not found in the contract? It is unpublished — surface it; do
  not invent a page.
- Both a report's `.qmd` and its contract entry changed? Treat it as a structure
  change (Step 3d), then re-render (Step 3b) before Step 4.

## Related Files

| File | Role |
|------|------|
| `_frontend-<ID>/UPDATE-GUIDE.md` | Frontend-specific update procedure (authoritative when present) |
| `_frontend-<ID>/README.md` | Intent record: audience, protocol, structural constraints |
| `_frontend-<ID>/publishing-contract.prompt.md` | Source -> page -> protocol map (the classifier) |
| `.github/agents/publishing-writer.agent.md` | Executes content lanes |
| `.github/agents/publishing-interviewer.agent.md` | Re-plans the contract for structure changes |
| `.github/skills/publishing-fidelity-audit/SKILL.md` | Deeper fidelity analysis |
| `.github/publishing-orchestra.md` | Two-agent architecture reference |
