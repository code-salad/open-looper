#!/bin/bash
set -euo pipefail

# looper-worker.sh - Run looper-worker inside opencode via mngr
# Usage: looper-worker.sh <issue-number> [task-arg]
#
# This script runs opencode in a way that works with mngr's tmux setup.
# Uses opencode serve + attach pattern for headless operation.

ISSUE_NUM="${1:-}"
TASK_ARG="${2:-}"

if [ -z "$ISSUE_NUM" ]; then
    echo "Usage: looper-worker.sh <issue-number> [task-arg]"
    exit 1
fi

# Extract issue number if passed with #
ISSUE_NUM=$(echo "$ISSUE_NUM" | tr -d '#')

# Build the task
if [ -n "$TASK_ARG" ]; then
    TASK="/looper-worker #${ISSUE_NUM} ${TASK_ARG}"
else
    TASK="/looper-worker #${ISSUE_NUM}"
fi

echo "[looper-worker] Starting with task: $TASK"

# Get port - use 4096 as default
PORT="${OPENCODE_PORT:-4096}"

# Start opencode serve in background using nohup + dev null redirection
echo "[looper-worker] Starting opencode server on port $PORT..."
nohup opencode serve --port "$PORT" </dev/null >/tmp/opencode-serve.log 2>&1 &
SERVER_PID=$!

# Wait for server to be ready
echo "[looper-worker] Waiting for server to be ready..."
for i in $(seq 1 30); do
    if curl -s "http://localhost:$PORT/" >/dev/null 2>&1; then
        echo "[looper-worker] Server is ready on port $PORT"
        break
    fi
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "[looper-worker] Server exited prematurely"
        cat /tmp/opencode-serve.log
        exit 1
    fi
    sleep 1
done

# Check if server is actually running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "[looper-worker] Server exited"
    cat /tmp/opencode-serve.log
    exit 1
fi

# Send the task using attach with --continue
echo "[looper-worker] Sending task to opencode..."
opencode run --attach "http://localhost:$PORT" --continue "$TASK" 2>&1

# Capture exit code
EXIT_CODE=$?

# Cleanup
if kill -0 $SERVER_PID 2>/dev/null; then
    echo "[looper-worker] Stopping server..."
    kill $SERVER_PID 2>/dev/null || true
fi

echo "[looper-worker] Done with exit code $EXIT_CODE"
exit $EXIT_CODE