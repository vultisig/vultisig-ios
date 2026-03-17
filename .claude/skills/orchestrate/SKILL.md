---
name: orchestrate
description: God-mode orchestrator. Takes a GitHub issue or PR and handles the ENTIRE workflow end-to-end — branch creation, implementation, testing, commits, PR creation, OR exhaustive PR review with parallel agents. Use for complete feature delivery or deep PR audits.
argument-hint: "[issue-number or PR branch/URL] [--review] [--auto]"
disable-model-invocation: true
---

# Orchestrator: End-to-End Workflow

Two operating modes:

## Mode A — Feature Delivery (default)
Takes a GitHub issue and handles the entire pipeline:
1. Fetch and understand the issue
2. Create a git branch
3. Plan implementation
4. Implement across all files with maximum parallelism
5. Build-review-fix loop until clean
6. Commit, push, create PR

## Mode B — PR Review (`--review`)
Takes a PR branch name or URL and performs an exhaustive audit:
1. Fetch all commits and changed files
2. Spawn parallel review agents across every domain
3. Report findings with file:line references and fix suggestions

---

## Parallelization Philosophy

**Use as many parallel agents as needed to complete tasks in the fastest, most efficient, and highest-quality way possible.** Spawn agents aggressively for independent work streams.

### Worker Coordination Protocol

1. **File-based coordination** — Each agent works on independent files. Never assign two agents to the same file.
2. **Cross-agent synthesis** — The orchestrator reads deliverables and feeds relevant context between agents. Workers never talk directly.
3. **Quality gates with push-back** — No agent's work is marked done until deliverables are reviewed.
4. **Stall detection** — If an agent is stuck, reassess and push with specific unblocking instructions.
5. **Convergence criteria** — When parallel agents start producing overlapping concerns, collapse to sequential.

---

## Step-by-Step: Feature Delivery (Mode A)

### Step 1: Fetch Issue
```bash
gh issue view NUMBER --repo vultisig/vultisig-ios
```
Extract title, description, labels, acceptance criteria.

### Step 2: Git Branch Setup
```bash
git checkout main && git pull
git checkout -b feature/ISSUE-description
```

### Step 3: Plan Implementation
1. Understand requirements and acceptance criteria
2. Map architecture: which files/modules are affected
3. Identify dependencies between files
4. Create parallelization strategy
5. Present to user (unless `--auto`)

### Step 4: Implement (PARALLEL where possible)
Split implementation across independent modules/files:
- Agent A: Core logic (ViewModels, Services)
- Agent B: UI components (Views)
- Agent C: Localization (all 7 Localizable.strings files)
- Agent D: Tests

Follow ALL `.claude/rules/` strictly.

### Step 5: Build-Review-Fix Loop

**Persistent loop — do NOT stop until ALL gates pass:**

```
while true:
  1. Run swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/
  2. If fails → fix issues, go to 1
  3. Run xcodebuild (if available)
  4. If fails → fix issues, go to 1
  5. All gates pass → break
```

### Step 6: Commit
```bash
git add <specific-files>
git commit -m "$(cat <<'EOF'
feat(scope): imperative description

- Detail 1
- Detail 2

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 7: Push + Create PR
```bash
git push -u origin $(git branch --show-current)
gh pr create --title "feat(scope): description" --body "$(cat <<'EOF'
## Summary
- What and why

## Test Plan
- [ ] SwiftLint passes
- [ ] Build succeeds
- [ ] Manual verification

## Related
- Closes #ISSUE_NUMBER

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)" --draft
```

---

## PR Review (Mode B)

### Stage 1 — Gather PR Context (PARALLEL)
- Agent A: Fetch all commits, diff, and changed file list
- Agent B: Read project rules and CLAUDE.md for standards
- Agent C: Identify all domains touched (chain logic, UI, state, etc.)

### Stage 2 — Deep Review (PARALLEL, one agent per domain)
- **Architecture Agent**: MVVM compliance, business logic placement, service injection
- **Code Quality Agent**: DRY violations, dead code, force unwraps, SwiftLint compliance
- **Concurrency Agent**: async/await correctness, MainActor usage, data races
- **UI Agent**: Theme token usage, PrimaryButton, Screen component, .foregroundStyle()
- **Localization Agent**: All 7 files updated, camelCase keys, alphabetical order
- **Security Agent**: Key material exposure, credential leaks, TSS boundary violations

### Stage 3 — Synthesize & Report (SEQUENTIAL)
- Merge findings, deduplicate, prioritize: **critical** > **important** > **nitpick**
- Present report with file:line references

---

## Pre-Submit Gate

- [ ] Issue fetched and understood
- [ ] Branch created from issue
- [ ] Implementation complete
- [ ] SwiftLint passes
- [ ] All `.claude/rules/` satisfied
- [ ] Localization: all 7 files updated and sorted
- [ ] Commit with conventional format + Co-Authored-By
- [ ] PR created as draft
