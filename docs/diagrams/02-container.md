# Container Diagram (L2)

## open-looper Container Architecture

```mermaid
C4Container
    title Container Diagram - open-looper PDC Loop

    Person(user, "User", "Issues /looper commands via OpenCode")

    Container_Boundary(opencode_plugin, "OpenCode Plugin") {
        Container(opencode_core, "OpenCode Core", "AI coding assistant core")
        Container(skill_looper, "looper Skill", "Orchestrates PDC loop via Task tool")
    }

    Container_Boundary(agents, "Agents Container") {
        Container(planner, "Planner Agent", "Creates actionable plans from tasks")
        Container(doer, "Doer Agent", "Implements via TDD (red-green cycle)")
        Container(checker, "Checker Agent", "Reviews and issues PASS/FAIL verdict")
        Container(subagents, "Subagents", "debugger, simplifier, check-*, plan-*")
    }

    Container_Boundary(scripts, "Scripts Container") {
        Container(git_scripts, "Git Scripts", "git-commit-loop, setup-worktree, git-loop-context")
        Container(docker_scripts, "Docker Scripts", "compose-lifecycle, run-integration-tests")
        Container(stack_scripts, "Stack Scripts", "detect-stack, run-tests, run-lint, run-typecheck")
        Container(check_scripts, "Check Scripts", "check-scope, detect-resume, resolve-plan-pointers")
    }

    Container_Boundary(worktrees, "Worktrees Container") {
        Container(worktree_manager, "Worktree Manager", "Creates/removes isolated git worktrees")
        Container(task_worktrees, "Task Worktrees", ".worktrees/<task>/ per iteration")
    }

    System_Ext(github, "GitHub", "Repository, CI/CD, Pull Requests")
    System_Ext(docker, "Docker", "Integration test runtime")
    System_Ext(git, "Git", "Version control with worktree support")

    Rel(user, opencode_core, "/looper <task>")
    Rel(opencode_core, skill_looper, "Triggers looper skill")
    Rel(skill_looper, planner, "Spawns planner agent")
    Rel(skill_looper, doer, "Spawns doer agent")
    Rel(skill_looper, checker, "Spawns checker agent")
    Rel(planner, subagents, "Spawns for parallel analysis")
    Rel(doer, subagents, "Spawns simplifier, debugger")
    Rel(checker, subagents, "Spawns check-* subagents")
    Rel(subagents, scripts, "Uses helper scripts")
    Rel(scripts, worktree_manager, "Manages worktrees")
    Rel(worktree_manager, task_worktrees, "Creates isolated development")
    Rel(scripts, github, "gh CLI for commits/PRs")
    Rel(docker_scripts, docker, "Runs containers")
    Rel(task_worktrees, git, "Git operations")
```

## Legend

| Container Type | Description |
|----------------|-------------|
| **OpenCode Plugin** | The OpenCode platform with looper skill |
| **Agents Container** | PDC loop agents (planner, doer, checker + subagents) |
| **Scripts Container** | Helper scripts for git, docker, stack detection |
| **Worktrees Container** | Git worktree isolation per task |

## Technology Stack

| Component | Technology |
|-----------|------------|
| Agent Definitions | Markdown (`.md` files) |
| Scripting | Bash, Node.js |
| Version Control | Git with worktrees |
| Container Runtime | Docker, docker-compose |
| Communication | Task tool (OpenCode) |

## Container Responsibilities

| Container | Responsibility |
|-----------|----------------|
| **Planner Agent** | Explores codebase, produces actionable plan |
| **Doer Agent** | TDD red-green cycle, commits implementation |
| **Checker Agent** | Reviews code, issues PASS/FAIL verdict |
| **Subagents** | Specialized tasks (debug, simplify, check-*) |
| **Git Scripts** | Worktree setup, conventional commits |
| **Docker Scripts** | Integration test execution |
| **Worktrees** | Isolated development per task/iteration |
