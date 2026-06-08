//
//  CosmosUndelegateTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Pins the undelegate insufficient-fee pre-flight (fee-audit finding #5).
//  The undelegate amount comes out of the staked pool, so only the network
//  fee draws on the liquid (spendable) balance — `hasSufficientBalanceForFee`
//  must gate on `spendable >= fee` independently of the staked amount.
//

@testable import VultisigApp
import XCTest

@MainActor
final class CosmosUndelegateTransactionViewModelTests: XCTestCase {

    /// QBTC: 8 decimals, fee 800 base units => 0.000008 QBTC. `balance` is in
    /// human-decimal QBTC.
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

    private static func makeVM(coin: Coin) -> CosmosUndelegateTransactionViewModel {
        CosmosUndelegateTransactionViewModel(
            coin: coin,
            vault: .example,
            validatorAddress: "qbtcvaloper1abc",
            validatorMoniker: "Validator",
            stakedBalance: 1000
        )
    }

    func testFeeDecimalMatchesConfig() {
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: 1))
        // 800 / 10^8
        XCTAssertEqual(vm.feeDecimal, Decimal(string: "0.000008"))
    }

    func testInsufficientWhenSpendableBelowFee() {
        // 180 base units = 0.0000018 QBTC < 0.000008 fee (800 base units) — the
        // real on-device failure (`spendable 180qbtc < fee`). Staked pool is
        // large, so this isolates the spendable-vs-fee gate.
        let coin = Self.makeQbtcCoin(balance: Decimal(string: "0.0000018")!)
        let vm = Self.makeVM(coin: coin)
        XCTAssertFalse(vm.hasSufficientBalanceForFee)
        XCTAssertNil(vm.transactionBuilder, "Insufficient fee balance must block the builder")
    }

    func testSufficientWhenSpendableMeetsFee() {
        // Spendable comfortably above the fee while the staked pool is what's
        // being undelegated.
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: 1))
        XCTAssertTrue(vm.hasSufficientBalanceForFee)
    }

    func testSufficientAtExactFeeBoundary() {
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: Decimal(string: "0.000008")!))
        XCTAssertTrue(vm.hasSufficientBalanceForFee, "spendable == fee must pass")
    }

    func testTerraSharedVMAlsoGuards() {
        // Shared VM => Terra is covered too. Terra fee 10000 / 10^6 = 0.01 LUNA.
        let meta = CoinMeta(
            chain: .terra,
            ticker: "LUNA",
            logo: "LunaLogo",
            decimals: 6,
            priceProviderId: "terra-luna-2",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(
            asset: meta,
            address: "terra1delegator0000000000000000000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
        coin.rawBalance = String(describing: NSDecimalNumber(decimal: Decimal(string: "0.005")! * 1_000_000))
        let vm = CosmosUndelegateTransactionViewModel(
            coin: coin,
            vault: .example,
            validatorAddress: "terravaloper1abc",
            validatorMoniker: "Validator",
            stakedBalance: 1000
        )
        XCTAssertEqual(vm.feeDecimal, Decimal(string: "0.01"))
        XCTAssertFalse(vm.hasSufficientBalanceForFee, "0.005 LUNA < 0.01 fee")
    }
}
