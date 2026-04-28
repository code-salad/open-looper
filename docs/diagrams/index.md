# open-looper C4 Architecture Diagrams

This directory contains C4 architecture diagrams documenting the open-looper system.

## Diagram Overview

| Level | Diagram | Purpose |
|-------|---------|---------|
| **L1** | [01-context.md](./01-context.md) | System context — external actors and interactions |
| **L2** | [02-container.md](./02-container.md) | Container architecture — 4 main containers |
| **L3** | [03-component.md](./03-component.md) | Component internals — agents and scripts |
| **L4** | [04-code.md](./04-code.md) | Code patterns — key implementation formats |

## Quick Reference

### External Actors
- **User** — Issues `/looper <task>` commands
- **GitHub** — Repository, CI/CD, Pull Requests
- **Docker** — Integration test runtime
- **Git** — Version control with worktree support

### Core Containers
1. **OpenCode Plugin** — OpenCode platform with looper skill
2. **Agents Container** — Planner, Doer, Checker + subagents
3. **Scripts Container** — Git, Docker, Stack helper scripts
4. **Worktrees Container** — Git worktree isolation per task

### PDC Loop Phases
```
PLAN → RED → GREEN → SIMPLIFY → (INTEGRATION) → CHECK
           ↓
        [iterate until PASS]
```

### Key Technologies
| Component | Technology |
|-----------|------------|
| Agent Definitions | Markdown (`.md`) |
| Scripting | Bash, Node.js |
| Version Control | Git with worktrees |
| Container Runtime | Docker, docker-compose |
| Communication | OpenCode Task tool |

## Diagram Relationships

```
┌─────────────────────────────────────────────────────────┐
│ L1: Context — External actors (User, GitHub, Docker)     │
│    ↓                                                    │
│ L2: Container — 4 containers (Agents, Scripts, Plugin,   │
│              Worktrees)                                 │
│    ↓                                                    │
│ L3: Component — Agent internals (Planner, Doer,        │
│              Checker) + Script libraries                │
│    ↓                                                    │
│ L4: Code — Implementation patterns (formats, trailers, │
│          TDD cycle)                                     │
└─────────────────────────────────────────────────────────┘
```

## Viewing Diagrams

These diagrams use **Mermaid** syntax and are compatible with:

- GitHub Markdown (rendered via github.com)
- GitLab Markdown (rendered via gitlab.com)
- VS Code Mermaid extension
- [Mermaid Live Editor](https://mermaid.live)

### Render Example

````markdown
```mermaid
C4Context
    title Context Diagram
    ...
```
````

## Legend

| C4 Element | Description |
|-----------|-------------|
| `Person` | Human actor |
| `Container` | Application or data store |
| `Component` | Internal component of a container |
| `System_Ext` | External system |
| `Enterprise_Boundary` | Groups elements of same platform |
| `Container_Boundary` | Groups elements of same container |
| `Component_Boundary` | Groups elements of same component |

## Maintenance

When modifying the system:

1. Update **L4** (code patterns) for implementation changes
2. Update **L3** (components) for structural changes
3. Update **L2** (containers) for container-level changes
4. Update **L1** (context) for external actor changes

## Files

| File | Lines | Description |
|------|-------|-------------|
| `index.md` | This file | Overview and navigation |
| `01-context.md` | ~60 | Context diagram (L1) |
| `02-container.md` | ~90 | Container diagram (L2) |
| `03-component.md` | ~120 | Component diagram (L3) |
| `04-code.md` | ~180 | Code diagram (L4) |
