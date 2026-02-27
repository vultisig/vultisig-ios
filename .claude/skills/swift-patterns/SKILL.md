---
name: swift-patterns
description: State management, navigation, code style, naming conventions, common patterns, testing, and build commands.
user-invocable: false
---

# Swift Patterns & Conventions

## State Management

### App-Level State

Singletons injected via `environmentObject` from `VultisigApp.swift`:

```swift
@EnvironmentObject var appViewModel: AppViewModel
@EnvironmentObject var homeViewModel: HomeViewModel
@EnvironmentObject var settingsViewModel: SettingsViewModel
```

### Feature ViewModels

```swift
class MyFeatureViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var error: String?

    func loadItems() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await service.getItems()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

### Local State

```swift
@State private var showSheet = false
@State private var selectedItem: Item?
```

---

## Navigation

### Route Definition

```swift
enum MyFeatureRoute: Hashable {
    case list
    case detail(item: Item)
    case edit(item: Item)
}
```

### Router Implementation

```swift
struct MyFeatureRouter {
    @ViewBuilder
    func build(_ route: MyFeatureRoute) -> some View {
        switch route {
        case .list: MyListView()
        case .detail(let item): MyDetailView(item: item)
        case .edit(let item): MyEditView(item: item)
        }
    }
}
```

### Navigation Usage

```swift
@Environment(\.router) var router
router.navigate(to: MyFeatureRoute.detail(item: item))
router.navigateBack()
router.replace(to: MyFeatureRoute.list)
```

Register in `ContentView.swift`:
```swift
.navigationDestination(for: MyFeatureRoute.self) { route in
    router.myFeatureRouter.build(route)
}
```

---

## Code Style

### Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Screens | `*Screen.swift` | `HomeScreen.swift`, `VaultSettingsScreen.swift` |
| Components | `*View.swift` | `VaultCellView.swift` |
| ViewModels | `*ViewModel.swift` | `HomeViewModel.swift` |
| Services | `*Service.swift` | `THORChainAPIService.swift` |
| API Endpoints | `*API.swift` | `THORChainAPI.swift` |
| Routes | `*Route.swift` | `HomeRoute.swift` |
| Routers | `*Router.swift` | `HomeRouter.swift` |
| Models | Descriptive name | `THORChainPoolResponse.swift` |
| Errors | `*Error.swift` | `THORChainAPIError.swift` |

### Swift Conventions

- Use `Codable` for all API models
- Prefer `struct` over `class` unless reference semantics needed
- Use protocol-based dependency injection
- Prefer throwing functions over `Result` type

---

## Common Patterns

### Async Data Loading

```swift
struct MyView: View {
    @State private var data: [Item] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading { ProgressView() }
            else { List(data) { item in ItemRow(item: item) } }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        defer { isLoading = false }
        do { data = try await service.getData() }
        catch { /* handle error */ }
    }
}
```

### Caching

```swift
actor MyCache {
    private var cachedData: [Item]?
    private var lastFetch: Date?
    private let cacheDuration: TimeInterval = 300

    func getCachedData() -> [Item]? {
        guard let data = cachedData, let lastFetch,
              Date().timeIntervalSince(lastFetch) < cacheDuration
        else { return nil }
        return data
    }

    func cacheData(_ data: [Item]) {
        cachedData = data
        lastFetch = Date()
    }
}
```

**Reference:** `Services/THORChainAPI/THORChainAPICache.swift`

---

## Testing

- Unit tests for Services and ViewModels
- Use protocol-based DI to inject mock HTTPClient
- Test files mirror source structure in test target

## Build Commands

```bash
# Build
xcodebuild -project VultisigApp/VultisigApp.xcodeproj -scheme VultisigApp -sdk iphonesimulator build

# Run tests
xcodebuild -project VultisigApp/VultisigApp.xcodeproj -scheme VultisigApp -sdk iphonesimulator test
```
