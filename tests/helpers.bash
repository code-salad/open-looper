#!/usr/bin/env bash
# -*- shell-bats -*-
# Common helpers for bats test suite.
# Sets up an isolated fixture repo once per test file.

FIXTURE_REPO=""
export FIXTURE_REPO

# Source the scripts' own helpers to get functions like ensure_not_bare
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../.opencode/skills/looper/scripts" && pwd)"
export SCRIPTS_DIR

# Create a shared fixture repo once per process (bats spawns one shell per @test)
setup_fixture_repo() {
  if [ -z "$FIXTURE_REPO" ] || [ ! -d "$FIXTURE_REPO" ]; then
    FIXTURE_REPO=$(mktemp -d)
    export FIXTURE_REPO

    git init -q "$FIXTURE_REPO"
    git -C "$FIXTURE_REPO" config user.email "test@example.com"
    git -C "$FIXTURE_REPO" config user.name "Test User"

    # Create an initial commit
    touch "$FIXTURE_REPO/README"
    git -C "$FIXTURE_REPO" add README
    git -C "$FIXTURE_REPO" commit -q -m "init"

    # Create an origin remote so DEFAULT_REMOTE_BRANCH detection works
    mkdir -p "$FIXTURE_REPO/.git/refs/remotes/origin"
    echo "refs/heads/main" > "$FIXTURE_REPO/.git/refs/remotes/origin/HEAD"
    git -C "$FIXTURE_REPO" remote add origin "file://$FIXTURE_REPO/.git" 2>/dev/null || true
  fi
}

teardown_fixture_repo() {
  if [ -n "$FIXTURE_REPO" ] && [ -d "$FIXTURE_REPO" ]; then
    rm -rf "$FIXTURE_REPO"
  fi
}

# bats runs setup() once before the first test; teardown() once after the last
setup() {
  setup_fixture_repo
}

teardown() {
  teardown_fixture_repo
}
