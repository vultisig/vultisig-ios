//
//  TonStakeTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Covers the TON stake form view-model: destination-address selection
//  (existing pool reuse vs first-time typed field) and the fee headroom that
//  backs the min-stake / max-stakeable calculations.
//

@testable import VultisigApp
import XCTest

@MainActor
final class TonStakeTransactionViewModelTests: XCTestCase {

    private static let poolAddress = "EQDInDQGu7271ihfBYrR6oN0B0sn2K6cVtPbX4ckk466dIQr"

    private func makeTonCoin(rawBalance: String = "100000000000") -> Coin {
        let meta = CoinMeta(
            chain: .ton,
            ticker: "GRAM",
            logo: "gram",
            decimals: 9,
            priceProviderId: "the-open-network",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(
            asset: meta,
            address: "UQAfixturetonchainvaultaddress00000000000000000",
            hexPublicKey: ""
        )
        coin.rawBalance = rawBalance
        return coin
    }

    func testAddMoreReusesExistingPoolAddress() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            existingPoolAddress: Self.poolAddress
        )
        XCTAssertFalse(vm.isFirstTimeStake)
        XCTAssertEqual(vm.destinationPoolAddress, Self.poolAddress)
    }

    func testFirstTimeStakeUsesTypedPoolAddress() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            existingPoolAddress: nil
        )
        XCTAssertTrue(vm.isFirstTimeStake)
        vm.poolAddress = Self.poolAddress
        XCTAssertEqual(vm.destinationPoolAddress, Self.poolAddress)
        XCTAssertTrue(vm.isPoolAddressValid)
    }

    func testFirstTimeStakeRejectsInvalidPoolAddress() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(),
            vault: .example,
            existingPoolAddress: nil
        )
        vm.poolAddress = "not-a-ton-address"
        XCTAssertFalse(vm.isPoolAddressValid)
    }

    func testMaxStakeableReservesNetworkFee() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(rawBalance: "100000000000"), // 100 TON
            vault: .example,
            existingPoolAddress: Self.poolAddress
        )
        // 100 TON minus the 0.05 TON default fee.
        XCTAssertEqual(vm.maxStakeableAmount, Decimal(string: "99.95"))
    }

    func testInsufficientBalanceForFeeWhenBelowFee() {
        let vm = TonStakeTransactionViewModel(
            coin: makeTonCoin(rawBalance: "10000000"), // 0.01 TON < 0.05 fee
            vault: .example,
            existingPoolAddress: Self.poolAddress
        )
        XCTAssertFalse(vm.hasSufficientBalanceForFee)
        XCTAssertEqual(vm.maxStakeableAmount, 0)
    }
}
