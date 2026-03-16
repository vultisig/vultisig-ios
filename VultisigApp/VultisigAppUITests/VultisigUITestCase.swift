//
//  VultisigUITestCase.swift
//  VultisigAppUITests
//

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
    var settingsPage: SettingsPage { SettingsPage(app: app) }
    var createVaultPage: CreateVaultPage { CreateVaultPage(app: app) }

    // MARK: - State Detection

    /// Whether the app launched to the home screen (has vaults) vs create vault (fresh install)
    var isOnHomeScreen: Bool {
        app.buttons[AccessibilityID.Home.vaultSelector].waitForExistence(timeout: 3)
    }

    var isOnCreateVaultScreen: Bool {
        app.buttons[AccessibilityID.Onboarding.createVaultButton].waitForExistence(timeout: 3)
    }

    // MARK: - Common Flows

    /// Launch app skipping auth, wait for either home or create vault
    func launchApp() {
        app.launchSkippingAuth()
    }

    /// Launch app and assert we land on the home screen (requires vaults to exist)
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
