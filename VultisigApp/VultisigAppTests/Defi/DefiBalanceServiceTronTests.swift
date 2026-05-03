//
//  DefiBalanceServiceTronTests.swift
//  VultisigAppTests
//
//  Regression coverage for #4284: the DeFi Portfolio Tron row must report
//  frozen / staked TRX (sourced from `vault.stakePositions`), NOT the wallet
//  balance held on the Coin's `rawBalance`.
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class DefiBalanceServiceTronTests: XCTestCase {
    private var storeToken: DefiTestContextToken!
    private var vault: Vault!
    private let service = DefiBalanceService()
    /// Test rate: 1 TRX = $0.10 USD. Mirrors how production sets price rates via
    /// `RateProvider.save(rates:)` after `CryptoPriceService.fetchPrices`.
    private let trxPriceRate = 0.10

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try DefiTestStore.installInMemoryContainer()
        vault = DefiTestStore.makeVault()

        try await RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: "tron", value: trxPriceRate)
        ])
    }

    override func tearDown() async throws {
        vault = nil
        DefiTestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - Empty / disabled

    func testTronBalanceZeroWhenNoDefiPositions() {
        let total = service.totalBalanceInFiat(for: .tron, vault: vault)
        XCTAssertEqual(total, .zero, "Without a `.tron` defiPositions entry the row must read zero, not the wallet balance.")
    }

    func testTronBalanceZeroWhenDefiPositionsHasNoTrx() {
        // defiPositions for .tron exists but its staking set is empty — nothing to sum.
        vault.defiPositions = [
            DefiPositions(chain: .tron, bonds: [], staking: [], lps: [])
        ]
        try? Storage.shared.save()

        let total = service.totalBalanceInFiat(for: .tron, vault: vault)
        XCTAssertEqual(total, .zero)
    }

    // MARK: - Bug fix

    /// Core regression test for #4284: total fiat must equal `stakePosition.amount * priceRate`,
    /// NOT `walletBalance * priceRate`.
    func testTronBalanceUsesStakePositionAmountNotWalletBalance() throws {
        let trxMeta = TokensStore.trx
        let trxCoin = makeTrxCoin(rawBalance: "100000000")  // 100 TRX wallet balance
        vault.coins.append(trxCoin)

        vault.defiPositions = [
            DefiPositions(chain: .tron, bonds: [], staking: [trxMeta], lps: [])
        ]

        let storage = DefiPositionsStorageService()
        try storage.upsert(stake: [
            StakePositionData(coin: trxMeta, type: .stake, amount: 5)
        ], for: vault)

        let total = service.totalBalanceInFiat(for: .tron, vault: vault)
        let expected = Decimal(5) * Decimal(trxPriceRate)
        XCTAssertEqual(
            total,
            expected,
            "Total must reflect 5 TRX staked (= 5 * 0.10 = 0.50), not the 100 TRX wallet balance."
        )

        // Sanity check the bug we're fixing: the wallet balance would otherwise be 100 TRX
        // worth $10. Make sure we're not accidentally hitting that path.
        XCTAssertNotEqual(total, Decimal(100) * Decimal(trxPriceRate))
    }

    // MARK: - Helpers

    private func makeTrxCoin(rawBalance: String) -> Coin {
        let coin = Coin(
            asset: TokensStore.trx,
            address: "TtestAddress",
            hexPublicKey: "hex"
        )
        coin.rawBalance = rawBalance
        return coin
    }
}
