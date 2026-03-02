---
name: lint
description: Run SwiftLint on the codebase and fix any warnings.
---

# Lint

Run SwiftLint to check code quality and fix all warnings.

## Commands

**Lint entire project:**
```bash
swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/
```

**Lint specific files:**
```bash
swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/VultisigApp/Path/To/File.swift
```

## Workflow

1. Run SwiftLint on changed files
2. Fix all warnings and errors
3. Re-run to confirm zero new warnings
4. Only then consider the task complete

## Current Config Summary

**Config file:** `VultisigApp/.swiftlint.yml`

**Disabled rules (lenient):** line_length, identifier_name, type_body_length, function_body_length, cyclomatic_complexity, force_cast, function_parameter_count, large_tuple, nesting, file_length, type_name, todo, and others.

**Opt-in rules (enforced):**
- `unused_parameter` - Unused function parameters
- `async_without_await` - Async functions with no await
- `empty_string` / `empty_count` - Use `.isEmpty` idiom
- `contains_over_filter_count` / `contains_over_filter_is_empty` / `contains_over_first_not_nil` / `contains_over_range_nil_comparison` - Prefer `.contains()`
- `discouraged_none_name` - Don't use "none" as variable name
- `empty_collection_literal` - Empty collection literals

**Analyzer rules:**
- `unused_declaration` - Unused declarations
- `unused_import` - Unused imports

## Common Warnings & Fixes

| Warning | Fix |
|---------|-----|
| `unused_setter_value` | Use `_ = newValue` or use the parameter |
| `force_unwrapping` | Use optional binding (`if let`, `guard let`) |
| `trailing_whitespace` | Remove trailing spaces |
| `unused_closure_parameter` | Use `_` for unused parameters |
| `unused_parameter` | Use `_` prefix or remove parameter |

## Suppression (use sparingly)

```swift
// Preferred: explicit ignore
set { _ = newValue }

// Last resort: inline comment
// swiftlint:disable:next rule_name
let value = someCode()
```

Never disable rules globally or for entire files without explicit approval.
