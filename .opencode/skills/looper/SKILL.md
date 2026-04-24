---
name: looper
description: Use this skill when the user wants to run an iterative Plan-Do-Check agent loop. Three agents (Planner, Doer, Checker) cycle until the Checker passes the work. Triggered by "/looper" followed by a task description.
tools: Bash, Read, Edit, Write, Grep, Glob, Task
---

# PDC Loop Skill

Three subagents (Planner, Doer, Checker) iterate until the Checker issues a PASS verdict.

## Spawning planner / doer / checker

Spawn the three subagents in sequence: planner → doer → checker. Wait for
each to complete before spawning the next.

Use the `Task` tool:
```
Task(subagent_type="planner", prompt=<Planner context>)
Task(subagent_type="doer", prompt=<Doer context>)
Task(subagent_type="checker", prompt=<Checker context>)
```

**Never run the PDC loop inline.** Do not skip the subagent boundary and
do planner/doer/checker work directly in this session — it defeats the
loop's isolation, commit trail, and worktree guarantees.

## Steps

### 0. Verify environment

Before ANY side effect, verify the scripts directory is available:

```bash
SCRIPTS_DIR="$(pwd)/.opencode/skills/looper/scripts"
if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "ERROR: looper scripts not found at $SCRIPTS_DIR" >&2
    exit 1
fi
```

**Gate:** If this check fails, abort immediately.

### 1. Validate environment

```bash
git rev-parse --is-inside-work-tree
```

**Gate:** Abort if not in a git repo.

Run `gh auth status`. If it fails, warn:
> "Warning: `gh` is not authenticated. PR creation will fail at the end. Run `gh auth login` to fix."

Continue anyway — do not abort.

### 2. Validate argument

If `$ARGUMENTS` is empty, ask the user for a task description. Do not proceed without one.

### 3. Generate task name

Sanitize `$ARGUMENTS` into a kebab-case task name: lowercase, replace spaces/underscores
with hyphens, remove non-alphanumeric characters (except hyphens), truncate to 50 characters,
strip leading/trailing hyphens.

### 4. Create worktree

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
SCRIPTS_DIR="${REPO_ROOT}/.opencode/skills/looper/scripts"
WORKTREE_DIR=$($SCRIPTS_DIR/setup-worktree --task "$TASK_NAME")
cd "$WORKTREE_DIR"
```

**Gate:** If `setup-worktree` exits non-zero or `WORKTREE_DIR` is empty, abort immediately.
**CRITICAL:** All work MUST happen inside the worktree. NEVER commit directly to the default branch.
Verify you are on a `loop/` branch:

```bash
git branch --show-current | grep -q '^loop/' || { echo "ERROR: not on a loop/ branch"; exit 1; }
```

### 4b. Sync worktree with remote

Fetch the latest remote and rebase the worktree branch onto the default remote branch.
This ensures the loop starts from an up-to-date base.

```bash
SYNC_OUTPUT=$($SCRIPTS_DIR/sync-with-remote) && SYNC_EXIT=0 || SYNC_EXIT=$?
eval "$SYNC_OUTPUT"
```

- **`STATUS=up-to-date` or `STATUS=rebased` (exit 0):** Continue to step 5.
- **`STATUS=conflicts` (exit 1):** The rebase is paused with conflicts. Resolve them:
  1. List conflicted files: `git diff --name-only --diff-filter=U`
  2. Read each conflicted file, understand both sides of the conflict.
  3. Edit the file to resolve the conflict (remove conflict markers, keep correct code).
  4. Stage each resolved file: `git add <file>`
  5. Continue the rebase: `git rebase --continue`
  6. If new conflicts appear, repeat until the rebase completes.
- **Exit 2 (error):** Warn and continue — the loop can still proceed without sync.

### 4c. Fetch issue context (if referenced)

```bash
FETCH_OUTPUT=$($SCRIPTS_DIR/fetch-issue-context --args "$ARGUMENTS") \
    && FETCH_EXIT=0 || FETCH_EXIT=$?
if [ "$FETCH_EXIT" -eq 1 ]; then
    echo "Issue is blocked. Aborting."
    exit 1
fi
ISSUE_NUMBER=$(echo "$FETCH_OUTPUT" | head -1 | sed 's/^NUMBER=//')
ISSUE_BODY=$(echo "$FETCH_OUTPUT" | tail -n +2)
```

### 5. Detect resume iteration

```bash
START_ITERATION=$($SCRIPTS_DIR/detect-resume)
```

### 6. Run the PDC loop

```bash
MAX_ITERATIONS="${LOOPER_MAX_ITERATIONS:-10}"
```

For each iteration from `START_ITERATION` to `MAX_ITERATIONS`:

#### 6a. Generate isolated dev port

```bash
LOOPER_DEV_PORT=$(( ( $(echo "$TASK_NAME" | cksum | cut -d' ' -f1) % 50000 ) + 10000 ))
```

#### 6b. Detect docker-compose (if applicable)

```bash
COMPOSE_INFO=$($SCRIPTS_DIR/detect-compose)
HAS_COMPOSE=$(echo "$COMPOSE_INFO" | jq -r 'if .compose_file != "none" then "true" else "false" end')
COMPOSE_SERVICES="none"
if [ "$HAS_COMPOSE" = "true" ]; then
    $SCRIPTS_DIR/compose-isolate --task "$TASK_NAME" >&2
    COMPOSE_SERVICES=$(echo "$COMPOSE_INFO" | jq -r '[.services | keys[]] | join(", ")')
fi
```

#### 6c. Build agent context

```bash
if [ "$ITERATION" -gt 1 ]; then
    LAST_CHECK_HASH=$(git log --grep="Loop-Phase: check" \
        --grep="Loop-Iteration: $((ITERATION - 1))" \
        --all-match --format="%H" -1 2>/dev/null || echo "")
    if [ -n "$LAST_CHECK_HASH" ]; then
        DIFF_CONTEXT=$(git diff --stat "$LAST_CHECK_HASH" HEAD 2>/dev/null | head -50)
    else
        DIFF_CONTEXT="First review — full review required."
    fi
else
    DIFF_CONTEXT="First iteration — full review required."
fi

CTX_COMMON=(
    --task "$TASK_NAME" --iteration "$ITERATION"
    --task-prompt "$ARGUMENTS" --scripts-dir "$SCRIPTS_DIR"
    --worktree-dir "$WORKTREE_DIR" --dev-port "$LOOPER_DEV_PORT"
    --compose "${HAS_COMPOSE:-false}" --compose-services "${COMPOSE_SERVICES:-none}"
    --issue-body "$ISSUE_BODY"
)

PLANNER_CONTEXT=$($SCRIPTS_DIR/build-agent-context --role planner "${CTX_COMMON[@]}")
DOER_CONTEXT=$($SCRIPTS_DIR/build-agent-context --role doer "${CTX_COMMON[@]}")
CHECKER_CONTEXT=$($SCRIPTS_DIR/build-agent-context --role checker "${CTX_COMMON[@]}" \
    --diff-context "$DIFF_CONTEXT")
```

#### 6d. Spawn agents

1. `=== Iteration ${ITERATION}/${MAX_ITERATIONS}: PLAN phase ===`
   Spawn `planner` with the Planner context.

2. `=== Iteration ${ITERATION}/${MAX_ITERATIONS}: DO phase (TDD: red→green) ===`
   Spawn `doer` with the Doer context.

   Before spawning the Checker, run pre-checks:
   ```bash
   PRE_CHECK_OUTPUT=$($SCRIPTS_DIR/pre-check 2>&1)
   PRE_CHECK_EXIT=$?
   ```
   If pre-check fails, commit synthetic FAIL and continue to next iteration without spawning Checker:
   ```bash
   $SCRIPTS_DIR/git-commit-loop --type "test" --scope "$TASK_NAME" \
       --message "check iteration ${ITERATION} — FAIL (pre-check)" \
       --body "Pre-check failed.\n\n${PRE_CHECK_OUTPUT}" \
       --phase "check" --iteration ${ITERATION} --verdict "FAIL"
   continue
   ```

3. `=== Iteration ${ITERATION}/${MAX_ITERATIONS}: CHECK phase ===`
   Spawn `checker` with the Checker context.

#### 6e. Read verdict

```bash
VERDICT=$(git log --grep="Loop-Verdict:" -1 --format="%B" \
    | grep -oE 'Loop-Verdict: (PASS|FAIL)' | sed 's/Loop-Verdict: //' || echo "")
```

- **PASS:** Break out of the loop, proceed to step 7.
- **FAIL** (or no verdict): Continue to next iteration.

### 7. Sync before PR

```bash
SYNC_OUTPUT=$($SCRIPTS_DIR/sync-with-remote) && SYNC_EXIT=0 || SYNC_EXIT=$?
eval "$SYNC_OUTPUT"
```

Resolve any conflicts as in step 4b.

### 8. Report results and create PR

- **PASS:** Report success with iteration count. Then invoke the `create-github-pr` skill to push the branch and create a PR.
- **FAIL (max iterations):** Report failure. The worktree is preserved for debugging.

### 9. Clean up

After PASS, the `create-github-pr` skill will handle squash-merge (if no DB migrations) and worktree cleanup.
