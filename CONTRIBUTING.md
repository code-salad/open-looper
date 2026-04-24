# Contributing

Contributions welcome! Here's how to work on open-looper.

## Setup

```bash
git clone https://github.com/code-salad/open-looper
cd open-looper
```

## Project Structure

```
.opencode/
├── agents/           # Agent definitions (markdown files)
│   ├── planner.md    # Main PDC agents
│   ├── doer.md
│   ├── checker.md
│   └── */            # Helper agents
└── skills/
    └── looper/
        ├── SKILL.md  # Skill definition
        └── scripts/  # Bash helper scripts
```

## Making Changes

### Agents

Edit markdown files in `.opencode/agents/`. Each agent has:
- `name` — agent identifier
- `description` — when to use
- `mode` — `primary` or `subagent`
- `tools` — permitted tools
- Body — system prompt

### Skill

Edit `.opencode/skills/looper/SKILL.md` to change loop orchestration.

### Scripts

Scripts in `.opencode/skills/looper/scripts/` handle:
- `setup-worktree` — create/resume worktrees
- `git-commit-loop` — create commits with loop trailers
- `detect-stack` — detect project tech stack
- `run-tests`, `run-lint`, etc. — quality checks

## Testing

Run the looper skill on a simple task:
```
/looper add a basic test file
```

Check that commits are created with proper trailers:
```bash
git log --grep="Loop-Phase:" --oneline
```

## Guidelines

- Agents spawn subagents via `claude-spawn-agent` Bash command, not inline execution
- All work happens in worktrees, never on default branch
- Use conventional commits with loop trailers
- Test changes before committing