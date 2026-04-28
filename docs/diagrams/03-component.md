# Component Diagram (L3)

## open-looper Component Architecture

```mermaid
C4Component
    title Component Diagram - Agent and Script Internals

    Component_Boundary(planner_boundary, "Planner Agent") {
        Component(planner_explore, "Explorer", "Spawns Explore subagents to read files")
        Component(planner_plan_writer, "Plan Writer", "Writes plan to .opencode/plans/")
        Component(planner_committer, "Git Committer", "Commits plan via git-commit-loop")
    }

    Component_Boundary(doer_boundary, "Doer Agent") {
        Component(doer_red, "RED Phase", "Writes failing tests first (TDD)")
        Component(doer_green, "GREEN Phase", "Implements minimal code to pass tests")
        Component(doer_simplify, "SIMPLIFY Phase", "Refines implementation via simplifier subagent")
        Component(doer_integration, "INTEGRATION Phase", "Writes integration tests if applicable")
    }

    Component_Boundary(checker_boundary, "Checker Agent") {
        Component(checker_review, "Reviewer", "Spawns check-* subagents for reviews")
        Component(checker_verdict, "Verdict Issuer", "Issues PASS/FAIL based on subagent reports")
        Component(checker_pr, "PR Creator", "Creates GitHub PR on PASS verdict")
    }

    Component_Boundary(scripts_boundary, "Script Libraries") {
        Component(git_commit_loop, "git-commit-loop", "Creates conventional commits with loop trailers")
        Component(setup_worktree, "setup-worktree", "Creates isolated git worktree per task")
        Component(git_loop_context, "git-loop-context", "Reads prior loop iterations from git log")
        Component(run_tests, "run-tests", "Executes project test suite")
        Component(run_lint, "run-lint", "Runs linter with auto-fix")
        Component(run_typecheck, "run-typecheck", "Runs type checker")
        Component(compose_lifecycle, "compose-lifecycle", "Manages docker-compose services")
        Component(detect_stack, "detect-stack", "Detects project tech stack")
        Component(check_scope, "check-scope", "Detects scope drift in commits")
    }

    Rel(planner_explore, planner_plan_writer, "Produces exploration results")
    Rel(planner_plan_writer, planner_committer, "Commits plan")
    Rel(doer_red, doer_green, "Tests fail → implement")
    Rel(doer_green, doer_simplify, "Tests pass → refine")
    Rel(doer_simplify, doer_integration, "Simplify complete → integration")
    Rel(checker_review, checker_verdict, "Reviews complete → verdict")
    Rel(checker_verdict, checker_pr, "PASS verdict → create PR")
    Rel(doer_green, git_commit_loop, "Commits with trailers")
    Rel(doer_green, setup_worktree, "Creates worktrees")
    Rel(doer_green, run_tests, "Runs tests")
    Rel(doer_green, run_lint, "Runs linter")
    Rel(doer_green, run_typecheck, "Runs typecheck")
    Rel(doer_integration, compose_lifecycle, "Manages docker services")
    Rel(checker_review, detect_stack, "Detects tech stack")
    Rel(checker_review, check_scope, "Checks scope compliance")
```

## Legend

| Component Type | Description |
|----------------|-------------|
| **Planner Agent** | Phase 1: Exploration, planning, plan commit |
| **Doer Agent** | Phase 2: TDD red-green-simplify cycle |
| **Checker Agent** | Phase 3: Review, verdict, PR creation |
| **Script Libraries** | Reusable helper scripts |

## Agent State Machine

### Planner Agent States
1. **EXPLORE** → Spawns Explore subagents for parallel analysis
2. **PLAN** → Writes actionable plan to filesystem
3. **COMMIT** → Commits plan via git-commit-loop with phase trailers

### Doer Agent States
1. **RED** → Writes failing tests, commits test-only changes
2. **GREEN** → Implements minimal code, commits implementation
3. **SIMPLIFY** → Refines code via simplifier subagent
4. **INTEGRATION** → Writes integration tests (if applicable)

### Checker Agent States
1. **REVIEW** → Spawns check-* subagents in parallel
2. **VERDICT** → Aggregates reviews, issues PASS/FAIL
3. **PR** → On PASS: creates GitHub PR via gh CLI

## Script Library Details

| Script | Purpose | Key Functions |
|--------|---------|---------------|
| `git-commit-loop` | Conventional commits | Adds Loop-Phase, Loop-Iteration trailers |
| `setup-worktree` | Worktree creation | Creates .worktrees/<task>/ isolated branch |
| `git-loop-context` | Git history analysis | Extracts prior iterations from commit messages |
| `run-tests` | Test execution | Runs project-specific test command |
| `run-lint` | Linting | Runs linter, supports --fix |
| `run-typecheck` | Type checking | Runs type checker for the language |
| `compose-lifecycle` | Docker management | up/down/status for backing services |
| `detect-stack` | Stack detection | Detects Node.js, Python, Rust, etc. |
| `check-scope` | Scope compliance | Detects drift from planned files |
