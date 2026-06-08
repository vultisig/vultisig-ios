//
//  CosmosDelegateTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Pins the delegate insufficient-fee pre-flight + fee-reserving "Max"
//  (fee-audit finding #5). For delegate the staked amount AND the fee both
//  draw on the liquid (spendable) balance, so:
//   - `stakeableBalance` ("Max") reserves the fee: balance - fee, floored at 0.
//   - the amount validator is bound to `stakeableBalance`, enforcing
//     `amount + fee <= balance` (just-fits valid, over-by-one invalid).
//   - `hasSufficientBalanceForFee` blocks when spendable is below the fee.
//

@testable import VultisigApp
import XCTest

@MainActor
final class CosmosDelegateTransactionViewModelTests: XCTestCase {

    private static let qbtcFee = Decimal(string: "0.000075")! // 7500 / 10^8

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

    private static func makeVM(coin: Coin) -> CosmosDelegateTransactionViewModel {
        CosmosDelegateTransactionViewModel(coin: coin, vault: .example)
    }

    /// Formats a `Decimal` the way the amount field would — via a locale-aware
    /// `.decimal` formatter — so the string round-trips through
    /// `AmountBalanceValidator` regardless of the host locale's decimal
    /// separator. (Hardcoding a `.`-string fails under comma-separator locales.)
    private static func localizedAmount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = 8
        formatter.usesGroupingSeparator = false
        return formatter.string(from: value as NSDecimalNumber) ?? value.description
    }

    func testFeeDecimalMatchesConfig() {
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: 1))
        XCTAssertEqual(vm.feeDecimal, Self.qbtcFee)
    }

    // MARK: - Max reserves the fee

    func testMaxReservesFee() {
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: 2))
        // "Max" stakes everything except the reserved fee.
        XCTAssertEqual(vm.stakeableBalance, 2 - Self.qbtcFee)
    }

    func testStakeableBalanceFlooredAtZeroWhenBelowFee() {
        // Liquid below the fee => nothing is stakeable (no negative max).
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: Decimal(string: "0.0000018")!))
        XCTAssertEqual(vm.stakeableBalance, 0)
    }

    // MARK: - amount + fee <= balance boundary

    func testAmountPlusFeeBoundaryJustFitsIsValid() {
        let balance = Decimal(2)
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: balance))
        let validator = AmountBalanceValidator(balance: vm.stakeableBalance)
        // amount == balance - fee  <=>  amount + fee == balance: must pass.
        let justFits = Self.localizedAmount(balance - Self.qbtcFee)
        XCTAssertNoThrow(try validator.validate(value: justFits))
    }

    func testAmountPlusFeeBoundaryOverByOneIsInvalid() {
        let balance = Decimal(2)
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: balance))
        let validator = AmountBalanceValidator(balance: vm.stakeableBalance)
        // One base unit (10^-8) over the fee-reserved max => amount + fee > balance.
        let overByOne = Self.localizedAmount(balance - Self.qbtcFee + Decimal(string: "0.00000001")!)
        XCTAssertThrowsError(try validator.validate(value: overByOne)) { error in
            XCTAssertEqual(
                error as? AmountBalanceValidator.ValidationError,
                .exceedsBalance
            )
        }
    }

    // MARK: - insufficient-fee pre-flight

    func testInsufficientWhenSpendableBelowFee() {
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: Decimal(string: "0.0000018")!))
        XCTAssertFalse(vm.hasSufficientBalanceForFee)
        XCTAssertNil(vm.transactionBuilder, "Insufficient fee balance must block the builder")
    }

    func testSufficientAtExactFeeBoundary() {
        let vm = Self.makeVM(coin: Self.makeQbtcCoin(balance: Self.qbtcFee))
        XCTAssertTrue(vm.hasSufficientBalanceForFee, "spendable == fee must pass")
    }

    func testTerraSharedVMReservesFee() {
        // Shared VM => Terra covered. Terra fee 10000 / 10^6 = 0.01 LUNA.
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
        coin.rawBalance = String(describing: NSDecimalNumber(decimal: Decimal(5) * 1_000_000))
        let vm = CosmosDelegateTransactionViewModel(coin: coin, vault: .example)
        XCTAssertEqual(vm.feeDecimal, Decimal(string: "0.01"))
        XCTAssertEqual(vm.stakeableBalance, 5 - Decimal(string: "0.01")!)
    }
}
