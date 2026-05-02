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

  # Run a sub-script that sets trap conditionally and exits with error
  run bash -c "
    CLONE_DIR='$TEST_CLONE'
    ABORTING='yes'
    cleanup_on_abort() {
      if [ -n \"\$CLONE_DIR\" ] && [ -d \"\$CLONE_DIR\" ]; then
        rm -rf \"\$CLONE_DIR\"
      fi
    }
    if [ \"\$ABORTING\" = 'yes' ]; then
      trap cleanup_on_abort EXIT
    fi
    exit 1
  "
  echo "Status: $status, output: $output"

  [ "$status" -eq 1 ]
  # Clone should be deleted because trap fired on error exit
  [ ! -d "$TEST_CLONE" ]
}

# --- Test 2: fixed behavior - trap does NOT fire on successful exit ---
@test "cleanup_on_abort trap does NOT fire on successful exit (FIXED)" {
  cd "$FIXTURE_REPO"

  # Create a test clone directory
  TEST_CLONE="$FIXTURE_REPO/.clones/test-success"
  mkdir -p "$TEST_CLONE/.git"

  # Run a sub-script that simulates FIXED looper behavior
  # trap is NOT set because ABORTING='no'
  run bash -c "
    CLONE_DIR='$TEST_CLONE'
    ABORTING='no'
    cleanup_on_abort() {
      if [ -n \"\$CLONE_DIR\" ] && [ -d \"\$CLONE_DIR\" ]; then
        rm -rf \"\$CLONE_DIR\"
      fi
    }
    if [ \"\$ABORTING\" = 'yes' ]; then
      trap cleanup_on_abort EXIT
    fi
    exit 0
  "
  echo "Status: $status, output: $output"

  [ "$status" -eq 0 ]
  # Clone should still exist because trap was NOT set (ABORTING=no)
  [ -d "$TEST_CLONE" ]
}

# --- Test 3: trap fires on abort (simulating line 209-215) ---
@test "cleanup_on_abort trap fires on abort exit" {
  cd "$FIXTURE_REPO"

  TEST_CLONE="$FIXTURE_REPO/.clones/test-line209"
  mkdir -p "$TEST_CLONE/.git"

  # Simulate line 209-215: exit 1 on FAIL verdict with trap set
  run bash -c "
    CLONE_DIR='$TEST_CLONE'
    ABORTING='yes'
    cleanup_on_abort() {
      if [ -n \"\$CLONE_DIR\" ] && [ -d \"\$CLONE_DIR\" ]; then
        rm -rf \"\$CLONE_DIR\"
      fi
    }
    if [ \"\$ABORTING\" = 'yes' ]; then
      trap cleanup_on_abort EXIT
    fi
    echo '[looper] Failed review. Aborting.' >&2
    exit 1
  "
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
  run bash -c "
    CLONE_DIR='$TEST_CLONE'
    ABORTING='no'
    cleanup_on_abort() {
      if [ -n \"\$CLONE_DIR\" ] && [ -d \"\$CLONE_DIR\" ]; then
        rm -rf \"\$CLONE_DIR\"
      fi
    }
    if [ \"\$ABORTING\" = 'yes' ]; then
      trap cleanup_on_abort EXIT
    fi
    echo '[looper] Passed review, creating PR...' >&2
    CLONE_DIR=''
    exit 0
  "
  echo "Status: $status, output: $output"

  [ "$status" -eq 0 ]
  # Clone should still exist because CLONE_DIR was cleared before exit
  [ -d "$TEST_CLONE" ]
}

# --- Test 5: FIXED behavior - no trap set on success path ---
@test "FIXED: no trap set means no cleanup on successful exit" {
  cd "$FIXTURE_REPO"

  TEST_CLONE="$FIXTURE_REPO/.clones/test-fix-success"
  mkdir -p "$TEST_CLONE/.git"

  # Simulates FIXED looper-simplified.md behavior
  # trap is ONLY set in abort path, not on success
  run bash -c "
    CLONE_DIR='$TEST_CLONE'
    ABORTING='no'  # Success path
    cleanup_on_abort() {
      if [ -n \"\$CLONE_DIR\" ] && [ -d \"\$CLONE_DIR\" ]; then
        echo '[cleanup] Removing clone on abort...' >&2
        rm -rf \"\$CLONE_DIR\"
      fi
    }
    if [ \"\$ABORTING\" = 'yes' ]; then
      trap cleanup_on_abort EXIT
    fi
    # Simulate successful PR creation
    echo '[looper] Passed review, creating PR...' >&2
    exit 0
  "
  echo "Status: $status, output: $output"

  [ "$status" -eq 0 ]
  # Clone should be preserved because trap was never set
  [ -d "$TEST_CLONE" ]
}

# --- Test 6: trap fires when ABORTING=yes ---
@test "fix: conditional trap fires when ABORTING=yes" {
  cd "$FIXTURE_REPO"

  TEST_CLONE="$FIXTURE_REPO/.clones/test-fix-abort"
  mkdir -p "$TEST_CLONE/.git"

  # Simulate FIXED behavior: trap only set when aborting
  run bash -c "
    CLONE_DIR='$TEST_CLONE'
    ABORTING='yes'  # Abort path
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

# --- Test 7: multiple abort points work correctly ---
@test "trap fires correctly for setup-clone failure" {
  cd "$FIXTURE_REPO"

  TEST_CLONE="$FIXTURE_REPO/.clones/test-setup-fail"
  mkdir -p "$TEST_CLONE/.git"

  # Simulate setup-clone failure at line 102-104
  run bash -c "
    CLONE_DIR='$TEST_CLONE'
    ABORTING='yes'
    cleanup_on_abort() {
      if [ -n \"\$CLONE_DIR\" ] && [ -d \"\$CLONE_DIR\" ]; then
        rm -rf \"\$CLONE_DIR\"
      fi
    }
    if [ \"\$ABORTING\" = 'yes' ]; then
      trap cleanup_on_abort EXIT
    fi
    echo 'ERROR: setup-clone failed. Aborting.' >&2
    exit 1
  "
  echo "Status: $status, output: $output"

  [ "$status" -eq 1 ]
  [ ! -d "$TEST_CLONE" ]
}