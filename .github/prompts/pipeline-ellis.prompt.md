---
description: >
  Phase 2 of the Pipeline Orchestra. Guides iterative development of Ellis transformation lanes
  from Ferry output into analysis-ready tables or files.
agent: Pipeline Engineer
---

# Pipeline Ellis

Develop or refine Ellis transformation lanes. This is Phase 2 of the Pipeline Orchestra.

## When to Use

- Ferry output exists and transformation logic needs to be implemented
- Project requirements changed and Ellis needs revision
- A new analytical rectangle or intermediate Ellis table is required
- Existing Ellis logic needs better documentation or validation checkpoints

## Prerequisites

- At least one numbered Ferry lane exists and has been run successfully
- `manipulation/pipeline-project-spec.md` identifies the current Ellis sequence
- The project-specific helper surfaces, if any, are documented locally in `manipulation/`

## Process

### Step 1: Read Context

1. Read `.github/pipeline-orchestra.md`.
2. Read `manipulation/README.md`.
3. Read `manipulation/pipeline-project-spec.md`.
4. Read existing numbered Ellis lanes in `manipulation/`.
5. Read `data-public/metadata/CACHE-manifest.md` if it exists.
6. Read any local helper files the existing Ellis lanes depend on.
7. Read the relevant templates in `scripts/templates/`.

### Step 2: Interview

Ask adaptive questions based on what already exists.

Typical questions:

1. Which entities and variables must survive into the analysis-ready output?
2. What exclusions, joins, or interval rules define the analytical cohort?
3. Which derivations belong in SQL versus R?
4. Which output object is provisional and which one is canonical for documentation?
5. What validation checkpoints would cheaply catch wrong joins or wrong row grain?

### Step 3: Scaffold or Refine Ellis Script

Create or update the appropriate numbered Ellis lane.

Each Ellis lane should make these sections easy to identify:

- setup and configuration
- input loading
- transformation logic
- validation or diagnostic checks
- output materialization

The lane may target tables, views, files, or a combination, depending on the project contract in
`manipulation/pipeline-project-spec.md`.

### Step 4: Document Inline

Document transformation decisions where the reasoning would otherwise be hard to recover.

Focus comments on:

- why a join or exclusion exists
- why a derived field is defined that way
- what row grain the output represents
- which downstream artifact depends on the result

### Step 5: Instruct Human

Tell the human what to run, what output to inspect, and what evidence to report before moving to
validation and documentation.
