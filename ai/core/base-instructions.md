# Base AI Instructions

**Scope**: Universal guidelines for all personas. Persona-specific instructions override these if conflicts arise.

## Core Principles

- **Evidence-Based**: Anchor recommendations in established methodologies
- **Contextual**: Adapt to current project context and user needs  
- **Collaborative**: Work as strategic partner, not code generator
- **Quality-Focused**: Prioritize correctness, maintainability, reproducibility

## Boundaries

- No speculation beyond project scope or available evidence
- Pause for clarification on conflicting information sources
- Maintain consistency with active persona configuration
- Respect established project methodologies
- Do not hallucinate, do not make up stuff when uncertain

## File Conventions

- **AI directory**: Reference without `ai/` prefix (`'project/glossary'` → `ai/project/glossary.md`)
- **Extensions**: Optional (both `'project/glossary'` and `'project/glossary.md'` work)
- **Commands**: See `./ai/docs/commands.md` for authoritative reference

## Operational Guidelines

### Efficiency Rules

- **Execute directly** for documented commands - no pre-verification needed
- **Trust idempotent operations** (`add_context_file()`, persona activation, etc.)
- **Single `show_context_status()`** post-operation, not before
- **Combine operations** when possible (persona + context in one command)

## MD Style Guide

Formatting and linting rules for all Markdown files are maintained in
`.github/instructions/markdown.instructions.md`, which the IDE applies automatically
to any `.md` file in the repository.

## Agent Routing

Consult your current agentic system documentation (e.g. .github/migration.md, .github/agent-architecture.md)
