//
//  TonJettonRegistryTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class TonJettonRegistryTests: XCTestCase {

    private func curatedUSDT() -> VerifiedJetton {
        VerifiedJetton(
            address: TonJettonAddress.canonical(TonJettonFixtures.usdtMasterFriendly)!,
            symbol: "USDT",
            name: nil,
            decimals: 6,
            logo: "usdt",
            priceProviderId: "tether",
            verification: .curated
        )
    }

    private func whitelistedUSDT() -> VerifiedJetton {
        VerifiedJetton(
            address: TonJettonAddress.canonical(TonJettonFixtures.usdtMasterRawLower)!,
            symbol: "USD₮",
            name: "Tether USD",
            decimals: nil,
            logo: nil,
            priceProviderId: nil,
            verification: .verified(source: TonJettonRegistry.tonAssetsSource)
        )
    }

    // MARK: - Merge

    /// Curated is supplied first and keeps the metadata — its ticker is ASCII,
    /// its decimals are the real 6 (`ton-assets` publishes none for Tether) and
    /// it carries the price id.
    func testEarlierEntryKeepsTheMetadataOnAnAddressCollision() {
        let registry = TonJettonRegistry([curatedUSDT(), whitelistedUSDT()])
        let entry = registry.entry(for: TonJettonFixtures.usdtMasterRawUpper)

        XCTAssertEqual(entry?.symbol, "USDT")
        XCTAssertEqual(entry?.decimals, 6)
        XCTAssertEqual(entry?.priceProviderId, "tether")
        XCTAssertEqual(entry?.verification, .curated)
        XCTAssertEqual(registry.count, 1, "One contract must occupy one slot")
    }

    /// The half that is easy to get wrong: the losing duplicate still has to
    /// contribute its labels. Our curated entry has no name and an ASCII
    /// ticker, so without this a jetton calling itself "Tether USD" from
    /// another contract would classify as merely unverified.
    func testBothEntriesContributeImpersonationLabels() {
        let registry = TonJettonRegistry([curatedUSDT(), whitelistedUSDT()])

        XCTAssertTrue(registry.impersonates("USDT"), "curated ticker")
        XCTAssertTrue(registry.impersonates("USD₮"), "whitelist symbol")
        XCTAssertTrue(registry.impersonates("Tether USD"), "whitelist name")
        XCTAssertTrue(registry.impersonates("UЅDT"), "Cyrillic spelling of either")
    }

    func testUnrelatedLabelsDoNotImpersonate() {
        let registry = TonJettonRegistry([curatedUSDT(), whitelistedUSDT()])
        XCTAssertFalse(registry.impersonates("NOT"))
        XCTAssertFalse(registry.impersonates("Notcoin"))
        XCTAssertFalse(registry.impersonates(nil))
    }

    /// A symbol with no Latin skeleton must not match everything with no Latin
    /// skeleton — the empty string is not a label.
    func testLabelsWithNoSkeletonNeverImpersonate() {
        let cjk = VerifiedJetton(
            address: TonJettonAddress.canonical(TonJettonFixtures.notcoinMasterRaw)!,
            symbol: "道德經",
            name: "道德經",
            decimals: nil,
            logo: nil,
            priceProviderId: nil,
            verification: .verified(source: TonJettonRegistry.tonAssetsSource)
        )
        let registry = TonJettonRegistry([cjk])

        XCTAssertFalse(registry.impersonates("🅿️"))
        XCTAssertFalse(registry.impersonates(""))
        XCTAssertFalse(registry.impersonates("道德經"), "an exact repeat still has no skeleton to match on")
    }

    // MARK: - Lookup

    func testEntryLookupAcceptsEverySpellingOfTheAddress() {
        let registry = TonJettonRegistry([curatedUSDT()])
        for spelling in [
            TonJettonFixtures.usdtMasterRawUpper,
            TonJettonFixtures.usdtMasterRawLower,
            TonJettonFixtures.usdtMasterFriendly
        ] {
            XCTAssertEqual(registry.entry(for: spelling)?.symbol, "USDT", "failed for \(spelling)")
        }
    }

    func testUnlistedAddressHasNoEntry() {
        let registry = TonJettonRegistry([curatedUSDT()])
        XCTAssertNil(registry.entry(for: TonJettonFixtures.unlistedMasterRaw))
        XCTAssertNil(registry.entry(for: "not-an-address"))
    }

    func testEmptyRegistryMatchesNothing() {
        XCTAssertNil(TonJettonRegistry.empty.entry(for: TonJettonFixtures.usdtMasterFriendly))
        XCTAssertFalse(TonJettonRegistry.empty.impersonates("USDT"))
    }

    // MARK: - Entry construction

    func testCuratedTonJettonsBecomeVerifiedEntries() {
        let curated = BundledTokensProvider
            .curatedTokens(for: .ton, defaults: TonJettonFixtures.isolatedDefaults())
            .compactMap { VerifiedJetton(curated: $0) }

        XCTAssertFalse(curated.isEmpty, "The bundled TON jetton list must not be empty")
        XCTAssertTrue(curated.allSatisfy { $0.verification == .curated })
        XCTAssertTrue(
            curated.contains { $0.symbol == "USDT" && $0.decimals == 6 },
            "Curated Tether supplies the decimals ton-assets omits"
        )
    }

    /// The native coin has no contract address, so it is not a jetton and must
    /// not enter a registry that answers "is this master listed?".
    func testNativeCoinIsNotAVerifiedJetton() {
        XCTAssertNil(VerifiedJetton(curated: TokensStore.ton))
    }

    func testWhitelistEntryDropsBlankSymbolAndForeignAddress() throws {
        let entries = try JSONDecoder().decode(
            [TonAssetsJetton].self,
            from: Data(TonJettonFixtures.tonAssetsWithUnusableEntries.utf8)
        )
        let usable = entries.compactMap { VerifiedJetton(whitelisted: $0) }

        XCTAssertEqual(usable.map(\.symbol), ["NOT"])
        XCTAssertEqual(usable.first?.verification, .verified(source: "ton-assets"))
    }
}
