#!/bin/bash
set -e

AGENT_ID="${AGENT_ID:-$$}"
WORKTREE_DIR="/tmp/wt-agent-${AGENT_ID}"
PROJECT_PATH="/home/ubuntu/open-looper"
YOLOBOX_BIN="${HOME}/.local/bin/yolobox"

usage() {
    cat <<EOF
Usage: $0 [command]

Commands:
  create <branch-name>   Create worktree and start yolobox with opencode
  shell                 Start yolobox shell in existing worktree
  done                  Remove worktree and cleanup
  status                Show worktree status

Examples:
  AGENT_ID=1 $0 create issue-123
  AGENT_ID=1 $0 shell
  AGENT_ID=1 $0 done
  $0 status
EOF
    exit 1
}

cmd_create() {
    local branch="${1:-agent-$AGENT_ID}"

    echo "=== Creating worktree ==="
    echo "Worktree dir: ${WORKTREE_DIR}"
    echo "Branch: ${branch}"

    # Create worktree (fast! ~17ms)
    cd "$PROJECT_PATH"
    if git worktree list | grep -q "$WORKTREE_DIR"; then
        echo "Worktree already exists, removing first..."
        git worktree remove "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
    fi

    git worktree add "$WORKTREE_DIR" -b "$branch"
    echo "Worktree created!"

    # The worktree's .git file points to the host's .git/worktrees/<name>
    # When yolobox mounts the worktree, we need to mount the host .git dir
    # at /home/ubuntu/open-looper/.git to make git work inside the container
    echo "=== Git file (do not modify) ==="
    cat "$WORKTREE_DIR/.git"

    echo ""
    echo "=== Starting yolobox ==="
    cmd_shell
}

cmd_shell() {
    if [ ! -d "$WORKTREE_DIR" ]; then
        echo "Error: Worktree doesn't exist at ${WORKTREE_DIR}"
        echo "Run '$0 create <branch>' first"
        exit 1
    fi

    # Ensure we're in the worktree directory for yolobox to pick it up
    cd "$WORKTREE_DIR"

    echo "Starting yolobox..."
    echo "Worktree: ${WORKTREE_DIR}"
    echo "Branch: $(git -C "$WORKTREE_DIR" branch --show-current)"
    echo ""

    # Key insight: Mount the host's .git directory at /home/ubuntu/open-looper/.git
    # This makes the git worktree references work inside the container
    # Yolobox automatically mounts the worktree at /home/ubuntu/open-looper
    "$YOLOBOX_BIN" run \
        --docker \
        --gh-token \
        --mount "/home/ubuntu/open-looper/.git:/home/ubuntu/open-looper/.git" \
        -- opencode
}

cmd_done() {
    if [ ! -d "$WORKTREE_DIR" ]; then
        echo "No worktree to remove"
        return
    fi

    echo "=== Cleaning up ==="
    cd "$WORKTREE_DIR"

    if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
        echo "No uncommitted changes"
    else
        echo "Warning: uncommitted changes exist:"
        git status --short
        echo "Remove manually with: rm -rf ${WORKTREE_DIR}"
        return
    fi

    cd "$PROJECT_PATH"
    if git worktree remove "$WORKTREE_DIR" 2>/dev/null; then
        echo "Worktree removed"
    else
        rm -rf "$WORKTREE_DIR"
        echo "Removed manually"
    fi
}

cmd_status() {
    echo "=== Worktree Agent Status ==="
    echo "Agent ID: ${AGENT_ID}"
    echo "Worktree dir: ${WORKTREE_DIR}"
    echo "Exists: $([ -d "$WORKTREE_DIR" ] && echo 'yes' || echo 'no')"
    echo ""

    if [ -d "$WORKTREE_DIR" ]; then
        echo "=== Git Status ==="
        cd "$WORKTREE_DIR" && git status --short 2>/dev/null || echo "Not a git repo"
        echo ""
        echo "=== Branch ==="
        cd "$WORKTREE_DIR" && git branch --show-current 2>/dev/null || echo "N/A"
    fi

    echo ""
    echo "=== All Worktrees ==="
    cd "$PROJECT_PATH" && git worktree list 2>/dev/null || echo "N/A"
}

CMD="${1:-help}"
shift 2>/dev/null || true

case "$CMD" in
    create|shell|done|status)
        "cmd_$CMD" "$@"
        ;;
    *)
        usage
        ;;
esac