//
//  PortfolioSearchTests.swift
//  VultisigAppUITests
//

import XCTest

/// Regression coverage for the portfolio search bar scrolling itself out of the
/// viewport when it takes focus.
///
/// Two limits worth knowing before trusting a green run:
///
/// - Both cases need a vault on the device. A clean simulator boots into the
///   create-vault flow, so on CI these skip rather than pass — there is no
///   seeded-vault launch argument yet.
/// - The size of the jump scaled with the length of the chain list, so a vault
///   with only a handful of chains exercises this far more weakly than a full
///   one: the scroll clamps against the content's end long before the field
///   leaves the screen.
final class PortfolioSearchTests: VultisigUITestCase {

    /// The scroll this covers used to fire on a fixed delay after focus, so the
    /// assertions deliberately settle for longer than that before looking.
    private let settleDelay: TimeInterval = 1.5

    func testWalletSearchFieldStaysVisibleAfterFocus() throws {
        launchApp()

        guard isOnHomeScreen else {
            throw XCTSkip("No vault available; portfolio search scenario not applicable")
        }
        homePage.assertVisible()

        try assertSearchStaysVisible(
            screen: "Wallet",
            searchButtonID: AccessibilityID.VaultMain.searchButton,
            searchFieldID: AccessibilityID.VaultMain.searchField,
            cancelButtonID: AccessibilityID.VaultMain.searchCancelButton
        )
    }

    func testDefiSearchFieldStaysVisibleAfterFocus() throws {
        launchApp()

        guard isOnHomeScreen else {
            throw XCTSkip("No vault available; DeFi search scenario not applicable")
        }
        homePage.assertVisible()

        guard let defiTab = resolvedDefiTab() else {
            throw XCTSkip("DeFi tab not addressable on this tab-bar style")
        }
        defiTab.tap()

        try assertSearchStaysVisible(
            screen: "DeFi",
            searchButtonID: AccessibilityID.DefiMain.searchButton,
            searchFieldID: AccessibilityID.DefiMain.searchField,
            cancelButtonID: AccessibilityID.DefiMain.searchCancelButton
        )
    }

    // MARK: - Helpers

    /// The identifier is only attached on the custom tab bar; the native tab
    /// bar iOS 26 draws instead exposes the tab by its label.
    private func resolvedDefiTab() -> XCUIElement? {
        let byIdentifier = app.buttons[AccessibilityID.Home.defiTab]
        if byIdentifier.waitForExistence(timeout: 5) {
            return byIdentifier
        }
        let byLabel = app.tabBars.buttons[HomeTabName.defi]
        return byLabel.waitForExistence(timeout: 5) ? byLabel : nil
    }

    private func assertSearchStaysVisible(
        screen: String,
        searchButtonID: String,
        searchFieldID: String,
        cancelButtonID: String
    ) throws {
        let searchButton = app.buttons[searchButtonID]
        guard searchButton.waitForExistence(timeout: 15) else {
            throw XCTSkip("\(screen) search control not reachable in this state")
        }
        searchButton.tap()

        // Not only "did it render": the field used to scroll clean out of the
        // viewport within a second of the tap, so it can also fail here by
        // having appeared and then left before the query resolved.
        let field = app.textFields[searchFieldID]
        XCTAssertTrue(
            field.waitForExistence(timeout: 5),
            "\(screen) search field is not present after tapping search — it never appeared, or it left the viewport first"
        )

        // Assert on the *untouched* focused state first. Order matters: typing
        // narrows the list, which shrinks the scroll content and clamps the
        // offset back, and on a short list that is enough to drag a runaway
        // field back into view — masking the very bug this covers.
        Thread.sleep(forTimeInterval: settleDelay)

        let cancel = app.buttons[cancelButtonID]
        assertUsable(field, named: "\(screen) search field")
        assertUsable(cancel, named: "\(screen) Cancel action")

        takeScreenshot(name: "\(screen) search focused")

        // Then prove the field genuinely holds focus, and that typing into it
        // does not push it out of reach either. Typing is used rather than
        // `app.keyboards` so an attached hardware keyboard cannot break this.
        field.typeText("v")
        XCTAssertEqual(field.value as? String, "v", "\(screen) search field never took focus")

        Thread.sleep(forTimeInterval: settleDelay)

        assertUsable(field, named: "\(screen) search field after typing")
        assertUsable(cancel, named: "\(screen) Cancel action after typing")

        cancel.tap()
        XCTAssertTrue(
            searchButton.waitForExistence(timeout: 5),
            "\(screen) search control did not come back after cancelling"
        )
    }

    /// On screen, inside the window, and reachable by a tap — the three things
    /// the forced scroll took away from the search bar.
    private func assertUsable(
        _ element: XCUIElement,
        named name: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.exists,
            "\(name) left the accessibility tree — it scrolled out of the viewport",
            file: file,
            line: line
        )
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(
            window.contains(element.frame),
            "\(name) at \(element.frame) is outside the window \(window)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            element.isHittable,
            "\(name) is not hittable — it is off-screen or covered",
            file: file,
            line: line
        )
    }
}

private enum HomeTabName {
    static let defi = "DeFi"
}
