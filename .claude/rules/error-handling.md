---
paths:
  - "VultisigApp/**/*.swift"
---

# Error Handling Rules

- Use async/await with do/catch — never use completion handlers
- Never silently swallow errors — always log or propagate
- Use typed errors (enums conforming to `Error`) where appropriate
- Log errors with `Logger.error()` (OSLog), never `print()`
- Use `guard` + `throw` for precondition failures
- Prefer `Result` type for functions that can fail in expected ways
- Network errors: use the HTTPClient error handling pattern (see networking-guide skill)
- Show user-facing errors via appropriate UI (alerts, inline messages)
- Never use `try!` in production code — use `try?` only when the failure case is truly ignorable
