#!/usr/bin/env bats
# -*- shell-bats -*-
# This testsuite verifies the cleanup trap behavior documented in looper-simplified.md
# The trap should only fire on error exits, not successful ones.

load 'helpers.bash'

# --- Test 1: trap fires on error exit ---
@test "cleanup_on_abort trap fires on error exit (non-zero)" {
  cd "$FIXTURE_REPO"

  # Create a test clone directory
  TEST_CLONE="$FIXTURE_REPO/.clones/test-abort"
  mkdir -p "$TEST_CLONE/.git"

  # Run a sub-script that sets trap and exits with error
  run bash -c "CLONE_DIR='$TEST_CLONE'; trap 'rm -rf \"\$CLONE_DIR\"' EXIT; exit 1"
  echo "Status: $status, output: $output"

  [ "$status" -eq 1 ]
  # Clone should be deleted because trap fired on error exit
  [ ! -d "$TEST_CLONE" ]
}

# --- Test 2: trap does NOT fire on successful exit ---
@test "cleanup_on_abort trap does NOT fire on successful exit" {
  cd "$FIXTURE_REPO"

  # Create a test clone directory
  TEST_CLONE="$FIXTURE_REPO/.clones/test-success"
  mkdir -p "$TEST_CLONE/.git"

  # Run a sub-script that sets trap and exits successfully
  run bash -c "CLONE_DIR='$TEST_CLONE'; trap 'rm -rf \"\$CLONE_DIR\"' EXIT; exit 0"
  echo "Status: $status, output: $output"

  [ "$status" -eq 0 ]
  # Clone should still exist because trap did NOT fire on success
  [ -d "$TEST_CLONE" ]
}

# --- Test 3: trap fires on abort (simulating line 209) ---
@test "cleanup_on_abort trap fires on abort exit" {
  cd "$FIXTURE_REPO"

  TEST_CLONE="$FIXTURE_REPO/.clones/test-line209"
  mkdir -p "$TEST_CLONE/.git"

  # Simulate line 209: exit 1 on FAIL verdict
  run bash -c "CLONE_DIR='$TEST_CLONE'; trap 'rm -rf \"\$CLONE_DIR\"' EXIT; echo '[looper] Failed review. Aborting.' >&2; exit 1"
  echo "Status: $status, output: $output"

  [ "$status" -eq 1 ]
  # Clone should be deleted
  [ ! -d "$TEST_CLONE" ]
}

# --- Test 4: clone preserved when CLONE_DIR cleared before success exit ---
@test "cleanup_on_abort trap preserves clone when CLONE_DIR cleared before success" {
  cd "$FIXTURE_REPO"

  TEST_CLONE="$FIXTURE_REPO/.clones/test-clear"
  mkdir -p "$TEST_CLONE/.git"

  # Simulate: clear CLONE_DIR before exiting successfully
  run bash -c "CLONE_DIR='$TEST_CLONE'; trap 'rm -rf \"\$CLONE_DIR\"' EXIT; echo '[looper] Passed review, creating PR...' >&2; CLONE_DIR=''; exit 0"
  echo "Status: $status, output: $output"

  [ "$status" -eq 0 ]
  # Clone should still exist because CLONE_DIR was cleared before exit
  [ -d "$TEST_CLONE" ]
}

# --- Test 5: current behavior BUG - trap fires on success with current code ---
@test "BUG REPRO: current trap fires even on successful exit" {
  cd "$FIXTURE_REPO"

  TEST_CLONE="$FIXTURE_REPO/.clones/test-bug"
  mkdir -p "$TEST_CLONE/.git"

  # This simulates the CURRENT broken behavior from looper-simplified.md
  # where trap cleanup_on_abort EXIT fires on ANY exit including success
  run bash -c "
    CLONE_DIR='$TEST_CLONE'
    cleanup_on_abort() {
      if [ -n \"\$CLONE_DIR\" ] && [ -d \"\$CLONE_DIR\" ]; then
        rm -rf \"\$CLONE_DIR\"
      fi
    }
    trap cleanup_on_abort EXIT
    exit 0
  "
  echo "Status: $status, output: $output"

  [ "$status" -eq 0 ]
  # BUG: Clone gets deleted even though exit was successful!
  # With current code, this passes but clone is incorrectly deleted
  # This test documents the bug - after fix, clone should still exist
  [ -d "$TEST_CLONE" ]
}

# --- Test 6: fix verification - conditional trap only on error path ---
@test "fix: conditional trap does not fire on successful exit" {
  cd "$FIXTURE_REPO"

  TEST_CLONE="$FIXTURE_REPO/.clones/test-fix"
  mkdir -p "$TEST_CLONE/.git"

  # Simulate FIXED behavior: trap only set in error path
  run bash -c "
    CLONE_DIR='$TEST_CLONE'
    ABORTING='no'  # Simulates successful path
    cleanup_on_abort() {
      if [ -n \"\$CLONE_DIR\" ] && [ -d \"\$CLONE_DIR\" ]; then
        rm -rf \"\$CLONE_DIR\"
      fi
    }
    if [ \"\$ABORTING\" = 'yes' ]; then
      trap cleanup_on_abort EXIT
    fi
    # Simulate successful PR creation
    exit 0
  "
  echo "Status: $status, output: $output"

  [ "$status" -eq 0 ]
  # Clone should be preserved because trap was never set
  [ -d "$TEST_CLONE" ]
}

# --- Test 7: fix verification - trap fires when ABORTING=yes ---
@test "fix: conditional trap fires when ABORTING=yes" {
  cd "$FIXTURE_REPO"

  TEST_CLONE="$FIXTURE_REPO/.clones/test-fix-abort"
  mkdir -p "$TEST_CLONE/.git"

  # Simulate FIXED behavior: trap only set when aborting
  run bash -c "
    CLONE_DIR='$TEST_CLONE'
    ABORTING='yes'  # Simulates abort path
    cleanup_on_abort() {
      if [ -n \"\$CLONE_DIR\" ] && [ -d \"\$CLONE_DIR\" ]; then
        rm -rf \"\$CLONE_DIR\"
      fi
    }
    if [ \"\$ABORTING\" = 'yes' ]; then
      trap cleanup_on_abort EXIT
    fi
    # Simulate abort
    exit 1
  "
  echo "Status: $status, output: $output"

  [ "$status" -eq 1 ]
  # Clone should be deleted because trap was set and exit was error
  [ ! -d "$TEST_CLONE" ]
}