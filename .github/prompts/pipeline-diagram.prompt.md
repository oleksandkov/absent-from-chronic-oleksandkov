---
description: Create or update the canonical pipeline diagram embedded in manipulation/pipeline.md.
---

# Pipeline Diagram

Maintain the canonical pipeline diagram for a project pipeline.

## Canonical Source

The canonical Mermaid source lives in `manipulation/pipeline.md`.

The line immediately before the Mermaid fence must be:

```markdown
<!-- PIPELINE-DIAGRAM-SOURCE -->
```

After any edit, remind the user to regenerate the rendered image with the project render task or
the repository render script if one exists.

## Diagram Rules

- Use `flowchart LR`
- Group related stages with `subgraph`
- Keep numbered Ferry and Ellis lanes explicit
- Show downstream consumers only when they help explain the contract
- Keep the diagram synchronized with `manipulation/pipeline-project-spec.md`

## Update Mode

When updating an existing diagram:

1. Read `manipulation/pipeline.md`.
2. Read `manipulation/pipeline-project-spec.md`.
3. Ask only for changes that are still unclear.
4. Return a revised Mermaid block suitable for `manipulation/pipeline.md`.

## Create Mode

When creating a new diagram:

1. Read `manipulation/README.md`.
2. Read `manipulation/pipeline-project-spec.md`.
3. Discover existing numbered lanes in `manipulation/`.
4. Draft a Mermaid diagram that reflects the active or planned sequence.
5. Instruct the user to place it under the `<!-- PIPELINE-DIAGRAM-SOURCE -->` marker in
   `manipulation/pipeline.md`.
