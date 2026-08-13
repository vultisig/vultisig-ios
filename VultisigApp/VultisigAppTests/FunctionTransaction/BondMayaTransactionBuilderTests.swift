//
//  BondMayaTransactionBuilderTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

/// ⚠️ These tests exist for the ATTACHED AMOUNT, which the builder used to
/// hardcode to `"1"` for both directions.
///
/// The builder's `amount` is a human decimal string: the send pipeline runs it
/// through `SendCryptoLogic.amountInRaw`, which multiplies by `10^decimals`
/// before it reaches the keysign payload. So `"1"` on an UNBOND signs a whole
/// CACAO where a 1e-8 dust transfer is intended — 10^8 times too much, on the
/// direction the user takes to get their money out.
final class BondMayaTransactionBuilderTests: XCTestCase {

    private static let cacao = Coin(
        asset: TokensStore.cacao,
        address: "maya1sender",
        hexPublicKey: "HexPublicKeyExample"
    )

    private func makeBuilder(isBond: Bool) -> BondMayaTransactionBuilder {
        BondMayaTransactionBuilder(
            coin: Self.cacao,
            isBond: isBond,
            nodeAddress: "maya1node",
            selectedAsset: "MAYA.CACAO",
            lpUnits: 1_000
        )
    }

    // MARK: - Attached amount

    /// Legacy pinned the unbond dust at `1 / pow(10, 8)` CACAO
    /// (`FunctionCallUnbondMayaChain.amount`, covered by its own
    /// `testAmountIsFixedDust`). CACAO carries **10** decimals, so that is 100
    /// base units — asserted in base units because that is what is signed, and
    /// because the string form is locale-formatted.
    func testUnbondAttachesTheFixedDustNotAWholeCacao() {
        let tx = makeBuilder(isBond: false).buildSendTransaction(vault: .example)

        XCTAssertEqual(
            tx.amountDecimal, 1 / pow(Decimal(10), 8),
            "unbond must attach 1e-8 CACAO, matching what this app has always signed"
        )
        XCTAssertEqual(
            tx.amountInRaw, BigInt(100),
            "1e-8 CACAO at 10 decimals is 100 base units"
        )
    }

    /// A zero-amount unbond would broadcast without carrying the memo the node
    /// reads, so the dust has a floor as well as a ceiling.
    func testUnbondDustIsNonZero() {
        XCTAssertGreaterThan(makeBuilder(isBond: false).buildSendTransaction(vault: .example).amountInRaw, .zero)
    }

    /// Bond keeps the 1 CACAO the legacy `FunctionCallBondMayaChain.amount`
    /// sent, so migrating the user to the DeFi tab does not change what a bond
    /// costs them.
    func testBondAttachesOneWholeCacao() {
        let tx = makeBuilder(isBond: true).buildSendTransaction(vault: .example)

        XCTAssertEqual(tx.amountDecimal, 1)
        XCTAssertEqual(tx.amountInRaw, BigInt(10).power(TokensStore.cacao.decimals))
    }

    /// The regression itself: one shared constant served both directions. Pin
    /// that they diverge, so re-collapsing them fails here rather than on chain.
    func testBondAndUnbondDoNotShareAnAmount() {
        let bond = makeBuilder(isBond: true).buildSendTransaction(vault: .example)
        let unbond = makeBuilder(isBond: false).buildSendTransaction(vault: .example)

        XCTAssertGreaterThan(bond.amountInRaw, unbond.amountInRaw)
        XCTAssertEqual(bond.amountInRaw, unbond.amountInRaw * BigInt(100_000_000))
    }

    // MARK: - Memo

    func testMemoShapeMatchesTheLegacyMemoForBothDirections() {
        XCTAssertEqual(makeBuilder(isBond: true).memo, "BOND:MAYA.CACAO:1000:maya1node")
        XCTAssertEqual(makeBuilder(isBond: false).memo, "UNBOND:MAYA.CACAO:1000:maya1node")
    }

    func testMemoFunctionDictionaryCarriesTheLegacyKeys() {
        let dict = makeBuilder(isBond: false).memoFunctionDictionary.allItems()

        XCTAssertEqual(dict["asset"], "MAYA.CACAO")
        XCTAssertEqual(dict["LPUNITS"], "1000")
        XCTAssertEqual(dict["nodeAddress"], "maya1node")
        XCTAssertEqual(dict["memo"], "UNBOND:MAYA.CACAO:1000:maya1node")
    }

    /// A memo-only MsgDeposit: no recipient, and never a max-send.
    func testUsesTheMemoOnlyDepositShape() {
        for isBond in [true, false] {
            let builder = makeBuilder(isBond: isBond)

            XCTAssertEqual(builder.toAddress, "")
            XCTAssertFalse(builder.sendMaxAmount)
            XCTAssertEqual(builder.transactionType, .unspecified)
            XCTAssertNil(builder.wasmContractPayload)
        }
    }
}
