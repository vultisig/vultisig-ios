//
//  InitiatorDecodingFallbackTests.swift
//  VultisigAppTests
//
//  The initiator's side of the same reading, and the two places it must not be
//  taken.
//
//  A builder only needs to declare a `functionKind` where the transaction does
//  not already say what it is. Four declarations were removed once the decoder
//  could read them off the memo; these pin that the fallback carries them, and
//  that the declaration still wins where it knows more.
//

import BigInt
@testable import VultisigApp
import VultisigCommonData
import XCTest

@MainActor
final class InitiatorDecodingFallbackTests: XCTestCase {

    /// ⚠️ A fresh store per test, not merely distinct fixture keys.
    ///
    /// `Vault` carries unique attributes, so a vault left behind by an earlier
    /// test is still there when the next one inserts — and SwiftData resolves
    /// the collision by upserting, which would leave a test asserting over a
    /// single survivor of two fixtures. Isolating the container is what makes
    /// each test independent of whatever ran before it.
    private var storeToken: TestContextToken?

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDownWithError() throws {
        if let storeToken { TestStore.restore(storeToken) }
        storeToken = nil
        try super.tearDownWithError()
    }

    /// ⚠️ The declaration is preferred where it exists, because an initiator
    /// holds a figure the transaction does not carry. A fractional withdrawal
    /// resolves `withdrawDisplayAmount` against the position its form was
    /// showing; decoding can only ever name the fraction, since the memo commits
    /// to a share and nothing in it names the position.
    func testADeclaredKindStillWinsWhereItKnowsMore() throws {
        let hero = try XCTUnwrap(FunctionTransactionPresentation.hero(
            for: makeTransaction(memo: "tcy-:5006", kind: .unstake, withdrawDisplay: Decimal(string: "1002.57"))
        ))

        // The SHAPE is the property, not the string. A declared kind renders a
        // quantity (`.send`); the decoded fallback could only render the memo's
        // fraction as a caption (`.title`). Pinning the formatted figure instead
        // would assert the running locale's grouping separator — "1,002.57" here
        // — and fail on a machine set to a region that groups differently.
        guard case let .send(_, coin) = hero else {
            return XCTFail("expected a quantity from the declared kind, got \(hero)")
        }
        XCTAssertTrue(coin.amount.contains("002"), "expected the quantised figure, got \(coin.amount)")
    }

    /// And where nothing is declared, the transaction is read the way a
    /// co-signer reads its payload — which is what lets a builder stop declaring
    /// a kind its own memo already states.
    func testAnUndeclaredTransactionIsDecodedInstead() throws {
        let hero = try XCTUnwrap(FunctionTransactionPresentation.hero(
            for: makeTransaction(memo: "tcy+", kind: nil)
        ))
        XCTAssertEqual(hero.title, "youreStaking".localized)
    }

    /// ⚠️ An UNBOND is the case that improves. Its transaction amount is zero —
    /// the instruction is the memo — so the declared path rendered no hero at
    /// all, while the memo states the exact figure in base units.
    func testAnUnbondGainsAFigureItPreviouslyLacked() throws {
        let hero = try XCTUnwrap(FunctionTransactionPresentation.hero(
            for: makeTransaction(memo: "UNBOND:thor1node:150000000", kind: nil, amount: "0")
        ))

        guard case let .send(title, coin) = hero else {
            return XCTFail("expected a figure, got \(hero)")
        }
        XCTAssertEqual(title, "youreUnbonding".localized)
        XCTAssertEqual(coin.amount, "1.5")
    }

    private func makeTransaction(
        memo: String,
        kind: FunctionTransactionKind?,
        amount: String = "1",
        withdrawDisplay: Decimal? = nil
    ) -> SendTransaction {
        let coin = Coin(
            asset: CoinMeta(
                chain: .thorChain, ticker: "TCY", logo: "tcy", decimals: 8,
                priceProviderId: "tcy", contractAddress: "", isNativeToken: false
            ),
            address: "thor1from",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )

        return SendTransaction(
            coin: coin,
            vault: TestStore.makeVault(pubKey: "test-pub-fallback-\(memo)"),
            fromAddress: coin.address,
            toAddress: "thor1to",
            toAddressLabel: nil,
            amount: amount,
            amountInFiat: "0",
            memo: memo,
            gas: .zero,
            fee: .zero,
            feeMode: .normal,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: true,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin,
            withdrawDisplayAmount: withdrawDisplay,
            functionKind: kind
        )
    }
}
