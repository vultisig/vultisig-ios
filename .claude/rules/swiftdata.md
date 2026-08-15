---
paths:
  - "VultisigApp/**/Model/**/*.swift"
---

# SwiftData Rules

- Never access `@Model` classes off MainActor
- Use value types (structs) to pass data across actor boundaries
- Follow the three-phase architecture: load -> transform -> save
- `@Transient` properties are **not observation-tracked**. Writing one publishes nothing to SwiftUI, even when the value genuinely changes, so a view reading it (or anything derived from it) never re-renders — it will *appear* to work whenever a neighbouring `Storage.shared.save()` happens to re-render the tree, which is an accident, not a mechanism. A plain `@Transient` is only safe for state that no view body ever reads. Otherwise hold the value on an `ObservedTransient` box (`Core/Models/ObservedTransient.swift`) behind a computed property of the same name, and cover it with a `withObservationTracking` test that asserts the write is *published*, not just stored.
