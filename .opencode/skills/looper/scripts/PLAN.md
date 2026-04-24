# Plan: Clarify looper SKILL.md documentation (issue #5)

## Goal

Fix all 16 clarity/documentation issues identified in the looper skill SKILL.md. No functional changes — only documentation improvements.

## Issues to Fix

### 1. $ARGUMENTS never documented
Add a **"Variables" section** near the top of SKILL.md documenting:
- `ARGUMENTS` — task description or issue reference (e.g., `#5`, `https://github.com/owner/repo/issues/5`). Required unless running auto-selection.
- `LOOPER_MAX_ITERATIONS` — environment variable defaulting to 10.
- `LOOPER_DEV_PORT` — derived port (document formula).
- `WORKTREE_DIR` — set by `setup-worktree`, critical side effect.

### 2. Code block unclosed (Lines 18-21)
The triple-backtick block starting at line 17 is never closed. Add closing ``` after line 21.

### 3. cd $WORKTREE_DIR side effect buried
In step 4, add a **WARNING** callout immediately after the `cd "$WORKTREE_DIR"` line:
> **WARNING:** `cd "$WORKTREE_DIR"` changes the working directory. All subsequent steps run inside the worktree. Never commit directly to the default branch.

### 4. eval output contract undocumented
For each `eval "$SYNC_OUTPUT"` (steps 4b, 7), document the expected output contract:
- `STATUS=up-to-date|rebased|conflicts`
- `DEFAULT_BRANCH=<branch-name>`
- Exit codes: 0=clean, 1=conflicts, 2=error

Add a **Security note** that `eval` executes shell output — scripts must be trusted.

### 5. LOOPER_MAX_ITERATIONS not discoverable
Document it in the new Variables section (see #1 above).

### 6. Port formula unexplained
In step 6a, add an inline comment explaining the formula:
```bash
# Derive a deterministic port from task name: hash → modulo 50000 → offset 10000
LOOPER_DEV_PORT=$(( ( $(echo "$TASK_NAME" | cksum | cut -d' ' -f1) % 50000 ) + 10000 ))
```

### 7. Verdict format contract implicit
In step 6e, add a **Verdict extraction** callout documenting:
- Format: `Loop-Verdict: PASS` or `Loop-Verdict: FAIL` in commit subject/body
- Source: most recent commit matching `Loop-Verdict:` pattern
- Tool: `git log --grep="Loop-Verdict:" -1 --format="%B"`

### 8. eval pattern dangerous
Add a **Security** section in the preamble listing all uses of `eval`:
> **eval usage:** Steps 4b and 7 use `eval "$SYNC_OUTPUT"` to apply shell variable assignments from `sync-with-remote`. Only call `eval` on output from trusted scripts in this codebase.

### 9. FETCH_EXIT=2 silently ignored
In step 4c, after the `FETCH_EXIT=2` check, add handling:
```bash
if [ "$FETCH_EXIT" -eq 2 ]; then
    echo "Warning: fetch-issue-context returned exit 2 — continuing without issue context" >&2
fi
```

### 10. Unbounded START_ITERATION
In step 5, add an **upper bound** check:
> `detect-resume` may return iteration numbers above `LOOPER_MAX_ITERATIONS`. If `START_ITERATION > MAX_ITERATIONS`, the loop skips to the verdict step (pass or fail based on existing commits).

Add to step 6 loop header:
```bash
if [ "$START_ITERATION" -gt "$MAX_ITERATIONS" ]; then
    echo "Warning: resume from iteration $START_ITERATION exceeds max $MAX_ITERATIONS" >&2
    START_ITERATION=$(( MAX_ITERATIONS + 1 ))
fi
```

### 11. Protected-branch bypass
In step 4b (sync-with-remote), the script performs a direct rebase. Document the risk and mitigation:
> **Protected branch note:** If the default branch is protected, `git rebase` may fail silently. The script catches this via exit code but does not explicitly check protection status. On protected repos, ensure the loop branch is not itself protected.

### 12. detect-resume underspecified
Add a **"detect-resume contract"** section in step 5:
> **Contract:**
> - Outputs a single integer (start iteration) to stdout
> - Info/debug messages go to stderr
> - Returns 1 = resume from prior iteration, 2 = no prior loop found (start fresh)
> - Recognized phases: `plan`, `do-red`, `do-green`, `do-simplify`, `do-integration`, `check`, `report`

### 13. Pre-check buried inside DO phase
Move pre-check out of step 6d into its own **step 6c (pre-DO check)** and document it as a separate phase gate:
> **Phase gate:** Before spawning the Checker, pre-check runs to validate the worktree state. If it fails, the iteration is marked FAIL without Checker review.

### 14. Phase goals not listed
Add a **"Phase goals"** section after the spawn instructions in step 6d:
> - **PLAN phase:** Understand the task, explore the codebase, produce an actionable plan. Output: git commit with plan.
> - **DO phase:** Implement the plan using TDD (red → green). Output: git commits with implementation.
> - **CHECK phase:** Verify the implementation against the plan. Output: git commit with verdict (PASS/FAIL).

### 15. Conflict resolution no strategy
In step 4b (conflict resolution), add guidance:
> **Conflict resolution strategy:**
> 1. Prioritize the incoming change (the worktree branch) over the base, unless the base contains bug fixes or security patches.
> 2. If conflicts span multiple files, resolve files in dependency order (e.g., shared utilities before consumers).
> 3. After resolving, verify the staged result compiles and tests pass before continuing.
> 4. If conflicts are unsolvable, abort the sync (`git rebase --abort`) and proceed without rebasing (step 4b exit 2 path).

### 16. Step 7 re-sync rationale missing
In step 7, add a header and rationale:
> **Step 7: Sync before PR**
>
> **Rationale:** The worktree may have drifted from the default branch during the loop (e.g., if another PR was merged). Re-syncing ensures the PR is mergeable without conflicts. This is especially important for long-running loops or multi-iteration tasks.

## Files to modify

- `.opencode/skills/looper/SKILL.md` — add all documentation improvements

## Tests

No functional tests needed — this is a documentation-only task. However, after making changes, verify:
1. All code blocks are properly closed (no triple-backtick left open)
2. All `eval` usages are documented with output contracts
3. All shell variables referenced in documentation are defined or link to their source

## Acceptance Criteria

1. Every one of the 16 issues listed in the issue description is addressed in SKILL.md.
2. No code blocks left unclosed.
3. `$ARGUMENTS`, `LOOPER_MAX_ITERATIONS`, `LOOPER_DEV_PORT`, `WORKTREE_DIR` all documented in one place.
4. `eval` usage documented with security note in at least one prominent location.
5. Conflict resolution includes a strategy (not just a checklist of commands).
6. Pre-check is visible as its own phase gate before CHECK.
7. Phase goals are listed explicitly.
8. Step 7 includes rationale for re-syncing.
9. `FETCH_EXIT=2` is handled (warning printed, not silently ignored).
10. `detect-resume` contract is documented.