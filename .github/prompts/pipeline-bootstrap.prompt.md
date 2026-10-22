---
description: >
   Phase 1 of the Pipeline Orchestra. Guides discovery of raw source systems and scaffolding of
   Ferry lanes that transport data into project staging. Produces or refreshes INPUT-manifest.
agent: Pipeline Engineer
---

# Pipeline Bootstrap

Bootstrap or refine a project pipeline from raw source systems. This is Phase 1 of the Pipeline
Orchestra.

## When to Use

- A project has no Ferry lane yet
- A new source must be added to an existing pipeline
- The source contract changed and Ferry needs redesign
- The INPUT manifest is missing or stale

## Process

### Step 1: Read Context

1. Read `.github/pipeline-orchestra.md`.
2. Read `manipulation/README.md`.
3. Read `manipulation/pipeline-project-spec.md`.
4. Read `manipulation/pipeline.md` if it exists.
5. Read `config.yml` for available DSNs and path conventions.
6. Read `scripts/templates/ferry-to-cache.R` when an R Ferry lane is appropriate.
7. Discover existing numbered Ferry lanes in `manipulation/`.
8. Read `data-public/metadata/INPUT-manifest.md` if it exists.

### Step 2: Interview

Ask 3 to 5 adaptive questions based on what the project adapter files do not already answer.

Typical questions:

1. Which source systems and objects must be transported?
2. What DSN, credentials pattern, or file locations should the lane use?
3. Should the Ferry output remain split by source or be unified?
4. Are there transport constraints such as very wide tables, very large extracts, or incremental windows?
5. What naming or versioning convention should the staged outputs follow?

### Step 3: Scaffold Ferry Script

Create or update the appropriate numbered Ferry lane in `manipulation/`.

The lane should:

- declare its inputs and outputs
- follow the Ferry Pattern constraints
- use project configuration rather than hardcoded secrets
- produce durable staging artifacts
- emit at least one cheap validation checkpoint

### Step 4: Draft INPUT-Manifest

Create or update `data-public/metadata/INPUT-manifest.md` from actual source inspection.

Capture:

- source inventory
- transport scope
- expected keys or row grain
- staging outputs created by Ferry
- known limitations or access caveats

### Step 5: Instruct Human

Tell the human what to run, what artifact to inspect, and what to report back before moving to
Ellis development.
