# Plan: add auto-issue-selection path

## Goal

When `/looper` is invoked without arguments, automatically select the oldest ready issue, claim it, and proceed with the PDC loop on that issue.

## Problem

Currently SKILL.md step 1 (Validate argument) asks the user for a task description when no arguments are provided. The expected behavior is to auto-select from ready issues instead.

## Files to create

### 1. `scripts/claim-issue` (new)

A TOCTOU-safe script to claim a GitHub issue before creating a worktree.

**Purpose:** Atomically assign an issue to the current user, handling race conditions via retry logic.

**Usage:** `claim-issue --issue <NUMBER> [--repo owner/repo]`

**Behavior:**
- Exit 0: Successfully claimed (issue assigned to current user)
- Exit 1: Issue could not be claimed (already assigned, blocked, or not found)
- Exit 2: Invalid arguments

**TOCTOU-safe approach:**
1. Use `gh issue edit --assignee @me` which fails if already assigned
2. Retry up to 3 times with 1-second delay on "already assigned" failure
3. Also check issue is still open and unassigned before retrying

```bash
#!/usr/bin/env bash
set -euo pipefail

# claim-issue — TOCTOU-safe issue claim
# Usage: claim-issue --issue <NUMBER> [--repo owner/repo]

ISSUE_NUMBER=""
REPO_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --issue) ISSUE_NUMBER="$2"; shift 2 ;;
        --repo) REPO_ARG="$2"; shift 2 ;;
        *) echo "Usage: claim-issue --issue <NUMBER> [--repo owner/repo]" >&2; exit 2 ;;
    esac
done

if [ -z "$ISSUE_NUMBER" ]; then
    echo "Usage: claim-issue --issue <NUMBER> [--repo owner/repo]" >&2
    echo "Error: --issue is required" >&2
    exit 2
fi

GH_REPO_ARGS=()
if [ -n "$REPO_ARG" ]; then
    GH_REPO_ARGS=("--repo" "$REPO_ARG")
fi

MAX_RETRIES=3
RETRY_DELAY=1

for attempt in $(seq 1 $MAX_RETRIES); do
    # Check current state
    STATE=$(gh issue view "$ISSUE_NUMBER" --json state --jq '.state' "${GH_REPO_ARGS[@]}" 2>/dev/null || echo "NOT_FOUND")
    if [ "$STATE" != "OPEN" ]; then
        echo "Issue #$ISSUE_NUMBER is not open (state: $STATE)" >&2
        exit 1
    fi

    # Try to assign
    if gh issue edit "$ISSUE_NUMBER" --add-assignee "@me" "${GH_REPO_ARGS[@]}" 2>/dev/null; then
        echo "Claimed issue #$ISSUE_NUMBER"
        exit 0
    fi

    if [ "$attempt" -lt "$MAX_RETRIES" ]; then
        sleep "$RETRY_DELAY"
    fi
done

echo "Failed to claim issue #$ISSUE_NUMBER after $MAX_RETRIES attempts (already assigned?)" >&2
exit 1
```

## Files to modify

### 2. `SKILL.md` (line 51-53)

**Change step 1 from:**
```markdown
### 1. Validate argument

If no task description is provided, ask the user for one. Do not proceed without one.
```

**To:**
```markdown
### 1. Validate argument

If no task description is provided, run the auto-issue-selection path (step 1a).
Otherwise, use the provided arguments as the task description.
```

**Add new step 1a after step 1:**
```markdown
### 1a. Auto-issue-selection (when no arguments)

If `$ARGUMENTS` is empty:
1. Run `list-ready-issues --json --limit 30` to get open, unassigned, non-blocked issues.
2. Select the oldest ready issue (first in the sorted list).
3. Run `claim-issue --issue <NUMBER>` to atomically claim it (TOCTOU-safe with retry).
4. If no ready issues found, ask the user for a task description.
5. If claiming fails (issue already assigned), ask the user for a task description.
6. On success, set `ARGUMENTS` to the issue reference (e.g., `#<NUMBER>`) and proceed to step 2.
```

## Implementation approach

1. **Create `claim-issue`** script with retry-based TOCTOU safety
2. **Update `SKILL.md`** step 1 to branch on empty vs non-empty `$ARGUMENTS`:
   - Empty → run auto-selection (step 1a)
   - Non-empty → use as task description (existing behavior)

## Corner cases to handle

1. **No ready issues** → Ask user for task description
2. **Issue already claimed** (race condition) → Retry, then ask user if all retries fail
3. **gh auth not configured** → Should propagate error from list-ready-issues/claim-issue
4. **Network failure** → Retry in claim-issue, propagate on persistent failure

## Testing approach

Write tests for `claim-issue`:
1. Successfully claim an open, unassigned issue
2. Handle "already assigned" failure with retry
3. Reject already-closed issues
4. Invalid issue number handling