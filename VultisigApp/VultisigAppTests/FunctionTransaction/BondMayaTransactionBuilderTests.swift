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
/// CACAO where one base unit is intended — 10^10 times too much, on the
/// direction the user takes to get their money out.
final class BondMayaTransactionBuilderTests: XCTestCase {

    private static let cacao = Coin(
        asset: TokensStore.cacao,
        address: "maya1sender",
        hexPublicKey: "HexPublicKeyExample"
    )

    private func makeBuilder(isBond: Bool, coin: Coin = BondMayaTransactionBuilderTests.cacao) -> BondMayaTransactionBuilder {
        BondMayaTransactionBuilder(
            coin: coin,
            isBond: isBond,
            nodeAddress: "maya1node",
            selectedAsset: "MAYA.CACAO",
            lpUnits: 1_000
        )
    }

    /// A CACAO-shaped coin with a different `decimals`, to prove the dust is
    /// derived rather than written down.
    private static func cacao(decimals: Int) -> Coin {
        let asset = CoinMeta(
            chain: .mayaChain,
            ticker: "CACAO",
            logo: "cacao",
            decimals: decimals,
            priceProviderId: "cacao",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "maya1sender", hexPublicKey: "HexPublicKeyExample")
    }

    // MARK: - Attached amount

    /// ⚠️ The whole point: exactly ONE base unit.
    ///
    /// Asserted in base units, not on the string, because base units are what
    /// gets signed and the string form is locale-formatted. Android
    /// (`UnbondStrategy`, `BigInteger.ONE`) and Windows
    /// (`getDustDepositAmountString`) send the same. iOS's own legacy screen
    /// sent `1e-8` CACAO — 100 base units — and was the outlier; that parity
    /// was dropped deliberately in favour of the other clients.
    func testUnbondAttachesExactlyOneBaseUnit() {
        let tx = makeBuilder(isBond: false).buildSendTransaction(vault: .example)

        XCTAssertEqual(
            tx.amountInRaw, BigInt(1),
            "unbond must attach one base unit — not 100 (legacy iOS), and not 10^10 (a whole CACAO)"
        )
        XCTAssertEqual(tx.amountDecimal, 1 / pow(Decimal(10), TokensStore.cacao.decimals))
    }

    /// The dust must be *derived* from the coin's decimals. A literal exponent
    /// is one base unit for exactly one `decimals` value and a multiple of it
    /// for every other, which is how the 100x came about in the first place.
    func testUnbondDustTracksTheCoinsDecimals() {
        for decimals in [6, 8, 10, 18] {
            let tx = makeBuilder(isBond: false, coin: Self.cacao(decimals: decimals))
                .buildSendTransaction(vault: .example)

            XCTAssertEqual(
                tx.amountInRaw, BigInt(1),
                "one base unit at \(decimals) decimals must still be one base unit"
            )
        }
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
        XCTAssertEqual(
            bond.amountInRaw,
            unbond.amountInRaw * BigInt(10).power(TokensStore.cacao.decimals),
            "a whole CACAO is 10^decimals base units; the dust is one"
        )
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
