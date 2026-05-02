# L2 Container Diagram - Open-Looper Architecture

```mermaid
C4Container
  title Open-Looper Container Diagram

  Person(user, "User", "Human developer")

  Boundary(looper, "Open-Looper") {
    Container(agents, "Agents", "Node.js/TypeScript", "Orchestrates PDC loop: looper-planner, looper-doer, looper-checker")
    Container(scripts, "Scripts", "Bash/sh", ".opencode/scripts/*.sh - Automation utilities")
    Container(plugin, "Plugin", "TypeScript", "OpenCode plugin framework integration")
    Container(clones, "Clones", "Git", ".clones/ - Isolated development clones (no master access)")
  }

  System_Ext(github, "GitHub", "Issue tracking and PRs via gh CLI")
  System_Ext(docker, "Docker", "Container runtime for isolation")
  System_Ext(opencode, "OpenCode", "Plugin host environment")

  Rel(user, plugin, "Invokes via OpenCode", "Plugin API")
  Rel(plugin, agents, "Delegates to agents", "Direct function call")
  Rel(agents, scripts, "Executes scripts", "Bash subprocess")
  Rel(agents, clones, "Manages clones", "Git commands")
  Rel(agents, github, "API calls via gh", "REST API")
  Rel(scripts, docker, "Container ops", "docker CLI")
  Rel(clones, github, "Remote sync", "git push/fetch")

  Rel_D(agents, plugin, "Reports status", "Event emitter")

  ShowLegend()
```

## Container Responsibilities

| Container | Technology | Purpose |
|-----------|------------|---------|
| **Agents** | Node.js/TypeScript | Core PDC orchestration - Planner creates plans, Doer implements, Checker verifies |
| **Scripts** | Bash/sh | Automation utilities for git operations, docker management, file manipulation |
| **Plugin** | TypeScript | Integrates looper into OpenCode as a plugin, exposes CLI commands |
| **Clones** | Git | Isolated development clones in `.clones/` — branch-only clones with no access to master branch |

## Key Interactions

1. User invokes the plugin via OpenCode
2. Plugin delegates to the Agents container
3. Agents orchestrate the loop using Scripts for automation
4. Clones provide isolated development environments with no master access
5. GitHub integration handles version control and collaboration
6. Docker provides runtime isolation for agent execution