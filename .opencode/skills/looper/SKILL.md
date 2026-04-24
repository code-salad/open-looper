---
name: looper
description: Use this skill when the user wants to run an iterative Plan-Do-Check agent loop. Three agents (Planner, Doer, Checker) cycle until the Checker passes the work. Triggered by "/looper" followed by a task description.
tools: Bash, Read, Edit, Write, Grep, Glob, Task, Todowrite
---

# PDC Loop Skill

Three agents (Planner, Doer, Checker) iterate until the Checker issues a PASS verdict.

## Key Principles

**Always use worktrees.** All work happens in isolated git worktrees under `.worktrees/<task>`.
**Never commit directly to the default branch.**

## Spawning planner / doer / checker

Use the `Task` tool to spawn subagents:
```
Task(subagent_type="planner", prompt=<Planner context>)
Task(subagent_type="doer", prompt=<Doer context>)
Task(subagent_type="checker", prompt=<Checker context>)
```

Wait for each to complete before spawning the next.

**Never run the PDC loop inline.** Do not skip the subagent boundary and
do planner/doer/checker work directly in this session — it defeats the
loop's isolation and iteration guarantees.

## Steps

### 0. Verify environment

Before any side effect, verify we are in a git repo:
```bash
git rev-parse --is-inside-work-tree
```

**Gate:** Abort if not in a git repo.

Also verify the scripts directory is available:
```bash
SCRIPTS_DIR="$(pwd)/.opencode/skills/looper/scripts"
if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "ERROR: looper scripts not found at $SCRIPTS_DIR" >&2
    exit 1
fi
```

### 1. Validate argument

If no task description is provided, ask the user for one. Do not proceed without one.

### 2. Generate task name

Sanitize the task description into a kebab-case task name: lowercase,
replace spaces/underscores with hyphens, remove non-alphanumeric
characters (except hyphens), truncate to 50 characters, strip
leading/trailing hyphens.

```bash
TASK_NAME=$(echo "$ARGUMENTS" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | tr -cd 'a-z0-9-' | head -c 50 | sed 's/^-*//;s/-*$//')
```

### 3. Create worktree

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_DIR=$($SCRIPTS_DIR/setup-worktree --task "$TASK_NAME")
cd "$WORKTREE_DIR"
```

**Gate:** If `setup-worktree` exits non-zero or `WORKTREE_DIR` is empty, abort immediately.

Verify we are on a loop branch:
```bash
git branch --show-current | grep -q '^loop/' || { echo "ERROR: not on a loop/ branch"; exit 1; }
```

### 4. Sync with remote

Fetch the latest and rebase onto the default branch:
```bash
SYNC_OUTPUT=$($SCRIPTS_DIR/sync-with-remote) && SYNC_EXIT=0 || SYNC_EXIT=$?
eval "$SYNC_OUTPUT"
```

Handle conflicts if STATUS=conflicts (exit 1):
1. List conflicted files: `git diff --name-only --diff-filter=U`
2. Read and resolve each conflict
3. Stage: `git add <file>`
4. Continue: `git rebase --continue`

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

#### 6b. Build agent context

```bash
CTX_COMMON=(
    --task "$TASK_NAME" --iteration "$ITERATION"
    --task-prompt "$ARGUMENTS" --scripts-dir "$SCRIPTS_DIR"
    --worktree-dir "$WORKTREE_DIR" --dev-port "$LOOPER_DEV_PORT"
)

PLANNER_CONTEXT=$($SCRIPTS_DIR/build-agent-context --role planner "${CTX_COMMON[@]}")
DOER_CONTEXT=$($SCRIPTS_DIR/build-agent-context --role doer "${CTX_COMMON[@]}")
CHECKER_CONTEXT=$($SCRIPTS_DIR/build-agent-context --role checker "${CTX_COMMON[@]}")
```

#### 6c. Run PLAN phase

```
=== Iteration ${ITERATION}/${MAX_ITERATIONS}: PLAN phase ===
```

Spawn the `planner` agent with the Planner context. Wait for completion.

#### 6d. Run DO phase (TDD: red→green)

```
=== Iteration ${ITERATION}/${MAX_ITERATIONS}: DO phase (TDD: red→green) ===
```

Spawn the `doer` agent with the Doer context. Wait for completion.

Before spawning the Checker, run pre-check:
```bash
PRE_CHECK_OUTPUT=$($SCRIPTS_DIR/pre-check 2>&1)
PRE_CHECK_EXIT=$?
```

If pre-check fails, skip Checker and commit synthetic FAIL, then continue to next iteration.

#### 6e. Run CHECK phase

```
=== Iteration ${ITERATION}/${MAX_ITERATIONS}: CHECK phase ===
```

Spawn the `checker` agent with the Checker context. Wait for completion.

#### 6f. Read verdict

```bash
VERDICT=$(git log --grep="Loop-Verdict:" -1 --format="%B" \
    | grep -oE 'Loop-Verdict: (PASS|FAIL)' | sed 's/Loop-Verdict: //' || echo "")
```

- **PASS:** Break out of the loop, proceed to step 7.
- **FAIL** (or no verdict): Report and continue to next iteration.

### 7. Sync before PR

After PASS, sync again to ensure clean PR:
```bash
SYNC_OUTPUT=$($SCRIPTS_DIR/sync-with-remote) && SYNC_EXIT=0 || SYNC_EXIT=$?
eval "$SYNC_OUTPUT"
```

Resolve any conflicts as in step 4.

### 8. Report results

- **PASS:** Report success with iteration count. The worktree at `$WORKTREE_DIR` is preserved.
- **FAIL (max iterations):** Report that max iterations were reached.
  Show the last checker verdict. The worktree is preserved for debugging.

### 9. Clean up (optional)

After PASS, push the branch:
```bash
git push -u origin "loop/$(echo "$TASK_NAME" | head -c 40)"
```

The loop branch is preserved for PR creation.