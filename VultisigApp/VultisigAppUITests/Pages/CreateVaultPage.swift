//
//  CreateVaultPage.swift
//  VultisigAppUITests
//

import XCTest

struct CreateVaultPage {

    let app: XCUIApplication

    // MARK: - Elements

    var getStartedButton: XCUIElement {
        app.buttons[AccessibilityID.Onboarding.createVaultButton]
    }

    var importButton: XCUIElement {
        app.buttons[AccessibilityID.Onboarding.importVaultButton]
    }

    // MARK: - Actions

    @discardableResult
    func tapGetStarted() -> Self {
        getStartedButton.waitAndTap()
        return self
    }

    // MARK: - Assertions

    func assertVisible(timeout: TimeInterval = 10) {
        XCTAssertTrue(
            getStartedButton.waitForExistence(timeout: timeout),
            "Create vault screen not visible — Get Started button not found"
        )
    }
}
