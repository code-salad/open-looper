# L1 Context Diagram - Open-Looper System Overview

```mermaid
C4Context
  title Open-Looper System Context

  Person(user, "User", "Human developer who initiates development tasks and reviews results")

  System_Ext(github, "GitHub", "GitHub platform for repository hosting, issues, and pull requests")
  System_Ext(docker, "Docker", "Container runtime for isolated execution environments")
  System_Ext(opencode, "OpenCode", "Plugin host that loads and executes the looper plugin")

  System(looper, "Open-Looper", "AI-powered Plan-Do-Check loop orchestration system")
  System_Ext(scripts, "Scripts", ".opencode/scripts - Bash scripts for automation and integration")
  System_Ext(clones, "Clones", ".clones/ - Isolated git clones for sandboxed development")

  Rel(user, github, "Creates issues, reviews PRs", "gh CLI")
  Rel(user, opencode, "Invokes via plugin API", "OpenCode plugin interface")

  Rel(looper, github, "Reads/writes issues, creates PRs", "GitHub API")
  Rel(looper, docker, "Spawns containers for execution", "Docker API")
  Rel(looper, opencode, "Runs as plugin within host", "Plugin protocol")
  Rel(looper, scripts, "Executes via bash", "Shell commands")
  Rel(looper, clones, "Creates and manages isolated clones", "Git clone commands")

  Rel(scripts, github, "CI/CD integration", "gh/webhooks")
  Rel(scripts, docker, "Container management", "docker CLI")
  Rel(clones, github, "Linked to remotes", "git push/fetch")

  ShowLegend()
```

## Description

The context diagram shows the open-looper system as the central component, with four external actors:

| Actor | Role |
|-------|------|
| **User** | Human developer who initiates tasks, reviews AI-generated code, and approves changes |
| **GitHub** | Repository platform providing issue tracking, PR capabilities, and CI/CD hooks |
| **Docker** | Container runtime providing isolated execution environments for agent operations |
| **OpenCode** | Plugin host that loads and executes the looper as a plugin within its context |

The system interacts with all four actors to orchestrate the Plan-Do-Check development loop.