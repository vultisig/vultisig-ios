//
//  VaultIsFastVaultTests.swift
//  VultisigAppTests
//
//  Pins the current contract of `Vault.isFastVault` so the fix for
//  vultisig-ios#4348 can't silently change behavior without updating the
//  tests too.
//
//  Background — #4348: today `isFastVault` is purely structural. Any signer
//  in `vault.signers` whose name starts with `server-` flips the property to
//  `true`, and the rest of the app uses that one bool as the migrate-routing
//  key (UpgradeVaultViewModifier, VaultSettingsScreen, VaultRouteBuilder,
//  VaultShareBackupsView). There's no way for iOS to know whether the
//  server share is still online-managed or has been imported into another
//  peer device (e.g. a Windows install holds the share locally). The fix
//  must replace or supplement this check — Option A/C in the issue both
//  require additional state or a user prompt.
//
//  When that fix lands, the assertion in
//  `testIsFastVaultIsPurelyStructural_serverSignerWins` is the canary —
//  it should fail or have to flip, surfacing the contract change in code
//  review.
//

@testable import VultisigApp
import XCTest

@MainActor
final class VaultIsFastVaultTests: XCTestCase {

    // MARK: - Pin: structural-only contract (the bug behind #4348)

    /// Pre-#4348: any `server-*` signer flips `isFastVault` to `true`,
    /// regardless of whether the server share is still online-managed.
    /// This is the property the migrate flow keys off — and exactly the
    /// gap reported in the issue. When the fix lands this test must
    /// change.
    func testIsFastVaultIsPurelyStructural_serverSignerWins() {
        let vault = Vault(name: "test")
        vault.localPartyID = "iPhone-12345"
        vault.signers = ["iPhone-12345", "server-abc"]

        XCTAssertTrue(
            vault.isFastVault,
            """
            Pre-#4348 contract: any `server-*` signer => `isFastVault == true`.
            If you're here because this assertion failed, you're either fixing
            or regressing #4348. Update the test alongside the fix — don't loosen
            it silently.
            """
        )
    }

    // MARK: - Companion invariants (these stay true after #4348 is fixed)

    /// A device that IS itself the server-side party (its `localPartyID`
    /// starts with `server-`) must never read as a fast vault — only the
    /// user-side devices ever route to the FastVault flow.
    func testIsFastVault_serverLocalParty_returnsFalse() {
        let vault = Vault(name: "test")
        vault.localPartyID = "server-12345"
        vault.signers = ["iPhone-1", "server-12345"]

        XCTAssertFalse(vault.isFastVault)
    }

    /// No `server-*` signer in the list => peer flow, always.
    func testIsFastVault_noServerSigner_returnsFalse() {
        let vault = Vault(name: "test")
        vault.localPartyID = "iPhone-1"
        vault.signers = ["iPhone-1", "iPhone-2"]

        XCTAssertFalse(vault.isFastVault)
    }
}
