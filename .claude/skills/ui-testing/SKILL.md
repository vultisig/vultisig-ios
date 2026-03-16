---
name: ui-testing
description: Write, review, or orchestrate XCUITest UI tests — accessibility identifiers, page objects, test helpers, and test execution.
user-invocable: false
---

# UI Testing Guide

## Architecture Overview

UI tests live in the `VultisigAppUITests` target and use Apple's XCUITest framework. The testing architecture follows three layers:

```
┌─────────────────────────────────────────┐
│  Test Cases  (XCTestCase subclasses)    │  — what to verify
├─────────────────────────────────────────┤
│  Page Objects  (Screen abstractions)    │  — how to interact
├─────────────────────────────────────────┤
│  Accessibility IDs  (in app source)     │  — where to find elements
└─────────────────────────────────────────┘
```

### Directory Structure

```
VultisigApp/VultisigAppUITests/
├── Helpers/
│   ├── XCUIApplication+Launch.swift     # Launch helpers & environment config
│   └── XCUIElement+Helpers.swift        # waitForExistence, tap-if-exists, etc.
├── Pages/
│   ├── HomePage.swift                   # Home screen interactions
│   ├── VaultSelectorPage.swift          # Vault selector overlay
│   ├── SendPage.swift                   # Send transaction flow
│   ├── SettingsPage.swift               # Settings screen
│   └── ...                              # One page per screen
├── Tests/
│   ├── HomeScreenTests.swift            # Home screen test cases
│   ├── SendFlowTests.swift              # Send transaction tests
│   ├── VaultCreationTests.swift         # Vault creation tests
│   ├── SettingsTests.swift              # Settings tests
│   └── LaunchTests.swift                # App launch & screenshot tests
└── VultisigAppUITests.swift             # Base test class (shared setup)
```

---

## Accessibility Identifiers

### The `AccessibilityID` Enum

All identifiers are defined in a single enum in the **main app target** (not the test target), organized by screen:

**File:** `VultisigApp/VultisigApp/Utils/AccessibilityID.swift`

```swift
import Foundation

enum AccessibilityID {
    enum Home {
        static let walletTab = "home.walletTab"
        static let defiTab = "home.defiTab"
        static let agentTab = "home.agentTab"
        static let settingsButton = "home.settingsButton"
        static let historyButton = "home.historyButton"
        static let vaultSelector = "home.vaultSelector"
        static let cameraButton = "home.cameraButton"
    }

    enum VaultSelector {
        static let container = "vaultSelector.container"
        static let addVaultButton = "vaultSelector.addVaultButton"
        static func vaultCell(name: String) -> String {
            "vaultSelector.vault.\(name)"
        }
    }

    enum Send {
        static let amountField = "send.amountField"
        static let addressField = "send.addressField"
        static let memoField = "send.memoField"
        static let continueButton = "send.continueButton"
        static let coinSelector = "send.coinSelector"
        static let maxButton = "send.maxButton"
    }

    enum Verify {
        static let confirmButton = "verify.confirmButton"
        static let amountLabel = "verify.amountLabel"
        static let addressLabel = "verify.addressLabel"
        static let feeLabel = "verify.feeLabel"
    }

    enum Settings {
        static let container = "settings.container"
        static let languageCell = "settings.languageCell"
        static let currencyCell = "settings.currencyCell"
        static let vaultSettingsCell = "settings.vaultSettingsCell"
        static let faqCell = "settings.faqCell"
    }

    enum Onboarding {
        static let createVaultButton = "onboarding.createVaultButton"
        static let importVaultButton = "onboarding.importVaultButton"
        static let vaultNameField = "onboarding.vaultNameField"
    }

    // Add more screens as tests expand
}
```

### Applying Identifiers in Views

Add `.accessibilityIdentifier()` to interactive and assertable elements:

```swift
// Buttons
PrimaryButton(title: "continue".localized, type: .primary, size: .medium) {
    onContinue()
}
.accessibilityIdentifier(AccessibilityID.Send.continueButton)

// Text fields
CommonTextField(text: $amount, label: "amount".localized, placeholder: "0.0")
    .accessibilityIdentifier(AccessibilityID.Send.amountField)

// Tab items
Button { selectedTab = .wallet } label: { ... }
    .accessibilityIdentifier(AccessibilityID.Home.walletTab)

// Navigation elements
Button(action: onSettings) { Image(systemName: "gear") }
    .accessibilityIdentifier(AccessibilityID.Home.settingsButton)

// Dynamic cells (use a function with the unique identifier)
VaultCell(vault: vault)
    .accessibilityIdentifier(AccessibilityID.VaultSelector.vaultCell(name: vault.name))
```

### Rules for Identifiers

1. **Namespace by screen** — `"screen.element"` format (e.g., `"home.settingsButton"`)
2. **Only tag interactive or assertable elements** — buttons, fields, labels you'll assert on, cells you'll tap
3. **Use static strings for fixed elements, functions for dynamic ones** — cells with IDs, lists with indices
4. **Define ALL identifiers in `AccessibilityID`** — never use inline string literals in `.accessibilityIdentifier()`
5. **Keep the enum in the main target** — it's app code, not test code

---

## Page Objects

Each screen gets a page object that encapsulates element queries and interactions. Page objects live in the **test target**.

### Pattern

```swift
import XCTest

struct HomePage {

    let app: XCUIApplication

    // MARK: - Elements

    var walletTab: XCUIElement {
        app.buttons[AccessibilityID.Home.walletTab]
    }

    var defiTab: XCUIElement {
        app.buttons[AccessibilityID.Home.defiTab]
    }

    var settingsButton: XCUIElement {
        app.buttons[AccessibilityID.Home.settingsButton]
    }

    var vaultSelector: XCUIElement {
        app.buttons[AccessibilityID.Home.vaultSelector]
    }

    // MARK: - Actions

    @discardableResult
    func tapWalletTab() -> Self {
        walletTab.tap()
        return self
    }

    @discardableResult
    func tapSettings() -> SettingsPage {
        settingsButton.tap()
        return SettingsPage(app: app)
    }

    @discardableResult
    func tapVaultSelector() -> VaultSelectorPage {
        vaultSelector.tap()
        return VaultSelectorPage(app: app)
    }

    // MARK: - Assertions

    func assertVisible(timeout: TimeInterval = 5) {
        XCTAssertTrue(walletTab.waitForExistence(timeout: timeout), "Home screen not visible")
    }
}
```

### Key Principles

- **Return `self` or the next page** — enables fluent chaining: `homePage.tapSettings().assertVisible()`
- **Use `@discardableResult`** — callers can ignore the return when they don't chain
- **Element queries use `AccessibilityID` constants** — the page never contains string literals
- **Assertions live in the page** — `assertVisible()`, `assertAmount(equals:)`, etc.
- **One file per screen** — matches the `*Screen.swift` naming in the app

### Page Objects Need AccessibilityID Visibility

Since `AccessibilityID` is defined in the main app target, the test target needs access. Two options:

**Option A (recommended):** Add `AccessibilityID.swift` to both targets in the project file (main + UI test target membership).

**Option B:** Import the app module in the test target:
```swift
@testable import VultisigApp
```

---

## Test Helpers

### App Launch Configuration

```swift
// VultisigAppUITests/Helpers/XCUIApplication+Launch.swift

import XCTest

extension XCUIApplication {

    /// Launch with standard test configuration
    func launchForTesting() {
        launchArguments += ["-UITesting"]
        launchArguments += ["-disableAnimations"]
        launchEnvironment["UI_TESTING"] = "1"
        launch()
    }

    /// Launch with a specific vault pre-selected (via launch environment)
    func launchWithVault(named name: String) {
        launchEnvironment["TEST_VAULT_NAME"] = name
        launchForTesting()
    }

    /// Launch skipping authentication (for tests that don't test auth)
    func launchSkippingAuth() {
        launchArguments += ["-skipAuthentication"]
        launchForTesting()
    }
}
```

### App-Side Launch Argument Handling

The app must check for these arguments to configure test mode:

```swift
// In VultisigApp.swift or AppViewModel
#if DEBUG
if CommandLine.arguments.contains("-UITesting") {
    // Disable analytics, push notifications, etc.
}
if CommandLine.arguments.contains("-skipAuthentication") {
    // Bypass biometric auth
}
if CommandLine.arguments.contains("-disableAnimations") {
    UIView.setAnimationsEnabled(false)
}
if let testVault = ProcessInfo.processInfo.environment["TEST_VAULT_NAME"] {
    // Pre-select vault by name
}
#endif
```

### Element Wait Helpers

```swift
// VultisigAppUITests/Helpers/XCUIElement+Helpers.swift

import XCTest

extension XCUIElement {

    /// Wait for element to exist, then tap
    func waitAndTap(timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) {
        let exists = waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "Element \(identifier) not found after \(timeout)s", file: file, line: line)
        tap()
    }

    /// Tap only if the element exists (no assertion failure)
    func tapIfExists(timeout: TimeInterval = 2) {
        if waitForExistence(timeout: timeout) {
            tap()
        }
    }

    /// Clear text field and type new text
    func clearAndType(_ text: String) {
        guard exists else { return }
        tap()
        // Select all + delete
        if let value = value as? String, !value.isEmpty {
            let selectAll = XCUIApplication().menuItems["Select All"]
            if selectAll.exists {
                selectAll.tap()
            }
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        typeText(text)
    }

    /// Assert element label contains expected text
    func assertLabelContains(_ text: String, file: StaticString = #file, line: UInt = #line) {
        let labelValue = label
        XCTAssertTrue(labelValue.contains(text),
                      "Expected label to contain '\(text)', got '\(labelValue)'",
                      file: file, line: line)
    }
}
```

---

## Writing Test Cases

### Base Test Class

```swift
// VultisigAppUITests/VultisigAppUITests.swift

import XCTest

class VultisigUITestCase: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Page Factories

    var homePage: HomePage { HomePage(app: app) }
    var sendPage: SendPage { SendPage(app: app) }
    var settingsPage: SettingsPage { SettingsPage(app: app) }
    var vaultSelectorPage: VaultSelectorPage { VaultSelectorPage(app: app) }

    // MARK: - Common Flows

    /// Launch app and navigate to home (skipping auth)
    func launchToHome() {
        app.launchSkippingAuth()
        homePage.assertVisible()
    }

    /// Take a screenshot and attach to the test report
    func takeScreenshot(name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
```

### Test Case Example

```swift
// VultisigAppUITests/Tests/HomeScreenTests.swift

import XCTest

final class HomeScreenTests: VultisigUITestCase {

    func testHomeScreenShowsTabs() throws {
        launchToHome()

        homePage.assertVisible()
        XCTAssertTrue(homePage.walletTab.exists)
        XCTAssertTrue(homePage.defiTab.exists)
    }

    func testNavigateToSettings() throws {
        launchToHome()

        let settings = homePage.tapSettings()
        settings.assertVisible()
    }

    func testSwitchTabs() throws {
        launchToHome()

        homePage.tapWalletTab()
        // Assert wallet content visible

        homePage.tapDefiTab()
        // Assert DeFi content visible
    }

    func testVaultSelectorOpens() throws {
        launchToHome()

        let selector = homePage.tapVaultSelector()
        selector.assertVisible()
    }
}
```

### Multi-Step Flow Example

```swift
// VultisigAppUITests/Tests/SendFlowTests.swift

import XCTest

final class SendFlowTests: VultisigUITestCase {

    func testSendFlowNavigatesToVerify() throws {
        launchToHome()

        // Navigate to send
        // (depends on how send is accessed — coin tap, toolbar button, etc.)

        sendPage.assertVisible()
        sendPage
            .enterAmount("0.001")
            .enterAddress("0x1234567890abcdef1234567890abcdef12345678")
            .tapContinue()

        // Should navigate to verify screen
        let verifyPage = VerifyPage(app: app)
        verifyPage.assertVisible()
    }
}
```

---

## Running UI Tests

UI tests have their own dedicated scheme (`VultisigAppUITests`) and test plan (`VultisigAppUITests.xctestplan`), separate from unit tests. This keeps CI fast — unit tests run on the main `VultisigApp` scheme, UI tests run on `VultisigAppUITests`.

### Command Line

```bash
# Run all UI tests (dedicated scheme)
xcodebuild test \
    -project VultisigApp/VultisigApp.xcodeproj \
    -scheme VultisigAppUITests \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' \
    2>&1 | xcpretty

# Run a specific test class
xcodebuild test \
    -project VultisigApp/VultisigApp.xcodeproj \
    -scheme VultisigAppUITests \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' \
    -only-testing:VultisigAppUITests/HomeScreenTests \
    2>&1 | xcpretty

# Run a specific test method
xcodebuild test \
    -project VultisigApp/VultisigApp.xcodeproj \
    -scheme VultisigAppUITests \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' \
    -only-testing:VultisigAppUITests/HomeScreenTests/testHomeScreenShowsTabs \
    2>&1 | xcpretty
```

### Scheme & Test Plan Structure

| Scheme | Test Plan | Targets | Purpose |
|--------|-----------|---------|---------|
| `VultisigApp` | `VultisigApp.xctestplan` | `VultisigAppTests` | Unit + integration tests (CI) |
| `VultisigAppUITests` | `VultisigAppUITests.xctestplan` | `VultisigAppUITests` | UI tests (separate CI step) |

---

## Workflow: Adding UI Tests for a New Screen

Follow this checklist when adding UI tests for a screen:

### Step 1 — Define Accessibility IDs

1. Open `VultisigApp/VultisigApp/Utils/AccessibilityID.swift`
2. Add a new nested enum for the screen (e.g., `enum Swap { ... }`)
3. Add `static let` constants for each interactive/assertable element
4. Use functions for dynamic elements (cells, list items)

### Step 2 — Apply IDs to the View

1. Open the screen's SwiftUI view file
2. Add `.accessibilityIdentifier(AccessibilityID.Screen.element)` to each tagged element
3. Focus on: buttons, text fields, labels with dynamic content, navigation triggers, cells

### Step 3 — Create the Page Object

1. Create `VultisigAppUITests/Pages/{Screen}Page.swift`
2. Add element properties using `app.buttons[...]`, `app.textFields[...]`, etc.
3. Add action methods that return `self` or the destination page
4. Add `assertVisible()` and any screen-specific assertions

### Step 4 — Write Test Cases

1. Create `VultisigAppUITests/Tests/{Screen}Tests.swift`
2. Subclass `VultisigUITestCase`
3. Write focused tests — one behavior per test method
4. Use page objects for all interactions (never query elements directly in tests)

### Step 5 — Run and Verify

```bash
xcodebuild test \
    -project VultisigApp/VultisigApp.xcodeproj \
    -scheme VultisigAppUITests \
    -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' \
    -only-testing:VultisigAppUITests/{TestClass} \
    2>&1 | xcpretty
```

---

## App-Side Test Mode Setup

For UI tests to work reliably, the app needs test-mode hooks. Add these checks wrapped in `#if DEBUG`:

### Required Changes

**`VultisigApp.swift`** — Check for `-UITesting` launch argument:
```swift
#if DEBUG
private var isUITesting: Bool {
    CommandLine.arguments.contains("-UITesting")
}
#endif
```

**`AppViewModel.swift`** — Skip authentication in test mode:
```swift
#if DEBUG
if CommandLine.arguments.contains("-skipAuthentication") {
    isAuthenticated = true
    showSplashView = false
    return
}
#endif
```

**Animations** — Disable for test stability:
```swift
#if DEBUG
if CommandLine.arguments.contains("-disableAnimations") {
    UIView.setAnimationsEnabled(false)
}
#endif
```

---

## Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Test classes | `{Feature}Tests.swift` | `HomeScreenTests.swift` |
| Page objects | `{Screen}Page.swift` | `HomgPage.swift` |
| Test methods | `test{Behavior}` | `testNavigateToSettings` |
| Accessibility IDs | `{screen}.{element}` | `"home.settingsButton"` |
| Helpers | Descriptive name | `XCUIElement+Helpers.swift` |

## Common XCUIElement Queries

| SwiftUI Element | XCUITest Query |
|-----------------|----------------|
| `Button` | `app.buttons[id]` |
| `TextField` | `app.textFields[id]` |
| `SecureField` | `app.secureTextFields[id]` |
| `Text` | `app.staticTexts[id]` |
| `Image` | `app.images[id]` |
| `Toggle` | `app.switches[id]` |
| `NavigationLink` | `app.buttons[id]` |
| `List` / `ForEach` cell | `app.cells[id]` or `app.buttons[id]` |
| `TabView` item | `app.buttons[id]` |
| `ScrollView` | `app.scrollViews[id]` |
| `Alert` button | `app.alerts.buttons["OK"]` |
| `Sheet` content | `app.sheets.firstMatch` |

## Tips

- **Always use `waitForExistence(timeout:)`** before interacting — SwiftUI renders asynchronously
- **Disable animations** via launch arguments for faster, more reliable tests
- **One assertion focus per test** — test methods should be small and specific
- **Use screenshots** (`takeScreenshot(name:)`) at key checkpoints for debugging failures
- **Avoid sleep** — use `waitForExistence` or `XCTNSPredicateExpectation` instead
- **Test in landscape and portrait** if the app supports both: `XCUIDevice.shared.orientation = .landscapeLeft`
