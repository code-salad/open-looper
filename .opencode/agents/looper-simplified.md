---
name: looper-simplified
description: Entry point for looper. Fetches ready GitHub issues and dispatches work to sandboxed looper-workers inside yolobox containers. Triggered by "/looper".
tools:
  bash: true
  read: true
  glob: true
  grep: true
  task: true
---

# Looper Simplified

Entry point that dispatches to looper-worker inside yolobox.

**This is the dispatcher.** It handles:
1. Parse task / auto-select issue
2. Claim issue
3. Dispatch to looper-worker inside yolobox

The worker (`looper-worker`) runs in the container and handles the actual TDD loop.

```
/looper "fix parser"  →  looper-simplified (dispatcher)  →  yolobox  →  looper-worker
```

See `looper-dispatcher.md` for detailed flow and `looper-worker.md` for the worker logic.

## Quick Start

```bash
# Single issue
/looper #123

# Task description
/looper fix the parser bug

# Auto-select oldest ready issue
/looper
```

## Dispatcher Steps

### 0. Validate yolobox availability

```bash
YOLOBOX_BIN="$(command -v yolobox 2>/dev/null || echo "")"

if [ -z "$YOLOBOX_BIN" ]; then
    echo "[looper-simplified] yolobox not found. Worker will run on host." >&2
    YOLOBOX_AVAILABLE="no"
elif [ -n "$YOLOBOX" ]; then
    echo "[looper-simplified] Already inside yolobox. Running dispatcher directly." >&2
    YOLOBOX_AVAILABLE="no"  # Don't re-spawn
else
    YOLOBOX_AVAILABLE="yes"
fi
```

### 1. Parse arguments / select issue

```bash
TASK_ARG="${ARGUMENTS:-}"

if [ -z "$TASK_ARG" ]; then
    SCRIPTS_DIR="/home/ubuntu/open-looper/.opencode/scripts"
    echo "[looper-simplified] No task specified, auto-selecting from ready issues..." >&2
    READY_JSON=$("$SCRIPTS_DIR/list-ready-issues" --json 2>/dev/null || echo "[]")
    READY_COUNT=$(echo "$READY_JSON" | jq 'length' 2>/dev/null || echo "0")

    if [ "$READY_COUNT" -eq 0 ]; then
        echo "ERROR: No ready issues found. Provide a task explicitly." >&2
        exit 1
    fi

    SELECTED=$(echo "$READY_JSON" | jq -r '.[0]')
    ISSUE_NUMBER=$(echo "$SELECTED" | jq -r '.number')
    TASK_ARG=$(echo "$SELECTED" | jq -r '.title')
    echo "[looper-simplified] Auto-selected issue #$ISSUE_NUMBER: $TASK_ARG" >&2
else
    ISSUE_NUMBER=$(echo "$TASK_ARG" | grep -oE '#[0-9]+' | head -1 | tr -d '#' || echo "")
fi
```

### 2. Claim issue

```bash
SCRIPTS_DIR="/home/ubuntu/open-looper/.opencode/scripts"

if [ -n "$ISSUE_NUMBER" ]; then
    CLAIM_OUTPUT=$("$SCRIPTS_DIR/claim-issue" --issue "$ISSUE_NUMBER" 2>&1) && CLAIM_EXIT=0 || CLAIM_EXIT=$?
    if [ "$CLAIM_EXIT" -ne 0 ]; then
        echo "[looper-simplified] Issue #$ISSUE_NUMBER already claimed. Aborting." >&2
        exit 1
    fi
    echo "[looper-simplified] Claimed issue #$ISSUE_NUMBER" >&2
fi
```

### 3. Dispatch to worker

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Build worker invocation
if [ -n "$ISSUE_NUMBER" ]; then
    WORKER_TASK="/looper-worker #${ISSUE_NUMBER} ${TASK_ARG}"
else
    WORKER_TASK="/looper-worker ${TASK_ARG}"
fi

echo "[looper-simplified] Dispatching: $WORKER_TASK" >&2

if [ "$YOLOBOX_AVAILABLE" = "yes" ]; then
    echo "[looper-simplified] Spawning worker in yolobox..." >&2
    exec "$YOLOBOX_BIN" run \
        --docker \
        --gh-token \
        --mount "$REPO_ROOT":"$REPO_ROOT" \
        -- \
        opencode run "$WORKER_TASK"
else
    echo "[looper-simplified] Running worker directly..." >&2
    exec opencode run "$WORKER_TASK"
fi
```

## Parallel Dispatch (for multiple issues)

```bash
MAX_PARALLEL=3

READY_JSON=$("$SCRIPTS_DIR/list-ready-issues" --json 2>/dev/null || echo "[]")
COUNT=$(echo "$READY_JSON" | jq 'length' 2>/dev/null || echo "0")

for i in $(seq 0 $((COUNT - 1))); do
    ISSUE_OBJ=$(echo "$READY_JSON" | jq ".[$i]")
    ISSUE_NUM=$(echo "$ISSUE_OBJ" | jq -r '.number')
    ISSUE_TITLE=$(echo "$ISSUE_OBJ" | jq -r '.title')

    # Claim first
    if "$SCRIPTS_DIR/claim-issue" --issue "$ISSUE_NUM" >/dev/null 2>&1; then
        if [ "$YOLOBOX_AVAILABLE" = "yes" ]; then
            "$YOLOBOX_BIN" run --docker --gh-token --mount "$REPO_ROOT":"$REPO_ROOT" -- \
                opencode run "/looper-worker #${ISSUE_NUM} ${ISSUE_TITLE}" &
        else
            opencode run "/looper-worker #${ISSUE_NUM} ${ISSUE_TITLE}" &
        fi
    fi

    # Limit parallelism
    while [ $(jobs -r | wc -l) -ge "$MAX_PARALLEL" ]; do sleep 5; done
done

wait
echo "[looper-simplified] All workers complete."
```

## Rules

- **Dispatcher is entry point** — `/looper` invokes this
- **Worker does the actual work** — never directly invoked by user
- **Claim before dispatch** — prevents concurrent work on same issue
- **Yolobox for isolation** — each worker gets its own container
- **Parallel-safe** — multiple dispatchers can run concurrently on different issues