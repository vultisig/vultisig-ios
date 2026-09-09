//
//  BondTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Range gate for the THORChain BOND form's operator-fee field. The memo's fee
//  segment is read as basis points, so `0...10000` is the whole of what the
//  chain can honour — and the field used to accept anything `Int64` could parse,
//  including `50000` and negatives, straight into a signed memo.
//
//  Every rejection is asserted through `transactionBuilder` returning nil rather
//  than through `validForm`: `FormScreen` does not disable Continue on the flag,
//  so the builder is what actually stands between a bad value and a keysign
//  ceremony.
//

import Combine
@testable import VultisigApp
import XCTest

@MainActor
final class BondTransactionViewModelTests: XCTestCase {

    private static let nodeAddress = "thor1prxy0sufdqfve6ygkwu9gswe60cle8gy02ex2w"
    private static let providerAddress = "thor1pe0pspu4ep85gxr5h9l6k49g024vemtr80hg4c"

    /// No decimal separator, so the amount parses the same in every shipping
    /// locale — `AmountBalanceValidator` reads it through `Locale.current`.
    private static let amount = "100"

    /// Fills the form's other fields so each case varies only the operator fee.
    /// Validity is deliberately *not* awaited here: a provider with no fee is
    /// itself one of the rejection cases, so the caller states the settled
    /// answer it expects.
    private func makeLoadedViewModel(
        provider: String? = nil,
        operatorFee: String? = nil
    ) -> BondTransactionViewModel {
        let coin = FunctionActionFixture.makeRUNE()
        let viewModel = BondTransactionViewModel(
            coin: coin,
            vault: FunctionActionFixture.makeVault(coins: [coin]),
            initialBondAddress: nil
        )
        viewModel.onLoad()
        viewModel.addressViewModel.field.value = Self.nodeAddress
        if let provider {
            viewModel.providerViewModel.field.value = provider
        }
        if let operatorFee {
            viewModel.operatorFeeField.value = operatorFee
        }
        viewModel.amountField.value = Self.amount
        return viewModel
    }

    /// `setupForm()` publishes validity on the main run loop, so the flag
    /// settles a turn after the value is written.
    private func awaitValidForm(_ viewModel: BondTransactionViewModel, is expected: Bool) async {
        guard viewModel.validForm != expected else { return }
        let settled = XCTestExpectation(description: "validForm becomes \(expected)")
        var cancellable: AnyCancellable?
        cancellable = viewModel.$validForm
            .first(where: { $0 == expected })
            .sink { _ in settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        cancellable?.cancel()
    }

    private func builder(_ viewModel: BondTransactionViewModel) -> BondTransactionBuilder? {
        viewModel.transactionBuilder as? BondTransactionBuilder
    }

    // MARK: - Accepted range

    func testEmptyOperatorFeeBuildsWithNoFeeSegment() async {
        let viewModel = makeLoadedViewModel()
        await awaitValidForm(viewModel, is: true)

        let built = builder(viewModel)
        XCTAssertNil(built?.operatorFee, "An untouched fee field is no fee at all")
        XCTAssertEqual(built?.memo, "BOND:\(Self.nodeAddress)")
    }

    /// Zero is inside the range and stays inside it: it names the absence of a
    /// fee, and `BondTransactionBuilder` omits the segment rather than writing
    /// `:0`.
    func testZeroOperatorFeeIsAcceptedAndOmitsTheFeeSegment() async {
        let viewModel = makeLoadedViewModel(provider: Self.providerAddress, operatorFee: "0")
        await awaitValidForm(viewModel, is: true)

        let built = builder(viewModel)
        XCTAssertEqual(built?.operatorFee, 0)
        XCTAssertEqual(built?.memo, "BOND:\(Self.nodeAddress):\(Self.providerAddress)")
        XCTAssertNil(viewModel.operatorFeeField.error)
    }

    /// The top of the range — 100% — is a fee the chain honours, so the form
    /// must not fence it off.
    func testMaximumOperatorFeeIsAccepted() async {
        let viewModel = makeLoadedViewModel(provider: Self.providerAddress, operatorFee: "10000")
        await awaitValidForm(viewModel, is: true)

        let built = builder(viewModel)
        XCTAssertEqual(built?.operatorFee, 10_000)
        XCTAssertEqual(built?.memo, "BOND:\(Self.nodeAddress):\(Self.providerAddress):10000")
        XCTAssertNil(viewModel.operatorFeeField.error)
    }

    /// The fee still reaches the memo raw — no ×100 anywhere between the field
    /// and the signed bytes.
    func testInRangeOperatorFeeReachesTheMemoUnscaled() async {
        let viewModel = makeLoadedViewModel(provider: Self.providerAddress, operatorFee: "500")
        await awaitValidForm(viewModel, is: true)

        let built = builder(viewModel)
        XCTAssertEqual(built?.operatorFee, 500)
        XCTAssertEqual(built?.memo, "BOND:\(Self.nodeAddress):\(Self.providerAddress):500")
    }

    /// Without a provider the memo carries an empty provider segment, so the fee
    /// still lands in the fourth position.
    func testOperatorFeeWithoutAProviderKeepsTheEmptyProviderSegment() async {
        let viewModel = makeLoadedViewModel(operatorFee: "500")
        await awaitValidForm(viewModel, is: true)

        XCTAssertEqual(builder(viewModel)?.memo, "BOND:\(Self.nodeAddress)::500")
    }

    // MARK: - Out of range

    func testOperatorFeeAboveTenThousandBlocksTheBuilder() async {
        let viewModel = makeLoadedViewModel(provider: Self.providerAddress, operatorFee: "10001")
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder, "An out-of-range fee must not reach a keysign ceremony")
        XCTAssertEqual(viewModel.operatorFeeField.error, "operatorFeeRangeError".localized)
    }

    /// The value from the report: `50000` reads as a percentage carrying two
    /// decimals and was signed as basis points.
    func testFiftyThousandBasisPointsIsRefused() async {
        let viewModel = makeLoadedViewModel(provider: Self.providerAddress, operatorFee: "50000")
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testNegativeOperatorFeeBlocksTheBuilder() async {
        let viewModel = makeLoadedViewModel(provider: Self.providerAddress, operatorFee: "-1")
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertEqual(viewModel.operatorFeeField.error, "operatorFeeRangeError".localized)
    }

    // MARK: - Malformed

    func testNonNumericOperatorFeeBlocksTheBuilder() async {
        let viewModel = makeLoadedViewModel(provider: Self.providerAddress, operatorFee: "abc")
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertEqual(viewModel.operatorFeeField.error, "invalidOperatorFee".localized)
    }

    /// Basis points are whole. The iOS field is a decimal pad, so a decimal is
    /// reachable, and it is not a fee the segment can carry.
    func testDecimalOperatorFeeBlocksTheBuilder() async {
        let viewModel = makeLoadedViewModel(provider: Self.providerAddress, operatorFee: "0.5")
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertEqual(viewModel.operatorFeeField.error, "invalidOperatorFee".localized)
    }

    /// Too large for `Int64` fails the parse rather than the range check, and is
    /// refused either way — the point is that it never wraps into something in
    /// range.
    func testOperatorFeeBeyondInt64BlocksTheBuilder() async {
        let viewModel = makeLoadedViewModel(
            provider: Self.providerAddress,
            operatorFee: "99999999999999999999999"
        )
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertEqual(viewModel.operatorFeeField.error, "invalidOperatorFee".localized)
    }

    /// Whitespace is not trimmed, because `BondTransactionBuilder` parses the
    /// same string with plain `Int64`. Accepting it here would drop the fee
    /// segment from a memo the user believed carried it.
    func testPaddedOperatorFeeBlocksTheBuilder() async {
        let viewModel = makeLoadedViewModel(provider: Self.providerAddress, operatorFee: " 500")
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertEqual(viewModel.operatorFeeField.error, "invalidOperatorFee".localized)
    }

    // MARK: - Cross-field rule

    /// A provider with no fee is a bond whose operator takes an unstated cut;
    /// the pre-existing rule that refuses it has to survive the new validator.
    func testEmptyOperatorFeeWithAProviderBlocksTheBuilder() async {
        let viewModel = makeLoadedViewModel(provider: Self.providerAddress)
        await awaitValidForm(viewModel, is: false)

        XCTAssertNil(viewModel.transactionBuilder)
        XCTAssertEqual(viewModel.operatorFeeField.error, "operatorFeesError".localized)
    }

    // MARK: - Gate timing

    /// `validForm` is republished a run-loop turn late, so a Continue tap in the
    /// same turn as the edit would otherwise read the previous answer — here,
    /// building a memo from a fee the user has just pushed out of range.
    func testOutOfRangeFeeBlocksTheBuilderInTheSameRunLoopTurn() async {
        let viewModel = makeLoadedViewModel(provider: Self.providerAddress, operatorFee: "500")
        await awaitValidForm(viewModel, is: true)

        viewModel.operatorFeeField.value = "50000"
        XCTAssertTrue(viewModel.validForm, "Precondition: the aggregate has not settled yet")
        XCTAssertNil(viewModel.transactionBuilder, "A same-turn edit must not submit on a stale aggregate")
    }

    func testCorrectingAnOutOfRangeFeeReopensTheGate() async {
        let viewModel = makeLoadedViewModel(provider: Self.providerAddress, operatorFee: "10001")
        await awaitValidForm(viewModel, is: false)

        viewModel.operatorFeeField.value = "1000"
        await awaitValidForm(viewModel, is: true)

        XCTAssertNil(viewModel.operatorFeeField.error)
        XCTAssertEqual(builder(viewModel)?.memo, "BOND:\(Self.nodeAddress):\(Self.providerAddress):1000")
    }
}
