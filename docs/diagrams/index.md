# Open-Looper Architecture Diagrams

This directory contains C4 architecture diagrams documenting the open-looper system.

## Diagram Index

| Level | Diagram | Description |
|-------|---------|-------------|
| L1 | [01-context.md](./01-context.md) | Context Diagram - External actors and system boundaries |
| L2 | [02-container.md](./02-container.md) | Container Diagram - Major architectural components |
| L3 | [03-component.md](./03-component.md) | Component Diagram - Internal structure of containers |
| L4 | [04-code.md](./04-code.md) | Code Diagram - Key implementation patterns |

## Legend

```mermaid
C4Context
  boundary(OpenLooper, "Open-Looper System") {
    Person(user, "User", "Human developer using the system")
    System(looper, "Open-Looper", "AI-powered development loop orchestration")
  }
  Rel(user, looper, "Uses", "CLI/GUI")
```

## Quick Reference

- **L1 Context** - Shows external actors (User, GitHub, Docker, OpenCode) interacting with the system
- **L2 Container** - Breaks down the system into 4 primary containers (Agents, Scripts, Plugin, Worktrees)
- **L3 Component** - Details the internal structure of Agents and Script libraries
- **L4 Code** - Illustrates key implementation patterns and code organization