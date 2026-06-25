//
//  TonStakeTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the TON DeFi stake/unstake transaction builders: the nominator-pool
//  memo strings ("d"/"w"), the pool address as the transaction destination, and
//  the `SendTransaction` propagation. Mirrors `CosmosDelegateTransactionBuilderTests`.
//

@testable import VultisigApp
import XCTest

final class TonStakeTransactionBuilderTests: XCTestCase {

    private static let poolAddress = "EQDInDQGu7271ihfBYrR6oN0B0sn2K6cVtPbX4ckk466dIQr"

    private static func makeTonCoin(rawBalance: String = "100000000000") -> Coin {
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
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
        coin.rawBalance = rawBalance
        return coin
    }

    // MARK: - Stake (memo "d")

    func testStakeBuilderEmitsDepositMemo() {
        let builder = TonStakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "60",
            poolAddress: Self.poolAddress
        )
        XCTAssertEqual(builder.memo, "d")
    }

    func testStakeBuilderSendsToPoolAddress() {
        let builder = TonStakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "60",
            poolAddress: Self.poolAddress
        )
        XCTAssertEqual(builder.toAddress, Self.poolAddress)
    }

    func testStakeBuilderMemoDictionaryCarriesPoolAndMemo() {
        let builder = TonStakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "60",
            poolAddress: Self.poolAddress
        )
        let dict = builder.memoFunctionDictionary.allItems()
        XCTAssertEqual(dict["nodeAddress"], Self.poolAddress)
        XCTAssertEqual(dict["memo"], "d")
    }

    func testStakeBuildSendTransactionPropagatesMemoAndDestination() {
        let builder = TonStakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "60",
            poolAddress: Self.poolAddress
        )
        let tx = builder.buildSendTransaction(vault: .example)
        XCTAssertEqual(tx.memo, "d")
        XCTAssertEqual(tx.toAddress, Self.poolAddress)
        XCTAssertEqual(tx.amount, "60")
    }

    // MARK: - Unstake (memo "w")

    func testUnstakeBuilderEmitsWithdrawMemo() {
        let builder = TonUnstakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "1",
            poolAddress: Self.poolAddress
        )
        XCTAssertEqual(builder.memo, "w")
    }

    func testUnstakeBuilderSendsToPoolAddress() {
        let builder = TonUnstakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "1",
            poolAddress: Self.poolAddress
        )
        XCTAssertEqual(builder.toAddress, Self.poolAddress)
    }

    func testUnstakeBuildSendTransactionPropagatesMemoAndDestination() {
        let builder = TonUnstakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "1",
            poolAddress: Self.poolAddress
        )
        let tx = builder.buildSendTransaction(vault: .example)
        XCTAssertEqual(tx.memo, "w")
        XCTAssertEqual(tx.toAddress, Self.poolAddress)
    }
}
