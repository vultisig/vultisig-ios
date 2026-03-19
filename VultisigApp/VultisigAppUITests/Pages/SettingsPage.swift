//
//  SettingsPage.swift
//  VultisigAppUITests
//

import XCTest

struct SettingsPage {

    let app: XCUIApplication

    // MARK: - Elements

    var container: XCUIElement {
        app.otherElements[AccessibilityID.Settings.container]
    }

    var languageCell: XCUIElement {
        app.buttons[AccessibilityID.Settings.languageCell]
    }

    var currencyCell: XCUIElement {
        app.buttons[AccessibilityID.Settings.currencyCell]
    }

    var vaultSettingsCell: XCUIElement {
        app.buttons[AccessibilityID.Settings.vaultSettingsCell]
    }

    var faqCell: XCUIElement {
        app.buttons[AccessibilityID.Settings.faqCell]
    }

    // MARK: - Assertions

    func assertVisible(timeout: TimeInterval = 5) {
        XCTAssertTrue(
            container.waitForExistence(timeout: timeout),
            "Settings screen not visible"
        )
    }
}
