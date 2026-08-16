//
//  MergeTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the Rujira MERGE transaction: the exact memo string — casing included
//  — the per-token destination contract, and the attached amount. A memo
//  THORChain does not recognise is a silently failed merge, not a rejected
//  one, so these are golden fixtures carried from the deleted
//  `FunctionCallCosmosMergeTests`.
//

@testable import VultisigApp
import XCTest

@MainActor
final class MergeTransactionBuilderTests: XCTestCase {

    /// The catalog's own contract for `thor.kuji`, spelled out rather than
    /// read from the catalog so a silent edit to `ThorchainMergeTokens` fails
    /// here instead of passing against itself.
    private static let kujiContract = "thor14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9s3p2nzy"

    private static func makeKuji(rawBalance: String = "1000000000") -> Coin {
        FunctionActionFixture.makeCoin(
            .thorChain,
            ticker: "KUJI",
            decimals: 8,
            isNative: false,
            rawBalance: rawBalance,
            address: FunctionActionFixture.thorAddress
        )
    }

    private static func makeBuilder(
        denom: String = "THOR.KUJI",
        contractAddress: String = kujiContract,
        amount: String = "1.5"
    ) -> MergeTransactionBuilder {
        MergeTransactionBuilder(
            coin: makeKuji(),
            denom: denom,
            contractAddress: contractAddress,
            amount: amount
        )
    }

    // MARK: - Memo (golden fixture)

    /// Pin: legacy `toString()` was `"merge:\(selectedToken.value)"`, and
    /// `selectedToken.value` was the catalog denom **uppercased**.
    func testMemoIsLowercaseMergeColonUppercaseDenom() {
        XCTAssertEqual(Self.makeBuilder().memo, "merge:THOR.KUJI")
    }

    /// The two halves of the casing, asserted separately so a "tidy-up" that
    /// normalises either one fails loudly.
    func testMemoPrefixIsLowercaseAndTheDenomIsNotNormalised() {
        let memo = Self.makeBuilder().memo
        XCTAssertTrue(memo.hasPrefix("merge:"), "The prefix is lowercase on the wire")
        XCTAssertFalse(memo.hasPrefix("MERGE:"))
        XCTAssertEqual(memo.replacingOccurrences(of: "merge:", with: ""), "THOR.KUJI")
    }

    /// Every catalog entry, not just the first one: the memo names the token
    /// and the transaction is addressed to that token's own contract, so a
    /// mismatched pair deposits into the wrong merge pool.
    func testMemoAndDestinationMatchEveryCatalogEntry() {
        for token in ThorchainMergeTokens.tokensToMerge {
            let builder = Self.makeBuilder(
                denom: token.denom.uppercased(),
                contractAddress: token.wasmContractAddress
            )

            XCTAssertEqual(builder.memo, "merge:\(token.denom.uppercased())")
            XCTAssertEqual(builder.toAddress, token.wasmContractAddress)
            XCTAssertEqual(builder.memo.lowercased(), "merge:\(token.denom.lowercased())")
        }
    }

    // MARK: - Attached amount

    /// The amount rides through verbatim — `SendTransaction.amountInRaw` reads
    /// it as a human decimal and scales by the coin's decimals, exactly as the
    /// legacy `amount.formatToDecimal(digits:)` string did.
    func testAmountIsCarriedVerbatim() {
        XCTAssertEqual(Self.makeBuilder(amount: "1.5").amount, "1.5")
        XCTAssertFalse(Self.makeBuilder().sendMaxAmount)
    }

    // MARK: - Boundary (buildSendTransaction)

    /// Pin: the legacy boundary produced `toAddress` = the merge contract,
    /// `.thorMerge`, the memo, and a two-entry memo dictionary keyed
    /// `destinationAddress` / `memo`.
    func testSendTransactionMatchesTheLegacyBoundary() {
        let coin = Self.makeKuji()
        let vault = FunctionActionFixture.makeVault(coins: [FunctionActionFixture.makeRUNE(), coin])
        let builder = MergeTransactionBuilder(
            coin: coin,
            denom: "THOR.KUJI",
            contractAddress: Self.kujiContract,
            amount: "1.5"
        )

        let tx = builder.buildSendTransaction(vault: vault)

        XCTAssertEqual(tx.memo, "merge:THOR.KUJI")
        XCTAssertEqual(tx.amount, "1.5")
        XCTAssertEqual(tx.coin.ticker, "KUJI")
        XCTAssertEqual(tx.toAddress, Self.kujiContract)
        XCTAssertEqual(tx.transactionType, .thorMerge)
        XCTAssertFalse(tx.isStakingOperation)
        // `.thorMerge` builds its own wasm message downstream from the memo,
        // the recipient and the amount — there is no payload to carry.
        XCTAssertNil(tx.wasmContractPayload)
        // The legacy sub-model took `gas` as a parameter; builders never do —
        // `FunctionTransactionScreen.onVerify` fetches it before navigating.
        XCTAssertEqual(tx.gas, .zero)
        XCTAssertEqual(tx.memoFunctionDictionary["destinationAddress"], Self.kujiContract)
        XCTAssertEqual(tx.memoFunctionDictionary["memo"], "merge:THOR.KUJI")
        XCTAssertEqual(tx.memoFunctionDictionary.count, 2)
    }

    /// MERGE is not a staking operation and cancels no order — the
    /// `FunctionTransactionScreen` fee path branches on these.
    func testCarriesNoStakingPayload() {
        let builder = Self.makeBuilder()
        XCTAssertNil(builder.cosmosStakingPayload)
        XCTAssertNil(builder.solanaStakingPayload)
        XCTAssertNil(builder.limitCancelContext)
    }
}
