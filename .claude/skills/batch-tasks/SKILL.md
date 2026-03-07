---
name: batch-tasks
description: Run multiple tasks overnight as parallel PRs. Produces a PRD per task, selects skills/rules, spawns isolated agents, and reports PR links.
---

# Batch — Overnight Task Runner

## Overview

Orchestrates multiple independent tasks in parallel. Each task gets its own branch, isolated worktree, and PR. Designed for overnight/async workflows where the user reviews results later. Integrates with CodeRabbit for automated PR review.

## Usage

```
/batch-tasks
1. #42
2. Fix balance rounding on SendScreen
3. #108 (after #1)
4. https://github.com/vultisig/vultisig-ios/issues/55 (after #1, #3)
```

Or just invoke `/batch-tasks` without tasks and you'll be prompted for the task list.

## Input

The user provides a numbered list of tasks. Each task can be:
- **A GitHub issue** — `#123` or a full URL like `https://github.com/vultisig/vultisig-ios/issues/123`
- **Plain text** — a short description of work to be done
- **Mixed** — combine both formats freely

### Dependency Syntax

Tasks can declare dependencies using `(after #N)` where N is the task number in the list:

```
/batch-tasks
1. #42
2. #108 (after #1)
3. Fix balance rounding on SendScreen
4. https://github.com/vultisig/vultisig-ios/issues/55 (after #1, #3)
```

- `(after #1)` — task 2 waits for task 1 to complete and branches from task 1's branch instead of `main`
- `(after #1, #3)` — task 4 waits for both task 1 and 3; branches from the last dependency's branch
- Tasks without `(after ...)` are independent and run in parallel from `main`

If the user invokes `/batch-tasks` without tasks, ask them to provide the task list.

## Phase 0 — Issue Fetching

Before triaging, resolve all GitHub issue references. For each `#N` or issue URL, run:

```bash
gh issue view {N} --json title,body,labels,assignees
```

Extract from the response:
- **Title** — becomes the task title
- **Body** — provides requirements, context, and acceptance criteria for the PRD
- **Labels** — help with skill/rule selection (e.g. `bug`, `enhancement`, `ui`, `blockchain`)

If an issue cannot be fetched (not found, permissions), flag it in the PRD output and ask the user for clarification.

For plain-text tasks, skip this phase — use the description as-is.

### Label-to-Skill Hints

Use issue labels as additional signal for skill selection:

| Label contains... | Suggests skill |
|---|---|
| `ui`, `design`, `view` | `ui-components` |
| `network`, `api`, `service` | `networking-guide` |
| `model`, `data`, `storage` | `swiftdata-guide` |
| `chain`, `blockchain`, `keygen`, `keysign` | `blockchain-guide` |
| `bug`, `fix`, `refactor`, `enhancement` | `swift-patterns` |

## Phase 1 — Triage & PRD Generation

For each task, produce a PRD block. Research the codebase BEFORE generating PRDs — use Glob, Grep, and Read to find relevant files so the PRD is grounded in real code.

### Complexity Assessment

Evaluate each task and assign a complexity level:

| Complexity | Criteria | Action |
|---|---|---|
| **Simple** | 1-2 files, clear scope, no architectural decisions | Proceed normally |
| **Moderate** | 3-5 files, some design choices, clear pattern to follow | Proceed with detailed approach |
| **Complex** | 6+ files, architectural decisions, cross-cutting concerns, ambiguous requirements | Warn the user — suggest splitting or clarifying before approval |

### PRD Format

Present all PRDs in a single message for approval:

```
## Task {n}: {title}
- **Issue**: #{N} (if from GitHub, otherwise "N/A")
- **Complexity**: {Simple | Moderate | Complex} — {one-line justification}
- **Dependencies**: {none | "after Task #X" with explanation}
- **Branch**: `{type}/{issue-number}-{slugified-title}` if from issue, else `{type}/{kebab-case-name}` (max 50 chars). Type is `fix` for bugs, `feat` for features/enhancements, `refactor` for refactors, `chore` for maintenance. Default to `fix` if unclear.
- **Skills**: {comma-separated skill names to load}
- **CLAUDE.md Rules**: {rule numbers that apply, e.g. #1, #6, #9}
- **Key Files**: {files to read/modify, workspace-relative paths}
- **Approach**: {2-4 sentences describing the implementation strategy}
- **Acceptance Criteria**:
  - {criterion 1}
  - {criterion 2}
  - SwiftLint passes with no new warnings
```

If any task is **Complex**, add a warning block:

```
⚠️ Complex Tasks Detected:
- Task {n}: {reason why it's complex and suggestion to split or clarify}
```

### Skill Selection Guide

Choose from these based on task nature:

| Task involves... | Load skill |
|---|---|
| UI changes, colors, fonts, buttons, screens | `ui-components` |
| State management, ViewModels, navigation, code style | `swift-patterns` |
| API calls, networking, services | `networking-guide` |
| SwiftData models, Storage, persistence | `swiftdata-guide` |
| Blockchain logic, chains, TSS, keygen/keysign | `blockchain-guide` |

### Rule Selection Guide

Always include **#9 (SwiftLint)**. Then add relevant rules:

| Task involves... | Include rules |
|---|---|
| Any UI work | #1 (Design System), #6 (deprecated APIs) |
| User-facing text | #4 (Localization) |
| Buttons | #5 (PrimaryButton) |
| Full screens | #8 (Screen component) |
| Data models | #2 (SwiftData MainActor) |
| Networking | #3 (TargetType + HTTPClient), #7 (async/await) |
| Platform support | #10 (Cross-platform) |
| Architecture changes | #11 (Business logic in ViewModels) |

## Phase 2 — Approval

After presenting all PRDs, ask the user to approve or adjust. Use AskUserQuestion with options:
- "Approve all — start execution"
- "I want to adjust some tasks"

Do NOT proceed to Phase 3 until the user explicitly approves.

## Phase 3 — Parallel Execution

### Execution Order

1. **Independent tasks** (no dependencies) — spawn ALL in parallel in a single message
2. **Dependent tasks** — wait for their dependency to complete, then spawn them (using the dependency's branch as base)

For each task, spawn an Agent with:
- `subagent_type: "general-purpose"`
- `isolation: "worktree"`
- `run_in_background: true`

### Agent Prompt Template

Use this template for each agent's prompt, filling in the PRD values:

```
You are implementing a task for the Vultisig iOS app.

## Task
{task title}

{If from GitHub issue, include the full issue body here for context}

## Branch
Create branch: `{branch-name}` from `{base-branch}`
{base-branch is "main" for independent tasks, or the dependency's branch name for dependent tasks}

## Skills to Load
Load these skills before starting work (use the Skill tool):
{for each skill: - Load skill: `{skill-name}`}

## CLAUDE.md Rules to Follow
Pay special attention to these rules from CLAUDE.md:
{for each rule: - Rule #{n}: {brief description}}

## Key Files
Read these files first to understand the context:
{for each file: - `{file-path}`}

## Implementation Plan
{approach from PRD}

## Acceptance Criteria
{criteria from PRD}

## Workflow

### Step 1 — Setup
1. Load the skills listed above using the Skill tool
2. Read all key files to understand the current code
3. Create the branch: `git checkout {base-branch} && git pull && git checkout -b {branch-name}`

### Step 2 — Implement
4. Implement the changes following the plan and rules
5. Follow all CLAUDE.md rules strictly

### Step 3 — Quality Checks
6. Run SwiftLint: `swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/`
7. Fix any SwiftLint warnings you introduced
8. Run build check: `xcodebuild build -scheme VultisigApp -destination 'platform=iOS Simulator,name=iPhone 16' -skipMacroValidation -skipPackagePluginValidation 2>&1 | tail -20`
9. Fix any build errors (if build fails, prioritize fixing compile errors over creating the PR)

### Step 4 — Self-Review
10. Review your own changes by running: `git diff {base-branch}...HEAD`
11. Check the diff against each applicable CLAUDE.md rule:
    - Are there hardcoded colors/fonts? (Rule #1)
    - Any @Model access off MainActor? (Rule #2)
    - Hardcoded user-facing strings? (Rule #4)
    - Custom button styles instead of PrimaryButton? (Rule #5)
    - .foregroundColor() instead of .foregroundStyle()? (Rule #6)
    - Completion handlers instead of async/await? (Rule #7)
    - Any new SwiftLint warnings? (Rule #9)
12. Check for: dead code, unused imports, missing error handling, force unwraps
13. Fix any issues found in self-review before proceeding

### Step 5 — Commit & Push
14. Stage and commit changes with a clear message
15. Push: `git push -u origin {branch-name}`

### Step 6 — Create PR
16. Create a pull request (NOT draft):

gh pr create --title "{pr-title}" --body "$(cat <<'PREOF'
## Summary
{2-3 bullet points of what was done}

## Issue
{If from GitHub issue: "Closes #{N}" — otherwise omit this section}

## Changes
{List each file changed with a one-line description of what changed}

## CLAUDE.md Rules Applied
{list rules that were followed}

## Skills Used
{list skills that were loaded}

## Self-Review Checklist
- [x] No hardcoded colors/fonts — using Theme.colors.* and Theme.fonts.*
- [x] No hardcoded strings — using .localized
- [x] SwiftLint passes with no new warnings
- [x] Build succeeds
- [x] No .foregroundColor() — using .foregroundStyle()
- [x] async/await used — no completion handlers
{only include checklist items relevant to the rules applied}

## Test Plan
- [ ] Manual testing: {specific steps to verify the change}
{additional acceptance criteria as checkboxes}

Co-Authored-By: Claude <noreply@anthropic.com>
PREOF
)"

### CRITICAL — Branch & PR are Required
You MUST complete Steps 5 and 6. The task is NOT done until the branch is pushed and the PR is created. Do not stop after implementation — always push and create the PR.

### Error Handling
- If SwiftLint fails and you cannot fix the warnings, still create the PR but note the warnings in the PR body under a "Known Issues" section
- If the build fails and you cannot fix it, still create the PR but mark it as draft (`--draft` flag) and add a "Build Issues" section to the PR body explaining the errors
- If any step fails catastrophically (cannot checkout, cannot push), output a clear error message with the step that failed and the error details
```

## Phase 4 — Reporting

After ALL agents complete (including dependent tasks that run after their dependencies), present a summary table:

```
## Batch Complete

| # | Task | Complexity | Branch | PR | Build | Lint | Status |
|---|------|------------|--------|----|-------|------|--------|
| 1 | {title} | {S/M/C} | `{branch}` | {PR URL} | pass/fail | pass/fail | pass/fail |
| 2 | ... | ... | ... | ... | ... | ... | ... |

### Next Steps
- CodeRabbit will review each PR automatically
- Run `/batch-review` to see a summary of all PR statuses and CodeRabbit feedback
- Run `/batch-fix-reviews` to auto-fix CodeRabbit issues across all batch PRs
- Run `/batch-retry 2, 4` to retry any failed tasks
```

If any task failed, include the error summary below the table:

```
### Failures
- **Task {n}**: {error summary — which step failed and why}
```

## Rules
- Create real PRs (not draft) unless the build fails
- Never merge PRs
- Never force-push
- Each task gets its own isolated worktree — no conflicts between tasks
- Always run SwiftLint AND build check before creating the PR
- Always self-review the diff before creating the PR
- If a task is unclear, include a clarifying question in the PRD (Phase 1) rather than guessing
- Base independent branches on `main`, dependent branches on their dependency's branch
- Include full file change list in PR body for easier review
