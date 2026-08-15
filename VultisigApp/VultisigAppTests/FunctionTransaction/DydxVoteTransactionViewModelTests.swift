//
//  DydxVoteTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Validation gate for the dYdX governance vote form. `transactionBuilder`
//  returning nil is the enforcement — `FormScreen` does not disable Continue on
//  `validForm` — so every rejection is asserted through the builder rather than
//  through a flag.
//
//  The test that pays for this file is `testAnUnspecifiedOptionCanNeverBeSubmitted`.
//  It is the corrected form of the deleted
//  `FunctionCallVoteTests.testIsTheFormValidRequiresProposalIDGreaterThanZero`,
//  which pinned the defect: the legacy check was
//  `selectedMemo.rawValue >= 0 && proposalID > 0`, and `.unspecified` has raw
//  value 0, so the option clause was vacuous and an Unspecified ballot passed
//  validation, spent the fee and was rejected by the chain.
//

@testable import VultisigApp
import WalletCore
import XCTest

@MainActor
final class DydxVoteTransactionViewModelTests: XCTestCase {

    private static func makeDydxCoin() -> Coin {
        FunctionCallFixture.makeCoin(.dydx, ticker: "DYDX", decimals: 18, isNative: true)
    }

    private func makeViewModel() -> DydxVoteTransactionViewModel {
        let coin = Self.makeDydxCoin()
        return DydxVoteTransactionViewModel(
            coin: coin,
            vault: FunctionCallFixture.makeVault(coins: [coin])
        )
    }

    private func makeLoadedViewModel() -> DydxVoteTransactionViewModel {
        let viewModel = makeViewModel()
        viewModel.onLoad()
        return viewModel
    }

    // MARK: - The pristine form

    func testPristineFormDoesNotBuild() {
        let viewModel = makeLoadedViewModel()

        XCTAssertNil(viewModel.selectedOption, "The ballot opens with nothing picked")
        XCTAssertEqual(viewModel.proposalIDField.value, "")
        XCTAssertNil(viewModel.transactionBuilder)
    }

    /// The tap is what reveals the errors — `FormScreen` does not disable
    /// Continue, so a form the user has not touched has to say why it will not
    /// submit.
    func testTappingContinueOnAPristineFormShowsBothErrors() {
        let viewModel = makeLoadedViewModel()

        XCTAssertNil(viewModel.transactionBuilder)

        XCTAssertEqual(viewModel.optionField.error, "selectVoteOptionError".localized)
        XCTAssertEqual(viewModel.proposalIDField.error, "invalidProposalIDError".localized)
    }

    // MARK: - The defect, corrected

    /// The corrected form of the deleted validity test.
    ///
    /// Legacy: `selectedMemo` started at `.unspecified`, `rawValue >= 0` was
    /// satisfied by its raw value 0, and setting `proposalID = 1` made the whole
    /// form valid — an Unspecified ballot the chain rejects after the fee is
    /// spent. Here the same sequence produces no builder, because the option is
    /// gated by a validator that only accepts a submittable option.
    func testAnUnspecifiedOptionCanNeverBeSubmitted() {
        let viewModel = makeLoadedViewModel()
        viewModel.proposalIDField.value = "1"

        XCTAssertNil(viewModel.transactionBuilder, "A ballot with no option picked must not build")
        XCTAssertFalse(viewModel.optionField.valid)

        // Not offered to the user either — the legacy dropdown listed
        // `allCases`, which is how Unspecified became pickable in the first
        // place.
        XCTAssertFalse(viewModel.options.contains(.unspecified))

        // And it cannot be written in behind the picker's back.
        viewModel.select(.unspecified)
        XCTAssertNil(viewModel.selectedOption)
        XCTAssertNil(viewModel.transactionBuilder)
    }

    /// The other half of the same correction: a positive proposal ID was the
    /// *only* real gate legacy had. On its own it is no longer enough.
    func testAPositiveProposalIDAloneIsNotEnough() {
        let viewModel = makeLoadedViewModel()
        viewModel.proposalIDField.value = "42"
        XCTAssertNil(viewModel.transactionBuilder)

        viewModel.select(.yes)
        XCTAssertNotNil(viewModel.transactionBuilder, "Both fields together are what makes a ballot")
    }

    /// And a picked option alone is not enough either — the gate legacy did
    /// enforce still holds.
    func testAnOptionWithoutAProposalIDDoesNotBuild() {
        let viewModel = makeLoadedViewModel()
        viewModel.select(.yes)
        XCTAssertNil(viewModel.transactionBuilder)
    }

    // MARK: - The proposal ID gate

    /// There is no proposal 0, and legacy's `proposalID > 0` said so. Carried
    /// over verbatim.
    func testZeroAndNegativeProposalIDsDoNotBuild() {
        let viewModel = makeLoadedViewModel()
        viewModel.select(.yes)

        for input in ["0", "000", "-1"] {
            viewModel.proposalIDField.value = input
            XCTAssertNil(viewModel.transactionBuilder, "\(input) must not build")
        }
    }

    /// The tightening over legacy's locale-aware integer field: anything that
    /// is not unambiguously a run of digits is refused rather than reinterpreted
    /// into a different proposal.
    func testAmbiguousOrNonNumericProposalIDsDoNotBuild() {
        let viewModel = makeLoadedViewModel()
        viewModel.select(.yes)

        for input in ["", "   ", "abc", "42abc", "4 2", "1,234", "1.234", "1,5", "+42", "4e2", "42.0"] {
            viewModel.proposalIDField.value = input
            XCTAssertNil(viewModel.transactionBuilder, "\(input) must not build")
            XCTAssertEqual(viewModel.proposalIDField.error, "invalidProposalIDError".localized)
        }
    }

    /// A proposal ID past `uint64` names no proposal the chain has.
    func testAnOverflowingProposalIDDoesNotBuild() {
        let viewModel = makeLoadedViewModel()
        viewModel.select(.yes)
        viewModel.proposalIDField.value = "18446744073709551616"
        XCTAssertNil(viewModel.transactionBuilder)

        viewModel.proposalIDField.value = "18446744073709551615"
        XCTAssertEqual(
            (viewModel.transactionBuilder as? DydxVoteTransactionBuilder)?.proposalID,
            UInt64.max
        )
    }

    /// A non-Latin keyboard's digits reach the memo as the number they name.
    func testANonLatinProposalIDReachesTheMemoAsDigits() {
        let viewModel = makeLoadedViewModel()
        viewModel.select(.yes)
        viewModel.proposalIDField.value = "٤٢"

        XCTAssertEqual(viewModel.transactionBuilder?.memo, "DYDX_VOTE:Yes:42")
    }

    // MARK: - The memo, end to end

    /// Every offered option reaches the memo intact through the form, not just
    /// through the builder — including the one whose token contains spaces.
    func testEveryOfferedOptionReachesTheMemoThroughTheForm() {
        let expected: [(TW_Cosmos_Proto_Message.VoteOption, String)] = [
            (.yes, "DYDX_VOTE:Yes:42"),
            (.abstain, "DYDX_VOTE:Abstain:42"),
            (.no, "DYDX_VOTE:No:42"),
            (.noWithVeto, "DYDX_VOTE:No with Veto:42")
        ]

        for (option, memo) in expected {
            let viewModel = makeLoadedViewModel()
            viewModel.select(option)
            viewModel.proposalIDField.value = "42"

            let builder = viewModel.transactionBuilder as? DydxVoteTransactionBuilder
            XCTAssertEqual(builder?.option, option)
            XCTAssertEqual(builder?.memo, memo)
            XCTAssertEqual(builder?.amount, "0", "The ballot rides the memo, never the transaction")
            XCTAssertEqual(builder?.coin.ticker, "DYDX")
        }
    }

    /// Re-picking replaces the ballot rather than accumulating one.
    func testChangingTheOptionChangesTheMemo() {
        let viewModel = makeLoadedViewModel()
        viewModel.proposalIDField.value = "42"
        viewModel.select(.yes)
        XCTAssertEqual(viewModel.transactionBuilder?.memo, "DYDX_VOTE:Yes:42")

        viewModel.select(.noWithVeto)
        XCTAssertEqual(viewModel.selectedOption, .noWithVeto)
        XCTAssertEqual(viewModel.transactionBuilder?.memo, "DYDX_VOTE:No with Veto:42")
    }

    /// Surrounding whitespace from a paste is trimmed, not treated as a
    /// different proposal.
    func testAPastedProposalIDIsTrimmed() {
        let viewModel = makeLoadedViewModel()
        viewModel.select(.abstain)
        viewModel.proposalIDField.value = "  42  "
        XCTAssertEqual(viewModel.transactionBuilder?.memo, "DYDX_VOTE:Abstain:42")
    }

    // MARK: - Shown ballot == signed ballot

    /// The screen renders the checked row from `DydxVoteOption
    /// .option(forMemoValue:)` over the option field, and the builder reads the
    /// same expression through `selectedOption`. Writing the field directly —
    /// the only way to reach it behind the picker — therefore moves both at
    /// once, so no sequence can show one ballot and sign another.
    func testWritingTheOptionFieldDirectlyMovesDisplayAndMemoTogether() {
        let viewModel = makeLoadedViewModel()
        viewModel.select(.yes)
        viewModel.proposalIDField.value = "42"
        XCTAssertEqual(viewModel.selectedOption, .yes)

        viewModel.optionField.value = DydxVoteOption.memoValue(for: .no)

        XCTAssertEqual(viewModel.selectedOption, .no, "What the row draws follows the field")
        XCTAssertEqual(viewModel.transactionBuilder?.memo, "DYDX_VOTE:No:42", "And so does the memo")
    }

    /// And an unsubmittable token written straight into the field resolves to
    /// nothing, so it neither draws a checked row nor produces a builder.
    func testAnUnsubmittableTokenInTheFieldNeitherDisplaysNorSigns() {
        let viewModel = makeLoadedViewModel()
        viewModel.select(.yes)
        viewModel.proposalIDField.value = "42"

        for token in [DydxVoteOption.memoValue(for: .unspecified), "Unrecognized (9)", "yes", "Yes "] {
            viewModel.optionField.value = token
            XCTAssertNil(viewModel.selectedOption, "\(token) is not a ballot")
            XCTAssertNil(viewModel.transactionBuilder, "\(token) must not build")
        }
    }

    // MARK: - The stale aggregate

    /// `Form.setupForm()` republishes `validForm` on the main run loop, so a
    /// form completed and submitted within one turn still reads `false` there.
    /// `transactionBuilder` judges the fields directly for exactly this reason —
    /// this is the same guard REBOND, MERGE and UNMERGE carry.
    func testABuilderIsProducedInTheSameTurnTheFormIsCompleted() {
        let viewModel = makeLoadedViewModel()
        viewModel.select(.yes)
        viewModel.proposalIDField.value = "42"

        XCTAssertFalse(viewModel.validForm, "The aggregate has not been republished yet")
        XCTAssertNotNil(viewModel.transactionBuilder, "The fields, not the aggregate, decide this turn")
    }

    /// And the mirror image: a form emptied within one turn must not submit on
    /// a `validForm` that has not caught up either.
    func testAFormEmptiedInTheSameTurnDoesNotBuild() async {
        let viewModel = makeLoadedViewModel()
        viewModel.select(.yes)
        viewModel.proposalIDField.value = "42"
        await waitForValidForm(viewModel, expected: true)

        viewModel.proposalIDField.value = ""
        XCTAssertTrue(viewModel.validForm, "The aggregate still says the old answer")
        XCTAssertNil(viewModel.transactionBuilder, "The fields say otherwise, and they win")
    }

    /// The aggregate does settle — the guard above is about the turn it takes,
    /// not about it never arriving.
    func testValidFormSettlesTrueOnACompleteBallot() async {
        let viewModel = makeLoadedViewModel()
        viewModel.select(.no)
        viewModel.proposalIDField.value = "7"

        await waitForValidForm(viewModel, expected: true)
        XCTAssertEqual(viewModel.transactionBuilder?.memo, "DYDX_VOTE:No:7")
    }

    /// Polls the aggregate, which lands via `RunLoop.main` rather than through
    /// anything awaitable.
    private func waitForValidForm(
        _ viewModel: DydxVoteTransactionViewModel,
        expected: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(3)
        while viewModel.validForm != expected {
            if Date() > deadline {
                return XCTFail("Timed out waiting for validForm == \(expected)", file: file, line: line)
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}
