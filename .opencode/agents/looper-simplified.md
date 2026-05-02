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
  ├── Claim issue (prevent concurrent work)
  ├── Create isolated clone (clones only work branch from origin)
  ├── TDD Loop (Doer subagent, max 3 iterations)
  │     └── red → green → refactor
  │     └── On reviewer FAIL: re-run Doer for next iteration
  ├── Reviewer Loop (max 2 rounds)
  │     └── Validates: works, maintainable, fast, corner cases
  │     └── Round 1 FAIL → back to Doer (iteration 2)
  │     └── Round 2 FAIL → abort
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
for script in setup-clone fetch-issue-context git-commit-loop cleanup-clone claim-issue; do
    if [ ! -x "$SCRIPTS_DIR/$script" ]; then
        echo "ERROR: required script $script not found or not executable" >&2
        exit 1
    fi
done

# Verify git repo
git rev-parse --is-inside-work-tree
```

### 1. Parse arguments

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

### 2. Generate task name

```bash
TASK_NAME=$(echo "$TASK_ARG" \
    | sed 's/[][]//g; s/[#[:space:]_-]+/-/g; s/[^a-zA-Z0-9-]//g; s/\//-/g' \
    | sed 's/-\+/-/g; s/^-//; s/-$//' \
    | cut -c1-50 \
    | tr '[:upper:]' '[:lower:]')
TASK_NAME=${TASK_NAME%%-}
TASK_NAME=${TASK_NAME##-}
[ -z "$TASK_NAME" ] && TASK_NAME="task-$(date +%Y%m%d-%H%M%S)"
echo "[looper] Task name: $TASK_NAME" >&2
```

### 3. Claim issue (prevent concurrent work)

If we have an issue number, claim it before any work:
```bash
if [ -n "$ISSUE_NUMBER" ]; then
    CLAIM_OUTPUT=$("$SCRIPTS_DIR/claim-issue" --issue "$ISSUE_NUMBER" 2>&1) && CLAIM_EXIT=0 || CLAIM_EXIT=$?
    if [ "$CLAIM_EXIT" -ne 0 ]; then
        echo "[looper] Issue #$ISSUE_NUMBER already claimed or unavailable. Aborting." >&2
        echo "$CLAIM_OUTPUT" >&2
        exit 1
    fi
    echo "[looper] Claimed issue #$ISSUE_NUMBER" >&2
fi
```

### 4. Create isolated clone

```bash
CLONE_DIR=$($SCRIPTS_DIR/setup-clone --task "$TASK_NAME" --unique 2>&1)
SETUP_EXIT=$?
if [ "$SETUP_EXIT" -ne 0 ] || [ -z "$CLONE_DIR" ]; then
    echo "ERROR: setup-clone failed. Aborting." >&2
    exit 1
fi
echo "[looper] Isolated clone: $CLONE_DIR" >&2

# Verify isolation — clone should have only 1-2 branches (local + remote)
BRANCH_COUNT=$(git -C "$CLONE_DIR" branch -a 2>/dev/null | wc -l)
echo "[looper] Clone has $BRANCH_COUNT branch(es) — should be 1-2 (isolated)" >&2
if [ "$BRANCH_COUNT" -gt 5 ]; then
    echo "WARNING: Clone has many branches — isolation may be compromised" >&2
fi
```

### 5. Fetch issue context

```bash
FETCH_OUTPUT=$($SCRIPTS_DIR/fetch-issue-context --args "$TASK_ARG" 2>&1); FETCH_EXIT=$?
if [ "$FETCH_EXIT" -eq 1 ]; then
    echo "[looper] Issue is blocked. Aborting." >&2
    exit 1
fi
if [ "$FETCH_EXIT" -eq 2 ]; then
    ISSUE_NUMBER=""
    ISSUE_BODY=""
else
    ISSUE_NUMBER=$(echo "$FETCH_OUTPUT" | head -1 | sed 's/^NUMBER=//')
    ISSUE_BODY=$(echo "$FETCH_OUTPUT" | tail -n +2)
fi
echo "[looper] Working on issue #$ISSUE_NUMBER" >&2
```

### 6. TDD Loop (Doer — max 3 iterations)

```
echo ""
echo "=== TDD Loop: $TASK_NAME (max 3 iterations) ==="
echo ""
```

Spawn doer with iteration counter. Capture exit code:
```bash
ITERATION=1
MAX_TDD_ITERATIONS=3

DOER_RESULT=""

while [ "$ITERATION" -le "$MAX_TDD_ITERATIONS" ]; do
    echo "[looper] TDD iteration $ITERATION/$MAX_TDD_ITERATIONS" >&2

    DOER_OUTPUT=$(Task(subagent_type="looper-doer", prompt="TASK_NAME: $TASK_NAME
SCRIPTS_DIR: $SCRIPTS_DIR
CLONE_DIR: $CLONE_DIR
ISSUE_BODY: $ISSUE_BODY
ISSUE_NUMBER: $ISSUE_NUMBER
ITERATION: $ITERATION
MAX_TDD_ITERATIONS: $MAX_TDD_ITERATIONS") 2>&1) && DOER_EXIT=0 || DOER_EXIT=$?

    echo "$DOER_OUTPUT" >&2

    if [ "$DOER_EXIT" -ne 0 ]; then
        echo "[looper] Doer failed (exit $DOER_EXIT) on iteration $ITERATION. Aborting." >&2
        ABORTING="yes"
        trap cleanup_on_abort EXIT
        exit 1
    fi

    # Check for escalation signal from doer
    if echo "$DOER_OUTPUT" | grep -q "ESCALATE:"; then
        echo "[looper] Doer escalated. Aborting loop." >&2
        ABORTING="yes"
        trap cleanup_on_abort EXIT
        exit 1
    fi

    DOER_RESULT="done"
    ITERATION=$((ITERATION + 1))
done
```

**Escalation rules:**
- Doer exits non-zero → abort
- Doer emits `ESCALATE:` → abort
- After 3 iterations with no reviewer PASS → abort

### 7. Reviewer Loop (max 2 rounds)

```
echo ""
echo "=== Review: $TASK_NAME (max 2 rounds) ==="
echo ""
```

```bash
ROUND=1
MAX_ROUNDS=2
REVIEW_VERDICT=""

while [ "$ROUND" -le "$MAX_ROUNDS" ]; do
    echo "[looper] Review round $ROUND/$MAX_ROUNDS" >&2

    REVIEW_OUTPUT=$(Task(subagent_type="looper-reviewer", prompt="TASK_NAME: $TASK_NAME
SCRIPTS_DIR: $SCRIPTS_DIR
CLONE_DIR: $CLONE_DIR
ISSUE_BODY: $ISSUE_BODY
LOOPER_DEV_PORT: ${LOOPER_DEV_PORT:-3000}
ROUND: $ROUND
MAX_ROUNDS: $MAX_ROUNDS") 2>&1) && REVIEW_EXIT=0 || REVIEW_EXIT=$?

    echo "$REVIEW_OUTPUT" >&2

    # Read verdict from reviewer commit (written via git-commit-loop with --verdict)
    cd "$CLONE_DIR"
    VERDICT=$(git log --grep="Loop-Verdict:" --format="%B" -1 2>/dev/null \
        | grep -oE 'Loop-Verdict: (PASS|FAIL)' | tail -1 | sed 's/Loop-Verdict: //' || echo "")

    echo "[looper] Round $ROUND verdict: $VERDICT" >&2

    if [ "$VERDICT" = "PASS" ]; then
        REVIEW_VERDICT="PASS"
        break
    fi

    if [ "$VERDICT" = "FAIL" ]; then
        if [ "$ROUND" -eq "$MAX_ROUNDS" ]; then
            echo "[looper] Review failed on round $ROUND/$MAX_ROUNDS. Aborting." >&2
            ABORTING="yes"
            trap cleanup_on_abort EXIT
            exit 1
        fi

        # Round 1 FAIL → run another TDD iteration then review again
        echo "[looper] Review FAIL on round $ROUND. Re-running Doer for iteration $((ITERATION))..." >&2

        # Run doer for next iteration
        DOER_OUTPUT=$(Task(subagent_type="looper-doer", prompt="TASK_NAME: $TASK_NAME
SCRIPTS_DIR: $SCRIPTS_DIR
CLONE_DIR: $CLONE_DIR
ISSUE_BODY: $ISSUE_BODY
ISSUE_NUMBER: $ISSUE_NUMBER
ITERATION: $ITERATION
MAX_TDD_ITERATIONS: $MAX_TDD_ITERATIONS") 2>&1) && DOER_EXIT=0 || DOER_EXIT=$?

        echo "$DOER_OUTPUT" >&2

        if [ "$DOER_EXIT" -ne 0 ]; then
            echo "[looper] Doer failed on re-run. Aborting." >&2
            ABORTING="yes"
            trap cleanup_on_abort EXIT
            exit 1
        fi

        ITERATION=$((ITERATION + 1))
        if [ "$ITERATION" -gt "$MAX_TDD_ITERATIONS" ]; then
            echo "[looper] Max TDD iterations reached during reviewer retry. Aborting." >&2
            ABORTING="yes"
            trap cleanup_on_abort EXIT
            exit 1
        fi

        ROUND=$((ROUND + 1))
        continue
    fi

    # Could not read verdict
    echo "[looper] ERROR: Could not determine verdict from reviewer. Aborting." >&2
    ABORTING="yes"
    trap cleanup_on_abort EXIT
    exit 1
done
```

### 8. Sync and create PR

```bash
echo "[looper] Review PASSED. Syncing with remote..." >&2

# Sync with remote (may abort if conflicts)
SYNC_OUTPUT=$($SCRIPTS_DIR/sync-with-remote 2>&1); SYNC_EXIT=$?
echo "$SYNC_OUTPUT" >&2

if [ "$SYNC_EXIT" -ne 0 ]; then
    echo "[looper] Sync failed (exit $SYNC_EXIT). Resolve conflicts manually." >&2
    exit 1
fi

# Create PR
echo "[looper] Creating PR..." >&2
Task(subagent_type="looper-create-github-pr", prompt="TASK_NAME: $TASK_NAME
CLONE_DIR: $CLONE_DIR
SCRIPTS_DIR: $SCRIPTS_DIR
ISSUE_NUMBER: $ISSUE_NUMBER")
EXIT_CODE=$?

echo "[looper] PR creation complete (exit $EXIT_CODE)" >&2
exit $EXIT_CODE
```

---

## Abort Cleanup

**Declare before any early exit can reference it:**

```bash
ABORTING="no"
cleanup_on_abort() {
    local exit_code=$?
    if [ "$ABORTING" = "yes" ] && [ -n "$CLONE_DIR" ] && [ -d "$CLONE_DIR" ]; then
        echo "[looper] Cleaning up clone on abort..." >&2
        "$SCRIPTS_DIR/cleanup-clone" --dir "$CLONE_DIR" 2>/dev/null || true
    fi
    exit $exit_code
}
trap cleanup_on_abort EXIT
```

Place this immediately after step 1 (argument parsing), before any operation that could abort.

---

## Escalation rules

| Scenario | Action |
|----------|--------|
| No ready issues, no task arg | Exit 1 with error |
| setup-clone fails | Abort, cleanup |
| fetch-issue-context exit 1 (blocked) | Abort |
| claim-issue fails | Abort |
| Doer exits non-zero | Abort |
| Doer emits ESCALATE | Abort |
| Max TDD iterations exceeded | Abort |
| Reviewer round 1 FAIL | Run Doer again, then reviewer round 2 |
| Reviewer round 2 FAIL | Abort |
| sync-with-remote conflicts | Abort (manual rebase needed) |

---

## Rules

- **Never write code** — delegate to Doer subagent
- **Issue IS the spec** — no planner needed
- **TDD is mandatory** — red before green
- **Claim before clone** — prevents concurrent work on same issue
- **Max 3 TDD iterations, max 2 review rounds**
- **Abort cleanup** — clone deleted on failure
- **Use --unique flag** for setup-clone to allow parallel loops
- **Isolation guarantee** — clone has only `loop/<task>` branch; cannot reach master
- **Capture every subagent exit code** — never ignore failures