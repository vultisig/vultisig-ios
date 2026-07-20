//
//  CancelLimitOrderTransactionViewModelTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

@MainActor
final class CancelLimitOrderTransactionViewModelTests: XCTestCase {

    private func makeRune(balance: String) -> Coin {
        let asset = CoinMeta(
            chain: .thorChain,
            ticker: "RUNE",
            logo: "rune",
            decimals: 8,
            priceProviderId: "thorchain",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(asset: asset, address: "thor1sender", hexPublicKey: "HexPublicKeyExample")
        coin.rawBalance = balance
        return coin
    }

    private func makeViewModel(
        balance: String,
        duplicates: Int = 0
    ) -> CancelLimitOrderTransactionViewModel {
        CancelLimitOrderTransactionViewModel(
            coin: makeRune(balance: balance),
            vault: .example,
            request: LimitOrderCancelRequest(
                orderId: "order-1",
                inboundTxHash: "ABC123",
                memo: "m=<:100000000THOR.RUNE:15979057441BTC.BTC:0",
                sourceAsset: "THOR.RUNE",
                targetAsset: "BTC.BTC",
                sourceChainRawValue: Chain.thorChain.rawValue,
                duplicateRestingOrderCount: duplicates
            )
        )
    }

    /// A dust balance is NOT sufficient. Gating on "> 0" would enable Continue
    /// for a transaction the verify screen rejects two steps later, with nothing
    /// on screen explaining why.
    func testDustBalanceIsNotSufficientForTheDepositFee() {
        XCTAssertFalse(makeViewModel(balance: "1").hasSufficientBalance)
        XCTAssertFalse(makeViewModel(balance: "0").hasSufficientBalance)
        XCTAssertFalse(
            makeViewModel(balance: String(THORChainConstants.depositGasBaseUnits - 1)).hasSufficientBalance
        )
    }

    /// Exactly the fee is enough — the cancel sends no coins, so the fee is the
    /// entire cost.
    func testExactlyTheFeeIsSufficient() {
        XCTAssertTrue(
            makeViewModel(balance: String(THORChainConstants.depositGasBaseUnits)).hasSufficientBalance
        )
    }

    /// The pre-flight must track the number the signer actually stamps, not a
    /// second copy of it that can drift.
    func testFeeMatchesTheSignedDepositGas() {
        let viewModel = makeViewModel(balance: "100000000")
        let expected = Decimal(THORChainConstants.depositGasBaseUnits) / pow(Decimal(10), 8)

        XCTAssertEqual(viewModel.feeDecimal, expected)
    }

    func testBuilderIsWithheldUntilTheFeeIsCovered() {
        XCTAssertNil(makeViewModel(balance: "1").transactionBuilder)
        XCTAssertNotNil(makeViewModel(balance: "100000000").transactionBuilder)
    }

    func testDuplicateWarningTracksTheRequestCount() {
        XCTAssertFalse(makeViewModel(balance: "100000000", duplicates: 0).hasDuplicateWarning)
        XCTAssertTrue(makeViewModel(balance: "100000000", duplicates: 1).hasDuplicateWarning)
    }
}
