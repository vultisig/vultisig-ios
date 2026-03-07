---
name: resolve-pr-comments
description: Address CodeRabbit or other AI reviewer comments on a PR to make it merge-ready.
disable-model-invocation: true
---

# Resolve PR Review Comments

## Usage
Provide the PR link or number.

## Workflow

### 1. Fetch Review Comments
Use GitHub MCP `pull_request_read` with method `get_review_comments`. Focus on `IsResolved: false`.

### 2. Evaluate Critically
AI reviewers can be wrong. Before implementing:
- **Verify the claim** — does the code actually have the issue?
- **Question severity** — "critical" labels are often overstated
- **Check if code works** — suggestion may be based on misunderstanding
- **Ask the user** for questionable or significant changes

### 3. Address Valid Comments
Implement fixes. Skip invalid suggestions.

### 4. Run Checks
```bash
swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/
```

### 5. Push
```bash
git add -A && git commit -m "address review comments" && git push
```

### 6. Resolve Threads
Resolve all addressed threads using the GraphQL API:
```bash
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "THREAD_ID"}) { thread { isResolved } } }'
```

To get thread IDs, query unresolved threads:
```bash
gh api graphql -f query='{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 50) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes { path line body }
          }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | {id, path: .comments.nodes[0].path, line: .comments.nodes[0].line}'
```

Resolve all threads — both fixed and intentionally skipped (with valid reason).

## Goal
- All threads resolved, all checks pass, PR merge-ready
