//
//  CustomMemoTransactionBuilderTests.swift
//  VultisigAppTests
//
//  The raw-memo escape hatch has exactly one contract: whatever the user typed
//  is what the chain sees. Everything here exists to make a future
//  "helpful" trim, lowercase or escape fail loudly.
//
//  Also carries the boundary assertions from the deleted
//  `FunctionCallCustomTests` and `testCustomParity`: the memo, the attached
//  amount, the empty destination, `.unspecified`, and a one-entry memo
//  dictionary keyed `memo`.
//

@testable import VultisigApp
import XCTest

final class CustomMemoTransactionBuilderTests: XCTestCase {

    private static func rune(rawBalance: String = "100000000000") -> Coin {
        FunctionActionFixture.makeRUNE(rawBalance: rawBalance)
    }

    private static func cacao() -> Coin {
        FunctionActionFixture.makeCoin(
            .mayaChain,
            ticker: "CACAO",
            decimals: 10,
            isNative: true,
            address: FunctionActionFixture.mayaAddress
        )
    }

    // MARK: - The memo is the user's string, byte for byte

    /// The strings a normaliser would quietly change. Each is asserted as an
    /// exact `==` against what the legacy sub-model's `toString()` returned,
    /// which was the stored property itself.
    ///
    /// Compared as **UTF-8 bytes**, not as `String`: Swift's `==` and `count`
    /// are Unicode-canonical, so an NFC/NFD normaliser inserted into this path
    /// would change the bytes the chain sees while still comparing equal. The
    /// last two fixtures are the same text composed and decomposed, and they
    /// must stay distinct all the way to the builder.
    func testTheMemoIsCarriedVerbatim() {
        let awkward = [
            "arbitrary-memo-string",
            "SWAP:BTC.BTC:bc1qexample:12345/3/0",
            "  leading and trailing spaces  ",
            "\ttab-prefixed",
            "trailing newline\n",
            "MiXeD CaSe MeMo",
            "colons:everywhere:::",
            "spaces in the middle",
            "unicode ünïcodé 中文 🚀",
            "quotes \"double\" and 'single'",
            "backslash \\ and slash /",
            "=+equals+plus=",
            " ",
            "0",
            "caf\u{00E9}",          // precomposed é
            "cafe\u{0301}"          // e + combining acute — same text, different bytes
        ]

        for memo in awkward {
            let builder = CustomMemoTransactionBuilder(
                coin: Self.rune(),
                customMemo: memo,
                customAmount: .zero
            )
            XCTAssertEqual(
                Array(builder.memo.utf8),
                Array(memo.utf8),
                "The memo's bytes changed: \(memo.debugDescription)"
            )
        }
    }

    /// The composed and decomposed fixtures above are the same `String` to
    /// Swift, so without this the byte assertion could be read as accidental.
    /// They are different memos on the wire.
    func testComposedAndDecomposedMemosAreDistinctOnTheWire() {
        let composed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        XCTAssertEqual(composed, decomposed, "Fixture must be canonically equivalent to be worth testing")
        XCTAssertNotEqual(Array(composed.utf8), Array(decomposed.utf8))

        let vault = FunctionActionFixture.makeVault(coins: [Self.rune()])
        let composedTx = CustomMemoTransactionBuilder(
            coin: Self.rune(),
            customMemo: composed,
            customAmount: .zero
        ).buildSendTransaction(vault: vault)
        let decomposedTx = CustomMemoTransactionBuilder(
            coin: Self.rune(),
            customMemo: decomposed,
            customAmount: .zero
        ).buildSendTransaction(vault: vault)

        XCTAssertEqual(Array(composedTx.memo.utf8), Array(composed.utf8))
        XCTAssertEqual(Array(decomposedTx.memo.utf8), Array(decomposed.utf8))
    }

    /// A separate, blunter statement of the same rule at the `SendTransaction`
    /// boundary — the builder's `memo` and the transaction's must be the same
    /// string, and both must be the input.
    func testTheSendTransactionCarriesTheMemoVerbatim() {
        let coin = Self.rune()
        let vault = FunctionActionFixture.makeVault(coins: [coin])
        let memo = "  Tricky:Memo  With  Spaces  \n"

        let tx = CustomMemoTransactionBuilder(
            coin: coin,
            customMemo: memo,
            customAmount: .zero
        ).buildSendTransaction(vault: vault)

        XCTAssertEqual(Array(tx.memo.utf8), Array(memo.utf8))
    }

    // MARK: - Attached amount

    /// Legacy: `amount.formatToDecimal(digits: coin.decimals)`. A memo-only
    /// deposit attaches nothing, and `Decimal.zero` formats to "0" at any
    /// precision — the string `SendCryptoLogic.amountInRaw` scales by
    /// `10^decimals`.
    func testAZeroAmountFormatsToZeroOnBothChains() {
        for coin in [Self.rune(), Self.cacao()] {
            let builder = CustomMemoTransactionBuilder(coin: coin, customMemo: "memo", customAmount: .zero)
            XCTAssertEqual(builder.amount, "0", "\(coin.chain.rawValue) attached a non-zero amount")
        }
    }

    /// The attached amount round-trips through the same locale-aware pair the
    /// legacy sub-model used: rendered by `Decimal.formatToDecimal(digits:)`,
    /// read back by `SendCryptoLogic.amountDecimal`. A mismatch here is the
    /// class of bug that signs ten times the intended amount.
    func testTheAttachedAmountRoundTripsThroughTheSendTransaction() {
        let coin = Self.rune()
        let vault = FunctionActionFixture.makeVault(coins: [coin])

        for amount in [Decimal(0), Decimal(1), Decimal(string: "1.5")!, Decimal(string: "0.00000001")!] {
            let tx = CustomMemoTransactionBuilder(
                coin: coin,
                customMemo: "memo",
                customAmount: amount
            ).buildSendTransaction(vault: vault)

            XCTAssertEqual(tx.amountDecimal, amount, "\(amount) did not survive the string round-trip")
        }
    }

    /// Fraction digits past the coin's precision are dropped, not rounded up:
    /// the value was already measured against the balance.
    func testTheAmountIsTruncatedToTheCoinsPrecision() {
        let cacao = Self.cacao()
        let builder = CustomMemoTransactionBuilder(
            coin: cacao,
            customMemo: "memo",
            customAmount: Decimal(string: "1.99999999999999")!
        )
        XCTAssertEqual(builder.amount.toDecimal(), Decimal(string: "1.9999999999")!)
    }

    // MARK: - The rest of the transaction

    /// Every field the legacy `toSendTransaction` produced, on both chains.
    func testTheSendTransactionBoundaryMatchesTheLegacySubModel() {
        for coin in [Self.rune(), Self.cacao()] {
            let vault = FunctionActionFixture.makeVault(coins: [coin])
            let builder = CustomMemoTransactionBuilder(
                coin: coin,
                customMemo: "arbitrary-memo-string",
                customAmount: .zero
            )
            let tx = builder.buildSendTransaction(vault: vault)

            XCTAssertEqual(tx.memo, "arbitrary-memo-string")
            XCTAssertEqual(tx.transactionType, .unspecified)
            // A `MsgDeposit` is addressed by its memo; the legacy sub-model
            // built on `SendTransaction.empty`, which left this empty too.
            XCTAssertEqual(tx.toAddress, "")
            XCTAssertEqual(tx.fromAddress, coin.address)
            XCTAssertFalse(tx.sendMaxAmount)
            XCTAssertFalse(tx.isStakingOperation)
            XCTAssertNil(tx.wasmContractPayload)
            XCTAssertNil(builder.cosmosStakingPayload)
            XCTAssertNil(builder.solanaStakingPayload)
        }
    }

    /// Legacy `toDictionary()` set exactly one key. The verify screen renders
    /// these rows, so an extra key is a field the transaction does not have.
    func testTheMemoDictionaryHasOneEntryKeyedMemo() {
        let builder = CustomMemoTransactionBuilder(
            coin: Self.rune(),
            customMemo: "hello",
            customAmount: .zero
        )
        let dict = builder.memoFunctionDictionary.allItems()

        XCTAssertEqual(dict["memo"], "hello")
        XCTAssertEqual(dict.count, 1)
    }
}
