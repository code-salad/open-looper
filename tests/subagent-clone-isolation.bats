#!/usr/bin/env bats
# -*- shell-bats -*-
# This testsuite verifies that subagents (Doer, Reviewer) have explicit
# instructions to cd into CLONE_DIR before running any git commands.
#
# Issue #38: looper subagents don't operate inside isolated clone
# The orchestrator creates a clone via setup-clone and passes CLONE_DIR to
# subagents, but subagents never actually cd into the clone - they operate
# in the main workspace context instead.

load 'helpers.bash'

# Source path for agent files (the actual workspace, not fixture)
AGENTS_DIR="/home/ubuntu/open-looper/.opencode/agents"

# --- Test 1: Doer agent documentation must include cd instruction ---
@test "looper-doer.md: must document cd into CLONE_DIR before git commands" {
  cd "$FIXTURE_REPO"

  # Read looper-doer.md
  DOER_MD=$(cat "$AGENTS_DIR/looper-doer.md")

  # Check that there's a cd "$CLONE_DIR" instruction
  if echo "$DOER_MD" | grep -q 'cd "\$CLONE_DIR"'; then
    # Verify the cd appears early (before Phase 1: RED instructions)
    CD_LINE=$(echo "$DOER_MD" | grep -n 'cd "\$CLONE_DIR"' | head -1 | cut -d: -f1)
    echo "cd instruction found at line: $CD_LINE"

    # cd should appear within first 30 lines (before Phase 1: RED)
    if [ "$CD_LINE" -le 30 ]; then
      echo "CD_INSTRUCTION_OK: cd appears early in doer agent"
      exit 0
    else
      echo "CD_INSTRUCTION_LATE: cd appears too late (line $CD_LINE)"
      exit 1
    fi
  else
    echo "CD_INSTRUCTION_MISSING: no cd \"\$CLONE_DIR\" found in looper-doer.md"
    exit 1
  fi
}

# --- Test 2: Reviewer agent documentation must include cd instruction ---
@test "looper-reviewer.md: must document cd into CLONE_DIR before git commands" {
  cd "$FIXTURE_REPO"

  # Read looper-reviewer.md
  REVIEWER_MD=$(cat "$AGENTS_DIR/looper-reviewer.md")

  # Check that there's a cd "$CLONE_DIR" instruction
  if echo "$REVIEWER_MD" | grep -q 'cd "\$CLONE_DIR"'; then
    CD_LINE=$(echo "$REVIEWER_MD" | grep -n 'cd "\$CLONE_DIR"' | head -1 | cut -d: -f1)
    echo "cd instruction found at line: $CD_LINE"

    # cd should appear within first 40 lines
    if [ "$CD_LINE" -le 40 ]; then
      echo "CD_INSTRUCTION_OK: cd appears early in reviewer agent"
      exit 0
    else
      echo "CD_INSTRUCTION_LATE: cd appears too late (line $CD_LINE)"
      exit 1
    fi
  else
    echo "CD_INSTRUCTION_MISSING: no cd \"\$CLONE_DIR\" found in looper-reviewer.md"
    exit 1
  fi
}

# --- Test 3: Doer must cd before "Verify no prior work" git log command ---
@test "looper-doer.md: cd must precede the 'Verify no prior work' step" {
  cd "$FIXTURE_REPO"

  DOER_MD=$(cat "$AGENTS_DIR/looper-doer.md")

  # Find line numbers for key instructions
  CD_LINE=$(echo "$DOER_MD" | grep -n 'cd "\$CLONE_DIR"' | head -1 | cut -d: -f1)
  VERIFY_LINE=$(echo "$DOER_MD" | grep -n 'Verify no prior work' | head -1 | cut -d: -f1)

  echo "cd instruction at line: $CD_LINE"
  echo "Verify no prior work at line: $VERIFY_LINE"

  if [ -z "$CD_LINE" ]; then
    echo "MISSING: no cd instruction found"
    exit 1
  fi

  if [ -z "$VERIFY_LINE" ]; then
    echo "MISSING: no Verify no prior work step found"
    exit 1
  fi

  if [ "$CD_LINE" -lt "$VERIFY_LINE" ]; then
    echo "ORDER_OK: cd comes before Verify no prior work"
    exit 0
  else
    echo "ORDER_FAIL: cd must come BEFORE Verify no prior work"
    exit 1
  fi
}

# --- Test 4: Reviewer must cd before collecting changed files ---
@test "looper-reviewer.md: cd must precede the 'Collect changed files' step" {
  cd "$FIXTURE_REPO"

  REVIEWER_MD=$(cat "$AGENTS_DIR/looper-reviewer.md")

  CD_LINE=$(echo "$REVIEWER_MD" | grep -n 'cd "\$CLONE_DIR"' | head -1 | cut -d: -f1)
  COLLECT_LINE=$(echo "$REVIEWER_MD" | grep -n 'Collect changed files' | head -1 | cut -d: -f1)

  echo "cd instruction at line: $CD_LINE"
  echo "Collect changed files at line: $COLLECT_LINE"

  if [ -z "$CD_LINE" ]; then
    echo "MISSING: no cd instruction found"
    exit 1
  fi

  if [ -z "$COLLECT_LINE" ]; then
    echo "MISSING: no Collect changed files step found"
    exit 1
  fi

  if [ "$CD_LINE" -lt "$COLLECT_LINE" ]; then
    echo "ORDER_OK: cd comes before Collect changed files"
    exit 0
  else
    echo "ORDER_FAIL: cd must come BEFORE Collect changed files"
    exit 1
  fi
}

# --- Test 5: REGRESSION - Verify subagent WITHOUT cd operates in main workspace ---
@test "REGRESSION: subagent without cd operates in main workspace (bug demonstration)" {
  cd "$FIXTURE_REPO"

  # Create a clone
  CLONE_DIR=$($SCRIPTS_DIR/setup-clone --task test-regression --unique | tail -1)
  echo "Clone dir: $CLONE_DIR"

  # Make a commit in main workspace
  echo "main-workspace-commit" > main-workspace-marker.txt
  git add main-workspace-marker.txt
  git commit -m "main workspace commit"

  # Simulate a subagent that does NOT cd into clone
  # This demonstrates the bug - git log finds main workspace commit
  # because subagent operates in main workspace, not clone
  run bash -c '
    CLONE_DIR="'"$CLONE_DIR"'"
    # Intentionally NOT doing: cd "$CLONE_DIR"

    # When subagent runs git log without cd, it operates in main workspace
    # This demonstrates the bug
    LOG_RESULT=$(git log --grep="main workspace commit" --format="%H" -1 2>/dev/null || echo "NOT_FOUND")

    if [ "$LOG_RESULT" != "NOT_FOUND" ]; then
      echo "BUG_CONFIRMED: subagent without cd operates in main workspace"
      echo "Found main workspace commit: $LOG_RESULT"
      exit 0
    else
      echo "BUG_NOT_FOUND: expected to find main workspace commit"
      exit 1
    fi
  '
  echo "Status: $status, output: $output"

  # This test passes to confirm the bug exists
  [ "$status" -eq 0 ]
  [[ "$output" =~ "BUG_CONFIRMED" ]]
}

# --- Test 6: Doer cd instruction should be in the preamble or first instruction ---
@test "looper-doer.md: cd instruction must be in preamble or first instruction block" {
  cd "$FIXTURE_REPO"

  DOER_MD=$(cat "$AGENTS_DIR/looper-doer.md")

  # The cd instruction should appear BEFORE "### Phase 1: RED"
  CD_LINE=$(echo "$DOER_MD" | grep -n 'cd "\$CLONE_DIR"' | head -1 | cut -d: -f1)
  RED_PHASE_LINE=$(echo "$DOER_MD" | grep -n '### Phase 1: RED' | head -1 | cut -d: -f1)

  echo "cd at line: $CD_LINE, Phase 1 RED at line: $RED_PHASE_LINE"

  if [ -z "$CD_LINE" ]; then
    echo "MISSING: no cd instruction in looper-doer.md"
    exit 1
  fi

  if [ -z "$RED_PHASE_LINE" ]; then
    echo "WARNING: no Phase 1 RED found"
  else
    if [ "$CD_LINE" -lt "$RED_PHASE_LINE" ]; then
      echo "OK: cd appears before Phase 1 RED"
      exit 0
    else
      echo "FAIL: cd appears AFTER Phase 1 RED - cd must come first"
      exit 1
    fi
  fi
}

# --- Test 7: Verify the cd instruction explicitly mentions CLONE_DIR variable ---
@test "looper-doer.md: cd instruction must reference CLONE_DIR (not WORKTREE_DIR)" {
  cd "$FIXTURE_REPO"

  DOER_MD=$(cat "$AGENTS_DIR/looper-doer.md")

  # Check for proper cd with CLONE_DIR
  if echo "$DOER_MD" | grep -q 'cd "\$CLONE_DIR"'; then
    echo "OK: uses CLONE_DIR"
    exit 0
  elif echo "$DOER_MD" | grep -q 'cd "\$WORKTREE_DIR"'; then
    echo "FAIL: uses deprecated WORKTREE_DIR instead of CLONE_DIR"
    exit 1
  else
    echo "FAIL: no cd into CLONE_DIR found"
    exit 1
  fi
}