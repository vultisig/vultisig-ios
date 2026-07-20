//
//  CancelLimitOrderTransactionBuilderTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class CancelLimitOrderTransactionBuilderTests: XCTestCase {

    /// A cancel is always a THORChain `MsgDeposit`, so the fixture has to be a
    /// THORChain coin. `Coin.example` is Bitcoin, and `isDeposit` is hardcoded
    /// false for UTXO chains — testing against it would assert the opposite of
    /// what production does.
    private static let rune: Coin = {
        let asset = CoinMeta(
            chain: .thorChain,
            ticker: "RUNE",
            logo: "rune",
            decimals: 8,
            priceProviderId: "thorchain",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "thor1sender", hexPublicKey: "HexPublicKeyExample")
    }()

    private func makeBuilder(
        memo: String = "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0"
    ) -> CancelLimitOrderTransactionBuilder {
        CancelLimitOrderTransactionBuilder(
            coin: Self.rune,
            memo: memo,
            sourceAssetDisplay: "THOR.RUNE",
            targetAssetDisplay: "BTC.BTC"
        )
    }

    /// ⚠️ Fund-safety, and the invariant is the AMOUNT, not the coins array.
    ///
    /// THORNode donates funds arriving with an `m=<` transaction to the pool,
    /// gated on `!msg.DepositAmount.IsZero()`. The signer always emits a
    /// one-element `coins` array and omits only the amount, so an empty array is
    /// not a shape this app can produce — asserting on emptiness would be
    /// asserting something that is never true and never needed. A non-zero
    /// amount is what would staple an unrecoverable gift to a cancel.
    ///
    /// `sendMaxAmount` is asserted alongside because it is the other way a
    /// non-zero value could reach the wire.
    func testSendsAZeroAmountSoNothingIsDonatedToThePool() {
        XCTAssertEqual(makeBuilder().amount, "0")
        XCTAssertFalse(makeBuilder().sendMaxAmount)
    }

    /// ⚠️ `SendCryptoLogic.isDeposit` keys off this dictionary being NON-EMPTY,
    /// not off the memo. An empty dictionary silently signs the `m=<` memo as a
    /// plain `MsgSend` — a 0-RUNE self-transfer that broadcasts fine, costs a
    /// fee, and cancels nothing.
    func testMemoFunctionDictionaryIsNonEmptySoTheTxIsBuiltAsADeposit() {
        let dict = makeBuilder().memoFunctionDictionary.allItems()

        XCTAssertFalse(dict.isEmpty)
        XCTAssertTrue(
            SendCryptoLogic.isDeposit(coin: Self.rune, memoFunctionDictionary: dict),
            "a cancel must be built as a MsgDeposit, not a MsgSend"
        )
    }

    func testCarriesTheMemoVerbatim() {
        let memo = "m=<:250000000eth-usdc-0xa0b:1234567THOR.RUNE:0"

        XCTAssertEqual(makeBuilder(memo: memo).memo, memo)
        XCTAssertEqual(makeBuilder(memo: memo).memoFunctionDictionary.allItems()["memo"], memo)
    }

    func testUsesTheMemoOnlyDepositShape() {
        let builder = makeBuilder()

        XCTAssertEqual(builder.toAddress, "")
        XCTAssertEqual(builder.transactionType, .unspecified)
        XCTAssertNil(builder.wasmContractPayload)
    }

    /// The built `SendTransaction` is what actually reaches the signer, so the
    /// zero amount and the deposit-ness are asserted on it too — not just on the
    /// builder's properties.
    func testBuiltSendTransactionKeepsTheZeroAmountAndDepositShape() {
        let tx = makeBuilder().buildSendTransaction(vault: .example)

        XCTAssertEqual(tx.amount, "0")
        XCTAssertEqual(tx.memo, "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0")
        XCTAssertFalse(tx.memoFunctionDictionary.isEmpty)
        XCTAssertFalse(tx.isStakingOperation)
        // The property the signer actually reads to decide whether to stamp an
        // amount onto the deposit coin.
        XCTAssertEqual(tx.amountInRaw, .zero)
    }
}
