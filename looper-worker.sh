#!/bin/bash
set -euo pipefail

# looper-worker.sh - Run looper-worker inside opencode
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

# Start opencode serve in background
echo "[looper-worker] Starting opencode server..."
opencode serve &
SERVER_PID=$!

# Wait for server to be ready
sleep 3

# Get server port
PORT=$(opencode debug port 2>/dev/null || echo "4096")

echo "[looper-worker] Server started on port $PORT"

# Send the task
echo "[looper-worker] Sending task to opencode..."
echo "$TASK" | opencode attach http://localhost:$PORT

# Wait for completion (with timeout)
TIMEOUT=600
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "[looper-worker] Server exited"
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    echo "[looper-worker] Still running... (${ELAPSED}s)"
done

# Cleanup
if kill -0 $SERVER_PID 2>/dev/null; then
    echo "[looper-worker] Stopping server..."
    kill $SERVER_PID 2>/dev/null || true
fi

echo "[looper-worker] Done"