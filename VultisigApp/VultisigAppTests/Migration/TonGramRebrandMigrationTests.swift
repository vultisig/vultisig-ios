//
//  TonGramRebrandMigrationTests.swift
//  VultisigAppTests
//

import XCTest
import SwiftData
@testable import VultisigApp

@MainActor
final class TonGramRebrandMigrationTests: XCTestCase {
    private var token: TestContextToken?

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDownWithError() throws {
        TestStore.restore(token)
        token = nil
    }

    private func makeCoin(chain: Chain, ticker: String, logo: String, isNativeToken: Bool, contract: String = "") -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: logo,
            decimals: 9,
            priceProviderId: "the-open-network",
            contractAddress: contract,
            isNativeToken: isNativeToken
        )
        return Coin(asset: meta, address: "addr", hexPublicKey: "pub")
    }

    func test_migratesNativeTonCoinToGram() throws {
        let vault = TestStore.makeVault()
        let ton = makeCoin(chain: .ton, ticker: "TON", logo: "ton", isNativeToken: true)
        vault.coins.append(ton)
        try Storage.shared.save()

        try TonGramRebrandMigration().migrate()

        XCTAssertEqual(ton.ticker, "GRAM")
        XCTAssertEqual(ton.logo, "gram")
    }

    func test_isIdempotent() throws {
        let vault = TestStore.makeVault()
        let ton = makeCoin(chain: .ton, ticker: "TON", logo: "ton", isNativeToken: true)
        vault.coins.append(ton)
        try Storage.shared.save()

        try TonGramRebrandMigration().migrate()
        try TonGramRebrandMigration().migrate()

        XCTAssertEqual(ton.ticker, "GRAM")
        XCTAssertEqual(ton.logo, "gram")
    }

    func test_leavesJettonsAndOtherChainsUntouched() throws {
        let vault = TestStore.makeVault()
        // TON-chain jetton (non-native) keeps its own ticker/logo.
        let jetton = makeCoin(chain: .ton, ticker: "USDT", logo: "usdt", isNativeToken: false, contract: "EQjetton")
        // Native coin on another chain is unaffected.
        let eth = makeCoin(chain: .ethereum, ticker: "ETH", logo: "eth", isNativeToken: true)
        vault.coins.append(jetton)
        vault.coins.append(eth)
        try Storage.shared.save()

        try TonGramRebrandMigration().migrate()

        XCTAssertEqual(jetton.ticker, "USDT")
        XCTAssertEqual(jetton.logo, "usdt")
        XCTAssertEqual(eth.ticker, "ETH")
        XCTAssertEqual(eth.logo, "eth")
    }
}
