//
//  NotificationsIntroSheetTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class NotificationsIntroSheetTests: XCTestCase {
    func testDeniedPermissionDismissesWithoutEnablingVault() {
        let vault = Vault(name: "Vault")

        let destination = NotificationsIntroSheet.permissionDestination(
            granted: false,
            targetVault: vault,
            vaults: [vault]
        )

        guard case .dismiss = destination else {
            return XCTFail("Denied permission should dismiss")
        }
    }

    func testPerVaultPromptEnablesTriggeringVault() {
        let firstVault = Vault(name: "First")
        let triggeringVault = Vault(name: "Triggering")

        let destination = NotificationsIntroSheet.permissionDestination(
            granted: true,
            targetVault: triggeringVault,
            vaults: [firstVault, triggeringVault]
        )

        guard case .enableVault(let vault) = destination else {
            return XCTFail("Per-vault prompt should enable its triggering vault")
        }
        XCTAssertTrue(vault === triggeringVault)
    }

    func testGeneralPromptWithOneVaultEnablesThatVault() {
        let vault = Vault(name: "Vault")

        let destination = NotificationsIntroSheet.permissionDestination(
            granted: true,
            targetVault: nil,
            vaults: [vault]
        )

        guard case .enableVault(let enabledVault) = destination else {
            return XCTFail("Single-vault prompt should enable its only vault")
        }
        XCTAssertTrue(enabledVault === vault)
    }

    func testGeneralPromptWithMultipleVaultsShowsSelection() {
        let destination = NotificationsIntroSheet.permissionDestination(
            granted: true,
            targetVault: nil,
            vaults: [Vault(name: "First"), Vault(name: "Second")]
        )

        guard case .vaultSelection = destination else {
            return XCTFail("Multi-vault prompt should show vault selection")
        }
    }
}
