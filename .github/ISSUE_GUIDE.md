# Issue Writing Guide

_How to fill the Vultisig issue template so agents AND humans produce great results._

---

## Quick Start

1. Pick a template (Bug Report or Feature Request)
2. Fill all sections with specific details
3. Include device/OS info for bugs
4. Submit

**Time to fill:** 5-10 minutes for a well-scoped issue. If it takes longer, your scope is too big — split it.

---

## Size Guide

| Size | Files Changed | Lines of Code | Example |
|------|--------------|---------------|---------|
| **tiny** | 1 file | <50 lines | Fix a typo, update a constant |
| **small** | 1-3 files | 50-200 lines | Add a function, fix a bug |
| **medium** | 3-8 files | 200-500 lines | New feature with tests |
| **large** | 8+ files | 500+ lines | **SPLIT THIS.** |

---

## Key Rules for This Repo

- **DO NOT** edit `project.pbxproj` directly — use `/add-xcode-files` skill
- **DO NOT** modify TSS/crypto code without explicit review approval
- All user-facing strings must use `.localized` and appear in all 7 locale files
- All colors/fonts must use `Theme.colors.*` / `Theme.fonts.*`
- Run `swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/` to verify

---

## Pre-Submit Checklist

- [ ] Title starts with a verb
- [ ] Size is tiny/small/medium (never large)
- [ ] Affected feature area identified (vault, send, swap, chain)
- [ ] Steps to reproduce included (for bugs)
- [ ] Device and OS version included (for bugs)
