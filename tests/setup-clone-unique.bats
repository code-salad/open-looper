#!/usr/bin/env bats
# -*- shell-bats -*-
# This testsuite verifies setup-clone --unique functionality.
# Each test runs in an isolated temp repo so it doesn't pollute the main repo.

load 'helpers.bash'

# --- Test 1: unique flag produces unique paths ---
@test "setup-clone --unique creates unique per-run paths" {
  cd "$FIXTURE_REPO"

  run $SCRIPTS_DIR/setup-clone --task test-unique --unique
  echo "First run status: $status, output: $output"
  [ "$status" -eq 0 ]
  FIRST_PATH=$(echo "$output" | tail -1)

  [[ "$FIRST_PATH" =~ \.clones/test-unique-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$ ]]

  run $SCRIPTS_DIR/setup-clone --task test-unique --unique
  echo "Second run status: $status, output: $output"
  [ "$status" -eq 0 ]
  SECOND_PATH=$(echo "$output" | tail -1)
  echo "Second path: $SECOND_PATH"

  [[ "$SECOND_PATH" =~ \.clones/test-unique-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$ ]]

  [ "$FIRST_PATH" != "$SECOND_PATH" ]
}

# --- Test 2: backward compatibility (no --unique) ---
@test "setup-clone without --unique resumes same path" {
  cd "$FIXTURE_REPO"

  run $SCRIPTS_DIR/setup-clone --task test-resume
  echo "First run status: $status, output: $output"
  [ "$status" -eq 0 ]
  FIRST_PATH=$(echo "$output" | tail -1)
  echo "First path: $FIRST_PATH"

  [ "$FIRST_PATH" == "$FIXTURE_REPO/.clones/test-resume" ]

  run $SCRIPTS_DIR/setup-clone --task test-resume
  echo "Second run status: $status, output: $output"
  [ "$status" -eq 0 ]
  SECOND_PATH=$(echo "$output" | tail -1)
  echo "Second path: $SECOND_PATH"

  [ "$FIRST_PATH" == "$SECOND_PATH" ]
}

# --- Test 3: clone has proper isolation (only one branch) ---
@test "setup-clone --unique creates isolated clone with single branch" {
  cd "$FIXTURE_REPO"

  CLONE_DIR=$($SCRIPTS_DIR/setup-clone --task test-iso --unique | tail -1)
  echo "Clone dir: $CLONE_DIR"

  [ -d "$CLONE_DIR/.git" ]

  BRANCH_COUNT=$(git -C "$CLONE_DIR" branch -a | wc -l)
  echo "Branch count: $BRANCH_COUNT"
  [ "$BRANCH_COUNT" -le 2 ]

  run git -C "$CLONE_DIR" branch --show-current
  echo "Current branch: $output"
  [[ "$output" =~ ^loop/test-iso-[a-f0-9]{8}$ ]]
}

# --- Test 4: uuidgen fallback when uuidgen unavailable ---
@test "setup-clone falls back when uuidgen is missing" {
  cd "$FIXTURE_REPO"

  local ORIGINAL_PATH="$PATH"
  if command -v uuidgen &>/dev/null; then
    local UUIDGEN_PATH=$(command -v uuidgen)
    local UUIDGEN_DIR=$(dirname "$UUIDGEN_PATH")
    export PATH="${PATH//$UUIDGEN_DIR/}"
  fi

  run $SCRIPTS_DIR/setup-clone --task test-fallback --unique
  [ "$status" -eq 0 ]
  echo "Run with restricted PATH: status=$status, output=$output"
  export PATH="$ORIGINAL_PATH"
  [[ "$output" =~ \.clones/test-fallback-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$ ]]
}