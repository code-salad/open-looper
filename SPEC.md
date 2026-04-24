# SPEC.md — looper skill: make CI check and merge strategy explicit

## Goal

After Checker issues PASS, the looper skill must expose CI polling and DB-migration-aware merge strategy as **explicit phases** in the skill flow, not hidden inside the create-github-pr skill. The goal is visibility and control within the looper loop itself.

---

## Issue 1: Add explicit WAIT_FOR_CI phase to skill flow

**Problem:** CI polling is buried inside create-github-pr (Phase 5). The looper skill should have an explicit WAIT_FOR_CI phase so that:
- The loop does not exit until CI results are known
- Failure to pass CI is surfaced before attempting merge
- The user gets clear feedback on CI status

**Acceptance Criteria:**
- [ ] After step 8 (create PR), there is a new step 8a called "Wait for CI"
- [ ] Step 8a invokes CI polling directly (not via create-github-pr), using `gh pr checks --watch`
- [ ] If CI fails, the skill reports failure and does NOT proceed to merge
- [ ] If CI times out (>20 min), the skill reports timeout and does NOT proceed to merge
- [ ] Only after CI passes does the flow proceed to step 8b (merge decision)

**Implementation Detail:**
```bash
### 8a. Wait for CI

After creating the PR, poll until CI checks complete.

```bash
PR_NUMBER=$(gh pr view --json number --jq '.number')
CI_STATUS=$(gh pr checks $PR_NUMBER --watch 2>&1) || CI_EXIT=$?
```

- **All checks pass:** Proceed to step 8b.
- **Any check fails:** Report failure. Do NOT proceed to merge. Exit with error.
- **Timeout (>20 min):** Report timeout. Do NOT proceed to merge. Exit with error.
- **No checks configured:** Log "No CI checks configured" and proceed to step 8b.
```

---

## Issue 2: Make DB migration detection part of looper skill

**Problem:** DB migration detection (Phase 6a in create-github-pr) is only in create-github-pr. The looper skill should also detect DB migrations so it can make the merge-or-leave-open decision itself, rather than delegating entirely to create-github-pr.

**Acceptance Criteria:**
- [ ] Step 8b (merge decision) is in the looper skill, not deferred to create-github-pr
- [ ] Before calling create-github-pr, the looper skill checks for DB migrations in the changeset
- [ ] If DB migrations are detected, the looper skill leaves the PR open and reports the reason
- [ ] If no DB migrations, the looper skill proceeds with squash-merge via create-github-pr
- [ ] The DB migration detection patterns are the same as in create-github-pr (shared logic or re-implemented)

**Implementation Detail:**
```bash
### 8b. Detect DB migrations

Before merge, check whether the PR contains DB migration files:

```bash
CHANGED_FILES=$(git diff --name-only "$BASE_REF"...HEAD)
HAS_MIGRATIONS=false

if echo "$CHANGED_FILES" | grep -qiE \
    '(migrations?/|db/migrate|alembic/versions|flyway|prisma/migrations|drizzle/|knex/migrations|sequelize/migrations|typeorm/migrations|migrate.*\.sql$|migration.*\.sql$)'; then
    HAS_MIGRATIONS=true
fi
```

Migration patterns detected:
- `migrations/` or `migration/` — generic migration directories
- `db/migrate/` — Rails ActiveRecord migrations
- `alembic/versions/` — Python/Alembic migrations
- `prisma/migrations/` — Prisma ORM migrations
- `drizzle/` — Drizzle ORM migration files
- `knex/migrations/`, `sequelize/migrations/`, `typeorm/migrations/` — other ORMs
- `flyway/` — Flyway SQL migrations
- Files matching `migrate*.sql` or `migration*.sql`

### 8c. Merge or leave open

```bash
if [ "$HAS_MIGRATIONS" = true ]; then
    echo "DB migrations detected — leaving PR open for manual review."
    echo "Merge manually when ready: gh pr merge $PR_NUMBER --squash --delete-branch"
else
    # Proceed to create-github-pr for squash-merge
    invoke create-github-pr skill with --skip-db-check
fi
```
```

---

## Issue 3: Simplify step 7 — skip re-sync if no new commits since step 4b

**Problem:** Step 7 always runs `sync-with-remote`, but if step 4b already succeeded with `STATUS=up-to-date` or `STATUS=rebased` and no new commits were made since then, the re-sync is redundant.

**Acceptance Criteria:**
- [ ] Step 4b captures `SYNC_STATUS` (up-to-date, rebased, or conflicts)
- [ ] Step 7 checks: if `SYNC_STATUS` was `up-to-date` or `rebased` AND no new commits exist on the branch, skip the re-sync entirely
- [ ] A new helper script or inline check compares current HEAD vs the HEAD at step 4b completion
- [ ] Only if there are new commits (e.g., from the doer's work) does step 7 run the rebase

**Implementation Detail:**
```bash
### 7. Sync before PR (conditional)

```bash
# Check if we need to re-sync:
# 1. Did step 4b succeed with up-to-date or rebased?
# 2. Are there new commits since step 4b?

STEP4B_STATUS="${SYNC_STATUS:-}"
STEP4B_HEAD="${SYNC_HEAD:-}"  # captured at end of step 4b

CURRENT_HEAD=$(git rev-parse HEAD)
NEW_COMMITS=false

if [ "$STEP4B_STATUS" = "up-to-date" ] || [ "$STEP4B_STATUS" = "rebased" ]; then
    if [ "$CURRENT_HEAD" != "$STEP4B_HEAD" ]; then
        NEW_COMMITS=true
    fi
fi

if [ "$NEW_COMMITS" = true ]; then
    echo "New commits detected — re-syncing with remote..."
    SYNC_OUTPUT=$($SCRIPTS_DIR/sync-with-remote) && SYNC_EXIT=0 || SYNC_EXIT=$?
    eval "$SYNC_OUTPUT"
    # Handle conflicts as in step 4b
else
    echo "No new commits since step 4b — skipping re-sync."
fi
```
```

**Capture at end of step 4b:**
```bash
SYNC_STATUS="${STATUS:-}"
SYNC_HEAD=$(git rev-parse HEAD)
# Export these for use in step 7 (via environment or tempfile)
```

---

## Issue 4: Add conflict resolution guidance (prefer local or remote?)

**Problem:** Step 4b and step 7 conflict resolution provides no guidance on whether to prefer local changes or remote changes when resolving conflicts.

**Acceptance Criteria:**
- [ ] Conflict resolution in step 4b and step 7 specifies "prefer local changes" as the default strategy
- [ ] The guidance explains: `git checkout --ours` for conflicting files (keeps our loop/ branch changes) then `git add` and `git rebase --continue`
- [ ] The guidance is explicit that "ours" means the worktree branch (loop/ branch), not the incoming remote changes
- [ ] Alternative strategy (prefer remote) is documented but marked as not recommended for loop work

**Implementation Detail:**
```bash
Conflict resolution guidance (add to step 4b and step 7):

> **Conflict resolution strategy: prefer local (worktree) changes**
>
> When resolving rebase conflicts, prefer keeping your local changes (the worktree branch).
> This is because the worktree branch contains the planned implementation, while the
> remote branch is the shared baseline.
>
> For each conflicted file:
> 1. Read the file to understand both sides of the conflict
> 2. Edit the file to keep the version that preserves your intended implementation
>    (typically the "ours" side — your loop/ branch changes)
> 3. Stage the resolved file: `git add <file>`
> 4. Continue the rebase: `git rebase --continue`
>
> If new conflicts appear, repeat until the rebase completes.
>
> **Why prefer local?** The looper worktree is a disposable context for implementing
> a fix. The remote baseline is the source of truth. Preferring local ensures the
> planned changes are preserved.
>
> **Alternative (not recommended):** To prefer remote changes instead, use
> `git checkout --theirs <file>` before `git add`. This discards local changes
> and is generally not what you want in a loop/ worktree.
```

---

## Files to modify

1. **`.opencode/skills/looper/SKILL.md`** — update step 4b, step 7, step 8, and add new steps 8a/8b/8c

## Files to create

1. **`.opencode/skills/looper/scripts/detect-migrations`** — optional shared migration detection script (can be inline in SKILL.md)

---

## Corner cases

1. **CI never runs** — If no checks are configured, proceed directly to merge decision
2. **CI fails** — Report failure, leave PR open, do NOT merge, exit with error
3. **CI times out** — Report timeout, leave PR open, do NOT merge, exit with error
4. **DB migrations detected** — Leave PR open, report manual merge required
5. **No DB migrations + CI passes** — Squash-merge via create-github-pr
6. **Step 7 rebase has conflicts** — Use prefer-local strategy, resolve and continue
7. **Step 4b already rebased, no new commits** — Step 7 skips rebase entirely
8. **Step 4b had conflicts but step 7 would skip** — Never skip if STATUS=conflicts from step 4b

---

## Testing approach

Write tests for the new logic:

1. **Test detect-migrations script** — various migration file patterns (true positive and true negative)
2. **Test conditional re-sync** — when new commits exist vs when they don't
3. **Test conflict resolution guidance** — verify the "prefer local" strategy is documented

No TDD tests in SKILL.md since it's a specification document, not implementation code.
