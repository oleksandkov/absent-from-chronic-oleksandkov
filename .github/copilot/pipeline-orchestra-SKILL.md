---
name: pipeline-orchestra
description: "**WORKFLOW SKILL** — Develop, validate, and audit Ferry/Ellis data pipelines in manipulation/ using a single-agent pipeline (Pipeline Engineer). USE FOR: discovering raw inputs and scaffolding Ferry lanes; building Ellis transformation lanes with validation; generating INPUT/CACHE manifests; running the CACHE-manifest validator; auditing drift between lane code, manifests, and pipeline.md. DO NOT USE FOR: composing analytical reports (use composing-orchestra); publishing websites (use publishing-orchestra). INVOKES: Pipeline Engineer agent, which discovers project specifics from manipulation/ before proposing code or docs."
---

# Pipeline Orchestra

A single-agent system for developing data transformation pipelines (Ferry + Ellis lanes) and their companion documentation. The Pipeline Engineer agent reads project-specific rules from `manipulation/` and keeps `.github/` framework logic project-agnostic.

---

## Architecture

```text
Human ↔ Pipeline Engineer
              │
              ├──► manipulation/{N}-ferry-*.{R,sql}   (transport, minimal semantic change)
              ├──► manipulation/{N}-ellis-*.{R,sql}   (standardize, derive, validate)
              └──► data-public/metadata/{INPUT,CACHE}-manifest.md
```

### Agent

| Agent | Role | Invocation |
| --- | --- | --- |
| **Pipeline Engineer** | Discover, Ferry, Ellis, validate, audit | `@pipeline-engineer` |

### Four Phases

| Phase | Purpose | Output |
| --- | --- | --- |
| **Discovery + Ferry** | Move source data into staging with minimal change | Ferry lane + `INPUT-manifest.md` |
| **Ellis Development** | Transform staged data into analysis-ready outputs | Ellis lane(s) |
| **Validation + Documentation** | Document real outputs, verify against manifest | `CACHE-manifest.md`, `pipeline.md` |
| **Quality Audit** | Detect drift across lanes, manifests, and configs | Discrepancy report |

---

## Boundary Rule

- `.github/` contains transferable framework logic only.
- `manipulation/` contains project-specific pipeline rules, inventories, diagrams, and validator bindings.
- `data-public/metadata/` contains project-specific manifests such as `INPUT-manifest.md` and `CACHE-manifest.md`.

If a framework file needs a project-specific table name, schema, helper, or lane sequence, that information is discovered from `manipulation/`, not hardcoded.

## Workflow

1. **Human invokes** `@pipeline-engineer` or runs a `pipeline-*` prompt
2. **Engineer reads** the adapter files in `manipulation/` (project spec, validation binding)
3. **Engineer scaffolds or refines** the next Ferry or Ellis lane
4. **Engineer documents** outputs in the manifests and runs the CACHE validator
5. **Engineer audits** for drift between lane code, manifests, and `pipeline.md`

## Relationship to Other Orchestras

Pipeline Orchestra prepares analysis-ready data. Composing Orchestra consumes that data to build reports in `analysis/`; Publishing Orchestra curates analytical outputs into websites in `_frontend-*`. The systems are sequential but decoupled.

## Key References

- Design document: `.github/pipeline-orchestra.md`
- Agent definition: `.github/agents/pipeline-engineer.agent.md`
- Instructions: `.github/instructions/pipeline-scripts.instructions.md`
- Prompts: `.github/prompts/pipeline-{bootstrap,ellis,validate,audit,diagram}.prompt.md`
- Templates: `.github/templates/pipeline-diagram-template.mmd`
- Validation skill: `.github/skills/validate-cache-manifest/SKILL.md`
