//
//  SettingsWalletConnectOptionTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class SettingsWalletConnectOptionTests: XCTestCase {
    func testWalletConnectSessionsOptionIsNavigationOption() {
        XCTAssertEqual(SettingsOption.walletConnectSessions.title, "walletConnectSessions")
        XCTAssertNotNil(SettingsOption.walletConnectSessions.icon)

        guard case .navigation = SettingsOption.walletConnectSessions.type else {
            return XCTFail("WalletConnect sessions should navigate to its management screen")
        }
    }

    @MainActor
    func testSettingsMainGeneralGroupIncludesWalletConnectSessions() {
        let screen = SettingsMainScreen(vault: .example)
        let generalGroup = screen.groups.first { $0.title == "general" }

        XCTAssertTrue(generalGroup?.options.contains(.walletConnectSessions) == true)
    }

    func testSettingsRouteSupportsWalletConnectSessions() {
        XCTAssertEqual(SettingsRoute.walletConnectSessions, SettingsRoute.walletConnectSessions)
    }
}
