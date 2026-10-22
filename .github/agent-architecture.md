# Agent Architecture and Orchestration

This document describes how AI agents coordinate across analytical workflows in the current local project.

## Three-Orchestra Model

### 1. Pipeline Orchestra (`@pipeline-engineer`)

**Owned namespace**: `manipulation/`, `data-private/`

**Role**: Develop data transformation pipelines (Ferry + Ellis lanes)

**Workflow phases**:

1. **Discovery + Ferry**: Extract metadata, scaffold Ferry lane
2. **Ellis Development**: Build transformation scripts with validation
3. **Validation + Documentation**: Create manifests, pipeline.md
4. **Quality Audit**: Verify outputs and compliance

**Outputs**:

- `manipulation/{0-3}-*.R` (script files)
- `manipulation/{INPUT,CACHE}-manifest.md`
- `manipulation/pipeline.md`

**Tool constraints**:

- ✅ Write to `manipulation/` and `data-private/`
- ❌ Touch `analysis/`, `_frontend-*`

### 2. Composing Orchestra (`@report-composer`)

**Owned namespace**: `analysis/`

**Role**: Develop analytical reports (EDAs, Reports, Data Primer)

**Workflow phases**:

1. **Bootstrap (Phase 0)**: Scaffold directory and contracts
2. **Adaptive Interview (Phase 1)**: Refine research questions, plan artifacts
3. **Iterative Development (Phase 2)**: Develop graphs, tables, figures
4. **Completion (Phase 3)**: Audit and prepare for publication

**Outputs**:

- `analysis/{name}/report-contract.prompt.md`
- `analysis/{name}/{name}.R` and `.qmd`
- `analysis/{name}/prints/` (graph exports)

**Tool constraints**:

- ✅ Write to `analysis/`
- ✅ Read `data-private/derived/` and `data-public/metadata/`
- ❌ Modify `manipulation/`, `_frontend-*`

### 3. Publishing Orchestra (`@publishing-interviewer` + `@publishing-writer`)

**Owned namespace**: `_frontend-*`

**Role**: Assemble curated website from analytical content

**Workflow phases** (Interviewer):

1. **Intent capture**: Understand desired website
2. **Repository scan**: Discover publishable content
3. **Site design**: Specify navigation and protocols
4. **Contract writing**: Produce `publishing-contract.prompt.md`

**Workflow phases** (Writer):

1. **Contract reading**: Parse design decisions
2. **Asset resolution**: Collect and prepare source files
3. **Protocol application**: Apply protocol and mode per contract (Direct Line with VERBATIM or REDIRECTED mode, Technical Bridge, or Narrative Bridge)
4. **Configuration generation**: Build `_quarto.yml`
5. **Rendering**: Generate `_site/`

**Outputs**:

- `_frontend-N/publishing-contract.prompt.md`
- `_frontend-N/content/`
- `_frontend-N/_quarto.yml`
- `_frontend-N/_site/`

**Tool constraints**:

- ✅ Write to `_frontend-*`
- ✅ Read from all namespaces
- ❌ Modify source files in `analysis/`, `manipulation/`

## Namespace Ownership

| Namespace | Owner | Read | Write |
| --- | --- | --- | --- |
| `analysis/` | Report Composer | All | Composer only |
| `manipulation/` | Pipeline Engineer | All | Engineer only |
| `_frontend-*` | Publishing | All | Publishing only |
| `scripts/`, `ai/`, config | Shared | All | Rare coordination |

**Key principle**: Each agent only writes to its namespace. Read-only for all others.

## Data Provenance and Artifact Tracking

Artifacts flow through orchestras in sequence:

Raw Data
  → Pipeline Engineer (Ferry + Ellis)
    → Ellis parquet outputs
      → CACHE-manifest.md (versioned reference)
        → Report Composer (EDA/Report)
          → g1, g2, t1 artifact IDs (immutable)
            → Publishing (site assembly)
              → Published website

**Artifact IDs as stable references**: Once assigned (g1, g2, t1), IDs never change. Publishing Writer can reference these consistently.

## State Detection

### Report Composer Resumption

When invoked on existing report:

1. Read `report-contract.prompt.md` (mission, status)
2. Scan `.R` file (detect artifact chunks g*, t*, f*)
3. Scan `.qmd` file (verify chunk labels match, Data Context present)
4. Ask: "What would you like to work on next?"

**State classifications**:

- **Bootstrapped**: Scaffold exists, empty stubs → "Ready to interview?"
- **Interview active**: Contract has RQs, Data Context incomplete → "Develop Data Context?"
- **Development active**: Some g*, t* chunks coded → "Which graph next?"
- **Near complete**: All artifacts coded, audit pending → "Run final audit?"

### Publishing Writer

Reads contract, checks `content/`, determines resumption point, proceeds deterministically.

## Preventing Conflicts

### Principle 1: Write Isolation

Each agent writes only to its namespace. Conflicts impossible.

### Principle 2: Contract as Specification

Each orchestra maintains a contract:

- Report Composer: `report-contract.prompt.md`
- Publishing: `publishing-contract.prompt.md`
- Pipeline: Implicit phase-specific state

### Principle 3: Read-Only References

Shared reference layers enable coordination without direct communication:

- Pipeline maintains: `CACHE-manifest.md`
- Composer maintains: artifact naming conventions
- Publishing maintains: `publishing-contract.prompt.md`

### Principle 4: Single Handoff per Interaction

- **Publishing Interviewer → Writer**: Contract file is handoff token
- **Composer → Everything**: Published artifacts available downstream
- **Engineer → Everything**: Manifest documents outputs

### Principle 5: Idempotent Reruns

Agents can be safely rerun without starting over:

- Composer detects existing work and resumes
- Publishing Writer regenerates deterministically
- Engineer phases allow mid-stream resumption

## Failure Recovery

### Composer Crash

**State**: Some chunks coded, Data Context incomplete

**Recovery**:

1. Invoke again with same directory
2. Agent detects: contract exists, g1/g2 coded
3. Asks: "Continue with Data Context?"
4. Work resumes without loss

### Publishing Writer Failure

**State**: Partial assembly completed, render failed

**Recovery**:

1. Fix issue (e.g., broken hook script)
2. Invoke again
3. Reruns from contract; skips completed assembly
4. Render succeeds

### Pipeline Changes Break Reports

**State**: New Ellis column added, EDA references old column

**Recovery**:

1. Engineer updates `CACHE-manifest.md`
2. Composer reads new manifest
3. Agent alerts: "Column {name} not in current manifest"
4. Human decides: update report or revert?
5. Contract updated accordingly

## Reference Files

| File | Purpose |
| --- | --- |
| `composing-orchestra.md` | Composer system design |
| `pipeline-orchestra.md` | Pipeline system design |
| `publishing-orchestra.md` | Publishing system design |
| `.github/agents/report-composer.agent.md` | Composer role + capabilities |
| `.github/instructions/artifact-naming.instructions.md` | Artifact ID system |
| `.github/migration.md` | Whitelist of project-agnostic harness files |
| `.github/skills/evaluate-harness-equivalence/SKILL.md` | Byte-equivalence audit of the agnostic harness vs. an upstream repo |

## Summary

The three-orchestra model ensures:

- ✅ Agents never clobber each other (namespace isolation)
- ✅ Work is never lost (contract + state detection)
- ✅ Coordination is simple (read-only references + artifact IDs)
- ✅ Reruns are safe (idempotent operations)
- ✅ Failures are recoverable (manifests + explicit state)

Each agent owns its namespace, reads shared references, maintains clear handoff points, and together form a cohesive analytical infrastructure.

## Harness Integrity

The project-agnostic surface of this harness is enumerated in `.github/migration.md`. To
confirm a repository is in sync with the upstream support system, run the
`evaluate-harness-equivalence` skill (or the `/evaluate-harness-equivalence` prompt): it
byte-compares every whitelisted file against a reference repo and reports drift with
remediation suggestions.
