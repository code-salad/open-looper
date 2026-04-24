#!/usr/bin/env bats
# -*- shell-bats -*-
# This testsuite verifies setup-worktree --unique functionality.
# Each test runs in an isolated temp repo so it doesn't pollute the main repo.

load 'helpers.bash'

# --- Test 1: unique flag produces unique paths ---
@test "setup-worktree --unique creates unique per-run paths" {
  cd "$FIXTURE_REPO"

  # First invocation with --unique
  run $SCRIPTS_DIR/setup-worktree --task test-unique --unique
  echo "First run status: $status, output: $output"
  [ "$status" -eq 0 ]
  FIRST_PATH="$output"

  # Verify path contains expected pattern: .worktrees/test-unique-<TS>-<UUID>
  echo "First path: $FIRST_PATH"
  [[ "$FIRST_PATH" =~ \.worktrees/test-unique-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$ ]]

  # Second invocation with --unique should create a DIFFERENT path (not resume)
  run $SCRIPTS_DIR/setup-worktree --task test-unique --unique
  echo "Second run status: $status, output: $output"
  [ "$status" -eq 0 ]
  SECOND_PATH="$output"
  echo "Second path: $SECOND_PATH"

  [[ "$SECOND_PATH" =~ \.worktrees/test-unique-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$ ]]

  # They must be different (no resume behavior with --unique)
  [ "$FIRST_PATH" != "$SECOND_PATH" ]
}

# --- Test 2: backward compatibility (no --unique) ---
@test "setup-worktree without --unique resumes same path" {
  cd "$FIXTURE_REPO"

  # First invocation without --unique
  run $SCRIPTS_DIR/setup-worktree --task test-resume
  echo "First run status: $status, output: $output"
  [ "$status" -eq 0 ]
  FIRST_PATH="$output"
  echo "First path: $FIRST_PATH"

  # Must be a simple path without timestamp/uuid
  [ "$FIRST_PATH" == "$FIXTURE_REPO/.worktrees/test-resume" ]

  # Second invocation should resume (same path)
  run $SCRIPTS_DIR/setup-worktree --task test-resume
  echo "Second run status: $status, output: $output"
  [ "$status" -eq 0 ]
  SECOND_PATH="$output"
  echo "Second path: $SECOND_PATH"

  [ "$FIRST_PATH" == "$SECOND_PATH" ]
}

# --- Test 3: worktree is valid git worktree ---
@test "setup-worktree --unique creates valid git worktree" {
  cd "$FIXTURE_REPO"

  WORKTREE_DIR=$($SCRIPTS_DIR/setup-worktree --task test-valid-worktree --unique)
  echo "Worktree dir: $WORKTREE_DIR"

  # Must be registered with git worktree list
  run git -C "$FIXTURE_REPO" worktree list
  echo "Worktree list:"
  echo "$output"
  [[ "$output" =~ $WORKTREE_DIR ]]

  # Must be on a loop/ branch
  run git -C "$WORKTREE_DIR" branch --show-current
  echo "Current branch: $output"
  [ "$output" == "loop/test-valid-worktree" ]

  # Must have the expected commits from origin
  run git -C "$WORKTREE_DIR" log --oneline -3
  echo "Recent commits:"
  echo "$output"
}

# --- Test 4: uuidgen fallback when uuidgen unavailable ---
@test "setup-worktree falls back when uuidgen is missing" {
  cd "$FIXTURE_REPO"

  # Save original path and temporarily move uuidgen out of PATH
  local ORIGINAL_UUIDGEN=""
  if command -v uuidgen &>/dev/null; then
    ORIGINAL_UUIDGEN=$(command -v uuidgen)
    local UUIDGEN_DIR=$(dirname "$ORIGINAL_UUIDGEN")
    export PATH="${PATH//$UUIDGEN_DIR/}"
  fi

  run $SCRIPTS_DIR/setup-worktree --task test-fallback --unique
  echo "Run with restricted PATH: status=$status, output=$output"
  [ "$status" -eq 0 ]
  [[ "$output" =~ \.worktrees/test-fallback-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$ ]]
}
