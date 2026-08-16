//
//  RebondTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the THORChain node REBOND transaction: both memo shapes (whole bond
//  and partial bond), the 1e8 conversion the partial shape encodes, and — the
//  part that costs money if it drifts — the attached amount. Carries over the
//  golden fixtures from the deleted `FunctionCallReBondTests`, which captured
//  the legacy sub-model verbatim.
//

@testable import VultisigApp
import XCTest

final class RebondTransactionBuilderTests: XCTestCase {

    private static func makeBuilder(amount: Decimal = 0) -> RebondTransactionBuilder {
        RebondTransactionBuilder(
            coin: FunctionActionFixture.makeRUNE(),
            nodeAddress: "thor1node",
            newAddress: "thor1new",
            rebondAmount: amount
        )
    }

    // MARK: - Memo, whole bond (golden fixture)

    /// Pin: the legacy `FunctionCallReBond.toString()` returned
    /// `REBOND:<nodeAddress>:<newAddress>` with no third segment when the
    /// amount was zero. That shape moves the entire bond.
    func testWholeBondMemoOmitsTheAmountSegment() {
        XCTAssertEqual(Self.makeBuilder().memo, "REBOND:thor1node:thor1new")
    }

    // MARK: - Memo, partial bond (golden fixture)

    /// Pin: legacy appended `:<amount × 10^8>` as an integer. 100 RUNE is
    /// 10_000_000_000 base units — the exact fixture the deleted test used.
    func testPartialBondMemoAppendsTheAmountInBaseUnits() {
        XCTAssertEqual(Self.makeBuilder(amount: 100).memo, "REBOND:thor1node:thor1new:10000000000")
    }

    /// The exponent is 8, not `coin.decimals` and not 6 or 10: one base unit
    /// is 1e-8 RUNE. A wrong exponent here moves the wrong amount of someone's
    /// bond, so it gets its own assertion at the smallest representable value.
    func testOneBaseUnitEncodesAsOne() {
        let builder = Self.makeBuilder(amount: Decimal(string: "0.00000001")!)
        XCTAssertEqual(builder.memo, "REBOND:thor1node:thor1new:1")
        XCTAssertEqual(RebondTransactionBuilder.memoUnits(from: 1), 100_000_000)
    }

    /// `int64Value` truncates rather than rounds — the ninth decimal is
    /// dropped, matching the legacy conversion exactly.
    func testSubBaseUnitPrecisionIsTruncatedNotRounded() {
        let builder = Self.makeBuilder(amount: Decimal(string: "1.234567891")!)
        XCTAssertEqual(builder.memo, "REBOND:thor1node:thor1new:123456789")
    }

    /// Legacy parity for the shape the form's validator now rejects upstream:
    /// dust below one base unit scales to zero and emits `:0`, a rebond of
    /// nothing. It deliberately does *not* fall through to the whole-bond
    /// memo, which would move the entire stake.
    func testDustBelowOneBaseUnitEmitsAZeroSegmentRatherThanTheWholeBond() {
        let builder = Self.makeBuilder(amount: Decimal(string: "0.000000005")!)
        XCTAssertEqual(builder.memo, "REBOND:thor1node:thor1new:0")
    }

    // MARK: - Attached amount (fund safety)

    /// Pin: the legacy sub-model's `amount` was `.zero` regardless of the
    /// rebond amount — only the memo encodes it. `SendTransaction.amountInRaw`
    /// reads this as a human decimal, so anything else attaches real RUNE to a
    /// `MsgDeposit` that has no return path.
    func testAttachedAmountIsZeroForBothMemoShapes() {
        XCTAssertEqual(Self.makeBuilder().amount, "0")
        XCTAssertEqual(Self.makeBuilder(amount: 1_000).amount, "0")
        XCTAssertFalse(Self.makeBuilder(amount: 1_000).sendMaxAmount)
    }

    // MARK: - Memo dictionary (golden fixture)

    /// Pin: legacy `toDictionary()` omitted `rebondAmount` when the amount was
    /// zero, leaving three entries.
    func testMemoDictionaryOmitsTheAmountOnAWholeBond() {
        let dict = Self.makeBuilder().memoFunctionDictionary.allItems()
        XCTAssertEqual(dict["nodeAddress"], "thor1node")
        XCTAssertEqual(dict["newAddress"], "thor1new")
        XCTAssertNil(dict["rebondAmount"])
        XCTAssertEqual(dict["memo"], "REBOND:thor1node:thor1new")
        XCTAssertEqual(dict.count, 3)
    }

    /// Pin: legacy wrote the *human* amount into the dictionary (`"5"`), not
    /// the base-unit integer the memo carries.
    func testMemoDictionaryCarriesTheHumanAmountOnAPartialBond() {
        let dict = Self.makeBuilder(amount: 5).memoFunctionDictionary.allItems()
        XCTAssertEqual(dict["rebondAmount"], "5")
        XCTAssertEqual(dict["memo"], "REBOND:thor1node:thor1new:500000000")
        XCTAssertEqual(dict.count, 4)
    }

    // MARK: - Boundary (buildSendTransaction)

    /// Pin: the legacy boundary produced memo + zero amount + `.unspecified` +
    /// an empty `toAddress`.
    func testSendTransactionMatchesTheLegacyBoundary() {
        let coin = FunctionActionFixture.makeRUNE()
        let vault = FunctionActionFixture.makeVault(coins: [coin])
        let builder = RebondTransactionBuilder(
            coin: coin,
            nodeAddress: "thor1node",
            newAddress: "thor1new",
            rebondAmount: 100
        )

        let tx = builder.buildSendTransaction(vault: vault)

        XCTAssertEqual(tx.memo, "REBOND:thor1node:thor1new:10000000000")
        XCTAssertEqual(tx.amount, "0")
        XCTAssertEqual(tx.coin.ticker, "RUNE")
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertFalse(tx.isStakingOperation)
        XCTAssertNil(tx.wasmContractPayload)
        XCTAssertEqual(tx.memoFunctionDictionary["memo"], "REBOND:thor1node:thor1new:10000000000")
        XCTAssertEqual(tx.memoFunctionDictionary["nodeAddress"], "thor1node")
        XCTAssertEqual(tx.memoFunctionDictionary["newAddress"], "thor1new")
        XCTAssertEqual(tx.memoFunctionDictionary["rebondAmount"], "100")
        // Builders never take gas; `FunctionTransactionScreen.onVerify` fetches
        // it before the verify screen. The legacy sub-model took it as a
        // parameter.
        XCTAssertEqual(tx.gas, .zero)
    }

    /// REBOND is not a staking operation and carries no staking payload — the
    /// `FunctionTransactionScreen` fee path branches on these.
    func testCarriesNoStakingPayload() {
        let builder = Self.makeBuilder(amount: 100)
        XCTAssertNil(builder.cosmosStakingPayload)
        XCTAssertNil(builder.solanaStakingPayload)
        XCTAssertNil(builder.limitCancelContext)
    }
}
