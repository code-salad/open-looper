---
name: looper-dispatcher
description: Entry point for looper. Fetches ready GitHub issues and dispatches work to sandboxed looper-workers inside yolobox containers. Triggered by "/looper" followed by a task description.
mode: orchestrator
tools:
  bash: true
  read: true
  glob: true
  grep: true
  task: true
---

# Looper Dispatcher

Entry point that fetches ready issues and dispatches work to sandboxed looper-workers.

**Never does the actual TDD work itself** — it only orchestrates spawning workers.

## Flow

```
Dispatcher
  ├── Validate environment & yolobox availability
  ├── Parse task / auto-select from ready issues
  ├── Claim issue (lock for this dispatcher run)
  ├── Spawn looper-worker inside yolobox container
  │     └── Worker handles: clone → TDD → review → PR
  └── Clean up dispatcher-side state, report outcome
```

## Steps

### 0. Validate environment

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SCRIPTS_DIR="${REPO_ROOT}/.opencode/scripts"

# Verify yolobox is available
if ! command -v yolobox >/dev/null 2>&1; then
    echo "ERROR: yolobox not found on PATH. Install from https://github.com/finbarr/yolobox" >&2
    exit 1
fi

# Verify required scripts
for script in list-ready-issues claim-issue; do
    if [ ! -x "$SCRIPTS_DIR/$script" ]; then
        echo "ERROR: required script $script not found or not executable" >&2
        exit 1
    fi
done

git rev-parse --is-inside-work-tree
```

### 1. Parse arguments / select issue

```bash
TASK_ARG="${ARGUMENTS:-}"

if [ -z "$TASK_ARG" ]; then
    echo "[dispatcher] No task specified, auto-selecting from ready issues..." >&2
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
    echo "[dispatcher] Auto-selected issue #$ISSUE_NUMBER: $TASK_ARG" >&2
else
    ISSUE_NUMBER=$(echo "$TASK_ARG" | grep -oE '#[0-9]+' | head -1 | tr -d '#' || echo "")
fi
```

### 2. Claim issue

```bash
if [ -n "$ISSUE_NUMBER" ]; then
    CLAIM_OUTPUT=$("$SCRIPTS_DIR/claim-issue" --issue "$ISSUE_NUMBER" 2>&1) && CLAIM_EXIT=0 || CLAIM_EXIT=$?
    if [ "$CLAIM_EXIT" -ne 0 ]; then
        echo "[dispatcher] Issue #$ISSUE_NUMBER already claimed or unavailable. Aborting." >&2
        echo "$CLAIM_OUTPUT" >&2
        exit 1
    fi
    echo "[dispatcher] Claimed issue #$ISSUE_NUMBER" >&2
fi
```

### 3. Dispatch to worker

```bash
YOLOBOX_BIN="$(command -v yolobox)"

# Build the worker task
if [ -n "$ISSUE_NUMBER" ]; then
    WORKER_TASK="/looper-worker #${ISSUE_NUMBER} ${TASK_ARG}"
else
    WORKER_TASK="/looper-worker ${TASK_ARG}"
fi

echo "[dispatcher] Dispatching worker: $WORKER_TASK" >&2

# Check if yolobox is available
if [ -n "$YOLOBOX" ] || [ ! -x "$YOLOBOX_BIN" ]; then
    # Already inside yolobox OR yolobox not available → run worker directly
    echo "[dispatcher] No yolobox available, running worker directly on host" >&2
    opencode run "$WORKER_TASK"
else
    # Spawn worker inside yolobox container
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    echo "[dispatcher] Spawning worker in yolobox (repo: $REPO_ROOT)" >&2

    exec "$YOLOBOX_BIN" run \
        --docker \
        --gh-token \
        --mount "$REPO_ROOT":"$REPO_ROOT" \
        -- \
        opencode run "$WORKER_TASK"
fi
```

## Scaling to Multiple Parallel Workers

To run multiple issues in parallel:

```bash
# Fetch all ready issues
READY_JSON=$($SCRIPTS_DIR/list-ready-issues --json 2>/dev/null || echo "[]")
COUNT=$(echo "$READY_JSON" | jq 'length' 2>/dev/null || echo "0")

# Spawn up to N parallel workers
MAX_PARALLEL=3
for i in $(seq 0 $((COUNT - 1))); do
    ISSUE_OBJ=$(echo "$READY_JSON" | jq ".[$i]")
    ISSUE_NUM=$(echo "$ISSUE_OBJ" | jq -r '.number')
    ISSUE_TITLE=$(echo "$ISSUE_OBJ" | jq -r '.title')

    # Claim first
    "$SCRIPTS_DIR/claim-issue" --issue "$ISSUE_NUM" >/dev/null 2>&1 && {
        # Spawn in background yolobox
        "$YOLOBOX_BIN" run \
            --docker --gh-token \
            --mount "$REPO_ROOT":"$REPO_ROOT" \
            -- \
            opencode run "/looper-worker #${ISSUE_NUM} ${ISSUE_TITLE}" &
    }

    # Limit parallelism
    while [ $(jobs -r | wc -l) -ge "$MAX_PARALLEL" ]; do
        sleep 5
    done
done

# Wait for all workers
wait
echo "[dispatcher] All workers complete."
```

## Rules

- **Dispatcher is the entry point** — `/looper` invokes this, not looper-worker directly
- **Never does TDD work** — only claims and dispatches
- **One issue per dispatch** — each yolobox container handles one issue
- **Uses `--unique` via worker** — worker calls setup-clone --unique so clones don't conflict
- **Parallel-safe** — multiple dispatchers can run concurrently if they claim different issues