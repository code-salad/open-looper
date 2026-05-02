#!/usr/bin/env bats
set -euo pipefail

# verdicts-search.bats — Tests for Loop-Verdict search pattern in looper-simplified.md

CURRENT_USER="${CURRENT_USER:-testuser}"

teardown() {
    rm -rf "$BATS_TMPDIR/verdict-test-repo" 2>/dev/null || true
}

# Helper: create a test repo with a Loop-Verdict commit
create_verdict_repo() {
    local repo_dir="$BATS_TMPDIR/verdict-test-repo"
    mkdir -p "$repo_dir"
    git init -q "$repo_dir"
    git -C "$repo_dir" config user.email "test@example.com"
    git -C "$repo_dir" config user.name "Test User"

    touch "$repo_dir/README"
    git -C "$repo_dir" add README
    git -C "$repo_dir" commit -q -m "init"

    # Create a commit with Loop-Verdict trailer
    git -C "$repo_dir" commit --allow-empty -q -m "review: check passed

Loop-Phase: check
Loop-Iteration: 1
Loop-Verdict: PASS"

    echo "$repo_dir"
}

# ------------------------------------------------------------------------
# Tests: git log --grep with Loop-Verdict
# ------------------------------------------------------------------------

@test "git log --grep finds verdict without --all-match flag" {
    repo_dir="$(create_verdict_repo)"

    # Without --all-match, a single --grep should work
    verdict=$(git -C "$repo_dir" log --grep="Loop-Verdict:" --format="%B" -1 2>/dev/null \
        | grep -oE 'Loop-Verdict: (PASS|FAIL)' | tail -1 | sed 's/Loop-Verdict: //' || echo "")

    [ "$verdict" = "PASS" ]
}

@test "git log --grep with --all-match and single grep works correctly" {
    repo_dir="$(create_verdict_repo)"

    # With --all-match and a single --grep, git log should still find the verdict
    # The --all-match flag only affects behavior when multiple --grep flags are present
    verdict=$(git -C "$repo_dir" log --grep="Loop-Verdict:" --all-match --format="%B" -1 2>/dev/null \
        | grep -oE 'Loop-Verdict: (PASS|FAIL)' | tail -1 | sed 's/Loop-Verdict: //' || echo "")

    # This should now work (bug was: --all-match was incorrectly used with single grep)
    [ "$verdict" = "PASS" ]
}

@test "git log --grep works with --all-match when multiple greps are used" {
    repo_dir="$(create_verdict_repo)"

    # --all-match is correct when using multiple --grep patterns
    verdict=$(git -C "$repo_dir" log \
        --grep="Loop-Phase:" --grep="Loop-Iteration:" \
        --all-match --format="%B" -1 2>/dev/null \
        | grep -oE 'Loop-Verdict: (PASS|FAIL)' | tail -1 | sed 's/Loop-Verdict: //' || echo "")

    [ "$verdict" = "PASS" ]
}

# ------------------------------------------------------------------------
# Tests: verdict search in clone directory context
# ------------------------------------------------------------------------

@test "verdict search works when CLONE_DIR contains verdict commit" {
    repo_dir="$(create_verdict_repo)"

    cd "$repo_dir"

    # Simulate the looper's verdict search command (without --all-match bug)
    verdict=$(git log --grep="Loop-Verdict:" --format="%B" -1 2>/dev/null \
        | grep -oE 'Loop-Verdict: (PASS|FAIL)' | tail -1 | sed 's/Loop-Verdict: //' || echo "")

    [ "$verdict" = "PASS" ]
}

@test "verdict search returns empty when no verdict exists" {
    repo_dir="$BATS_TMPDIR/verdict-test-repo"
    mkdir -p "$repo_dir"
    git init -q "$repo_dir"
    git -C "$repo_dir" config user.email "test@example.com"
    git -C "$repo_dir" config user.name "Test User"

    touch "$repo_dir/README"
    git -C "$repo_dir" add README
    git -C "$repo_dir" commit -q -m "init"

    cd "$repo_dir"

    verdict=$(git log --grep="Loop-Verdict:" --format="%B" -1 2>/dev/null \
        | grep -oE 'Loop-Verdict: (PASS|FAIL)' | tail -1 | sed 's/Loop-Verdict: //' || echo "")

    [ -z "$verdict" ]
}