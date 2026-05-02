---
name: looper-dispatcher
description: Entry point for looper. Fetches ready GitHub issues and dispatches work to sandboxed looper-workers inside isolated mngr containers. Triggered by "/looper" followed by a task description.
mode: primary
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
  ├── Validate environment & mngr availability
  ├── Parse task / auto-select from ready issues
  ├── Claim issue (lock for this dispatcher run)
  ├── Spawn looper-worker inside mngr container
  │     └── Worker handles: clone → TDD → review → PR
  └── Clean up dispatcher-side state, report outcome
```

## Steps

### 0. Validate environment

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SCRIPTS_DIR="${REPO_ROOT}/.opencode/scripts"

# Verify mngr is available (used to spawn isolated worker containers)
if ! command -v mngr >/dev/null 2>&1; then
    echo "ERROR: mngr not found on PATH. Install from https://github.com/imbue-ai/mngr" >&2
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

### 3. Dispatch to worker via mngr

```bash
MNGR_BIN="$(command -v mngr)"

# Build the worker task
if [ -n "$ISSUE_NUMBER" ]; then
    WORKER_TASK="/looper-worker #${ISSUE_NUMBER} ${TASK_ARG}"
else
    WORKER_TASK="/looper-worker ${TASK_ARG}"
fi

echo "[dispatcher] Dispatching worker: $WORKER_TASK" >&2

# Spawn worker in isolated mngr container
# This gives each worker its own Docker container with its own filesystem
WORKER_NAME="looper-worker-${ISSUE_NUMBER:-$$}-$(date +%s)"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

echo "[dispatcher] Spawning worker in mngr container: $WORKER_NAME" >&2

# Run worker via mngr create - this creates a separate container with streaming output
# The --no-ensure-clean allows uncommitted changes (from claim) to be passed through
"$MNGR_BIN" create "$WORKER_NAME" \
    --provider docker \
    --new-host \
    --no-connect \
    -b "$REPO_ROOT" \
    --no-ensure-clean \
    -- \
    opencode serve --port 4096 &
SERV_PID=$!

# Wait for server to be ready
sleep 8

# Send task to worker
echo "[dispatcher] Sending task to worker..." >&2
opencode run --attach "http://localhost:4096" --continue "$WORKER_TASK" 2>&1

# Capture exit code
EXIT_CODE=$?

# Cleanup server
kill $SERV_PID 2>/dev/null || true

echo "[dispatcher] Worker completed with exit code $EXIT_CODE" >&2
exit $EXIT_CODE
```

## Scaling to Multiple Parallel Workers

To run multiple issues in parallel:

```bash
# Fetch all ready issues
READY_JSON=$($SCRIPTS_DIR/list-ready-issues --json 2>/dev/null || echo "[]")
COUNT=$(echo "$READY_JSON" | jq 'length' 2>/dev/null || echo "0")

# Spawn up to N parallel workers via mngr
MAX_PARALLEL=3
for i in $(seq 0 $((COUNT - 1))); do
    ISSUE_OBJ=$(echo "$READY_JSON" | jq ".[$i]")
    ISSUE_NUM=$(echo "$ISSUE_OBJ" | jq -r '.number')
    ISSUE_TITLE=$(echo "$ISSUE_OBJ" | jq -r '.title')

    # Claim first
    if "$SCRIPTS_DIR/claim-issue" --issue "$ISSUE_NUM" >/dev/null 2>&1; then
        WORKER_NAME="looper-worker-${ISSUE_NUM}-$(date +%s)"

        # Spawn in background mngr container
        "$MNGR_BIN" create "$WORKER_NAME" \
            --provider docker \
            --new-host \
            --no-connect \
            -b "$REPO_ROOT" \
            --no-ensure-clean \
            -- \
            opencode serve --port 4096 &
        SERV_PID=$!

        sleep 8

        # Send task
        opencode run --attach "http://localhost:4096" --continue "/looper-worker #${ISSUE_NUM} ${ISSUE_TITLE}" &

        # Limit parallelism
        while [ $(jobs -r | wc -l) -ge "$MAX_PARALLEL" ]; do
            sleep 5
        done
    fi
done

# Wait for all workers
wait
echo "[dispatcher] All workers complete."
```

## Rules

- **Dispatcher is the entry point** — `/looper` invokes this, not looper-worker directly
- **Never does TDD work** — only claims and dispatches
- **One issue per dispatch** — each mngr container handles one issue
- **Uses `--unique` via worker** — worker calls setup-clone --unique so clones don't conflict
- **Parallel-safe** — multiple dispatchers can run concurrently on different issues
- **Isolation via mngr** — each worker gets its own Docker container (separate filesystem, process space)