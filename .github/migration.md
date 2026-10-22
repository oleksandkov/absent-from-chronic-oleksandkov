# Orchestra Migration Whitelist

This document is the authoritative **whitelist of project-agnostic files** in `.github/`
that are safe to migrate into another repository. It exists so that a human or an agent
lifting the AI-support system into a repository that is behind on its version can copy the
right files — and only the right files — without dragging repo-specific logic along.

The whitelist is expressed as file-tree maps. Anything **not** shown in a map below is
either repo-specific (tied to this project's data, cohort, or schema) or a generated
artifact, and must **not** be migrated. The maps are the source of truth: when the system
changes, update the maps here rather than maintaining separate prose per file.

## How To Use This Whitelist

1. Start from the **Master Agnostic File Map** to see the full transferable set at a glance.
2. Use a **per-orchestra map** when you want to migrate exactly one orchestra — the map
   isolates every file that orchestra needs.
3. Use the **Extra-Orchestral map** for cross-cutting files that belong to no single
   orchestra (shared style rules, the writing coach, the talk scaffolder, and this guide).
4. Copy files into the target repo's `.github/`, preserving the directory structure exactly.
5. Apply the **Adaptation Notes** for each orchestra before running anything.
6. Follow the **Shared Migration Procedure** to verify the agents load in VS Code.

## Master Agnostic File Map

Every file below is project-agnostic and is a migration target. Preserve the structure
exactly when copying into the target repo.

```text
.github/
├── agent-architecture.md
├── composing-orchestra.md
├── migration.md
├── pipeline-orchestra.md
├── publishing-orchestra.md
├── agents/
│   ├── eloquence-writer.agent.md
│   ├── pipeline-engineer.agent.md
│   ├── publishing-interviewer.agent.md
│   ├── publishing-writer.agent.md
│   └── report-composer.agent.md
├── copilot/
│   ├── composing-orchestra-SKILL.md
│   ├── pipeline-orchestra-SKILL.md
│   └── publishing-orchestra-SKILL.md
├── hooks/
│   ├── ellis-validation-reminder.json
│   ├── publishing-validation-reminder.json
│   └── scripts/
│       ├── check-ellis-validation.ps1
│       └── check-publishing-validation.ps1
├── instructions/
│   ├── artifact-naming.instructions.md
│   ├── markdown.instructions.md
│   ├── pipeline-scripts.instructions.md
│   ├── publishing-rules.instructions.md
│   ├── qmd-documents.instructions.md
│   ├── r-scripts.instructions.md
│   └── report-composition.instructions.md
├── prompts/
│   ├── composing-new.prompt.md
│   ├── evaluate-harness-equivalence.prompt.md
│   ├── pipeline-audit.prompt.md
│   ├── pipeline-bootstrap.prompt.md
│   ├── pipeline-diagram.prompt.md
│   ├── pipeline-ellis.prompt.md
│   ├── pipeline-validate.prompt.md
│   ├── publishing-new.prompt.md
│   ├── publishing-export-site-pdf.prompt.md
│   ├── publishing-validate.prompt.md
│   ├── publishing-write.prompt.md
│   └── talk-new.prompt.md
├── skills/
│   ├── evaluate-harness-equivalence/
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       └── evaluate-harness-equivalence.ps1
│   ├── export-frontend-site-pdfs/
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       └── export-frontend-site-pdfs.R
│   ├── publishing-fidelity-audit/
│   │   └── SKILL.md
│   ├── update-frontend/
│   │   └── SKILL.md
│   └── validate-cache-manifest/
│       ├── SKILL.md
│       ├── references/
│       │   ├── extract-table-metadata.sql
│       │   └── report-template.md
│       └── scripts/
│           └── validate-cache-manifest.R
└── templates/
    ├── audit-fidelity-template.R
    ├── composing-contract-template.md
    ├── composing-template.R
    ├── composing-template.qmd
    ├── data-primer-template.qmd
    ├── pipeline-diagram-template.mmd
    ├── publishing-contract-template.md
    └── report-audit-checklist.md
```

## Per-Orchestra Maps

Each map isolates the files needed to migrate one orchestra independently. A file may
appear in only one orchestra map; shared and unaffiliated files live in the
Extra-Orchestral map.

### Pipeline Orchestra

Single-agent system (`@pipeline-engineer`) for Ferry/Ellis pipeline development,
validation, and audit.

```text
.github/
├── pipeline-orchestra.md
├── agents/
│   └── pipeline-engineer.agent.md
├── copilot/
│   └── pipeline-orchestra-SKILL.md
├── hooks/
│   ├── ellis-validation-reminder.json
│   └── scripts/
│       └── check-ellis-validation.ps1
├── instructions/
│   └── pipeline-scripts.instructions.md
├── prompts/
│   ├── pipeline-audit.prompt.md
│   ├── pipeline-bootstrap.prompt.md
│   ├── pipeline-diagram.prompt.md
│   ├── pipeline-ellis.prompt.md
│   └── pipeline-validate.prompt.md
├── skills/
│   └── validate-cache-manifest/
│       ├── SKILL.md
│       ├── references/
│       │   ├── extract-table-metadata.sql
│       │   └── report-template.md
│       └── scripts/
│           └── validate-cache-manifest.R
└── templates/
    └── pipeline-diagram-template.mmd
```

**Adaptation notes:**

- The framework is intentionally project-agnostic. All source systems, table names, and
  lane sequences live in the target repo's `manipulation/`, not in these files.
- `validate-cache-manifest` reads its target binding from
  `manipulation/pipeline-validation.dcf`; that binding file is repo-specific and is
  **not** migrated — create it fresh in the target repo.
- `hooks/*.json` reminder paths may need adjustment to match the target repo layout.

### Composing Orchestra

Single-agent system (`@report-composer`) for scaffolding and developing EDA and Report
content in `analysis/`.

```text
.github/
├── composing-orchestra.md
├── agents/
│   └── report-composer.agent.md
├── copilot/
│   └── composing-orchestra-SKILL.md
├── instructions/
│   ├── artifact-naming.instructions.md
│   └── report-composition.instructions.md
├── prompts/
│   └── composing-new.prompt.md
└── templates/
    ├── composing-contract-template.md
    ├── composing-template.R
    ├── composing-template.qmd
    ├── data-primer-template.qmd
    └── report-audit-checklist.md
```

**Adaptation notes:**

- Update hard-coded data paths in `composing-template.R`, `composing-template.qmd`, and
  `data-primer-template.qmd` to match the target repo's pipeline outputs (e.g. parquet
  reader calls).
- Compose `analysis/data-primer-1/` first in the target repo — it is data-specific and is
  never migrated, only produced fresh.

### Publishing Orchestra

Two-agent system (`@publishing-interviewer` → `@publishing-writer`) for assembling a
static Quarto website from analytical content in `_frontend-*`.

```text
.github/
├── publishing-orchestra.md
├── agents/
│   ├── publishing-interviewer.agent.md
│   └── publishing-writer.agent.md
├── copilot/
│   └── publishing-orchestra-SKILL.md
├── hooks/
│   ├── publishing-validation-reminder.json
│   └── scripts/
│       └── check-publishing-validation.ps1
├── instructions/
│   └── publishing-rules.instructions.md
├── prompts/
│   ├── publishing-new.prompt.md
│   ├── publishing-export-site-pdf.prompt.md
│   ├── publishing-validate.prompt.md
│   └── publishing-write.prompt.md
├── skills/
│   ├── export-frontend-site-pdfs/
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       └── export-frontend-site-pdfs.R
│   ├── publishing-fidelity-audit/
│   │   └── SKILL.md
│   └── update-frontend/
│       └── SKILL.md
└── templates/
    ├── audit-fidelity-template.R
    └── publishing-contract-template.md
```

**Adaptation notes:**

- `publishing-rules.instructions.md` uses the `applyTo: "_frontend-*/**"` frontmatter
  pattern. If the target repo uses a different frontend naming convention, update it.
- `hooks/*.json` reminder paths may need adjustment to match the target repo layout.
- Prerequisites: [Quarto](https://quarto.org/) and R installed; the target repo has at
  least one EDA beyond EDA-1 and one non-exploratory report with rendered HTML.

## Extra-Orchestral Map

These files are project-agnostic but belong to **no single orchestra**. They are shared
style rules, a general-purpose writing agent, a talk scaffolder, and the migration and
architecture references themselves. Migrate them regardless of which orchestras you take.

```text
.github/
├── agent-architecture.md
├── migration.md
├── agents/
│   └── eloquence-writer.agent.md
├── instructions/
│   ├── markdown.instructions.md
│   ├── qmd-documents.instructions.md
│   └── r-scripts.instructions.md
├── prompts/
│   ├── evaluate-harness-equivalence.prompt.md
│   └── talk-new.prompt.md
└── skills/
    └── evaluate-harness-equivalence/
        ├── SKILL.md
        └── scripts/
            └── evaluate-harness-equivalence.ps1
```

**Adaptation notes:**

- `eloquence-writer.agent.md` is a self-contained rhetorical writing coach, but it reads
  its knowledge base from `data-private/texts/eloquence/`. That corpus lives outside
  `.github/` and is **not** part of this whitelist — provide it in the target repo for the
  agent to function fully.
- `agent-architecture.md` describes the generic three-orchestra model and namespace
  ownership; adjust any repo-specific output paths it references after migration.
- The `markdown`, `r-scripts`, and `qmd-documents` instructions are style rules that apply
  repository-wide and support all three orchestras.

## Shared Migration Procedure

1. **Copy** the files for the orchestras you want, preserving the `.github/` structure.
   Always include the Extra-Orchestral map.
2. **Verify agents load**: open the target repo in VS Code, type `@` in Copilot chat, and
   confirm the migrated agents appear (e.g. **Pipeline Engineer**, **Report Composer**,
   **Publishing Interviewer**, **Publishing Writer**). If not, reload the window.
3. **Adapt paths**: apply the per-orchestra adaptation notes above (data paths, `applyTo`
   patterns, validation bindings, hook paths).
4. **Wire into instructions**: if the target repo has a `.github/copilot-instructions.md`,
   add short references to each migrated orchestra so the default agent knows it exists.
5. **Smoke-test**: run one bootstrap prompt per migrated orchestra to confirm the entry
   points resolve.
6. **Verify equivalence**: run the `evaluate-harness-equivalence` skill (or the
   `/evaluate-harness-equivalence` prompt) against the source repo to confirm every
   whitelisted file is byte-identical. It parses the maps in this document as its source of
   truth and reports any drift with remediation suggestions. See
   `.github/skills/evaluate-harness-equivalence/`.

## What Is Deliberately Excluded

Files in `.github/` that are **absent from every map above** are repo-specific and must
not be migrated. Do not add them to a target repo without deliberate re-authoring for that
repo's data and conventions.

## Version

Whitelist maintained against the live `.github/` layout as of 2026-07-08. When the
orchestra file set changes, update the maps in this document in the same commit — the
`evaluate-harness-equivalence` skill reads these maps directly, so stale maps produce
false drift reports.
