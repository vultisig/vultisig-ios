//
//  TCYUnstakeVerifyHeroTests.swift
//  VultisigAppTests
//
//  The verify screen used to announce "You're sending 0 TCY" over a withdrawal of
//  a thousand of them: a staked-TCY withdrawal is a memo-only `MsgDeposit`, so the
//  transaction's own `amount` really is "0" and the generic send header rendered
//  it verbatim.
//

@testable import VultisigApp
import XCTest

@MainActor
final class TCYUnstakeVerifyHeroTests: XCTestCase {

    private let staked = Decimal(string: "2002.74")!

    private func makeTCYCoin() -> Coin {
        Coin(
            asset: TokensStore.tcy,
            address: "thor1fixturetcyvaultaddress00000000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    private func makeWithdrawal(typing amount: String) throws -> SendTransaction {
        let vault = TestStore.makeVault()
        let viewModel = UnstakeTransactionViewModel(
            coin: makeTCYCoin(),
            vault: vault,
            isAutocompound: false,
            availableToUnstake: staked
        )
        viewModel.availableAmount = staked
        viewModel.amountField.value = amount
        viewModel.percentageSelected = viewModel.percentageFromAmount
        viewModel.onPercentage(viewModel.percentageFromAmount)
        viewModel.validForm = true

        let builder = try XCTUnwrap(viewModel.transactionBuilder)
        return builder.buildSendTransaction(vault: vault)
    }

    /// The wire truth has to stay untouched — the fix is about what the screen
    /// says, not about putting an amount into a transaction that must carry none.
    func testTheTransactionStillSendsZeroOnTheWire() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let tx = try makeWithdrawal(typing: "1002.73")
        XCTAssertEqual(tx.amount, "0")
        XCTAssertEqual(tx.memo, "tcy-:5006")
    }

    func testTheHeroQuotesTheAmountThatWillActuallyBeWithdrawn() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let tx = try makeWithdrawal(typing: "1002.73")
        // 5006 bps of 2002.74 — the quantised figure, not the typed one.
        let expected = (staked * 5006) / 10_000
        let carried = try XCTUnwrap(tx.withdrawDisplayAmount)
        XCTAssertEqual(
            NSDecimalNumber(decimal: carried).doubleValue,
            NSDecimalNumber(decimal: expected).doubleValue,
            accuracy: 0.00001
        )

        let hero = try XCTUnwrap(TCYUnstakePresentation.hero(for: tx))
        guard case .send(let title, let coin) = hero else {
            return XCTFail("a withdrawal should render as a resolved single-sided amount")
        }
        XCTAssertEqual(coin.ticker, "TCY")
        XCTAssertFalse(coin.amount.isEmpty)
        XCTAssertNotEqual(coin.amount, "0")
        // Grouping separators are locale-dependent, so match the part that is not.
        // Not "1002.73" — the memo cannot express that, and the screen must quote
        // what the chain will actually pay out.
        XCTAssertTrue(coin.amount.contains("002.57"), "rendered \(coin.amount)")
        XCTAssertFalse(coin.amount.contains("002.73"), "the typed figure is not the delivered one")
        // A missing localization would leave the raw key here.
        XCTAssertNotEqual(title, "tcyUnstakeVerifyTitle")
        XCTAssertEqual(title, "tcyUnstakeVerifyTitle".localized)
    }

    /// The function-call flow calls `copy(gas:)` after fetching chain-specific gas
    /// and before navigating to Verify. `copy` rebuilds the struct field by field,
    /// which is exactly the shape that drops a new one — and dropping this one
    /// puts "You're sending 0 TCY" straight back.
    func testTheCarriedAmountSurvivesTheGasCopy() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let tx = try makeWithdrawal(typing: "1002.73")
        let copied = tx.copy(gas: 2_000_000)

        XCTAssertEqual(copied.withdrawDisplayAmount, tx.withdrawDisplayAmount)
        XCTAssertNotNil(TCYUnstakePresentation.hero(for: copied))
    }

    /// Every other function call keeps the presentation it has.
    func testAnOrdinarySendGetsNoWithdrawalHero() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()
        let coin = makeTCYCoin()

        let tx = SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: coin.address,
            toAddress: coin.address,
            toAddressLabel: nil,
            amount: "10",
            amountInFiat: "",
            memo: "",
            gas: .zero,
            fee: .zero,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: SendTransaction.resolveFeeCoin(coin: coin, vault: vault)
        )

        XCTAssertNil(tx.withdrawDisplayAmount)
        XCTAssertNil(TCYUnstakePresentation.hero(for: tx))
    }
}
