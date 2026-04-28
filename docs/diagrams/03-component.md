# L3 Component Diagram - Agent Internals

```mermaid
C4Component
  title Open-Looper Component Diagram - Agents & Scripts

  Container_Boundary(agents, "Agents Container") {
    Component(planner, "Planner Agent", "TypeScript", "Creates implementation plans from task descriptions")
    Component(doer, "Doer Agent", "TypeScript", "Implements plans using TDD red-green cycle")
    Component(checker, "Checker Agent", "TypeScript", "Verifies implementation against acceptance criteria")
    Component(subagents, "Sub-Agents", "TypeScript", "looper-debugger, looper-simplifier, gh-issue-creator, etc.")

    Component(scripts_lib, "Scripts Library", "Bash", "git-commit-loop, run-tests, run-lint, detect-stack, etc.")
    Component(state, "State Manager", "TypeScript", "Manages loop iteration state and commit history")
  }

  Container_Boundary(scripts, "Scripts Container") {
    Component(git_ops, "Git Operations", "Bash", "git-commit-loop, git-loop-context, check-scope")
    Component(testing, "Testing Utils", "Bash", "run-tests, run-integration-tests, install-deps")
    Component(detection, "Detection Utils", "Bash", "detect-stack, detect-compose, resolve-plan-pointers")
    Component(lifecycle, "Lifecycle Scripts", "Bash", "compose-lifecycle, scaffold-integration-ci")
  }

  Rel(planner, state, "Reads/writes iteration state")
  Rel(doer, state, "Reads/writes iteration state")
  Rel(checker, state, "Reads iteration state for verification")

  Rel(doer, scripts_lib, "Calls scripts for execution")
  Rel(subagents, scripts_lib, "Calls scripts for execution")

  Rel(scripts_lib, git_ops, "Implements git operations")
  Rel(scripts_lib, testing, "Implements testing utilities")
  Rel(scripts_lib, detection, "Implements detection utilities")
  Rel(scripts_lib, lifecycle, "Implements lifecycle management")

  Rel(subagents, planner, "Spawned by planner for exploration")
  Rel(subagents, doer, "Spawned by doer for debugging")
  Rel(subagents, checker, "Spawned by checker for adversarial testing")

  ShowLegend()
```

## Component Details

### Core Agents
| Component | Responsibility |
|-----------|----------------|
| **Planner** | Analyzes task, explores codebase, creates implementation plans with test descriptions |
| **Doer** | Follows TDD cycle - writes failing tests (RED), implements to pass (GREEN), refactors (SIMPLIFY) |
| **Checker** | Reviews doer's work, runs verification, issues PASS/FAIL verdict |
| **Sub-Agents** | Specialized agents for debugging, simplification, issue creation, adversarial review |

### Script Libraries
| Component | Purpose |
|-----------|---------|
| **Git Operations** | Commit management, scope checking, plan pointer resolution |
| **Testing Utils** | Test execution, dependency installation, integration test runner |
| **Detection Utils** | Stack detection, docker-compose detection, plan resolution |
| **Lifecycle Scripts** | Docker compose management, CI scaffolding |

### State Management
The state manager maintains iteration context across the PDC loop, tracking:
- Current iteration number
- Plan/RED/GREEN/SIMPLIFY/INTEGRATION commit hashes
- Verdict history and checker feedback