---
name: looper
description: Use this skill when the user wants to run an iterative Plan-Do-Check agent loop. Three agents (Planner, Doer, Checker) cycle until the Checker passes the work. Triggered by "/looper" followed by a task description.
tools: Bash, Read, Edit, Write, Grep, Glob, Task
---

# PDC Loop Skill

Three subagents (Planner, Doer, Checker) iterate until the Checker issues a PASS verdict.

## Phase Goals

- **PLAN:** Planner analyzes the issue and creates a fix plan.
- **DO:** Doer implements the plan following TDD (red→green).
- **CHECK:** Checker validates the implementation and issues a verdict.

## Variables

| Variable | Source | Description |
|---|---|---|
| `ARGUMENTS` | User input | Task description or issue reference (e.g. `#5`). Empty means auto-select. |
| `TASK_NAME` | Derived | Sanitized kebab-case name derived from `ARGUMENTS`. |
| `WORKTREE_DIR` | `setup-worktree` | Absolute path to the isolated worktree for this task. |
| `SCRIPTS_DIR` | Computed | Path to `.opencode/skills/looper/scripts`. |
| `START_ITERATION` | `detect-resume` | Which iteration to resume from (1 if no prior work). Capped at `MAX_ITERATIONS`. |
| `MAX_ITERATIONS` | `LOOPER_MAX_ITERATIONS` env or 10 | Upper bound on loop iterations. Override: `export LOOPER_MAX_ITERATIONS=20`. |
| `LOOPER_DEV_PORT` | Derived | Isolated dev server port for this iteration. |
| `FETCH_EXIT` | `fetch-issue-context` exit code | 0=success, 1=blocked, 2=not found. Exit 2 prints warning and continues. |

> **Security note:** Steps 4b and 7 use `eval "$SYNC_OUTPUT"` to apply shell variable assignments from `sync-with-remote`. Only call `eval` on output from trusted scripts in this codebase.

## Spawning planner / doer / checker

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

If `ARGUMENTS` is empty, follow the auto-selection path (step 2a).
Otherwise, proceed directly to step 3.

### 2a. Auto-select issue (when no arguments)

```bash
SCRIPTS_DIR="${REPO_ROOT}/.opencode/skills/looper/scripts"
READY_JSON=$($SCRIPTS_DIR/list-ready-issues --json 2>/dev/null)
READY_COUNT=$(echo "$READY_JSON" | jq 'length')
```

- **If `READY_COUNT` > 0:** Select the oldest issue (`READY_JSON | jq '.[0]'`), extract its number, and claim it:
  ```bash
  OLDEST=$(echo "$READY_JSON" | jq '.[0]')
  ISSUE_NUM=$(echo "$OLDEST" | jq -r '.number')
  ISSUE_TITLE=$(echo "$OLDEST" | jq -r '.title')

  if $SCRIPTS_DIR/claim-issue "$ISSUE_NUM" 2>/dev/null; then
      ARGUMENTS="#$ISSUE_NUM"
  else
      echo "Warning: could not claim issue #$ISSUE_NUM — falling back to manual entry" >&2
      # Ask user for task description (continue to step 3 with empty → user prompt)
      ARGUMENTS=""
  fi
  ```
- **If `READY_COUNT` == 0:** Fall back to asking the user for a task description (continue to step 3 with empty → user prompt).

### 3. Generate task name

Sanitize `$ARGUMENTS` into a kebab-case task name: lowercase, replace spaces/underscores
with hyphens, remove non-alphanumeric characters (except hyphens), truncate to 50 characters,
strip leading/trailing hyphens.

### 4. Create worktree

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
SCRIPTS_DIR="${REPO_ROOT}/.opencode/skills/looper/scripts"
WORKTREE_DIR=$($SCRIPTS_DIR/setup-worktree --task "$TASK_NAME" --unique)
cd "$WORKTREE_DIR"
```

> **⚠️ WARNING:** `cd "$WORKTREE_DIR"` changes the working directory. All subsequent
> steps run inside the worktree. Never commit directly to the default branch.

**Gate:** If `setup-worktree` exits non-zero or `WORKTREE_DIR` is empty, abort immediately.
**CRITICAL:** All work MUST happen inside the worktree. NEVER commit directly to the default branch.
Verify you are on a `loop/` branch:

```bash
git branch --show-current | grep -q '^loop/' || { echo "ERROR: not on a loop/ branch"; exit 1; }
```

### 4b. Sync worktree with remote

Fetch the latest remote and rebase the worktree branch onto the default remote branch.
This ensures the loop starts from an up-to-date base.

> **Note:** Force-pushing to protected branches is blocked by GitHub's branch protection rules.
> The sync script handles this gracefully by detecting the protected branch and skipping force-push.

```bash
SYNC_OUTPUT=$($SCRIPTS_DIR/sync-with-remote) && SYNC_EXIT=0 || SYNC_EXIT=$?
eval "$SYNC_OUTPUT"
```

**eval output contract:** `sync-with-remote` emits `STATUS=<value>` to stdout.
The `eval` call makes `STATUS` available as a shell variable for the conditional below.

- **`STATUS=up-to-date` or `STATUS=rebased` (exit 0):** Continue to step 5.
- **`STATUS=conflicts` (exit 1):** The rebase is paused with conflicts. Resolve them using the **"prefer local changes"** strategy (see below).
- **Exit 2 (error):** Warn and continue — the loop can still proceed without sync.

**Capture sync state for step 7:**

```bash
SYNC_STATUS="${STATUS:-}"
SYNC_HEAD=$(git rev-parse HEAD)
```

> **Conflict resolution strategy: prefer local (worktree) changes**
>
> When resolving rebase conflicts, prefer keeping your local changes (the worktree branch).
> This is because the worktree branch contains the planned implementation, while the
> remote branch is the shared baseline.
>
> For each conflicted file:
> 1. Read the file to understand both sides of the conflict
> 2. Use `git checkout --ours <file>` to keep your loop/ branch version (the "ours" side)
> 3. Stage the resolved file: `git add <file>`
> 4. Continue the rebase: `git rebase --continue`
>
> If new conflicts appear, repeat until the rebase completes.
>
> **Why prefer local?** The looper worktree is a disposable context for implementing
> a fix. The remote baseline is the source of truth. Preferring local ensures the
> planned changes are preserved.
>
> **Alternative (not recommended):** To prefer remote changes instead, use
> `git checkout --theirs <file>` before `git add`. This discards local changes
> and is generally not what you want in a loop/ worktree.

### 4c. Fetch issue context (if referenced)

```bash
FETCH_OUTPUT=$($SCRIPTS_DIR/fetch-issue-context --args "$ARGUMENTS") \
    && FETCH_EXIT=0 || FETCH_EXIT=$?
if [ "$FETCH_EXIT" -eq 1 ]; then
    echo "Issue is blocked. Aborting."
    exit 1
fi
if [ "$FETCH_EXIT" -eq 2 ]; then
    echo "Warning: issue not found or not an issue reference — skipping context fetch" >&2
    ISSUE_NUMBER=""
    ISSUE_BODY=""
else
    ISSUE_NUMBER=$(echo "$FETCH_OUTPUT" | head -1 | sed 's/^NUMBER=//')
    ISSUE_BODY=$(echo "$FETCH_OUTPUT" | tail -n +2)
fi
```

### 5. Detect resume iteration

```bash
START_ITERATION=$($SCRIPTS_DIR/detect-resume)
```

**Contract:** `detect-resume` returns a positive integer ≥ 1. If prior loop commits
exist, it returns the next iteration number after the last completed phase. If no
prior work exists, it returns 1.

**Upper bound:** If `START_ITERATION` exceeds `MAX_ITERATIONS`, abort:
```bash
if [ "$START_ITERATION" -gt "$MAX_ITERATIONS" ]; then
    echo "ERROR: resume iteration $START_ITERATION exceeds max ($MAX_ITERATIONS). Aborting." >&2
    exit 1
fi
```

### 6. Run the PDC loop

```bash
MAX_ITERATIONS="${LOOPER_MAX_ITERATIONS:-10}"
```

For each iteration from `START_ITERATION` to `MAX_ITERATIONS`:

#### 6a. Generate isolated dev port

```bash
# Port derived from task name hash — deterministic, avoids collisions
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

**Verdict extraction contract:**
- Format: `Loop-Verdict: PASS` or `Loop-Verdict: FAIL` in commit subject/body
- Source: most recent commit matching `Loop-Verdict:` pattern
- Tool: `git log --grep="Loop-Verdict:" -1 --format="%B"`

- **PASS:** Break out of the loop, proceed to step 7.
- **FAIL** (or no verdict): Continue to next iteration.

### 7. Sync before PR

**Rationale:** The worktree may have drifted from the default branch during the loop (e.g., if another PR was merged). Re-syncing ensures the PR is mergeable without conflicts. This is especially important for long-running loops or multi-iteration tasks.

```bash
# Check if we need to re-sync:
# 1. Did step 4b succeed with up-to-date or rebased?
# 2. Are there new commits since step 4b?

STEP4B_STATUS="${SYNC_STATUS:-}"
STEP4B_HEAD="${SYNC_HEAD:-}"

CURRENT_HEAD=$(git rev-parse HEAD)
NEW_COMMITS=false

if [ "$STEP4B_STATUS" = "up-to-date" ] || [ "$STEP4B_STATUS" = "rebased" ]; then
    if [ "$CURRENT_HEAD" != "$STEP4B_HEAD" ]; then
        NEW_COMMITS=true
    fi
fi

if [ "$NEW_COMMITS" = true ]; then
    echo "New commits detected — re-syncing with remote..."
    SYNC_OUTPUT=$($SCRIPTS_DIR/sync-with-remote) && SYNC_EXIT=0 || SYNC_EXIT=$?
    eval "$SYNC_OUTPUT"
    # Handle conflicts using "prefer local" strategy (see step 4b)
else
    echo "No new commits since step 4b — skipping re-sync."
fi
```

**Never skip if step 4b had conflicts** — if `STEP4B_STATUS=conflicts`, always run the re-sync
to allow resolution to proceed.

### 8. Report results and create PR

- **PASS:** Report success with iteration count. Then invoke the `create-github-pr` skill to push the branch and create a PR.
- **FAIL (max iterations):** Report failure. The worktree is preserved for debugging.

### 8a. Wait for CI

After creating the PR, poll until CI checks complete.

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')
CI_STATUS=$(gh pr checks "$PR_NUMBER" --watch 2>&1) || CI_EXIT=$?
```

- **All checks pass:** Proceed to step 8b.
- **Any check fails:** Report failure. Do NOT proceed to merge. Exit with error.
- **Timeout (>20 min):** Report timeout. Do NOT proceed to merge. Exit with error.
- **No checks configured:** Log "No CI checks configured" and proceed to step 8b.

### 8b. Detect DB migrations

Before merge, check whether the PR contains DB migration files:

```bash
CHANGED_FILES=$(git diff --name-only "$BASE_REF"...HEAD)
HAS_MIGRATIONS=false

if echo "$CHANGED_FILES" | grep -qiE \
    '(migrations?/|db/migrate|alembic/versions|flyway|prisma/migrations|drizzle/|knex/migrations|sequelize/migrations|typeorm/migrations|migrate.*\.sql$|migration.*\.sql$)'; then
    HAS_MIGRATIONS=true
fi
```

Migration patterns detected:
- `migrations/` or `migration/` — generic migration directories
- `db/migrate/` — Rails ActiveRecord migrations
- `alembic/versions/` — Python/Alembic migrations
- `prisma/migrations/` — Prisma ORM migrations
- `drizzle/` — Drizzle ORM migration files
- `knex/migrations/`, `sequelize/migrations/`, `typeorm/migrations/` — other ORMs
- `flyway/` — Flyway SQL migrations
- Files matching `migrate*.sql` or `migration*.sql`

### 8c. Merge or leave open

```bash
if [ "$HAS_MIGRATIONS" = true ]; then
    echo "DB migrations detected — leaving PR open for manual review."
    echo "Merge manually when ready: gh pr merge $PR_NUMBER --squash --delete-branch"
else
    # Proceed to create-github-pr for squash-merge (with --skip-db-check since we already checked)
    invoke create-github-pr skill with --skip-db-check
fi
```

### 9. Clean up

After PASS, the `create-github-pr` skill will handle squash-merge (if no DB migrations) and worktree cleanup.
