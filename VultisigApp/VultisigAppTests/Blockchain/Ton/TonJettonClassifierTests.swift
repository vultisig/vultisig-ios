//
//  TonJettonClassifierTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class TonJettonClassifierTests: XCTestCase {

    /// Curated Tether plus the whitelist duplicate of the same contract, which
    /// is where the `USD₮` and `Tether USD` skeletons come from, plus one
    /// whitelist-only jetton.
    private func registry() -> TonJettonRegistry {
        TonJettonRegistry([
            VerifiedJetton(
                address: TonJettonAddress.canonical(TonJettonFixtures.usdtMasterFriendly)!,
                symbol: "USDT", name: nil, decimals: 6, logo: "usdt",
                priceProviderId: "tether", verification: .curated
            ),
            VerifiedJetton(
                address: TonJettonAddress.canonical(TonJettonFixtures.usdtMasterRawLower)!,
                symbol: "USD₮", name: "Tether USD", decimals: nil, logo: nil,
                priceProviderId: nil, verification: .verified(source: "ton-assets")
            ),
            VerifiedJetton(
                address: TonJettonAddress.canonical(TonJettonFixtures.notcoinMasterRaw)!,
                symbol: "NOT", name: "Notcoin", decimals: 9, logo: nil,
                priceProviderId: nil, verification: .verified(source: "ton-assets")
            )
        ])
    }

    private func classify(
        address: String,
        symbol: String? = nil,
        name: String? = nil,
        isFlaggedScam: Bool? = nil
    ) -> TokenVerification {
        TonJettonClassifier.classify(
            address: address,
            symbol: symbol,
            name: name,
            isFlaggedScam: isFlaggedScam,
            registry: registry()
        )
    }

    // MARK: - Listed

    func testListedAddressIsVerifiedWhateverItCallsItself() {
        XCTAssertEqual(classify(address: TonJettonFixtures.notcoinMasterRaw, symbol: "NOT"), .verified(source: "ton-assets"))
        XCTAssertEqual(
            classify(address: TonJettonFixtures.notcoinMasterRaw, symbol: "USDT", name: "Tether USD"),
            .verified(source: "ton-assets"),
            "The address is the identity; the labels are not"
        )
    }

    func testCuratedAddressKeepsTheCuratedTier() {
        XCTAssertEqual(classify(address: TonJettonFixtures.usdtMasterRawUpper, symbol: "USD₮"), .curated)
    }

    /// Even the indexer calling a listed jetton a scam does not unlist it — the
    /// address match is the stronger statement, and honouring the flag here
    /// would let a bad indexer entry hide a real holding.
    func testListedAddressSurvivesTheIndexerScamFlag() {
        XCTAssertEqual(
            classify(address: TonJettonFixtures.notcoinMasterRaw, symbol: "NOT", isFlaggedScam: true),
            .verified(source: "ton-assets")
        )
    }

    // MARK: - Scam

    /// The pattern the whole feature exists for, and the reason `is_scam` cannot
    /// be the signal: a counterfeit at an unlisted address, calling itself
    /// exactly what the real asset is called, reporting `is_scam: false` — which
    /// is what all 40 sampled blacklisted jettons reported.
    func testCounterfeitTetherIsScamDespiteTheIndexerSayingOtherwise() {
        for spelling in ["USD₮", "USDT", "UЅDT", "$USĐ₮", "ＵＳＤＴ"] {
            XCTAssertEqual(
                classify(address: TonJettonFixtures.unlistedMasterRaw, symbol: spelling, isFlaggedScam: false),
                .scam,
                "failed for \(spelling)"
            )
        }
    }

    func testImpersonationByNameAloneIsScam() {
        XCTAssertEqual(
            classify(address: TonJettonFixtures.unlistedMasterRaw, symbol: "FREE", name: "Tether USD"),
            .scam
        )
    }

    func testIndexerFlagIsHonouredForAnUnlistedJetton() {
        XCTAssertEqual(
            classify(address: TonJettonFixtures.unlistedMasterRaw, symbol: "WHATEVER", isFlaggedScam: true),
            .scam
        )
    }

    // MARK: - Unverified

    func testUnlistedAndNotImpersonatingIsUnverified() {
        XCTAssertEqual(
            classify(address: TonJettonFixtures.unlistedMasterRaw, symbol: "MMM", name: "MMM2049", isFlaggedScam: false),
            .unverified
        )
    }

    /// `jUSDT` is a real, distinct jetton. Folding must not swallow the leading
    /// letter and make it read as an impersonation of USDT.
    func testASimilarButDistinctSymbolIsNotScam() {
        XCTAssertEqual(classify(address: TonJettonFixtures.unlistedMasterRaw, symbol: "jUSDT"), .unverified)
    }

    func testMissingLabelsAreUnverifiedNotScam() {
        XCTAssertEqual(classify(address: TonJettonFixtures.unlistedMasterRaw), .unverified)
        XCTAssertEqual(classify(address: TonJettonFixtures.unlistedMasterRaw, symbol: "", name: ""), .unverified)
    }

    /// A degraded registry recognises fewer jettons, so more of them are
    /// unverified — never more of them verified.
    func testEmptyRegistryVerifiesNothing() {
        let tier = TonJettonClassifier.classify(
            address: TonJettonFixtures.usdtMasterFriendly,
            symbol: "USDT",
            name: nil,
            isFlaggedScam: nil,
            registry: .empty
        )
        XCTAssertEqual(tier, .unverified)
    }

    // MARK: - Auto-surfacing

    /// The property acceptance criterion 3 rests on: whatever the tier, only
    /// verified ones may auto-appear.
    func testOnlyVerifiedTiersAutoSurface() {
        XCTAssertTrue(classify(address: TonJettonFixtures.usdtMasterRawUpper).autoSurfaces)
        XCTAssertTrue(classify(address: TonJettonFixtures.notcoinMasterRaw, symbol: "NOT").autoSurfaces)
        XCTAssertFalse(classify(address: TonJettonFixtures.unlistedMasterRaw, symbol: "USD₮").autoSurfaces)
        XCTAssertFalse(classify(address: TonJettonFixtures.unlistedMasterRaw, symbol: "MMM").autoSurfaces)
    }
}
