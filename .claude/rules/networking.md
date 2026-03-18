---
paths:
  - "VultisigApp/**/Core/Services/**/*.swift"
  - "VultisigApp/**/Core/Networking/**/*.swift"
  - "VultisigApp/**/Features/*/Services/**/*.swift"
  - "VultisigApp/**/Blockchain/**/*.swift"
---

# Networking Rules

- Use `TargetType` protocol for all API endpoint definitions
- Use `HTTPClient` with async/await for all network calls
- Never use callbacks or completion handlers — always async/await
