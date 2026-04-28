# L4 Code Diagram - Key Implementation Patterns

```mermaid
C4Code
  title Open-Looper Code Diagram - Implementation Patterns

  Boundary(core, "Core Loop Pattern") {
    Component(plan_fn, "plan()", "Function", "Creates plan commit with test descriptions")
    Component(do_fn, "do()", "Function", "Executes RED→GREEN→SIMPLIFY cycle")
    Component(check_fn, "check()", "Function", "Runs verification and issues verdict")
    Component(loop, "while !done", "Loop", "Iterates until checker passes or max iterations")
  }

  Boundary(tdd, "TDD Cycle") {
    Component(red_phase, "RED Phase", "Phase", "Write failing tests first")
    Component(green_phase, "GREEN Phase", "Phase", "Implement minimum code to pass")
    Component(simplify_phase, "SIMPLIFY Phase", "Phase", "Refactor and clean up code")
  }

  Boundary(patterns, "Key Patterns") {
    Component(subagent_spawn, "Task() spawn", "Pattern", "Launch sub-agents with spec and context")
    Component(commit_trail, "Commit Trail", "Pattern", "Each phase commits with trailers for traceability")
    Component(pointer_resolution, "Delta Pointers", "Pattern", "Plans reference prior iterations by hash")
    Component(skill_discovery, "Skill Discovery", "Pattern", "Load skills via $SCRIPTS_DIR/<name>")
  }

  Rel(loop, plan_fn, "1. Plan")
  Rel(loop, do_fn, "2. Do")
  Rel(loop, check_fn, "3. Check")

  Rel(do_fn, red_phase, "Writes tests")
  Rel(do_fn, green_phase, "Implements")
  Rel(do_fn, simplify_phase, "Refactors")

  Rel(red_phase, green_phase, "Commits RED → GREEN")
  Rel(green_phase, simplify_phase, "Commits GREEN → SIMPLIFY")

  Rel(subagent_spawn, commit_trail, "Metadata in commits")
  Rel(pointer_resolution, commit_trail, "Hash references")
  Rel(skill_discovery, commit_trail, "Scripts track state")

  ShowLegend()
```

## Implementation Patterns

### Core Loop Pattern
The PDC loop follows a simple but powerful structure:

```javascript
async function runLoop(task, maxIterations = 10) {
  for (let i = 1; i <= maxIterations; i++) {
    const plan = await planner.createPlan(task, i);
    await doer.execute(plan, i);
    const verdict = await checker.verify(plan, i);
    if (verdict === 'PASS') break;
  }
}
```

### TDD Cycle (RED→GREEN→REFACTOR)
1. **RED** - Write failing tests derived from acceptance criteria
2. **GREEN** - Write minimum implementation to pass tests
3. **SIMPLIFY** - Refactor without changing behavior

### Sub-Agent Spawning Pattern
```javascript
Task(subagent_type="explore", prompt="<task-spec>", task_id?)
```
- Each sub-agent receives task description, context, and success criteria
- Results returned synchronously unless `run_in_background=true`

### Commit Trail Pattern
Each phase commits with trailers for traceability:
```
Loop-Phase: do-red
Loop-Iteration: 3
```

### Delta Pointer Resolution
Plans can reference prior iterations:
```
(unchanged from iteration 2 — see abc1234)
```
Resolved via `git log <hash> -1 --format="%B"`

### Skill Discovery
Scripts discovered and invoked via:
```bash
$SCRIPTS_DIR/<skill-name> [--args]
```