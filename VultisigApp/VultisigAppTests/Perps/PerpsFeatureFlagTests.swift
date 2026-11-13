//
//  PerpsFeatureFlagTests.swift
//  VultisigAppTests
//
//  Perps ships dark: off until the Settings > Advanced toggle is switched on.
//

import XCTest
@testable import VultisigApp

final class PerpsFeatureFlagTests: XCTestCase {
    private var saved: Any?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.object(forKey: PerpsConfig.featureFlagKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(saved, forKey: PerpsConfig.featureFlagKey)
        super.tearDown()
    }

    func testOffByDefault() {
        UserDefaults.standard.removeObject(forKey: PerpsConfig.featureFlagKey)
        XCTAssertFalse(PerpsConfig.isFeatureEnabled)
    }

    func testFollowsTheAdvancedToggle() {
        UserDefaults.standard.set(true, forKey: PerpsConfig.featureFlagKey)
        XCTAssertTrue(PerpsConfig.isFeatureEnabled)
        UserDefaults.standard.set(false, forKey: PerpsConfig.featureFlagKey)
        XCTAssertFalse(PerpsConfig.isFeatureEnabled)
    }

    func testSigningStaysOffUntilLiveSigningLands() {
        XCTAssertFalse(PerpsConfig.allowsSigning)
    }

    func testBuilderFeeNeverExceedsTheApprovedMax() {
        let tiers: [VultDiscountTier?] = [nil] + VultDiscountTier.allCases.map { $0 }
        for tier in tiers {
            let tenths = PerpsConfig.builderFeeTenthsBp(tier: tier)
            XCTAssertGreaterThanOrEqual(tenths, 0)
            XCTAssertLessThanOrEqual(tenths, 100, "\(String(describing: tier)) exceeds the 0.1% approval")
        }
        XCTAssertEqual(PerpsConfig.builderMaxFeeRate, "0.1%")
    }
}

final class PerpsVultTierTests: XCTestCase {
    func testSwitchingVaultDropsThePreviousTierAndIgnoresAStaleRefresh() async {
        await PerpsVultTier.refresh(vaultKey: "vault-a") { .gold }
        XCTAssertEqual(PerpsVultTier.current, .gold)

        // A different vault starts with no discount until its own tier resolves.
        await PerpsVultTier.refresh(vaultKey: "vault-b") {
            XCTAssertNil(PerpsVultTier.current)
            return .bronze
        }
        XCTAssertEqual(PerpsVultTier.current, .bronze)

        // A refresh for vault A that finishes after vault B became active never lands.
        await PerpsVultTier.refresh(vaultKey: "vault-a") {
            await PerpsVultTier.refresh(vaultKey: "vault-b") { .silver }
            return .diamond
        }
        XCTAssertEqual(PerpsVultTier.current, .silver)
    }
}
