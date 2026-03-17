//
//  HomePage.swift
//  VultisigAppUITests
//

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

    var agentTab: XCUIElement {
        app.buttons[AccessibilityID.Home.agentTab]
    }

    var settingsButton: XCUIElement {
        app.buttons[AccessibilityID.Home.settingsButton]
    }

    var historyButton: XCUIElement {
        app.buttons[AccessibilityID.Home.historyButton]
    }

    var vaultSelector: XCUIElement {
        app.buttons[AccessibilityID.Home.vaultSelector]
    }

    var cameraButton: XCUIElement {
        app.buttons[AccessibilityID.Home.cameraButton]
    }

    var balanceLabel: XCUIElement {
        app.staticTexts[AccessibilityID.Home.balanceLabel]
    }

    // MARK: - Actions

    @discardableResult
    func tapWalletTab() -> Self {
        walletTab.waitAndTap()
        return self
    }

    @discardableResult
    func tapDefiTab() -> Self {
        defiTab.waitAndTap()
        return self
    }

    @discardableResult
    func tapAgentTab() -> Self {
        agentTab.waitAndTap()
        return self
    }

    @discardableResult
    func tapSettings() -> SettingsPage {
        settingsButton.waitAndTap()
        return SettingsPage(app: app)
    }

    @discardableResult
    func tapVaultSelector() -> Self {
        vaultSelector.waitAndTap()
        return self
    }

    // MARK: - Assertions

    func assertVisible(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            vaultSelector.waitForExistence(timeout: timeout),
            "Home screen not visible — vault selector not found"
        )
    }

    func assertTabsExist() {
        XCTAssertTrue(walletTab.exists, "Wallet tab not found")
        XCTAssertTrue(defiTab.exists, "DeFi tab not found")
        XCTAssertTrue(agentTab.exists, "Agent tab not found")
    }
}
