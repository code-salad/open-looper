# Code Diagram (L4)

## open-looper Key Implementation Patterns

```mermaid
C4Component
    title Code Diagram - Key Patterns and Formats

    Component_Boundary(patterns, "Implementation Patterns") {
        Component(agent_def, "Agent Definition Format", "Markdown-based agent specifications")
        Component(git_trailers, "Git Commit Trailers", "Loop-Phase, Loop-Iteration, Loop-Verdict")
        Component(worktree_setup, "Worktree Setup", "Git worktree isolation per task")
        Component(tdd_cycle, "TDD Cycle", "RED → GREEN → SIMPLIFY")
    }

    Component_Boundary(formats, "Data Formats") {
        Component(plan_format, "Plan Format", ".opencode/plans/<task>/iteration-N.md")
        Component(context_format, "Context Format", "JSON with TASK_NAME, ITERATION, SCRIPTS_DIR")
        Component(commit_msg, "Commit Message", "type(scope): description body")
    }

    Rel(agent_def, git_trailers, "Uses for auditing")
    Rel(agent_def, worktree_setup, "Creates isolation")
    Rel(git_trailers, tdd_cycle, "Tracks phase progression")
    Rel(plan_format, context_format, "Passes context to agents")
    Rel(worktree_setup, commit_msg, "Creates conventional commits")
    Rel(tdd_cycle, commit_msg, "Generates commit messages")
```

## Pattern 1: Agent Definition Format

```markdown
# Agent Name

## Description
Brief description of agent purpose.

## Mode
primary | subagent

## Instructions
Step-by-step instructions...

## Usage
```bash
$AGENTS_DIR/<agent-name>
```

## Examples
Example invocations...
```

## Pattern 2: Git Commit Trailers

Commits follow conventional commit format with PDC loop trailers:

```
type(scope): short description

Longer description of changes made.

Loop-Phase: do-red | do-green | do-simplify | do-integration
Loop-Iteration: N
Loop-Verdict: PASS | FAIL (at checker phase)
```

### Trailer Types

| Trailer | Values | Purpose |
|---------|--------|---------|
| **Loop-Phase** | plan, do-red, do-green, do-simplify, do-integration, do-check | Current phase |
| **Loop-Iteration** | 1, 2, 3, ... | Iteration number |
| **Loop-Verdict** | PASS, FAIL | Checker verdict (if applicable) |

## Pattern 3: Worktree Setup

```bash
# Create isolated worktree for task
setup-worktree --task <task-name> --iteration <N>

# Result: .worktrees/<task-name>/
# - Isolated git branch per task
# - No interference with main branch
# - Easy cleanup on completion
```

### Worktree Directory Structure

```
.worktrees/
└── <task-name>/
    ├── .git/              # Worktree git data
    ├── .opencode/         # Agent definitions
    │   └── agents/
    ├── docs/              # Documentation
    └── [project files]    # Task-specific changes
```

## Pattern 4: TDD Cycle (RED-GREEN-SIMPLIFY)

```
┌─────────────────────────────────────────┐
│  RED PHASE                              │
│  - Write failing test first             │
│  - Commit: "red: add failing tests"     │
│  - Loop-Phase: do-red                   │
└────────────────┬──────────────────────┘
                 │ Tests fail
                 ▼
┌─────────────────────────────────────────┐
│  GREEN PHASE                            │
│  - Implement minimal code to pass       │
│  - Commit: "green: implement feature"   │
│  - Loop-Phase: do-green                 │
└────────────────┬──────────────────────┘
                 │ Tests pass
                 ▼
┌─────────────────────────────────────────┐
│  SIMPLIFY PHASE                         │
│  - Refine implementation                 │
│  - Remove redundancy, improve naming    │
│  - Commit: "simplify: refine impl"      │
│  - Loop-Phase: do-simplify               │
└─────────────────────────────────────────┘
```

## Pattern 5: Plan Format

```markdown
# Plan: <Task Name>

## Bug Analysis / Feature Description
...

## Fix Plan / Implementation Plan
...

## Files to modify
...

## Tests
...

## Acceptance Criteria
...

Loop-Phase: plan
Loop-Iteration: N
```

## Pattern 6: Agent Context (JSON)

```json
{
  "TASK_NAME": "add-authentication",
  "ITERATION": 1,
  "MAX_ITERATIONS": 5,
  "SCRIPTS_DIR": "/path/to/.opencode/scripts",
  "AGENTS_DIR": "/path/to/.opencode/agents",
  "WORKTREE_DIR": "/path/to/.worktrees/add-authentication"
}
```

## Pattern 7: Conventional Commit Format

```
<type>(<scope>): <short description>

[optional body]

[optional trailers]
```

### Commit Types

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Code refactoring |
| `test` | Test additions/changes |
| `docs` | Documentation changes |
| `chore` | Maintenance tasks |
| `plan` | Plan commit (planner phase) |
