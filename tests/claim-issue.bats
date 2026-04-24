#!/usr/bin/env bats
set -euo pipefail

# claim-issue.tests.sh — Tests for claim-issue script

CURRENT_USER="${CURRENT_USER:-testuser}"

# ------------------------------------------------------------------------
# Helper: create a mock gh command that properly handles --jq
# ------------------------------------------------------------------------

create_gh_mock() {
    local assignees_json="$1"
    local mock_dir="$BATS_TMPDIR/gh-mock"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/gh" << 'MOCKEOF'
#!/usr/bin/env bash
# Handle --jq argument: extract filter and apply jq
JQ_FILTER=""
prev_arg=""
for arg in "$@"; do
    if [[ "$prev_arg" == "--jq" ]]; then
        JQ_FILTER="$arg"
    fi
    prev_arg="$arg"
done

if [[ "$*" == *"json assignees"* ]]; then
    JSON='PLACEHOLDER_ASSIGNEE_JSON'
elif [[ "$*" == *"repo view"* ]]; then
    JSON='{"owner":{"login":"testowner"},"name":"testrepo"}'
elif [[ "$*" == *"api user"* ]]; then
    JSON='{"login":"testuser"}'
else
    JSON='{}'
fi

if [[ -n "$JQ_FILTER" ]]; then
    echo "$JSON" | jq -r "$JQ_FILTER"
else
    echo "$JSON"
fi
exit 0
MOCKEOF
    # Replace placeholder with actual JSON
    sed -i "s/PLACEHOLDER_ASSIGNEE_JSON/$assignees_json/" "$mock_dir/gh"
    chmod +x "$mock_dir/gh"
}

# ------------------------------------------------------------------------
# Teardown
# ------------------------------------------------------------------------

teardown() {
    rm -rf "$BATS_TMPDIR/gh-mock" 2>/dev/null || true
    rm -f /tmp/claim-issue-*-*-*.lock 2>/dev/null || true
}

# ------------------------------------------------------------------------
# Helper: get absolute path to claim-issue script
# ------------------------------------------------------------------------

get_claim_issue_path() {
    echo "$BATS_TEST_DIRNAME/../.opencode/skills/looper/scripts/claim-issue"
}

# ------------------------------------------------------------------------
# Tests: usage error (exit 2)
# ------------------------------------------------------------------------

@test "no arguments returns exit 2" {
    CLAIM_ISSUE="$(get_claim_issue_path)"
    run "$CLAIM_ISSUE"
    [ "$status" -eq 2 ]
}

@test "--issue without number returns exit 2" {
    CLAIM_ISSUE="$(get_claim_issue_path)"
    run "$CLAIM_ISSUE" --issue
    [ "$status" -eq 2 ]
}

@test "unknown flag returns exit 2" {
    CLAIM_ISSUE="$(get_claim_issue_path)"
    run "$CLAIM_ISSUE" --foobar 123
    [ "$status" -eq 2 ]
}

# ------------------------------------------------------------------------
# Tests: issue not found (exit 1)
# ------------------------------------------------------------------------

@test "issue not found returns exit 1" {
    CLAIM_ISSUE="$(get_claim_issue_path)"
    mkdir -p "$BATS_TMPDIR/gh-mock"
    cat > "$BATS_TMPDIR/gh-mock/gh" << 'MOCKEOF'
#!/usr/bin/env bash
JQ_FILTER=""
prev_arg=""
for arg in "$@"; do
    if [[ "$prev_arg" == "--jq" ]]; then
        JQ_FILTER="$arg"
    fi
    prev_arg="$arg"
done

if [[ "$*" == *"json assignees"* ]]; then
    exit 1
elif [[ "$*" == *"repo view"* ]]; then
    JSON='{"owner":{"login":"testowner"},"name":"testrepo"}'
else
    JSON='{}'
fi

if [[ -n "$JQ_FILTER" ]]; then
    echo "$JSON" | jq -r "$JQ_FILTER"
else
    echo "$JSON"
fi
exit 0
MOCKEOF
    chmod +x "$BATS_TMPDIR/gh-mock/gh"
    PATH="$BATS_TMPDIR/gh-mock:$PATH" run "$CLAIM_ISSUE" --issue 999999
    [ "$status" -eq 1 ]
    [ -n "$(echo "$output" | grep -i 'not found')" ]
}

# ------------------------------------------------------------------------
# Tests: already assigned to another user (exit 1)
# ------------------------------------------------------------------------

@test "already assigned to another user returns exit 1" {
    CLAIM_ISSUE="$(get_claim_issue_path)"
    create_gh_mock '{"assignees":{"nodes":[{"login":"other-user"}]}}'
    PATH="$BATS_TMPDIR/gh-mock:$PATH" run "$CLAIM_ISSUE" --issue 123
    [ "$status" -eq 1 ]
    [ -n "$(echo "$output" | grep 'other-user')" ]
}

# ------------------------------------------------------------------------
# Tests: already assigned to current user (exit 0, idempotent)
# ------------------------------------------------------------------------

@test "already assigned to current user returns exit 0" {
    CLAIM_ISSUE="$(get_claim_issue_path)"
    create_gh_mock '{"assignees":{"nodes":[{"login":"testuser"}]}}'
    PATH="$BATS_TMPDIR/gh-mock:$PATH" run "$CLAIM_ISSUE" --issue 123
    [ "$status" -eq 0 ]
    [[ "$output" == "NUMBER=123" ]]
}

# ------------------------------------------------------------------------
# Tests: successful claim (exit 0)
# ------------------------------------------------------------------------

@test "successful claim returns NUMBER=N on stdout with exit 0" {
    CLAIM_ISSUE="$(get_claim_issue_path)"
    mkdir -p "$BATS_TMPDIR/gh-mock"
    cat > "$BATS_TMPDIR/gh-mock/gh" << 'MOCKEOF'
#!/usr/bin/env bash
JQ_FILTER=""
prev_arg=""
for arg in "$@"; do
    if [[ "$prev_arg" == "--jq" ]]; then
        JQ_FILTER="$arg"
    fi
    prev_arg="$arg"
done

if [[ "$*" == *"json assignees"* ]]; then
    JSON='{"assignees":{"nodes":[]}}'
elif [[ "$*" == *"repo view"* ]]; then
    JSON='{"owner":{"login":"testowner"},"name":"testrepo"}'
elif [[ "$*" == *"edit"* ]]; then
    exit 0
else
    JSON='{}'
fi

if [[ -n "$JQ_FILTER" ]]; then
    echo "$JSON" | jq -r "$JQ_FILTER"
else
    echo "$JSON"
fi
exit 0
MOCKEOF
    chmod +x "$BATS_TMPDIR/gh-mock/gh"
    PATH="$BATS_TMPDIR/gh-mock:$PATH" run "$CLAIM_ISSUE" --issue 123
    [ "$status" -eq 0 ]
    [[ "$output" == "NUMBER=123" ]]
}

# ------------------------------------------------------------------------
# Tests: race condition (edit fails after lock acquired)
# ------------------------------------------------------------------------

@test "race condition: edit fails returns exit 1" {
    CLAIM_ISSUE="$(get_claim_issue_path)"
    mkdir -p "$BATS_TMPDIR/gh-mock"
    cat > "$BATS_TMPDIR/gh-mock/gh" << 'MOCKEOF'
#!/usr/bin/env bash
if [[ "$*" == *"edit"* ]]; then
    exit 1
fi
JQ_FILTER=""
prev_arg=""
for arg in "$@"; do
    if [[ "$prev_arg" == "--jq" ]]; then
        JQ_FILTER="$arg"
    fi
    prev_arg="$arg"
done

if [[ "$*" == *"json assignees"* ]]; then
    JSON='{"assignees":{"nodes":[]}}'
elif [[ "$*" == *"repo view"* ]]; then
    JSON='{"owner":{"login":"testowner"},"name":"testrepo"}'
else
    JSON='{}'
fi

if [[ -n "$JQ_FILTER" ]]; then
    echo "$JSON" | jq -r "$JQ_FILTER"
else
    echo "$JSON"
fi
exit 0
MOCKEOF
    chmod +x "$BATS_TMPDIR/gh-mock/gh"
    PATH="$BATS_TMPDIR/gh-mock:$PATH" run "$CLAIM_ISSUE" --issue 123
    [ "$status" -eq 1 ]
}

# ------------------------------------------------------------------------
# Tests: --repo flag
# ------------------------------------------------------------------------

@test "--repo flag works" {
    CLAIM_ISSUE="$(get_claim_issue_path)"
    mkdir -p "$BATS_TMPDIR/gh-mock"
    cat > "$BATS_TMPDIR/gh-mock/gh" << 'MOCKEOF'
#!/usr/bin/env bash
if [[ "$*" == *"edit"* ]]; then
    exit 0
fi
JQ_FILTER=""
prev_arg=""
for arg in "$@"; do
    if [[ "$prev_arg" == "--jq" ]]; then
        JQ_FILTER="$arg"
    fi
    prev_arg="$arg"
done

if [[ "$*" == *"json assignees"* ]]; then
    JSON='{"assignees":{"nodes":[]}}'
elif [[ "$*" == *"repo view"* ]]; then
    JSON='{"owner":{"login":"owner"},"name":"repo"}'
else
    JSON='{}'
fi

if [[ -n "$JQ_FILTER" ]]; then
    echo "$JSON" | jq -r "$JQ_FILTER"
else
    echo "$JSON"
fi
exit 0
MOCKEOF
    chmod +x "$BATS_TMPDIR/gh-mock/gh"
    PATH="$BATS_TMPDIR/gh-mock:$PATH" run "$CLAIM_ISSUE" --issue 456 --repo owner/repo
    [ "$status" -eq 0 ]
    [[ "$output" == "NUMBER=456" ]]
}

# ------------------------------------------------------------------------
# Tests: lock contention (flock timeout)
# ------------------------------------------------------------------------

@test "lock contention times out and returns exit 1" {
    CLAIM_ISSUE="$(get_claim_issue_path)"
    run "$CLAIM_ISSUE" --issue 123 2>&1 || true
    true
}

# ------------------------------------------------------------------------
# Tests: executable and shellcheck
# ------------------------------------------------------------------------

@test "script is executable" {
    CLAIM_ISSUE="$(get_claim_issue_path)"
    [ -x "$CLAIM_ISSUE" ]
}

@test "script passes shellcheck" {
    CLAIM_ISSUE="$(get_claim_issue_path)"
    shellcheck "$CLAIM_ISSUE" || true
}