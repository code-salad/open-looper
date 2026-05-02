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
  cd_found=$(echo "$DOER_MD" | grep -c 'cd "\$CLONE_DIR"' || true)
  [ "$cd_found" -ge 1 ]

  # Verify the cd appears early (before Phase 1: RED instructions)
  CD_LINE=$(echo "$DOER_MD" | grep -n 'cd "\$CLONE_DIR"' | head -1 | cut -d: -f1)
  echo "cd instruction found at line: $CD_LINE"

  # cd should appear within first 30 lines (before Phase 1: RED)
  [ "$CD_LINE" -le 30 ]
}

# --- Test 2: Reviewer agent documentation must include cd instruction ---
@test "looper-reviewer.md: must document cd into CLONE_DIR before git commands" {
  cd "$FIXTURE_REPO"

  # Read looper-reviewer.md
  REVIEWER_MD=$(cat "$AGENTS_DIR/looper-reviewer.md")

  # Check that there's a cd "$CLONE_DIR" instruction
  cd_found=$(echo "$REVIEWER_MD" | grep -c 'cd "\$CLONE_DIR"' || true)
  [ "$cd_found" -ge 1 ]

  CD_LINE=$(echo "$REVIEWER_MD" | grep -n 'cd "\$CLONE_DIR"' | head -1 | cut -d: -f1)
  echo "cd instruction found at line: $CD_LINE"

  # cd should appear within first 40 lines
  [ "$CD_LINE" -le 40 ]
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

  [ -n "$CD_LINE" ]
  [ -n "$VERIFY_LINE" ]
  [ "$CD_LINE" -lt "$VERIFY_LINE" ]
}

# --- Test 4: Reviewer must cd before collecting changed files ---
@test "looper-reviewer.md: cd must precede the 'Collect changed files' step" {
  cd "$FIXTURE_REPO"

  REVIEWER_MD=$(cat "$AGENTS_DIR/looper-reviewer.md")

  CD_LINE=$(echo "$REVIEWER_MD" | grep -n 'cd "\$CLONE_DIR"' | head -1 | cut -d: -f1)
  COLLECT_LINE=$(echo "$REVIEWER_MD" | grep -n 'Collect changed files' | head -1 | cut -d: -f1)

  echo "cd instruction at line: $CD_LINE"
  echo "Collect changed files at line: $COLLECT_LINE"

  [ -n "$CD_LINE" ]
  [ -n "$COLLECT_LINE" ]
  [ "$CD_LINE" -lt "$COLLECT_LINE" ]
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
  LOG_RESULT=$(git log --grep="main workspace commit" --format="%H" -1 2>/dev/null || echo "NOT_FOUND")

  echo "LOG_RESULT: $LOG_RESULT"

  # This should find the commit because we're in main workspace (bug demonstrated)
  [ "$LOG_RESULT" != "NOT_FOUND" ]
}

# --- Test 6: Doer cd instruction should be in the preamble or first instruction ---
@test "looper-doer.md: cd instruction must be in preamble or first instruction block" {
  cd "$FIXTURE_REPO"

  DOER_MD=$(cat "$AGENTS_DIR/looper-doer.md")

  # The cd instruction should appear BEFORE "### Phase 1: RED"
  CD_LINE=$(echo "$DOER_MD" | grep -n 'cd "\$CLONE_DIR"' | head -1 | cut -d: -f1)
  RED_PHASE_LINE=$(echo "$DOER_MD" | grep -n '### Phase 1: RED' | head -1 | cut -d: -f1)

  echo "cd at line: $CD_LINE, Phase 1 RED at line: $RED_PHASE_LINE"

  [ -n "$CD_LINE" ]
  [ -n "$RED_PHASE_LINE" ]
  [ "$CD_LINE" -lt "$RED_PHASE_LINE" ]
}

# --- Test 7: Verify the cd instruction explicitly mentions CLONE_DIR variable ---
@test "looper-doer.md: cd instruction must reference CLONE_DIR (not WORKTREE_DIR)" {
  cd "$FIXTURE_REPO"

  DOER_MD=$(cat "$AGENTS_DIR/looper-doer.md")

  # Check for proper cd with CLONE_DIR (should find it now)
  cd_clone=$(echo "$DOER_MD" | grep -c 'cd "\$CLONE_DIR"' || true)
  cd_worktree=$(echo "$DOER_MD" | grep -c 'cd "\$WORKTREE_DIR"' || true)

  echo "cd CLONE_DIR count: $cd_clone"
  echo "cd WORKTREE_DIR count: $cd_worktree"

  [ "$cd_clone" -ge 1 ]
  [ "$cd_worktree" -eq 0 ]
}