//
//  UnstakeAsyncBalanceLoadTests.swift
//  VultisigAppTests
//
//  The unstake sheet opens with the ceiling the DeFi card was showing and then
//  revises it from the network for an auto-compound position. The user can type
//  in the meantime — on a slow connection that is exactly what they do — so the
//  ordering these tests pin is: type first, balance lands second. What the user
//  entered has to survive it, and the transaction built afterwards has to be the
//  one the field is showing.
//
//  The read is injected and gated rather than slept on, so the ordering under
//  test is the ordering that actually runs.
//

@testable import VultisigApp
import XCTest

@MainActor
final class UnstakeAsyncBalanceLoadTests: XCTestCase {

    /// Holds the balance read open until the test says otherwise. Latching, so it
    /// does not matter whether the read reaches the gate before or after it is
    /// opened — there is no race to lose.
    private actor BalanceReadGate {
        private var isOpen = false
        private var waiting: CheckedContinuation<Void, Never>?

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuation in
                waiting = continuation
            }
        }

        func open() {
            isOpen = true
            waiting?.resume()
            waiting = nil
        }
    }

    private enum ReadOutcome {
        case succeeds(baseUnits: Decimal)
        case fails
    }

    private struct ReadFailure: Error {}

    /// Every auto-compound card that reaches the async revision, with the coin the
    /// unstake sheet is actually opened on (the compounded card maps its receipt
    /// back to the bond coin).
    private static let autocompoundCoins: [CoinMeta] = [
        TokensStore.tcy,
        TokensStore.brune,
        TokensStore.ruji
    ]

    private func makeCoin(_ meta: CoinMeta) -> Coin {
        Coin(
            asset: meta,
            address: "thor1fixtureunstakevaultaddress000000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    private func makeViewModel(
        coin: CoinMeta,
        vault: Vault,
        availableToUnstake: Decimal,
        gate: BalanceReadGate,
        outcome: ReadOutcome,
        isAutocompound: Bool = true
    ) -> UnstakeTransactionViewModel {
        UnstakeTransactionViewModel(
            coin: makeCoin(coin),
            vault: vault,
            isAutocompound: isAutocompound,
            availableToUnstake: availableToUnstake,
            readAutocompoundBalance: { _, _ in
                await gate.wait()
                switch outcome {
                case .succeeds(let baseUnits):
                    return baseUnits
                case .fails:
                    throw ReadFailure()
                }
            }
        )
    }

    /// What `AmountTextField` does when the user edits the field: the field takes
    /// ownership of the value and the percentage control is cleared.
    private func typeAmount(_ amount: String, into viewModel: UnstakeTransactionViewModel) {
        viewModel.amountField.value = amount
        viewModel.percentageSelected = nil
    }

    /// What `UnstakeTransactionScreen` does when the user moves the slider.
    private func selectPercentage(_ percentage: Double, on viewModel: UnstakeTransactionViewModel) {
        viewModel.percentageSelected = percentage
        viewModel.onPercentage(percentage)
    }

    /// `AmountTextField.setupAmount()` — the rule that actually rewrites the field
    /// whenever `availableAmount` moves: re-derive the amount from the percentage,
    /// and do nothing at all once the user has taken the field over. Mirrored here
    /// because the view is a SwiftUI body and a unit test cannot render it, and it
    /// is the step that turns a re-armed percentage into an overwritten amount.
    private func syncFieldToCeiling(_ viewModel: UnstakeTransactionViewModel) {
        guard let percentage = viewModel.percentageSelected else { return }
        let derived = viewModel.availableAmount * Decimal(percentage) / 100
        viewModel.amountField.value = derived.formatToDecimal(digits: 4)
    }

    private func completeLoad(_ viewModel: UnstakeTransactionViewModel, gate: BalanceReadGate) async {
        await gate.open()
        _ = await viewModel.autocompoundLoadTask?.value
        syncFieldToCeiling(viewModel)
    }

    // MARK: - A typed amount survives the load

    func testATypedAmountSurvivesALateBalanceLoad() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let gate = BalanceReadGate()
        let viewModel = makeViewModel(
            coin: TokensStore.tcy,
            vault: TestStore.makeVault(),
            availableToUnstake: 100,
            gate: gate,
            outcome: .succeeds(baseUnits: 25_000_000_000)
        )

        viewModel.onLoad()
        typeAmount("50", into: viewModel)
        await completeLoad(viewModel, gate: gate)

        XCTAssertEqual(viewModel.amountField.value, "50", "the load must not rewrite what the user typed")
        XCTAssertEqual(viewModel.availableAmount, 250, "the network figure is still the ceiling")
        XCTAssertNil(viewModel.percentageSelected, "the field, not the slider, still owns the value")
        // 50 of the corrected 250, not of the 100 the card was showing.
        XCTAssertEqual(viewModel.resolvedPercentage, 20, accuracy: 0.0001)
    }

    /// The acceptance criterion that actually moves money: the wasm execute has to
    /// spend the amount the field is showing, sized against the corrected ceiling.
    ///
    /// 50 of 250 is deliberately a whole percentage. The builders still take an
    /// `Int` percentage, so a ratio like 49/250 would lose the remainder to that
    /// truncation — a separate, pre-existing defect being fixed by moving the
    /// memo to basis points, and not something this test should pin either way.
    func testTheTransactionBuiltAfterTheLoadMatchesTheField() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let gate = BalanceReadGate()
        let viewModel = makeViewModel(
            coin: TokensStore.tcy,
            vault: TestStore.makeVault(),
            availableToUnstake: 100,
            gate: gate,
            outcome: .succeeds(baseUnits: 25_000_000_000)
        )

        viewModel.onLoad()
        typeAmount("50", into: viewModel)
        await completeLoad(viewModel, gate: gate)

        let builder = try XCTUnwrap(viewModel.transactionBuilder)
        let payload = try XCTUnwrap(builder.wasmContractPayload)
        let funds = try XCTUnwrap(payload.coins.first)
        XCTAssertEqual(funds.denom, "x/staking-tcy")
        // 20% of the 250 TCY receipt balance = the 50 TCY on screen.
        XCTAssertEqual(funds.amount, "5000000000")
    }

    /// Every asset that reaches the async revision, not sTCY alone. sRUJI keeps the
    /// card's RUJI-denominated ceiling by design — its receipt read only sizes the
    /// redeemed shares — so the assertion there is that the ceiling stays put.
    func testEveryAutoCompoundAssetKeepsATypedAmountAcrossTheLoad() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()

        for meta in Self.autocompoundCoins {
            let gate = BalanceReadGate()
            let viewModel = makeViewModel(
                coin: meta,
                vault: vault,
                availableToUnstake: 100,
                gate: gate,
                outcome: .succeeds(baseUnits: 25_000_000_000)
            )

            viewModel.onLoad()
            typeAmount("50", into: viewModel)
            await completeLoad(viewModel, gate: gate)

            XCTAssertEqual(viewModel.amountField.value, "50", "\(meta.ticker) overwrote the typed amount")
            XCTAssertNil(viewModel.percentageSelected, "\(meta.ticker) re-armed the percentage control")
            XCTAssertEqual(viewModel.autocompoundBalance, 250, "\(meta.ticker) did not record the receipt balance")

            let expectedCeiling: Decimal = meta.ticker.uppercased() == "RUJI" ? 100 : 250
            XCTAssertEqual(viewModel.availableAmount, expectedCeiling, "\(meta.ticker) ceiling")
        }
    }

    // MARK: - A selected percentage survives too

    func testASelectedPercentageSurvivesTheLoadAndRescalesToTheNewCeiling() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let gate = BalanceReadGate()
        let viewModel = makeViewModel(
            coin: TokensStore.tcy,
            vault: TestStore.makeVault(),
            availableToUnstake: 100,
            gate: gate,
            outcome: .succeeds(baseUnits: 25_000_000_000)
        )

        viewModel.onLoad()
        selectPercentage(40, on: viewModel)
        await completeLoad(viewModel, gate: gate)

        XCTAssertEqual(viewModel.percentageSelected, 40, "the load must not snap the slider back to 100%")
        XCTAssertFalse(viewModel.isMaxAmount, "a 40% withdrawal is not a max withdrawal")
        XCTAssertEqual(viewModel.availableAmount, 250)
        XCTAssertEqual(viewModel.resolvedPercentage, 40, accuracy: 0.0001)
        // Re-derived against the corrected ceiling: 40% of 250, not the whole 250.
        XCTAssertEqual(viewModel.amountField.value.toDecimal(), 100)
    }

    /// The untouched case has to keep behaving exactly as it did: the sheet opens on
    /// the whole position and the corrected ceiling is adopted wholesale.
    func testAnUntouchedFieldStillAdoptsTheLoadedCeilingAtFullPercentage() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let gate = BalanceReadGate()
        let viewModel = makeViewModel(
            coin: TokensStore.tcy,
            vault: TestStore.makeVault(),
            availableToUnstake: 100,
            gate: gate,
            outcome: .succeeds(baseUnits: 25_000_000_000)
        )

        viewModel.onLoad()
        await completeLoad(viewModel, gate: gate)

        XCTAssertEqual(viewModel.availableAmount, 250)
        XCTAssertEqual(viewModel.percentageSelected, 100)
        XCTAssertTrue(viewModel.isMaxAmount)
        XCTAssertEqual(viewModel.amountField.value.toDecimal(), 250, "nothing was entered, so the sheet still offers the whole position")
    }

    // MARK: - A ceiling that moves down

    /// The form pipeline only re-validates when the field's *value* changes, and a
    /// corrected ceiling moves the validator underneath a value that does not — so
    /// without an explicit re-validation the sheet would happily build a withdrawal
    /// for more than the position holds.
    func testALoweredCeilingInvalidatesATypedAmountThatNoLongerFits() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let gate = BalanceReadGate()
        let viewModel = makeViewModel(
            coin: TokensStore.tcy,
            vault: TestStore.makeVault(),
            availableToUnstake: 100,
            gate: gate,
            outcome: .succeeds(baseUnits: 5_000_000_000)
        )

        viewModel.onLoad()
        typeAmount("90", into: viewModel)
        await completeLoad(viewModel, gate: gate)

        XCTAssertEqual(viewModel.availableAmount, 50)
        XCTAssertEqual(viewModel.amountField.value, "90", "the amount is still the user's to correct")
        XCTAssertFalse(viewModel.validForm, "90 no longer fits in a 50 position")
        XCTAssertNil(viewModel.transactionBuilder)
    }

    /// A position that really is empty may lower the ceiling to zero — the existing
    /// "amount cannot be zero" copy is the honest answer there.
    func testAnEmptyPositionLowersTheCeilingAndInvalidatesTheForm() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let gate = BalanceReadGate()
        let viewModel = makeViewModel(
            coin: TokensStore.tcy,
            vault: TestStore.makeVault(),
            availableToUnstake: 100,
            gate: gate,
            outcome: .succeeds(baseUnits: 0)
        )

        viewModel.onLoad()
        typeAmount("50", into: viewModel)
        await completeLoad(viewModel, gate: gate)

        XCTAssertEqual(viewModel.availableAmount, 0)
        XCTAssertFalse(viewModel.validForm)
        XCTAssertEqual(viewModel.resolvedPercentage, 0, "a zero ceiling has no fraction to derive")
        XCTAssertNil(viewModel.transactionBuilder)
    }

    // MARK: - A read that failed

    /// A failure reports zero exactly as an empty position does, and it must not be
    /// mistaken for one: the card figure is a real number and the read result is
    /// not, so the ceiling — and the typed amount standing against it — stay.
    func testAFailedReadLeavesTheCeilingAndTheTypedAmountAlone() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let gate = BalanceReadGate()
        let viewModel = makeViewModel(
            coin: TokensStore.tcy,
            vault: TestStore.makeVault(),
            availableToUnstake: 100,
            gate: gate,
            outcome: .fails
        )

        viewModel.onLoad()
        typeAmount("50", into: viewModel)
        await completeLoad(viewModel, gate: gate)

        XCTAssertEqual(viewModel.availableAmount, 100, "a failed read must not replace a real ceiling with zero")
        XCTAssertEqual(viewModel.amountField.value, "50")
        XCTAssertEqual(viewModel.resolvedPercentage, 50, accuracy: 0.0001)
    }

    /// …and the sheet still refuses to sign it. The receipt balance is what funds
    /// every auto-compound redemption, so a zero there builds a wasm execute
    /// carrying no funds — a fee for a transaction that moves nothing.
    func testNoAutoCompoundRedemptionIsBuiltWithoutAReceiptBalance() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()

        for meta in Self.autocompoundCoins {
            let gate = BalanceReadGate()
            let viewModel = makeViewModel(
                coin: meta,
                vault: vault,
                availableToUnstake: 100,
                gate: gate,
                outcome: .fails
            )

            viewModel.onLoad()
            typeAmount("50", into: viewModel)
            await completeLoad(viewModel, gate: gate)
            // Isolate the receipt guard from form validity: the amount itself is
            // perfectly valid against the ceiling that survived the failure.
            viewModel.validForm = true

            XCTAssertEqual(viewModel.autocompoundBalance, 0)
            XCTAssertNil(viewModel.transactionBuilder, "\(meta.ticker) built a redemption with no funds")
            XCTAssertTrue(viewModel.isContinueDisabled, "\(meta.ticker) left Continue silently doing nothing")
        }
    }

    /// …and it has to say so rather than looking live and doing nothing when
    /// tapped. `AmountFunctionTransactionScreen` already takes this; the sheet
    /// just never passed it.
    func testContinueIsDisabledUntilTheReceiptBalanceIsIn() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let gate = BalanceReadGate()
        let viewModel = makeViewModel(
            coin: TokensStore.tcy,
            vault: TestStore.makeVault(),
            availableToUnstake: 100,
            gate: gate,
            outcome: .succeeds(baseUnits: 25_000_000_000)
        )

        viewModel.onLoad()
        typeAmount("50", into: viewModel)
        XCTAssertTrue(viewModel.isContinueDisabled, "nothing is signable while the read is in flight")

        await completeLoad(viewModel, gate: gate)

        XCTAssertFalse(viewModel.isContinueDisabled)
    }

    /// A bonded position must never be left waiting on a balance the sheet never
    /// asked for — that combination is a Continue button that can never enable and
    /// a transaction that can never be built. Looped over every asset because it is
    /// invisible on the one that reads nothing: TCY and RUJI bond by memo against
    /// the staked balance, while bRUNE is only ever held as the ybRUNE receipt and
    /// so spends receipt units whichever card opened the sheet.
    func testABondedPositionNeverWaitsOnAReceiptBalance() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()

        for meta in Self.autocompoundCoins {
            let gate = BalanceReadGate()
            let viewModel = makeViewModel(
                coin: meta,
                vault: vault,
                availableToUnstake: 100,
                gate: gate,
                outcome: .succeeds(baseUnits: 25_000_000_000),
                isAutocompound: false
            )

            viewModel.onLoad()

            let spendsReceiptUnits = meta.ticker.uppercased() == "BRUNE"
            XCTAssertEqual(
                viewModel.autocompoundLoadTask != nil,
                spendsReceiptUnits,
                "\(meta.ticker) reads a receipt it does not spend, or spends one it never reads"
            )

            await completeLoad(viewModel, gate: gate)
            // Isolate the receipt guard from form validity, as elsewhere here.
            viewModel.validForm = true

            XCTAssertFalse(viewModel.isContinueDisabled, "\(meta.ticker) left Continue disabled for good")
            XCTAssertNotNil(viewModel.transactionBuilder, "\(meta.ticker) can never build its withdrawal")
            XCTAssertEqual(viewModel.percentageSelected, 100, "\(meta.ticker) percentage")
            // Only the receipt-funded one takes its ceiling from the read.
            let expectedCeiling: Decimal = spendsReceiptUnits ? 250 : 100
            XCTAssertEqual(viewModel.availableAmount, expectedCeiling, "\(meta.ticker) ceiling")
        }
    }
}
