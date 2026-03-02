---
paths:
  - "VultisigApp/**/Services/**/*.swift"
---

# Networking Rules

- Use `TargetType` protocol for all API endpoint definitions
- Use `HTTPClient` with async/await for all network calls
- Never use callbacks or completion handlers — always async/await
