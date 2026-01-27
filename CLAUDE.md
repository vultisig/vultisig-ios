# Vultisig iOS - Claude Guidelines

## Project Overview

Vultisig is a multi-chain cryptocurrency wallet application for iOS and macOS built entirely with SwiftUI. It supports multiple blockchain networks (THORChain, Maya, EVM chains, Cosmos, Solana, UTXO chains, etc.) and features vault-based key management, DeFi integrations, and cross-device signing.

## Architecture

### Directory Structure

```
VultisigApp/
├── DesignSystem/              # Theme, colors, fonts (protocol-based)
│   ├── Theme/                 # Protocols (ThemeProtocol, ColorSystemProtocol, FontSystemProtocol)
│   ├── DefaultTheme/          # Implementations (Theme, ColorSystem, FontSystem)
│   ├── Colors/                # Color initialization with hex parsing
│   └── Fonts/                 # FontStyle enum
├── Services/                  # API clients and business logic
│   ├── Network/               # Core HTTP layer (HTTPClient, TargetType, HTTPError)
│   ├── THORChainAPI/          # THORChain-specific API
│   ├── MayaChainAPI/          # Maya-specific API
│   ├── Evm/                   # EVM chain services
│   ├── Tron/                  # Tron services
│   ├── Cosmos/                # Cosmos services
│   └── [chain]/               # Other chain-specific services
├── Views/
│   └── Components/            # Reusable UI components
│       ├── Buttons/           # PrimaryButton, IconButton, ActionButton
│       ├── TextField/         # CommonTextField, StyledTextField
│       ├── Layout/            # ContainerView, BoxView
│       ├── Navigation Header/ # Header components
│       ├── Sheet/             # Bottom sheets
│       └── ViewModifiers/     # Custom view modifiers
├── Features/                  # Feature-based modules
├── View Models/               # ObservableObject state containers
├── Navigation/                # Routing (NavigationRouter, VultisigRouter, *Route enums)
├── Model/                     # Data models (Codable structs)
├── Stores/                    # Shared data stores
└── Extensions/                # Swift type extensions
```

## API & Networking

### Core Pattern

All networking uses a custom HTTP client built on `URLSession` with Swift concurrency (async/await).

**Key files:**
- `Services/Network/HTTPClient.swift` - URLSession wrapper
- `Services/Network/HTTPClientProtocol.swift` - Protocol for DI
- `Services/Network/TargetType.swift` - Endpoint definition protocol
- `Services/Network/HTTPError.swift` - Error types
- `Services/Network/HTTPMethod.swift` - HTTP methods enum

### Creating API Endpoints

Define endpoints using the `TargetType` protocol:

```swift
// Services/[Feature]/[Feature]API.swift
enum MyFeatureAPI: TargetType {
    case getData(id: String)
    case postData(payload: MyPayload)

    var baseURL: URL {
        URL(string: "https://api.example.com")!
    }

    var path: String {
        switch self {
        case .getData(let id): return "/data/\(id)"
        case .postData: return "/data"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getData: return .get
        case .postData: return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .getData: return .requestPlain
        case .postData(let payload): return .requestCodable(payload, .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        ["X-Client-ID": "vultisig"]
    }
}
```

### Creating Services

Services use constructor injection for testability:

```swift
// Services/[Feature]/[Feature]Service.swift
struct MyFeatureService {
    let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func getData(id: String) async throws -> MyModel {
        let response = try await httpClient.request(
            MyFeatureAPI.getData(id: id),
            responseType: MyModel.self
        )
        return response.data
    }
}
```

### Error Handling

Use domain-specific error enums:

```swift
enum MyFeatureError: Error, LocalizedError {
    case notFound
    case invalidData

    var errorDescription: String? {
        switch self {
        case .notFound: return "Resource not found"
        case .invalidData: return "Invalid data received"
        }
    }
}
```

**Reference files:**
- `Services/THORChainAPI/THORChainAPIService.swift`
- `Services/THORChainAPI/TargetType/THORChainAPI.swift`
- `Services/THORChainAPI/Models/THORChainAPIError.swift`

## UI Components

### Design System Access

Always use the `Theme` enum for colors and fonts:

```swift
// Colors
Theme.colors.bgPrimary           // #02122B - Main background (dark navy)
Theme.colors.bgSurface1          // #061B3A - Card/container background
Theme.colors.bgSurface2          // #11284A - Elevated surface
Theme.colors.bgButtonPrimary     // #33E6BF - Primary button (turquoise)
Theme.colors.bgButtonSecondary   // #061B3A - Secondary button
Theme.colors.bgButtonTertiary    // #2155DF - Tertiary button (blue)
Theme.colors.textPrimary         // #F0F4FC - Primary text (light)
Theme.colors.textSecondary       // #C9D6E8 - Secondary text
Theme.colors.textTertiary        // #8295AE - Tertiary text
Theme.colors.border              // #1B3F73 - Border color
Theme.colors.alertSuccess        // #13C89D - Success (mint green)
Theme.colors.alertError          // #FF5C5C - Error (red)
Theme.colors.alertWarning        // #FFC25C - Warning (orange)
Theme.colors.turquoise           // #33E6BF - Brand turquoise

// Fonts (Brockmann family)
Theme.fonts.heroDisplay          // 72pt - Hero text
Theme.fonts.headline             // 40pt - Headlines
Theme.fonts.title1               // 28pt - Large titles
Theme.fonts.title2               // 22pt - Medium titles
Theme.fonts.title3               // 17pt - Small titles
Theme.fonts.bodyLMedium          // 18pt - Large body
Theme.fonts.bodyMMedium          // 16pt - Medium body (most common)
Theme.fonts.bodySMedium          // 14pt - Small body
Theme.fonts.caption12            // 12pt - Captions
Theme.fonts.buttonRegularSemibold // 16pt - Button text

// Price fonts (Satoshi family - for crypto amounts)
// IMPORTANT: Always use price fonts for numbers, prices, and balances
Theme.fonts.priceTitle1          // 28pt
Theme.fonts.priceBodyL           // 18pt
Theme.fonts.priceBodyS           // 14pt

// Gradients
LinearGradient.primaryGradient           // Turquoise → Blue (diagonal)
LinearGradient.primaryGradientLinear     // Turquoise → Blue (vertical)
LinearGradient.primaryGradientHorizontal // Turquoise → Blue (horizontal)
```

### Buttons

Use `PrimaryButton` for all buttons:

```swift
// Standard button
PrimaryButton(title: "Continue", type: .primary, size: .medium) {
    // action
}

// With icons
PrimaryButton(
    title: "Send",
    leadingIcon: "arrow.up",
    type: .primary,
    size: .medium
) {
    // action
}

// Loading state
PrimaryButton(
    title: "Processing",
    isLoading: true,
    type: .primary,
    size: .medium
) { }

// Button types:
// .primary        - Blue background (#2155DF)
// .secondary      - Dark background with border
// .primarySuccess - Turquoise background (#33E6BF)
// .alert          - Red background (#FF5C5C)
// .outline        - Transparent with border

// Button sizes:
// .medium  - Full width, 14pt vertical padding
// .small   - Medium, 12pt padding
// .mini    - Compact, 6pt padding
// .squared - Square-ish with 12pt radius
```

**Reference:** `Views/Components/Buttons/PrimaryButton/`

### Text Fields

Use `CommonTextField` for inputs:

```swift
@State private var text = ""
@State private var error: String? = nil
@State private var isValid: Bool? = nil

CommonTextField(
    text: $text,
    label: "Address",
    placeholder: "Enter wallet address",
    error: $error,
    isValid: $isValid
)
```

**Reference:** `Views/Components/TextField/CommonTextField.swift`

### Containers

Use `containerStyle` modifier or `ContainerView`:

```swift
// Modifier approach
VStack {
    // content
}
.containerStyle(padding: 16, radius: 12, bgColor: Theme.colors.bgSurface1)

// Component approach
ContainerView {
    // content
}
```

### View Modifiers

Common modifiers available:

```swift
// Conditional display
.showIf(condition)

// Conditional transformation
.if(condition) { view in view.opacity(0.5) }

// Plain list item styling
.plainListItem()

// Sheet styling
.sheetStyle(padding: 8)
```

### Icons

Use the `Icon` component:

```swift
Icon(named: "arrow.up", color: Theme.colors.primaryAccent4, size: 20)
Icon(named: "checkmark", isSystem: true)  // SF Symbol
```

## Screen Component

The `Screen` component is the standard wrapper for all screens in the app. It provides consistent layout, background, padding, and navigation bar handling across iOS and macOS.

**Reference:** `Views/Components/Screen/Screen.swift`

**Important:** Always use the `Screen` component for views that represent a whole screen. Use the `Screen` suffix in your struct name for consistency (e.g., `HomeScreen`, `VaultSettingsScreen`, not `HomeView` or `Home`).

### Basic Usage

```swift
struct MyScreen: View {
    var body: some View {
        Screen(title: "myScreenTitle".localized) {
            // Your content here
            VStack {
                Text("Hello")
            }
        }
    }
}
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `title` | `String` | `""` | Navigation bar title |
| `showNavigationBar` | `Bool` | `true` | Show/hide the navigation bar |
| `edgeInsets` | `ScreenEdgeInsets` | `.noInsets` | Custom padding overrides |
| `backgroundType` | `BackgroundType` | `.plain` | Background style |

### Edge Insets

Use `ScreenEdgeInsets` to customize padding:

```swift
// Remove bottom padding (useful for screens with bottom buttons)
Screen(title: "Settings", edgeInsets: ScreenEdgeInsets(bottom: 0)) {
    // content
}

// Custom padding on all sides
Screen(title: "Details", edgeInsets: ScreenEdgeInsets(top: 20, leading: 24, bottom: 16, trailing: 24)) {
    // content
}
```

### Background Types

```swift
// Plain dark background (default)
Screen(title: "Title", backgroundType: .plain) { ... }

// Gradient background (used on main screens like Home)
Screen(title: "Title", backgroundType: .gradient) { ... }
```

### Default Padding

- **iOS:** 16pt horizontal, 12pt vertical
- **macOS:** 40pt horizontal, 12pt vertical

### Complete Example

```swift
struct VaultSettingsScreen: View {
    var body: some View {
        Screen(title: "vaultSettings".localized) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    SettingsSectionView(title: "vaultManagement".localized) {
                        // settings rows
                    }
                }
            }
        }
    }
}
```

## Cross-Platform Toolbar

The `crossPlatformToolbar` modifier provides a unified toolbar API that works on both iOS and macOS. On iOS, it uses native SwiftUI toolbar. On macOS, it renders a custom toolbar with back button support.

**Reference:** `Views/Components/Toolbar/CrossPlatformToolbar/`

### Basic Usage

```swift
// Just title (back button automatic on macOS)
content
    .crossPlatformToolbar("Screen Title")

// Title with custom toolbar items
content
    .crossPlatformToolbar("Screen Title") {
        CustomToolbarItem(placement: .trailing) {
            ToolbarButton(image: "gear", action: onSettings)
        }
    }
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `navigationTitle` | `String?` | `nil` | Title displayed in center |
| `ignoresTopEdge` | `Bool` | `false` | macOS: overlay vs VStack layout |
| `showsBackButton` | `Bool` | `true` | macOS: auto back button |
| `items` | `[CustomToolbarItem]` | `[]` | Custom toolbar buttons |

### CustomToolbarItem

Define toolbar items with placement:

```swift
.crossPlatformToolbar("Title") {
    // Leading (left) side
    CustomToolbarItem(placement: .leading) {
        ToolbarButton(image: "chevron-left", action: goBack)
    }

    // Trailing (right) side
    CustomToolbarItem(placement: .trailing) {
        ToolbarButton(image: "square-3d", action: onExplorer)
    }
}
```

### ToolbarButton

Use `ToolbarButton` for consistent toolbar button styling with glass effect support:

```swift
// Basic
ToolbarButton(image: "gear", action: onTap)

// With type
ToolbarButton(image: "checkmark", type: .confirmation, action: onConfirm)
ToolbarButton(image: "trash", type: .destructive, action: onDelete)

// Custom icon size
ToolbarButton(image: "x", iconSize: 16, action: onClose)
```

**Button Types:**
- `.outline` - Default, subtle background
- `.confirmation` - Blue accent background
- `.destructive` - Red alert background

### Platform-Specific Behavior

```swift
.crossPlatformToolbar("Title", ignoresTopEdge: true, showsBackButton: false) {
    #if os(macOS)
    // macOS-only close button
    CustomToolbarItem(placement: .leading) {
        ToolbarButton(image: "x", action: dismiss)
    }
    #endif

    // Both platforms
    CustomToolbarItem(placement: .trailing) {
        ToolbarButton(image: "share", action: onShare)
    }
}
```

### Complete Example

```swift
struct CoinDetailScreen: View {
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            // content
        }
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: false) {
            #if os(macOS)
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    isPresented.toggle()
                }
            }
            CustomToolbarItem(placement: .trailing) {
                RefreshToolbarButton(onRefresh: onRefresh)
            }
            #endif

            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: "square-3d", action: onExplorer)
            }
        }
    }
}
```

## Cross-Platform Sheet

The `crossPlatformSheet` modifier provides unified sheet presentation across iOS and macOS. On iOS, it uses native sheets. On older macOS (< 26.0), it uses a custom modal implementation with blur backdrop.

**Reference:** `Views/Components/Sheet/CrossPlatformSheet.swift`

### Basic Usage (Boolean)

```swift
@State private var showSheet = false

var body: some View {
    content
        .crossPlatformSheet(isPresented: $showSheet) {
            MySheetContent()
        }
}
```

### Item-Based Usage

For sheets that depend on an optional identifiable item:

```swift
@State private var selectedItem: Item?  // Must be Identifiable & Equatable

var body: some View {
    content
        .crossPlatformSheet(item: $selectedItem) { item in
            ItemDetailSheet(item: item)
        }
}
```

### Sheet Content Guidelines

Sheet content should typically include:
- `.presentationDetents()` for iOS sizing
- `.presentationBackground()` for consistent theming
- `.presentationDragIndicator()` for drag handle

```swift
.crossPlatformSheet(isPresented: $showSheet) {
    VStack {
        // Sheet content
    }
    .presentationDetents([.medium, .large])
    .presentationBackground(Theme.colors.bgSurface1)
    .presentationDragIndicator(.visible)
}
```

### Complete Example

```swift
struct HomeScreen: View {
    @State var showVaultSelector = false
    @State var showScanner = false

    var body: some View {
        content
            // Boolean sheet
            .crossPlatformSheet(isPresented: $showVaultSelector) {
                VaultManagementSheet(
                    isPresented: $showVaultSelector,
                    availableHeight: 600
                )
            }
            // Scanner sheet (iOS only, macOS navigates)
            #if !os(macOS)
            .crossPlatformSheet(isPresented: $showScanner) {
                GeneralCodeScannerView(showSheet: $showScanner)
            }
            #endif
    }
}
```

### Platform Differences

| Feature | iOS | macOS < 26 | macOS 26+ |
|---------|-----|------------|-----------|
| Presentation | Native sheet | Custom ZStack modal | Native sheet |
| Backdrop | System blur | 5px blur + dim | System blur |
| Dismiss | Swipe/tap outside | Tap backdrop | Swipe/tap outside |
| Animation | System | Spring (0.2s) | System |

## Combining Screen, Toolbar, and Sheet

Here's how these components work together in a typical screen:

```swift
struct MyFeatureScreen: View {
    @State private var showDetailSheet = false
    @State private var selectedItem: Item?

    var body: some View {
        Screen(title: "myFeature".localized) {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(items) { item in
                        ItemRow(item: item)
                            .onTapGesture {
                                selectedItem = item
                            }
                    }
                }
            }
        }
        // Add toolbar items
        .crossPlatformToolbar {
            CustomToolbarItem(placement: .trailing) {
                ToolbarButton(image: "plus") {
                    showDetailSheet = true
                }
            }
        }
        // Boolean sheet
        .crossPlatformSheet(isPresented: $showDetailSheet) {
            AddItemSheet(isPresented: $showDetailSheet)
        }
        // Item-based sheet
        .crossPlatformSheet(item: $selectedItem) { item in
            ItemDetailSheet(item: item)
        }
    }
}
```

## State Management

### App-Level State

Singletons injected via `environmentObject` from `VultisigApp.swift`:

```swift
// Access in views
@EnvironmentObject var appViewModel: AppViewModel
@EnvironmentObject var homeViewModel: HomeViewModel
@EnvironmentObject var settingsViewModel: SettingsViewModel
```

### Feature ViewModels

Create `ObservableObject` classes with `@Published` properties:

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

Use `@State` for view-local state:

```swift
struct MyView: View {
    @State private var showSheet = false
    @State private var selectedItem: Item?
}
```

## Navigation

### Route Definition

Define routes as `Hashable` enums:

```swift
// Features/[Feature]/Navigation/[Feature]Route.swift
enum MyFeatureRoute: Hashable {
    case list
    case detail(item: Item)
    case edit(item: Item)
}
```

### Router Implementation

Create routers that build views from routes:

```swift
// Features/[Feature]/Navigation/[Feature]Router.swift
struct MyFeatureRouter {
    @ViewBuilder
    func build(_ route: MyFeatureRoute) -> some View {
        switch route {
        case .list:
            MyListView()
        case .detail(let item):
            MyDetailView(item: item)
        case .edit(let item):
            MyEditView(item: item)
        }
    }
}
```

### Navigation Usage

```swift
@Environment(\.router) var router

// Navigate forward
router.navigate(to: MyFeatureRoute.detail(item: item))

// Go back
router.navigateBack()

// Replace root
router.replace(to: MyFeatureRoute.list)
```

### Register Routes

Add to `ContentView.swift`:

```swift
.navigationDestination(for: MyFeatureRoute.self) { route in
    router.myFeatureRouter.build(route)
}
```

## Code Style

### Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Screens (full screen views with `Screen` component) | `*Screen.swift` | `HomeScreen.swift`, `VaultSettingsScreen.swift` |
| Components (reusable UI elements) | `*View.swift` | `VaultCellView.swift`, `ButtonView.swift` |
| ViewModels | `*ViewModel.swift` | `HomeViewModel.swift` |
| Services | `*Service.swift` | `THORChainAPIService.swift` |
| API Endpoints | `*API.swift` | `THORChainAPI.swift` |
| Routes | `*Route.swift` | `HomeRoute.swift` |
| Routers | `*Router.swift` | `HomeRouter.swift` |
| Models | Descriptive name | `THORChainPoolResponse.swift` |
| Errors | `*Error.swift` | `THORChainAPIError.swift` |

### Swift Conventions

- Use Swift concurrency (async/await) for all async operations
- Use `Codable` for all API models
- Prefer `struct` over `class` unless reference semantics needed
- Use protocol-based dependency injection
- Use `Result` type sparingly; prefer throwing functions

### Do NOT

- Hardcode colors or fonts; always use `Theme.colors.*` and `Theme.fonts.*`
- Use UIKit unless absolutely necessary (camera, share sheets)
- Create new button styles; use `PrimaryButton` with appropriate type
- Use callbacks/completion handlers; use async/await
- Put business logic in views; use ViewModels or Services
- Use `.foregroundColor()` modifier; it's deprecated in favor of `.foregroundStyle()`
- Create platform-specific view files (e.g., `MyView_iOS.swift`, `MyView_macOS.swift`); use cross-platform modifiers and components (`crossPlatformToolbar`, `crossPlatformSheet`, `#if os(macOS)` blocks) to keep code in a single file

### SwiftLint Compliance

**CRITICAL:** Never introduce new SwiftLint warnings. The codebase uses SwiftLint for code quality enforcement.

**Before submitting code:**

1. Ensure all code changes are SwiftLint-compliant
2. Do not introduce any new warnings
3. Follow existing code patterns to maintain consistency

**Common warnings to avoid:**

- `unused_setter_value` - Always use setter parameters or explicitly ignore with `_ = newValue`
- `force_unwrapping` - Avoid force unwrapping (`!`); use optional binding or guard statements
- `force_cast` - Use conditional casting (`as?`) instead of force casting (`as!`)
- `line_length` - Keep lines under the configured limit (typically 120-140 characters)
- `function_body_length` - Break down large functions into smaller, focused functions
- `type_body_length` - Split large types into smaller, focused types or extensions
- `trailing_whitespace` - Remove trailing spaces from lines
- `unused_closure_parameter` - Use `_` for unused closure parameters

**Suppressing warnings (use sparingly):**

Only suppress warnings when absolutely necessary and the code is intentionally designed that way:

```swift
// For unused setter values (when implementing protocol requirements):
var myProperty: String {
    get { storedValue }
    set { _ = newValue }  // Preferred: explicit ignore
}

// OR with SwiftLint comment (last resort):
var myProperty: String {
    get { storedValue }
    // swiftlint:disable:next unused_setter_value
    set { }
}

// For other legitimate cases:
// swiftlint:disable:next rule_name
let value = someCode()
```

**Guidelines for suppressions:**

- Use `_ = newValue` for unused setters (preferred over comments)
- Only use `// swiftlint:disable:next` comments when there's no code-level solution
- Always add a brief comment explaining why the suppression is necessary
- Never disable rules globally or for entire files without explicit approval

## Common Patterns

### Async Data Loading in Views

```swift
struct MyView: View {
    @State private var data: [Item] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else {
                List(data) { item in
                    ItemRow(item: item)
                }
            }
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        defer { isLoading = false }
        do {
            data = try await service.getData()
        } catch {
            // handle error
        }
    }
}
```

### Caching Pattern

```swift
actor MyCache {
    private var cachedData: [Item]?
    private var lastFetch: Date?
    private let cacheDuration: TimeInterval = 300 // 5 minutes

    func getCachedData() -> [Item]? {
        guard let data = cachedData,
              let lastFetch,
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

## Testing

- Unit tests for Services and ViewModels
- Use protocol-based DI to inject mock HTTPClient
- Test files mirror source structure in test target

## Build Commands

```bash
# Build via xcodebuild
xcodebuild -project VultisigApp/VultisigApp.xcodeproj -scheme VultisigApp -sdk iphonesimulator build

# Run tests
xcodebuild -project VultisigApp/VultisigApp.xcodeproj -scheme VultisigApp -sdk iphonesimulator test
```

## Key Reference Files

| Pattern | Reference File |
|---------|---------------|
| API Service | `Services/THORChainAPI/THORChainAPIService.swift` |
| TargetType | `Services/THORChainAPI/TargetType/THORChainAPI.swift` |
| HTTP Client | `Services/Network/HTTPClient.swift` |
| Button Component | `Views/Components/Buttons/PrimaryButton/PrimaryButton.swift` |
| TextField Component | `Views/Components/TextField/CommonTextField.swift` |
| Color System | `DesignSystem/DefaultTheme/ColorSystem.swift` |
| Font System | `DesignSystem/DefaultTheme/FontSystem.swift` |
| Navigation Router | `Navigation/NavigationRouter.swift` |
| Route Example | `Features/Home/Navigation/HomeRoute.swift` |
| ViewModel Example | `View Models/HomeViewModel.swift` |
| App Entry | `VultisigApp/VultisigApp.swift` |
| Screen Component | `Views/Components/Screen/Screen.swift` |
| CrossPlatformToolbar | `Views/Components/Toolbar/CrossPlatformToolbar/CrossPlatformToolbarModifier.swift` |
| ToolbarButton | `Views/Components/Toolbar/ToolbarButton.swift` |
| CrossPlatformSheet | `Views/Components/Sheet/CrossPlatformSheet.swift` |
| Screen Example | `Views/Vault/Settings/VaultSettingsScreen.swift` |
