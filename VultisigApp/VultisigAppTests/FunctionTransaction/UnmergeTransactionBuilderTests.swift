//
//  UnmergeTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the THORChain RUJI UNMERGE transaction. The memo matters more here than
//  on any other migrated operation: `THORChainHelper` builds the wasm message by
//  re-parsing the share count out of the memo string, so the memo IS the
//  instruction — a wrong digit in it withdraws a different amount.
//
//  Carries over the golden fixtures from the deleted `FunctionCallCosmosUnmergeTests`
//  and `testUnmergeParity`, which captured the legacy sub-model verbatim.
//

import BigInt
@testable import VultisigApp
import XCTest

final class UnmergeTransactionBuilderTests: XCTestCase {

    private static let contract = "thor1mergecontract"

    private static func makeBuilder(
        denom: String = "THOR.RUJI",
        shares: BigInt,
        coin: Coin = FunctionCallFixture.makeRUJI()
    ) -> UnmergeTransactionBuilder {
        UnmergeTransactionBuilder(
            coin: coin,
            denom: denom,
            contractAddress: contract,
            shares: shares
        )
    }

    // MARK: - Memo (golden fixtures)

    /// Pin: legacy `toString()` returned
    /// `unmerge:<selectedToken.lowercased()>:<amount × 1e8 as an integer>`.
    /// 1.5 shares is 150_000_000 base units — the exact fixture the deleted test
    /// used, reached here through the exact parser rather than through a Double.
    func testMemoMatchesTheLegacyShareEncoding() {
        let shares = UnmergeShares.parse("1.5", locale: Locale(identifier: "en_US"))!
        XCTAssertEqual(Self.makeBuilder(shares: shares).memo, "unmerge:thor.ruji:150000000")
    }

    func testWholeShareMemo() {
        XCTAssertEqual(Self.makeBuilder(shares: BigInt(100_000_000)).memo, "unmerge:thor.ruji:100000000")
    }

    /// Pin: the deleted test's fractional fixture. `0.000000014` shares is 1.4
    /// base units, which lands on 1 either way — legacy rounded, this truncates.
    func testSubBaseUnitFixtureStillLandsOnOne() {
        let shares = UnmergeShares.parse("0.000000014", locale: Locale(identifier: "en_US"))!
        XCTAssertEqual(Self.makeBuilder(shares: shares).memo, "unmerge:thor.ruji:1")
    }

    // MARK: - Casing (both halves)

    /// Two separate lowercase requirements, pinned separately because they have
    /// different reasons: the operation word is a literal the contract matches
    /// on, and the denom is lowercased from whatever the picker held. The
    /// signing path lowercases the whole memo before parsing it, so an uppercase
    /// denom would sign a memo that no longer names what the user picked.
    func testMemoIsLowercaseInBothTheOperationAndTheDenom() {
        let memo = Self.makeBuilder(denom: "THOR.KUJI", shares: BigInt(1)).memo
        XCTAssertEqual(memo, "unmerge:thor.kuji:1")
        XCTAssertTrue(memo.hasPrefix("unmerge:"))
        XCTAssertEqual(memo, memo.lowercased())
    }

    /// An already-lowercase denom — what the catalog actually supplies — is
    /// unchanged.
    func testLowercaseDenomIsPassedThrough() {
        XCTAssertEqual(
            Self.makeBuilder(denom: "thor.kuji", shares: BigInt(1)).memo,
            "unmerge:thor.kuji:1"
        )
    }

    // MARK: - Precision (the reason this migration exists)

    /// The named defect. `123456789.12345679` shares is `12345678912345679`
    /// base units; the legacy Decimal → Double → `%.0f` path answers a
    /// different integer, and the contract acts on whichever one the memo
    /// carries.
    func testMemoKeepsAShareCountThatWouldRoundThroughDouble() {
        let shares = UnmergeShares.parse("123456789.12345679", locale: Locale(identifier: "en_US"))!
        XCTAssertEqual(
            Self.makeBuilder(denom: "thor.kuji", shares: shares).memo,
            "unmerge:thor.kuji:12345678912345679"
        )
    }

    /// Well past any `Double`: a share count with 25 significant digits still
    /// reaches the memo digit for digit.
    func testMemoCarriesAnArbitraryPrecisionShareCount() {
        let shares = BigInt("1234567890123456789012345")
        XCTAssertEqual(
            Self.makeBuilder(denom: "thor.kuji", shares: shares).memo,
            "unmerge:thor.kuji:1234567890123456789012345"
        )
    }

    // MARK: - Attached amount (fund safety)

    /// UNMERGE attaches nothing: the wasm execute carries an empty `coins`
    /// array and the contract returns the merged tokens on its own.
    ///
    /// This is the one place the migration deviates from the legacy sub-model,
    /// which attached the human share count. That value never reached the chain
    /// but the app's own pre-flight read it: shares live in the contract, not
    /// the wallet, so comparing them to the merged token's wallet balance
    /// rejected a transaction the chain would have accepted.
    func testAttachedAmountIsZeroRegardlessOfTheShareCount() {
        XCTAssertEqual(Self.makeBuilder(shares: BigInt(1)).amount, "0")
        XCTAssertEqual(Self.makeBuilder(shares: BigInt("999999999999999999")).amount, "0")
        XCTAssertFalse(Self.makeBuilder(shares: BigInt(1)).sendMaxAmount)
    }

    // MARK: - Memo dictionary (golden fixture)

    /// Pin: legacy `toDictionary()` wrote exactly these three keys, with the
    /// token in the uppercase form the dropdown displayed.
    func testMemoDictionaryMatchesTheLegacyKeys() {
        let dict = Self.makeBuilder(denom: "thor.ruji", shares: BigInt(100_000_000))
            .memoFunctionDictionary
            .allItems()
        XCTAssertEqual(dict["destinationAddress"], Self.contract)
        XCTAssertEqual(dict["selectedToken"], "THOR.RUJI")
        XCTAssertEqual(dict["memo"], "unmerge:thor.ruji:100000000")
        XCTAssertEqual(dict.count, 3)
    }

    // MARK: - Boundary (buildSendTransaction)

    /// Pin: the legacy boundary routed to the merge contract with
    /// `.thorUnmerge` and the memo above. The amount is the deliberate
    /// deviation documented on `testAttachedAmountIsZeroRegardlessOfTheShareCount`.
    func testSendTransactionMatchesTheLegacyBoundary() {
        let ruji = FunctionCallFixture.makeRUJI()
        let vault = FunctionCallFixture.makeVault(coins: [FunctionCallFixture.makeRUNE(), ruji])
        let builder = Self.makeBuilder(denom: "THOR.RUJI", shares: BigInt(100_000_000), coin: ruji)

        let tx = builder.buildSendTransaction(vault: vault)

        XCTAssertEqual(tx.memo, "unmerge:thor.ruji:100000000")
        XCTAssertEqual(tx.transactionType, .thorUnmerge)
        XCTAssertEqual(tx.toAddress, Self.contract)
        XCTAssertEqual(tx.coin.ticker, "RUJI")
        XCTAssertEqual(tx.amount, "0")
        XCTAssertFalse(tx.isStakingOperation)
        XCTAssertNil(tx.wasmContractPayload)
        XCTAssertEqual(tx.memoFunctionDictionary["destinationAddress"], Self.contract)
        XCTAssertEqual(tx.memoFunctionDictionary["selectedToken"], "THOR.RUJI")
        XCTAssertEqual(tx.memoFunctionDictionary["memo"], "unmerge:thor.ruji:100000000")
        // Builders never take gas; `FunctionTransactionScreen.onVerify` fetches
        // it before the verify screen. The legacy sub-model took it as a
        // parameter.
        XCTAssertEqual(tx.gas, .zero)
    }

    /// UNMERGE is not a staking operation and carries no staking payload — the
    /// `FunctionTransactionScreen` fee path branches on these.
    func testCarriesNoStakingPayload() {
        let builder = Self.makeBuilder(shares: BigInt(1))
        XCTAssertNil(builder.cosmosStakingPayload)
        XCTAssertNil(builder.solanaStakingPayload)
        XCTAssertNil(builder.limitCancelContext)
    }
}
