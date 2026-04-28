# Context Diagram (L1)

## open-looper System Context

```mermaid
C4Context
    title Context Diagram - open-looper System

    Enterprise_Boundary(enterprise, "open-looper Platform") {
        Person(user, "User", "Initiates PDC loop tasks via OpenCode")
        Container(opencode, "OpenCode", "AI coding assistant platform")
        Container(agents, "Agents", "PDC loop agents (planner, doer, checker, subagents)")
        Container(scripts, "Scripts", "Helper scripts for git, docker, etc.")
        Container(worktrees, "Worktrees", "Git worktree isolation layer")
    }

    System_Ext(github, "GitHub", "Hosts repository, CI/CD, Pull Requests")
    System_Ext(docker, "Docker", "Container runtime for integration tests")
    System_Ext(git, "Git", "Version control with worktree support")
    System_Ext(opencode_ext, "OpenCode API", "External OpenCode platform API")

    Rel(user, opencode, "Issues /looper commands")
    Rel(opencode, agents, "Spawns PDC agents")
    Rel(agents, scripts, "Uses helper scripts")
    Rel(agents, worktrees, "Createsisolated worktrees per task")
    Rel(agents, github, "Creates commits, PRs via gh CLI")
    Rel(scripts, docker, "Runs integration tests")
    Rel(worktrees, git, "Manages git repository state")
    Rel(github, opencode_ext, "Webhook notifications")
    Rel(docker, github, "Builds and pushes images")

    UpdateRelStyle(user, opencode, $offsetX="0", $offsetY="-40")
    UpdateRelStyle(opencode, agents, $offsetX="0", $offsetY="40")
    UpdateRelStyle(agents, github, $offsetX="40", $offsetY="0")
    UpdateRelStyle(github, docker, $offsetX="40", $offsetY="20")
```

## Legend

| Element | Description |
|---------|-------------|
| **Person** | Human actors (User) |
| **Container** | Applications or data stores within the system |
| **System_Ext** | External systems outside the open-looper boundary |
| **Enterprise_Boundary** | Groups elements belonging to the same platform |

## External Dependencies

- **GitHub**: Repository hosting, CI/CD pipelines, PR creation via `gh` CLI
- **Docker**: Integration test execution, container builds
- **Git**: Worktree management, commit history
- **OpenCode API**: External platform for webhook events

## Key Interactions

1. User issues a `/looper <task>` command via OpenCode
2. OpenCode spawns the Planner → Doer → Checker cycle
3. Agents create git worktrees for isolated development
4. Helper scripts manage Docker containers for integration tests
5. Commits and PRs are pushed to GitHub via `gh` CLI
