---
paths:
  - "VultisigApp/**/Model/**/*.swift"
---

# SwiftData Rules

- Never access `@Model` classes off MainActor
- Use value types (structs) to pass data across actor boundaries
- Follow the three-phase architecture: load -> transform -> save
