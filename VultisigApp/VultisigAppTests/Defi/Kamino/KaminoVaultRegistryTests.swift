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

    /// Mints and farms are pinned here rather than read from the API, because a
    /// transaction the API built cannot be validated against metadata the same
    /// API supplied. That only helps if the pinned values are themselves real
    /// Solana addresses.
    func test_allowList_pinnedMintsAndFarmsAreValidSolanaAddresses() {
        for descriptor in KaminoVaultRegistry.allowList {
            for (label, address) in [
                ("tokenMint", descriptor.tokenMint),
                ("sharesMint", descriptor.sharesMint)
            ] + (descriptor.farm.map { [("farm", $0)] } ?? []) {
                XCTAssertNotNil(
                    AnyAddress(string: address, coin: .solana),
                    "\(descriptor.fallbackName) has an invalid \(label)"
                )
            }
        }
    }

    /// Every launch vault stakes deposits into a farm, so the shares never reach
    /// the user's wallet and the position cannot be read from an ATA.
    func test_allowList_everyLaunchVaultHasAFarm() {
        for descriptor in KaminoVaultRegistry.allowList {
            XCTAssertNotNil(descriptor.farm, "\(descriptor.fallbackName) has no farm")
        }
    }

    /// The decimal scales index a `10^n` factor in every conversion. They used to
    /// be bounds-checked at the service boundary; now they are constants, so this
    /// is where that guarantee lives.
    func test_allowList_decimalScalesAreSane() {
        for descriptor in KaminoVaultRegistry.allowList {
            XCTAssertTrue((0...KaminoBaseUnits.maxDecimals).contains(descriptor.tokenDecimals))
            XCTAssertTrue((0...KaminoBaseUnits.maxDecimals).contains(descriptor.sharesDecimals))
        }
    }

    /// The SOL vault is the counterexample to any code that assumes a vault's two
    /// decimal scales match.
    func test_allezSol_pinsMismatchedDecimalScales() {
        XCTAssertEqual(KaminoVaultRegistry.allezSOL.tokenMint, KaminoVaultRegistry.wrappedSolMint)
        XCTAssertEqual(KaminoVaultRegistry.allezSOL.tokenDecimals, 9)
        XCTAssertEqual(KaminoVaultRegistry.allezSOL.sharesDecimals, 6)
    }

    /// Two vaults over the same token, with different share mints and different
    /// farms — a mix-up between them would deposit into the wrong curator's book.
    func test_usdcVaults_shareATokenButNotAShareMintOrFarm() {
        XCTAssertEqual(KaminoVaultRegistry.steakhouseUSDC.tokenMint, KaminoVaultRegistry.rwaUSDC.tokenMint)
        XCTAssertNotEqual(KaminoVaultRegistry.steakhouseUSDC.sharesMint, KaminoVaultRegistry.rwaUSDC.sharesMint)
        XCTAssertNotEqual(KaminoVaultRegistry.steakhouseUSDC.farm, KaminoVaultRegistry.rwaUSDC.farm)
    }

    func test_descriptorLookup_isAddressKeyed() {
        let descriptor = KaminoVaultRegistry.descriptor(for: KaminoVaultRegistry.allezSOL.address)
        XCTAssertEqual(descriptor?.curator, "Allez Labs")
        XCTAssertNil(KaminoVaultRegistry.descriptor(for: "nope"))
    }
}
