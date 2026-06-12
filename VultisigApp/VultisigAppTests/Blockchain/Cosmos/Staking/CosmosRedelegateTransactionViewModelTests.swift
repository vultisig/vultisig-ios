//
//  CosmosRedelegateTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Pins the redelegate insufficient-fee pre-flight (fee-audit finding #5).
//  Redelegation moves staked balance between validators, so only the network
//  fee draws on the liquid (spendable) balance — `hasSufficientBalanceForFee`
//  must gate on `spendable >= fee`. Cooldown state is left untouched (no
//  `onLoad`), so these tests never hit the network.
//

@testable import VultisigApp
import XCTest

@MainActor
final class CosmosRedelegateTransactionViewModelTests: XCTestCase {

    private static func makeQbtcCoin(balance: Decimal) -> Coin {
        let meta = CoinMeta(
            chain: .qbtc,
            ticker: "QBTC",
            logo: "qbtc",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(
            asset: meta,
            address: "qbtc1delegator000000000000000000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
        coin.rawBalance = String(describing: NSDecimalNumber(decimal: balance * 100_000_000))
        return coin
    }

    private static func makeVM(coin: Coin) -> CosmosRedelegateTransactionViewModel {
        CosmosRedelegateTransactionViewModel(
            coin: coin,
            vault: .example,
            validatorSrcAddress: "qbtcvaloper1src",
            validatorSrcMoniker: "Source",
            stakedBalance: 1000
        )
    }

    func testFeeDecimalMatchesConfig() {
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: 1))
        // 800 / 10^8
        XCTAssertEqual(vm.feeDecimal, Decimal(string: "0.000008"))
    }

    func testInsufficientWhenSpendableBelowFee() {
        let coin = Self.makeQbtcCoin(balance: Decimal(string: "0.0000018")!)
        let vm = Self.makeVM(coin: coin)
        XCTAssertFalse(vm.hasSufficientBalanceForFee)
        XCTAssertNil(vm.transactionBuilder, "Insufficient fee balance must block the builder")
    }

    func testSufficientWhenSpendableMeetsFee() {
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: 1))
        XCTAssertTrue(vm.hasSufficientBalanceForFee)
    }

    func testSufficientAtExactFeeBoundary() {
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: Decimal(string: "0.000008")!))
        XCTAssertTrue(vm.hasSufficientBalanceForFee, "spendable == fee must pass")
    }

    func testTerraClassicSharedVMAlsoGuards() {
        // Shared VM => TerraClassic covered. LUNC fee 133333334 / 10^6 ≈ 133.33.
        let meta = CoinMeta(
            chain: .terraClassic,
            ticker: "LUNC",
            logo: "LunaLogo",
            decimals: 6,
            priceProviderId: "terra-luna",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(
            asset: meta,
            address: "terra1delegator0000000000000000000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
        coin.rawBalance = String(describing: NSDecimalNumber(decimal: Decimal(100) * 1_000_000))
        let vm = CosmosRedelegateTransactionViewModel(
            coin: coin,
            vault: .example,
            validatorSrcAddress: "terravaloper1src",
            validatorSrcMoniker: "Source",
            stakedBalance: 1000
        )
        XCTAssertFalse(vm.hasSufficientBalanceForFee, "100 LUNC < ~133.33 fee")
    }
}
