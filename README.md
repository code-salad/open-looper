# open-looper

A [Plan-Do-Check](https://en.wikipedia.org/wiki/PDCA) loop plugin for [OpenCode](https://opencode.ai).

Three agents — **Planner**, **Doer**, **Checker** — iterate until the Checker passes the work.

## Overview

open-looper provides an automated development cycle:
1. **Plan** — Explore codebase and produce an actionable plan
2. **Do** — Write code and tests (TDD red→green)
3. **Check** — Review work and issue PASS/FAIL verdict
4. **Repeat** — On FAIL, iterate with feedback until PASS

Uses git worktrees for isolated development and produces conventional commits with full audit trail.

## Quick Start

### Setup

```bash
# Agents are in .opencode/agents/
# Skills are in .opencode/skills/looper/
# Scripts are in .opencode/skills/looper/scripts/
```

### Run a loop

```
/looper add authentication to the login endpoint
```

The skill triggers on `/looper <task>` and orchestrates the PDC loop.

## Structure

```
.opencode/
├── agents/           # PDC loop agents
│   ├── planner.md     # Creates execution plans
│   ├── doer.md        # Implements via TDD
│   ├── checker.md     # Issues PASS/FAIL verdict
│   └── */             # Helper agents (debugger, simplifier, etc.)
└── skills/
    └── looper/
        ├── SKILL.md   # PDC loop orchestration skill
        └── scripts/   # Helper scripts (setup-worktree, git-commit-loop, etc.)
```

## Agents

| Agent | Mode | Purpose |
|-------|------|---------|
| `planner` | primary | Explores codebase, produces actionable plan |
| `doer` | subagent | Implements via TDD (red→green→simplify) |
| `checker` | subagent | Reviews and issues verdict |
| `debugger` | subagent | Root-cause analysis for stuck iterations |
| `simplifier` | subagent | Refines implementation |
| `check-*` | subagent | Specialized review (build, tests, code, runtime, adversarial) |
| `plan-*` | subagent | Plan review (feasibility, completeness, scope) |

## Key Features

- **Worktree isolation** — Each task runs in `.worktrees/<task>/`
- **TDD enforcement** — Red phase (tests) must commit before green (implementation)
- **Resume support** — Pick up interrupted loops from last iteration
- **Conventional commits** — Full audit trail with `Loop-Phase:`, `Loop-Iteration:`, `Loop-Verdict:` trailers
- **Parallel exploration** — Agents spawn subagents for concurrent analysis

## Requirements

- Git repository
- `gh` CLI authenticated for PR creation (optional)
- Docker/docker-compose for integration tests (optional)

## License

MIT