//
//  TonStakeTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the TON DeFi stake/unstake transaction builders: the per-implementation
//  nominator-pool deposit/withdraw comments (whales → "Stake"/"Withdraw",
//  tf → "d"/"w"), the bounceable pool address as the transaction destination,
//  and the `SendTransaction` propagation. Also pins the `TonStakingComment`
//  mapping that resolves those comments. Mirrors
//  `CosmosDelegateTransactionBuilderTests`.
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

    // MARK: - TonStakingComment mapping

    func testCommentMappingForWhales() {
        XCTAssertEqual(TonStakingComment.deposit(for: "whales"), "Stake")
        XCTAssertEqual(TonStakingComment.withdraw(for: "whales"), "Withdraw")
    }

    func testCommentMappingForTf() {
        XCTAssertEqual(TonStakingComment.deposit(for: "tf"), "d")
        XCTAssertEqual(TonStakingComment.withdraw(for: "tf"), "w")
    }

    func testCommentMappingForUnknownIsNil() {
        XCTAssertNil(TonStakingComment.deposit(for: "liquidTF"))
        XCTAssertNil(TonStakingComment.withdraw(for: "liquidTF"))
        XCTAssertNil(TonStakingComment.deposit(for: nil))
        XCTAssertNil(TonStakingComment.withdraw(for: nil))
        XCTAssertNil(TonStakingComment.deposit(for: "somethingNew"))
    }

    // MARK: - Stake (per-implementation deposit comment)

    func testStakeBuilderEmitsWhalesDepositComment() {
        let builder = TonStakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "60",
            poolAddress: Self.poolAddress,
            memo: "Stake"
        )
        XCTAssertEqual(builder.memo, "Stake")
    }

    func testStakeBuilderEmitsTfDepositComment() {
        let builder = TonStakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "60",
            poolAddress: Self.poolAddress,
            memo: "d"
        )
        XCTAssertEqual(builder.memo, "d")
    }

    func testStakeBuilderSendsToPoolAddress() {
        let builder = TonStakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "60",
            poolAddress: Self.poolAddress,
            memo: "Stake"
        )
        XCTAssertEqual(builder.toAddress, Self.poolAddress)
    }

    func testStakeBuilderMemoDictionaryCarriesPoolAndMemo() {
        let builder = TonStakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "60",
            poolAddress: Self.poolAddress,
            memo: "Stake"
        )
        let dict = builder.memoFunctionDictionary.allItems()
        XCTAssertEqual(dict["nodeAddress"], Self.poolAddress)
        XCTAssertEqual(dict["memo"], "Stake")
    }

    func testStakeBuildSendTransactionPropagatesMemoAndDestination() {
        let builder = TonStakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "60",
            poolAddress: Self.poolAddress,
            memo: "Stake"
        )
        let tx = builder.buildSendTransaction(vault: .example)
        XCTAssertEqual(tx.memo, "Stake")
        XCTAssertEqual(tx.toAddress, Self.poolAddress)
        XCTAssertEqual(tx.amount, "60")
    }

    // MARK: - Unstake (per-implementation withdraw comment)

    func testUnstakeBuilderEmitsWhalesWithdrawComment() {
        let builder = TonUnstakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "1",
            poolAddress: Self.poolAddress,
            memo: "Withdraw"
        )
        XCTAssertEqual(builder.memo, "Withdraw")
    }

    func testUnstakeBuilderEmitsTfWithdrawComment() {
        let builder = TonUnstakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "1",
            poolAddress: Self.poolAddress,
            memo: "w"
        )
        XCTAssertEqual(builder.memo, "w")
    }

    func testUnstakeBuilderSendsToPoolAddress() {
        let builder = TonUnstakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "1",
            poolAddress: Self.poolAddress,
            memo: "Withdraw"
        )
        XCTAssertEqual(builder.toAddress, Self.poolAddress)
    }

    func testUnstakeBuildSendTransactionPropagatesMemoAndDestination() {
        let builder = TonUnstakeTransactionBuilder(
            coin: Self.makeTonCoin(),
            amount: "1",
            poolAddress: Self.poolAddress,
            memo: "Withdraw"
        )
        let tx = builder.buildSendTransaction(vault: .example)
        XCTAssertEqual(tx.memo, "Withdraw")
        XCTAssertEqual(tx.toAddress, Self.poolAddress)
    }
}
