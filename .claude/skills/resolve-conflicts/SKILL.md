---
name: resolve-conflicts
description: Resolve git merge conflicts, especially in project.pbxproj. Keeps both sides and maintains sorted order.
---

# Resolve Conflicts

## Overview

Resolves git merge conflicts in the current branch. Handles `project.pbxproj` conflicts (the most common case) as well as Swift source files and localization files.

## Usage

```
/resolve-conflicts              # resolve all conflicting files
/resolve-conflicts project.pbxproj   # resolve a specific file
```

## Workflow

### Step 1 — Identify Conflicts

```bash
git diff --name-only --diff-filter=U
```

List all unmerged files and categorize them:

| File type | Resolution strategy |
|---|---|
| `project.pbxproj` | Keep both sides, re-sort by hex ID prefix |
| `Localizable.strings` | Keep both sides, re-sort alphabetically |
| `.swift` source files | Analyze semantically — keep both changes if independent, ask user if they conflict |
| Other files | Show both sides, ask user which to keep |

### Step 2 — Resolve Each File

#### project.pbxproj Conflicts

pbxproj conflicts are almost always "both sides added different lines in the same section." The resolution is always: **keep both sides**.

1. Read the file and find all conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
2. For each conflict region, keep ALL lines from both HEAD and the incoming branch (remove only the markers)
3. After resolving, verify the entries are sorted by their hex ID prefix within each section:
   - `PBXBuildFile` section: sorted by the hex ID at the start of each line
   - `PBXFileReference` section: sorted by the hex ID at the start of each line
4. Verify no duplicate entries exist

Use the Edit tool to resolve (the protect-files hook allows pbxproj edits when the file has unmerged status).

#### Localizable.strings Conflicts

1. Keep both sides of each conflict
2. Remove duplicate keys (if both sides added the same key, keep one)
3. Ensure alphabetical order by key
4. Run `python3 scripts/sort_localizable.py` after resolving

#### Swift Source Conflicts

1. Read the full file to understand context
2. If both sides made independent changes (different functions, different areas): keep both
3. If both sides modified the same code: present both versions and ask the user which to keep
4. Run SwiftLint after resolving

### Step 3 — Mark Resolution

After resolving each file:

```bash
git add {resolved-file}
```

### Step 4 — Verify

After all files are resolved:

```bash
# Verify no remaining conflicts
git diff --name-only --diff-filter=U

# For pbxproj — verify it parses correctly
plutil -lint VultisigApp/VultisigApp.xcodeproj/project.pbxproj
```

### Step 5 — Complete the Merge

```bash
git commit --no-edit
```

## pbxproj Sorting Rules

Entries in pbxproj are sorted by their hex UUID prefix. When keeping both sides of a conflict, interleave the entries to maintain sort order:

```
/* Example: HEAD adds 83..., incoming adds 84... */
/* Correct order: 83 before 84 */
    834B4865... /* from HEAD */
    84EDDEF7... /* from incoming */
    8540533A... /* from HEAD */
```

Compare the hex prefixes lexicographically (string comparison, not numeric).

## Rules
- Always keep both sides of pbxproj conflicts — never discard entries
- Verify with `plutil -lint` after resolving pbxproj
- Never force-push after resolving
- If a Swift conflict is ambiguous, always ask the user
- Run SwiftLint on resolved Swift files
