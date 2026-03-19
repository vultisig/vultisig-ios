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
- **Models**: Core SwiftData `@Model` classes stay in `Model/`, feature-specific models in `Features/<Name>/Models/`, value types for cross-boundary passing
- **Feature organization**: each feature lives in `Features/<Name>/` with `Views/`, `ViewModels/`, `Services/`, `Models/` subdirectories. Shared infrastructure lives in `Core/`. Chain-specific code lives in `Blockchain/`.
- **Cross-platform**: use `#if os(iOS)` / `#if os(macOS)` blocks in main files. Native UIKit/AppKit code lives in `Core/Platform/iOS/` and `Core/Platform/macOS/`
