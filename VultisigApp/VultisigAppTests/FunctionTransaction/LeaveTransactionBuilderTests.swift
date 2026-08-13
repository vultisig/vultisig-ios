//
//  LeaveTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Pins the node LEAVE transaction on both chains that offer it: the exact
//  memo string and — the part that costs money if it drifts — the attached
//  amount. Carries over the golden fixtures from the deleted
//  `FunctionCallLeaveTests`, which captured the legacy sub-model verbatim.
//

@testable import VultisigApp
import XCTest

final class LeaveTransactionBuilderTests: XCTestCase {

    private static let thorNode = "thor1prxy0sufdqfve6ygkwu9gswe60cle8gy02ex2w"
    private static let mayaNode = "maya18altpx2gwt4c4ejr5uzda4kyzsudyn9q5dhl9c"

    private static func makeRune() -> Coin {
        FunctionCallFixture.makeRUNE()
    }

    private static func makeCacao() -> Coin {
        FunctionCallFixture.makeCoin(
            .mayaChain,
            ticker: "CACAO",
            decimals: 10,
            isNative: true,
            address: FunctionCallFixture.mayaAddress
        )
    }

    // MARK: - Memo (golden fixture)

    /// Pin: the legacy `FunctionCallLeave.toString()` returned
    /// `LEAVE:<nodeAddress>` and nothing else.
    func testMemoIsLeaveColonNodeAddressOnThorchain() {
        let builder = LeaveTransactionBuilder(coin: Self.makeRune(), nodeAddress: Self.thorNode)
        XCTAssertEqual(builder.memo, "LEAVE:\(Self.thorNode)")
    }

    func testMemoIsLeaveColonNodeAddressOnMayachain() {
        let builder = LeaveTransactionBuilder(coin: Self.makeCacao(), nodeAddress: Self.mayaNode)
        XCTAssertEqual(builder.memo, "LEAVE:\(Self.mayaNode)")
    }

    /// The memo carries the address verbatim — no trimming, no casing, no
    /// extra fields. LEAVE has exactly one argument.
    func testMemoCarriesTheAddressVerbatim() {
        let builder = LeaveTransactionBuilder(coin: Self.makeRune(), nodeAddress: "thor1abc")
        XCTAssertEqual(builder.memo, "LEAVE:thor1abc")
    }

    // MARK: - Attached amount (fund safety)

    /// Pin: legacy attached `Decimal.zero.formatToDecimal(digits:)`, which is
    /// `"0"` at any precision. A non-zero amount on a LEAVE `MsgDeposit` is
    /// value the protocol never returns.
    func testAttachedAmountIsZeroOnThorchain() {
        let builder = LeaveTransactionBuilder(coin: Self.makeRune(), nodeAddress: Self.thorNode)
        XCTAssertEqual(builder.amount, "0")
        XCTAssertFalse(builder.sendMaxAmount)
    }

    func testAttachedAmountIsZeroOnMayachain() {
        let builder = LeaveTransactionBuilder(coin: Self.makeCacao(), nodeAddress: Self.mayaNode)
        XCTAssertEqual(builder.amount, "0")
        XCTAssertFalse(builder.sendMaxAmount)
    }

    // MARK: - Boundary (buildSendTransaction)

    /// Pin: the legacy boundary produced memo + zero amount + `.unspecified`
    /// + an empty `toAddress`, with a two-entry memo dictionary.
    func testSendTransactionMatchesLegacyBoundaryOnThorchain() {
        let coin = Self.makeRune()
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let builder = LeaveTransactionBuilder(coin: coin, nodeAddress: Self.thorNode)

        let tx = builder.buildSendTransaction(vault: vault)

        XCTAssertEqual(tx.memo, "LEAVE:\(Self.thorNode)")
        XCTAssertEqual(tx.amount, "0")
        XCTAssertEqual(tx.coin.ticker, "RUNE")
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertFalse(tx.isStakingOperation)
        XCTAssertNil(tx.wasmContractPayload)
        // The legacy sub-model took `gas` as a parameter; builders never do —
        // `FunctionTransactionScreen.onVerify` fetches the chain-specific gas
        // and copies it on before navigating, and Verify re-fetches it.
        XCTAssertEqual(tx.gas, .zero)
        XCTAssertEqual(tx.memoFunctionDictionary["memo"], "LEAVE:\(Self.thorNode)")
        XCTAssertEqual(tx.memoFunctionDictionary["nodeAddress"], Self.thorNode)
        XCTAssertEqual(tx.memoFunctionDictionary.count, 2)
    }

    func testSendTransactionMatchesLegacyBoundaryOnMayachain() {
        let coin = Self.makeCacao()
        let vault = FunctionCallFixture.makeVault(coins: [coin])
        let builder = LeaveTransactionBuilder(coin: coin, nodeAddress: Self.mayaNode)

        let tx = builder.buildSendTransaction(vault: vault)

        XCTAssertEqual(tx.memo, "LEAVE:\(Self.mayaNode)")
        XCTAssertEqual(tx.amount, "0")
        XCTAssertEqual(tx.coin.ticker, "CACAO")
        XCTAssertEqual(tx.toAddress, "")
        XCTAssertEqual(tx.transactionType, .unspecified)
        XCTAssertEqual(tx.memoFunctionDictionary["memo"], "LEAVE:\(Self.mayaNode)")
        XCTAssertEqual(tx.memoFunctionDictionary["nodeAddress"], Self.mayaNode)
        XCTAssertEqual(tx.memoFunctionDictionary.count, 2)
    }

    /// LEAVE is not a staking operation and carries no staking payload — the
    /// `FunctionTransactionScreen` fee path branches on these.
    func testCarriesNoStakingPayload() {
        let builder = LeaveTransactionBuilder(coin: Self.makeRune(), nodeAddress: Self.thorNode)
        XCTAssertNil(builder.cosmosStakingPayload)
        XCTAssertNil(builder.solanaStakingPayload)
        XCTAssertNil(builder.limitCancelContext)
    }
}
