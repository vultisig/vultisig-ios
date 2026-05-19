---
paths:
  - "VultisigApp/**/*.swift"
---

# Code Quality Rules

- Validate after every change: `swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/`
- Write readable code — prefer clear naming over comments
- No dead code: remove unused functions, variables, imports
- No commented-out code blocks
- No GitHub issue / PR mentions in code comments (`#1234`, `vultisig-ios#1234`, `See PR #...`). Issue context belongs in the commit message and PR description; comments must explain *why* the code is the way it is. Issue numbers rot when issues get closed, renumbered, or moved across repos.
- No force unwraps (`!`) except in tests or when provably safe
- Prefer `guard` for early returns over nested `if let`
- Keep functions focused — one responsibility per function
- Use `private` access control by default, widen only when needed
