//
//  KaminoVaultRegistryTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import WalletCore
import XCTest

/// The allow-list is money-critical: a mistyped address is a transaction built
/// against the wrong vault, and the API happily builds one for any vault that
/// exists. These tests pin the constants and prove each is a real Solana address.
final class KaminoVaultRegistryTests: XCTestCase {

    func test_allowList_addressesAreValidSolanaAddresses() {
        for descriptor in KaminoVaultRegistry.allowList {
            XCTAssertNotNil(
                AnyAddress(string: descriptor.address, coin: .solana),
                "\(descriptor.fallbackName) has an invalid Solana address"
            )
        }
    }

    func test_allowList_pinsTheLaunchSet() {
        XCTAssertEqual(
            KaminoVaultRegistry.allowList.map(\.address),
            [
                "HDsayqAsDWy3QvANGqh2yNraqcD8Fnjgh73Mhb3WRS5E",
                "DWSXb18xZApz29vnQpgR2m6MynCT7PznaXt7Ut7M7KaP",
                "A1so1bPD3W1TfeFwboDh8yfAAVaVtcdAYBYCjhg2mJQ"
            ]
        )
    }

    func test_allowList_addressesAreUnique() {
        let addresses = KaminoVaultRegistry.allowList.map(\.address)
        XCTAssertEqual(Set(addresses).count, addresses.count)
    }

    func test_rwaVaultIsRankedAboveTheConservativeTier() {
        // The RWA vault lends against tokenized private credit, not liquid
        // crypto collateral. It must never be presented at the same risk tier as
        // the plain lending vaults.
        XCTAssertEqual(KaminoVaultRegistry.rwaUSDC.riskTier, .privateCredit)
        XCTAssertEqual(KaminoVaultRegistry.steakhouseUSDC.riskTier, .conservative)
        XCTAssertEqual(KaminoVaultRegistry.allezSOL.riskTier, .conservative)
        XCTAssertGreaterThan(
            KaminoVaultRegistry.rwaUSDC.riskTier.rawValue,
            KaminoVaultRegistry.steakhouseUSDC.riskTier.rawValue
        )
    }

    func test_isAllowed_rejectsAnythingOutsideTheCuratedSet() {
        XCTAssertTrue(KaminoVaultRegistry.isAllowed(KaminoVaultRegistry.steakhouseUSDC.address))
        // A real Kamino vault, but not one we curate.
        XCTAssertFalse(KaminoVaultRegistry.isAllowed("5YxwKgsvyTdT8q2CBgwA4L9BKbnKNrB66K9wUzij5wH"))
        XCTAssertFalse(KaminoVaultRegistry.isAllowed(""))
    }

    func test_descriptorLookup_isAddressKeyed() {
        let descriptor = KaminoVaultRegistry.descriptor(for: KaminoVaultRegistry.allezSOL.address)
        XCTAssertEqual(descriptor?.curator, "Allez Labs")
        XCTAssertNil(KaminoVaultRegistry.descriptor(for: "nope"))
    }
}
