---
paths:
  - "VultisigApp/**/*.swift"
---

# Architecture Rules

- **MVVM pattern**: Views observe ViewModels, ViewModels call Services
- **Business logic** belongs in ViewModels and Services — never in Views
- **Views** are purely declarative UI — no networking, no business logic, no direct data access
- **Service injection**: pass services to ViewModels via initializer, not global singletons
- **Never import UIKit** in SwiftUI views unless absolutely necessary (e.g., platform bridging)
- **One ViewModel per screen** — shared state goes in Services or Stores
- **Navigation**: use NavigationRouter and Route enums, not ad-hoc navigation
- **Models**: SwiftData `@Model` classes stay in `Model/`, value types for cross-boundary passing
- **Feature organization**: group related files (View, ViewModel, Models) by feature when possible
