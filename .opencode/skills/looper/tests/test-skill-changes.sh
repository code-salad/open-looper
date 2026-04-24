#!/usr/bin/env bash
set -euo pipefail

# Tests for looper skill changes in iteration 3:
# - Issue 1: Step 8a (WAIT_FOR_CI)
# - Issue 2: Step 8b (DB migration detection), Step 8c (merge or leave open)
# - Issue 3: Step 7 conditional re-sync (SYNC_STATUS, SYNC_HEAD, NEW_COMMITS)
# - Issue 4: Conflict resolution guidance ("prefer local" / "--ours")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../SKILL.md"

# -------------------------------------------------------------------
# Issue 4: Conflict resolution guidance
# -------------------------------------------------------------------

echo "=== Test: conflict resolution guidance mentions 'prefer local' ==="
if grep -q "prefer local" "$SKILL_MD"; then
    echo "PASS: SKILL.md mentions 'prefer local' strategy"
else
    echo "FAIL: SKILL.md does not mention 'prefer local' strategy"
    exit 1
fi

echo "=== Test: conflict resolution guidance mentions '--ours' ==="
if grep -q '\-\-ours' "$SKILL_MD"; then
    echo "PASS: SKILL.md mentions '--ours' for conflict resolution"
else
    echo "FAIL: SKILL.md does not mention '--ours' for conflict resolution"
    exit 1
fi

echo "=== Test: conflict resolution guidance explains 'ours' means worktree branch ==="
# The guidance should explain that "ours" = the loop/ branch, not incoming remote
if grep -qE "ours.*(loop|worktree|branch)" "$SKILL_MD" || grep -qE "(loop|worktree|branch).*ours" "$SKILL_MD"; then
    echo "PASS: SKILL.md explains 'ours' in context of worktree branch"
else
    echo "FAIL: SKILL.md does not explain 'ours' meaning worktree branch"
    exit 1
fi

# -------------------------------------------------------------------
# Issue 3: Step 7 conditional re-sync
# -------------------------------------------------------------------

echo "=== Test: SKILL.md captures SYNC_STATUS at end of step 4b ==="
if grep -qE "SYNC_STATUS.*=" "$SKILL_MD"; then
    echo "PASS: SKILL.md references SYNC_STATUS"
else
    echo "FAIL: SKILL.md does not capture SYNC_STATUS"
    exit 1
fi

echo "=== Test: SKILL.md captures SYNC_HEAD at end of step 4b ==="
if grep -qE "SYNC_HEAD.*=" "$SKILL_MD"; then
    echo "PASS: SKILL.md references SYNC_HEAD"
else
    echo "FAIL: SKILL.md does not capture SYNC_HEAD"
    exit 1
fi

echo "=== Test: SKILL.md references NEW_COMMITS variable ==="
if grep -qE "NEW_COMMITS" "$SKILL_MD"; then
    echo "PASS: SKILL.md references NEW_COMMITS"
else
    echo "FAIL: SKILL.md does not reference NEW_COMMITS"
    exit 1
fi

echo "=== Test: SKILL.md step 7 has conditional re-sync logic ==="
# Step 7 should conditionally re-sync only if NEW_COMMITS=true
# It should compare CURRENT_HEAD vs STEP4B_HEAD (or SYNC_HEAD)
if grep -qE "NEW_COMMITS.*true|CURRENT_HEAD.*SYNC_HEAD" "$SKILL_MD"; then
    echo "PASS: SKILL.md has conditional re-sync logic"
else
    echo "FAIL: SKILL.md missing conditional re-sync logic"
    exit 1
fi

echo "=== Test: SKILL.md step 7 skips re-sync when no new commits ==="
if grep -qE "skip.*re.?sync|skipping.*re.?sync|No new commits" "$SKILL_MD"; then
    echo "PASS: SKILL.md mentions skipping re-sync when no new commits"
else
    echo "FAIL: SKILL.md does not mention skipping re-sync"
    exit 1
fi

# -------------------------------------------------------------------
# Issue 1: Step 8a (WAIT_FOR_CI)
# -------------------------------------------------------------------

echo "=== Test: SKILL.md has step 8a 'Wait for CI' ==="
if grep -qE "8a.*Wait for CI|Wait for CI" "$SKILL_MD"; then
    echo "PASS: SKILL.md has step 8a Wait for CI"
else
    echo "FAIL: SKILL.md missing step 8a Wait for CI"
    exit 1
fi

echo "=== Test: SKILL.md step 8a uses 'gh pr checks --watch' ==="
if grep -qE "gh pr checks.*\-\-watch" "$SKILL_MD"; then
    echo "PASS: SKILL.md uses 'gh pr checks --watch'"
else
    echo "FAIL: SKILL.md does not use 'gh pr checks --watch'"
    exit 1
fi

echo "=== Test: SKILL.md step 8a handles CI failure ==="
if grep -qE "CI fails|Check fails|fail.*CI|failure" "$SKILL_MD"; then
    echo "PASS: SKILL.md handles CI failure"
else
    echo "FAIL: SKILL.md does not handle CI failure"
    exit 1
fi

echo "=== Test: SKILL.md step 8a handles CI timeout ==="
if grep -qE "timeout|time.?out" "$SKILL_MD"; then
    echo "PASS: SKILL.md handles CI timeout"
else
    echo "FAIL: SKILL.md does not handle CI timeout"
    exit 1
fi

# -------------------------------------------------------------------
# Issue 2: Step 8b (DB migration detection)
# -------------------------------------------------------------------

echo "=== Test: SKILL.md has step 8b 'Detect DB migrations' ==="
if grep -qE "8b.*Detect|Detect DB migrations|DB migrations detected" "$SKILL_MD"; then
    echo "PASS: SKILL.md has step 8b Detect DB migrations"
else
    echo "FAIL: SKILL.md missing step 8b Detect DB migrations"
    exit 1
fi

echo "=== Test: SKILL.md step 8b checks for migration file patterns ==="
# Should check for patterns like migrations/, db/migrate, alembic/versions, etc.
if grep -qE "migrations?/|db/migrate|alembic/versions|prisma/migrations|drizzle/" "$SKILL_MD"; then
    echo "PASS: SKILL.md checks for migration file patterns"
else
    echo "FAIL: SKILL.md does not check migration file patterns"
    exit 1
fi

echo "=== Test: SKILL.md has step 8c 'Merge or leave open' ==="
if grep -qE "8c.*Merge|Merge or leave|leave.*open" "$SKILL_MD"; then
    echo "PASS: SKILL.md has step 8c Merge or leave open"
else
    echo "FAIL: SKILL.md missing step 8c Merge or leave open"
    exit 1
fi

echo "=== Test: SKILL.md step 8c leaves PR open when migrations detected ==="
if grep -qE "HAS_MIGRATIONS.*true|leaving.*open|leave.*open" "$SKILL_MD"; then
    echo "PASS: SKILL.md leaves PR open when migrations detected"
else
    echo "FAIL: SKILL.md does not leave PR open when migrations detected"
    exit 1
fi

echo "=== Test: SKILL.md step 8c proceeds with merge when no migrations ==="
# Should proceed to merge/squash when no migrations
if grep -qE "no.*migrations|skip.*merge|squash.*merge" "$SKILL_MD"; then
    echo "PASS: SKILL.md proceeds with merge when no migrations"
else
    echo "FAIL: SKILL.md does not proceed with merge when no migrations"
    exit 1
fi

# -------------------------------------------------------------------
# All tests passed
# -------------------------------------------------------------------
echo ""
echo "=== All tests passed ==="
exit 0
