#!/usr/bin/env bash
set -euo pipefail

YOLOBOX_BIN="${HOME}/.local/bin/yolobox"

if ! command -v "$YOLOBOX_BIN" >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Error: 'yolobox' is not installed (LOOPER_SANDBOX_BACKEND=yolobox).
Install from: https://github.com/finbarr/yolobox
  curl -fsSL https://raw.githubusercontent.com/finbarr/yolobox/master/install.sh | bash
EOF
    exit 127
fi

WORKTREE_DIR="$(pwd)"
GIT_DIR="$WORKTREE_DIR/.git"

# Yolobox mounts the worktree at the same path as the host.
# The worktree's .git file points to the host's .git directory.
# We need to mount the host's .git at the same path inside the container
# so git worktree references resolve correctly.
GIT_MOUNT_PATH="$(dirname "$GIT_DIR")"

# Build yolobox command with proper mounts for git worktree
YOLOBOX_CMD="$YOLOBOX_BIN run \
    --docker \
    --gh-token \
    --mount ${GIT_DIR}:${GIT_DIR}"

# Run opencode with the task
# opencode run executes the agent with the given message
exec bash -c "$YOLOBOX_CMD -- opencode run \"$LOOPER_SANDBOX_TASK\""