# Plan: Fix Planner agent to commit the plan

## Bug Analysis

**Bug Location:** `.opencode/agents/planner.md` — lines 265-277

**Root Cause:** The Planner agent's step 5 says it should commit the plan using `git-commit-loop`, but the Looper agent does NOT invoke the Planner with this expectation. Looking at the looper.md step 6d.1, it only logs "=== Iteration ${ITERATION}/${MAX_ITERATIONS}: PLAN phase ===" and spawns the planner. There's no verification that the Planner committed a plan, and the Looper proceeds directly to the DO phase regardless.

**What happens currently:**
1. Looper spawns Planner with `PLANNER_CONTEXT`
2. Planner writes a plan file to `.opencode/plans/<task>/iteration-XXX.md`
3. Planner's step 5 says to call `git-commit-loop` with `--phase plan`
4. But the Planner is a subagent — it runs in its own context and may not actually commit
5. Looper waits for Planner to finish, then spawns Doer directly
6. The plan file exists but is NOT committed to git

**Why it matters:** Only the Doer's implementation and the Checker's verdict get committed. The plan is lost in the file system, breaking the audit trail.

## Fix Plan

Modify the Planner agent to verify the plan commit was created after step 5, and raise an error if not found. This ensures the plan is always committed before the Doer phase begins.

### File to modify: `.opencode/agents/planner.md`

**Step 5 change** (lines 265-277):

Current text:
```markdown
5. **Commit the plan** — Use the git-commit-loop skill:
   ```bash
   $SCRIPTS_DIR/git-commit-loop \
       --type "chore" \
       --scope "$TASK_NAME" \
       --message "plan iteration $ITERATION" \
       --body "<your plan here>" \
       --phase "plan" \
       --iteration $ITERATION
   ```
```

Replace with:
```markdown
5. **Commit the plan** — Use the git-commit-loop skill:
   ```bash
   $SCRIPTS_DIR/git-commit-loop \
       --type "chore" \
       --scope "$TASK_NAME" \
       --message "plan iteration $ITERATION" \
       --body "<your plan here>" \
       --phase "plan" \
       --iteration $ITERATION
   ```

   **Verify commit exists** — After committing, confirm the plan commit is findable:
   ```bash
   PLAN_COMMIT=$(git log --grep="Loop-Phase: plan" --grep="Loop-Iteration: $ITERATION" \
       --all-match --format="%H" -1)
   if [ -z "$PLAN_COMMIT" ]; then
       echo "ERROR: Planner failed to commit the plan. Aborting." >&2
       exit 1
   fi
   ```
   If the commit is not found, the iteration cannot proceed — the Doer must receive a committed plan to work from.
```

**Rationale:** Adding the verification step ensures the plan is actually committed. The Doer (step 1) reads the plan from a git commit, so if the Planner doesn't commit, the Doer will fail. Better to fail fast with a clear error message than to let the Doer proceed on a missing plan.

## Files to modify

- `.opencode/agents/planner.md` — add plan commit verification after step 5

## Tests

No new tests needed for this documentation/agent-configuration change. The bug is about missing behavior, and verification is done via git log inspection.

## Acceptance Criteria

1. Planner agent commits the plan with `git-commit-loop` before the Doer phase begins
2. Commit includes `Loop-Phase: plan` and `Loop-Iteration: N` headers
3. Commit body contains the full plan content (analysis, changes, verification steps)
4. Plan file and plan commit reference the same iteration
5. If the plan commit is missing after step 5, the Planner exits with error instead of silently proceeding