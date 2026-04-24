# Plan: claim-issue TOCTOU-safe script

## Goal
Implement `claim-issue` in `.opencode/skills/looper/scripts/claim-issue` — a script that atomically claims a GitHub issue using a lock-file + `gh` API pattern to avoid TOCTOU races.

## Script Contract
```bash
claim-issue --issue N [--repo owner/repo]
# Exit 0: claimed successfully (prints NUMBER=N to stdout)
# Exit 1: already taken or blocked (prints reason to stderr)
# Exit 2: usage error
```

## Tech Stack Constraints
- Bash with `set -euo pipefail`
- `gh` CLI for all GitHub API calls
- `flock` for atomic locking (available on Linux)
- Follows existing script conventions (argument parsing, exit codes, repo args pattern)

## Implementation

### Step 1 — Acquire lock
Use an exclusive flock on `$LOCK_DIR/claim-issue-<owner>-<repo>-<issue>.lock` (default `$LOCK_DIR=/tmp`). The lock times out after 10 seconds to avoid indefinite blocking.

### Step 2 — Check assignees via `gh issue view --json assignees`
- If the issue does not exist → exit 1 with "Issue #N not found"
- If assigned to someone else → exit 1 with "Issue #N is already assigned to @<login>"
- If assigned to the current user → exit 0 with "Already claimed" (idempotent)
- If unassigned → proceed to step 3

### Step 3 — Assign via `gh issue edit`
Use `gh issue edit N --add-assignee @me` (or `--add-assignee $GITHUB_USER` if the user is explicitly passed). On success, print `NUMBER=N` and exit 0.

If the edit fails (race, permission, etc.) → exit 1 with the error message from `gh`.

## Tests

### Test file: `tests/claim-issue.bats`

```bats
#!/usr/bin/env bats

load helpers

@test "exit 2 when --issue is missing" {
  run bash -c "$SCRIPT_DIR/claim-issue"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "exit 2 when --issue is missing a value" {
  run bash -c "$SCRIPT_DIR/claim-issue --issue"
  [ "$status" -eq 2 ]
}

@test "exit 2 for unknown flag" {
  run bash -c "$SCRIPT_DIR/claim-issue --xyz 123"
  [ "$status" -eq 2 ]
}

@test "exit 1 when issue does not exist" {
  run bash -c "GITHUB_TOKEN=test GITHUB_USER=testuser $SCRIPT_DIR/claim-issue --issue 99999999 --repo owner/nonexistent 2>&1"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "not found"
}

@test "exit 1 when already assigned to another user" {
  # Mock gh issue view to return another assignee
  ...
}
```

Note: Full bats test suite requires mocking `gh` — see `tests/README.md` for approach.

### Corner cases to test (manual / integration)
1. **Already claimed by current user** → `NUMBER=N`, exit 0 (idempotent success)
2. **Already claimed by another user** → exit 1, reason to stderr
3. **Issue does not exist** → exit 1, "not found"
4. **No `--repo` passed** → defaults to current repo via `gh repo view`
5. **Lock contention** → flock times out after 10s, exit 1 "could not acquire lock"
6. **Race: issue claimed between lock-acquire and edit** → `gh issue edit` fails, exit 1
7. **Valid claim** → `NUMBER=N` on stdout, exit 0

## Files to create/modify

| File | Action |
|------|--------|
| `.opencode/skills/looper/scripts/claim-issue` | Create — the main script |
| `tests/claim-issue.bats` | Create — bats test suite |

## Acceptance Criteria
1. Script is executable and passes `shellcheck`
2. `claim-issue --issue N` returns `NUMBER=N` on stdout with exit 0 when unassigned
3. `claim-issue --issue N` returns exit 1 with stderr reason when assigned to another user
4. `claim-issue --issue N` returns exit 1 with stderr reason when issue doesn't exist
5. `claim-issue` (no args) returns exit 2
6. Idempotent: claiming an already-claimed-by-self issue returns exit 0 (no-op)
7. TOCTOU-safe: concurrent claim attempts are serialized via flock
8. Tests pass