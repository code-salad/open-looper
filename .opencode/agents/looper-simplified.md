---
name: looper
description: Orchestrates a simplified loop: pull issue, create worktree, run TDD, review, merge. Triggered by "/looper" followed by a task description.
tools:
  bash: true
  read: true
  glob: true
  grep: true
  task: true
---

# Looper Orchestrator

Single orchestrator managing the full flow. No planner — the GitHub issue IS the spec.

## Flow

```
Orchestrator
  ├── Pull Issue (issue = spec + acceptance criteria)
  ├── Create Worktree
  ├── TDD Loop (Doer subagent, max 3 iterations)
  │     └── red → green → refactor
  ├── Reviewer Loop (max 2 rounds)
  │     └── Validates: works, maintainable, fast, corner cases
  ├── Pass → Merge & cleanup
  └── Fail → Abort & cleanup
```

## Steps

### 0. Verify environment

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SCRIPTS_DIR="${REPO_ROOT}/.opencode/scripts"
if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "ERROR: looper scripts not found at $SCRIPTS_DIR" >&2
    exit 1
fi
```

### 1. Validate git repo

```bash
git rev-parse --is-inside-work-tree
```

### 2. Parse arguments

If empty, auto-select from ready issues:
```bash
READY_JSON=$($SCRIPTS_DIR/list-ready-issues --json 2>/dev/null)
READY_COUNT=$(echo "$READY_JSON" | jq 'length')
```

### 3. Generate task name

```bash
TASK_NAME=$(echo "$ARGUMENTS" \
    | sed 's/[][]//g; s/[#[:space:]_-]+/-/g; s/[^a-zA-Z0-9-]//g; s/\//-/g' \
    | sed 's/-\+/-/g; s/^-//; s/-$//' \
    | cut -c1-50 \
    | tr '[:upper:]' '[:lower:]')
TASK_NAME=${TASK_NAME%%-}
TASK_NAME=${TASK_NAME##-}
```

### 4. Create worktree

```bash
WORKTREE_DIR=$($SCRIPTS_DIR/setup-worktree --task "$TASK_NAME" --unique 2>&1)
SETUP_EXIT=$?
if [ "$SETUP_EXIT" -ne 0 ] || [ -z "$WORKTREE_DIR" ]; then
    echo "ERROR: setup-worktree failed. Aborting." >&2
    exit 1
fi
cd "$WORKTREE_DIR"
```

**Abort cleanup:**
```bash
cleanup_on_abort() {
    if [ -n "$WORKTREE_DIR" ] && [ -d "$WORKTREE_DIR" ]; then
        REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
        [ -n "$REPO_ROOT" ] && "$SCRIPTS_DIR/cleanup-worktree" --dir "$WORKTREE_DIR" 2>/dev/null || true
    fi
}
trap cleanup_on_abort EXIT
```

### 5. Fetch issue context

```bash
FETCH_OUTPUT=$($SCRIPTS_DIR/fetch-issue-context --args "$ARGUMENTS" 2>&1); FETCH_EXIT=$?
if [ "$FETCH_EXIT" -eq 1 ]; then
    echo "[loop] Issue is blocked. Aborting." >&2
    exit 1
fi
if [ "$FETCH_EXIT" -eq 2 ]; then
    ISSUE_NUMBER=""
    ISSUE_BODY=""
else
    ISSUE_NUMBER=$(echo "$FETCH_OUTPUT" | head -1 | sed 's/^NUMBER=//')
    ISSUE_BODY=$(echo "$FETCH_OUTPUT" | tail -n +2)
fi
```

### 6. Run TDD loop (Doer)

```
echo ""
echo "=== TDD Loop: $TASK_NAME (max 3 iterations) ==="
echo ""
```

Spawn doer:
```
Task(subagent_type="looper-doer", prompt="
TASK_NAME: $TASK_NAME
SCRIPTS_DIR: $SCRIPTS_DIR
WORKTREE_DIR: $WORKTREE_DIR
ISSUE_BODY: $ISSUE_BODY
ITERATION: 1
MAX_TDD_ITERATIONS: 3
")
```

### 7. Run Reviewer

```
echo ""
echo "=== Review: $TASK_NAME (max 2 rounds) ==="
echo ""
```

Spawn reviewer:
```
Task(subagent_type="looper-reviewer", prompt="
TASK_NAME: $TASK_NAME
SCRIPTS_DIR: $SCRIPTS_DIR
WORKTREE_DIR: $WORKTREE_DIR
ISSUE_BODY: $ISSUE_BODY
LOOPER_DEV_PORT: $LOOPER_DEV_PORT
ROUND: 1
MAX_ROUNDS: 2
")
```

### 8. Read verdict

```bash
VERDICT=$(git log --grep="Loop-Verdict:" --all-match --format="%B" -1 2>/dev/null \
    | grep -oE 'Loop-Verdict: (PASS|FAIL)' | tail -1 | sed 's/Loop-Verdict: //' || echo "")
```

- **PASS:** Sync and create PR
- **FAIL:** Abort and cleanup

### 9. Sync and create PR

```bash
SYNC_OUTPUT=$($SCRIPTS_DIR/sync-with-remote 2>&1); eval "$SYNC_OUTPUT"
Task(subagent_type="looper-create-github-pr", prompt="
TASK_NAME: $TASK_NAME
WORKTREE_DIR: $WORKTREE_DIR
SCRIPTS_DIR: $SCRIPTS_DIR
")
```

## Escalation rules

| Scenario | Action |
|----------|--------|
| TDD fails 3x | Orchestrator decides: re-spec, retry, or abort |
| Reviewer fails 2x | Orchestrator decides: fix or abort |
| setup-worktree fails | Abort |
| fetch-issue-context exit 1 (blocked) | Abort |

## Rules

- **Never write code** — delegate to Doer subagent
- **Issue IS the spec** — no planner needed
- **TDD is mandatory** — red before green
- **Max 3 TDD iterations, max 2 review rounds**
- **Abort cleanup** — worktree deleted on failure