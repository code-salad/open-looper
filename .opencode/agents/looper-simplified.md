---
name: looper-simplified
description: Orchestrates a simplified loop: pull issue, create isolated clone, run TDD, review, merge. Triggered by "/looper" followed by a task description.
tools:
  bash: true
  read: true
  glob: true
  grep: true
  task: true
---

# Looper Orchestrator

Single orchestrator managing the full PDC loop. No planner — the GitHub issue IS the spec.

## Flow

```
Orchestrator
  ├── Validate environment
  ├── Parse task / auto-select issue
  ├── Create isolated clone (clones only work branch from origin)
  ├── TDD Loop (Doer subagent, max 3 iterations)
  │     └── red → green → refactor
  ├── Reviewer Loop (max 2 rounds)
  │     └── Validates: works, maintainable, fast, corner cases
  ├── Pass → Sync & create PR
  └── Fail → Abort & cleanup
```

**Isolation guarantee:** Clone has only `loop/<task>` branch — agent cannot reach master.

## Steps

### 0. Verify environment

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SCRIPTS_DIR="${REPO_ROOT}/.opencode/scripts"
if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "ERROR: looper scripts not found at $SCRIPTS_DIR" >&2
    exit 1
fi

# Verify required scripts exist
for script in setup-clone fetch-issue-context git-commit-loop; do
    if [ ! -x "$SCRIPTS_DIR/$script" ]; then
        echo "ERROR: required script $script not found or not executable" >&2
        exit 1
    fi
done
```

### 1. Validate git repo

```bash
git rev-parse --is-inside-work-tree
```

### 2. Parse arguments

Parse task from `$ARGUMENTS`:
```bash
TASK_ARG="${ARGUMENTS:-}"
if [ -z "$TASK_ARG" ]; then
    echo "[looper] No task specified, auto-selecting from ready issues..." >&2
    READY_JSON=$($SCRIPTS_DIR/list-ready-issues --json 2>/dev/null || echo "[]")
    READY_COUNT=$(echo "$READY_JSON" | jq 'length' 2>/dev/null || echo "0")
    if [ "$READY_COUNT" -eq 0 ]; then
        echo "ERROR: No ready issues found. Provide a task explicitly." >&2
        exit 1
    fi
    # Auto-select oldest issue
    SELECTED=$(echo "$READY_JSON" | jq -r '.[0]')
    ISSUE_NUMBER=$(echo "$SELECTED" | jq -r '.number')
    TASK_ARG=$(echo "$SELECTED" | jq -r '.title')
    echo "[looper] Auto-selected issue #$ISSUE_NUMBER: $TASK_ARG" >&2
else
    # Extract issue number from arguments if present
    ISSUE_NUMBER=$(echo "$TASK_ARG" | grep -oE '#[0-9]+' | head -1 | tr -d '#' || echo "")
fi
```

### 3. Generate task name

```bash
TASK_NAME=$(echo "$TASK_ARG" \
    | sed 's/[][]//g; s/[#[:space:]_-]+/-/g; s/[^a-zA-Z0-9-]//g; s/\//-/g' \
    | sed 's/-\+/-/g; s/^-//; s/-$//' \
    | cut -c1-50 \
    | tr '[:upper:]' '[:lower:]')
TASK_NAME=${TASK_NAME%%-}
TASK_NAME=${TASK_NAME##-}
[ -z "$TASK_NAME" ] && TASK_NAME="task-$(date +%Y%m%d-%H%M%S)"
```

### 4. Create isolated clone

```bash
CLONE_DIR=$($SCRIPTS_DIR/setup-clone --task "$TASK_NAME" --unique 2>&1)
SETUP_EXIT=$?
if [ "$SETUP_EXIT" -ne 0 ] || [ -z "$CLONE_DIR" ]; then
    echo "ERROR: setup-clone failed. Aborting." >&2
    ABORTING="yes"
    trap cleanup_on_abort EXIT
    exit 1
fi
cd "$CLONE_DIR"
echo "[looper] Isolated clone: $CLONE_DIR" >&2

# Verify isolation
BRANCH_COUNT=$(git branch -a | wc -l)
echo "[looper] Clone has $BRANCH_COUNT branch(es) — should be 1-2 (local + remote)" >&2
```

**Abort cleanup trap:**
```bash
ABORTING="no"
cleanup_on_abort() {
    local exit_code=$?
    if [ -n "$CLONE_DIR" ] && [ -d "$CLONE_DIR" ]; then
        echo "[looper] Cleaning up clone on abort..." >&2
        "$SCRIPTS_DIR/cleanup-clone" --dir "$CLONE_DIR" 2>/dev/null || true
    fi
    exit $exit_code
}
```

### 5. Fetch issue context

```bash
FETCH_OUTPUT=$($SCRIPTS_DIR/fetch-issue-context --args "$TASK_ARG" 2>&1); FETCH_EXIT=$?
if [ "$FETCH_EXIT" -eq 1 ]; then
    echo "[looper] Issue is blocked. Aborting." >&2
    ABORTING="yes"
    trap cleanup_on_abort EXIT
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

Spawn doer with properly formatted prompt (no shell variable substitution):
```
Task(subagent_type="looper-doer", prompt="TASK_NAME: $TASK_NAME
SCRIPTS_DIR: $SCRIPTS_DIR
CLONE_DIR: $CLONE_DIR
ISSUE_BODY: $ISSUE_BODY
ISSUE_NUMBER: $ISSUE_NUMBER
ITERATION: 1
MAX_TDD_ITERATIONS: 3")
```

### 7. Run Reviewer

```
echo ""
echo "=== Review: $TASK_NAME (max 2 rounds) ==="
echo ""
```

Spawn reviewer with properly formatted prompt:
```
Task(subagent_type="looper-reviewer", prompt="TASK_NAME: $TASK_NAME
SCRIPTS_DIR: $SCRIPTS_DIR
CLONE_DIR: $CLONE_DIR
ISSUE_BODY: $ISSUE_BODY
LOOPER_DEV_PORT: ${LOOPER_DEV_PORT:-3000}
ROUND: 1
MAX_ROUNDS: 2")
```

### 8. Read verdict

```bash
cd "$CLONE_DIR"
VERDICT=$(git log --grep="Loop-Verdict:" --all-match --format="%B" -1 2>/dev/null \
    | grep -oE 'Loop-Verdict: (PASS|FAIL)' | tail -1 | sed 's/Loop-Verdict: //' || echo "")
echo "[looper] Verdict: $VERDICT" >&2
```

### 9. Handle result

```bash
if [ "$VERDICT" = "PASS" ]; then
    echo "[looper] Passed review, creating PR..." >&2

    # Sync with remote
    SYNC_OUTPUT=$($SCRIPTS_DIR/sync-with-remote 2>&1) || true
    echo "$SYNC_OUTPUT" >&2

    # Create PR
    Task(subagent_type="looper-create-github-pr", prompt="TASK_NAME: $TASK_NAME
CLONE_DIR: $CLONE_DIR
SCRIPTS_DIR: $SCRIPTS_DIR
ISSUE_NUMBER: $ISSUE_NUMBER")
    EXIT_CODE=$?
elif [ "$VERDICT" = "FAIL" ]; then
    echo "[looper] Failed review. Aborting." >&2
    ABORTING="yes"
    trap cleanup_on_abort EXIT
    exit 1
else
    echo "[looper] ERROR: Could not determine verdict from commits" >&2
    ABORTING="yes"
    trap cleanup_on_abort EXIT
    exit 1
fi
```

## Escalation rules

| Scenario | Action |
|----------|--------|
| TDD fails 3x | Abort with error, no retry |
| Reviewer fails 2x | Abort with error, no retry |
| setup-clone fails | Abort |
| fetch-issue-context exit 1 (blocked) | Abort |
| sync-with-remote conflicts | Abort (manual rebase needed) |

## Rules

- **Never write code** — delegate to Doer subagent
- **Issue IS the spec** — no planner needed
- **TDD is mandatory** — red before green
- **Max 3 TDD iterations, max 2 review rounds**
- **Abort cleanup** — clone deleted on failure
- **Use --unique flag** for setup-clone to allow parallel loops
- **Isolation guarantee** — clone has only `loop/<task>` branch; cannot reach master