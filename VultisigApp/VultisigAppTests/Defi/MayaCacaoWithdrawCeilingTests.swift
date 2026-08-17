//
//  MayaCacaoWithdrawCeilingTests.swift
//  VultisigAppTests
//
//  The MayaChain CACAO staked card and its withdraw sheet must be denominated in
//  the same thing. They were not: the card rendered the member's CACAO value and
//  the sheet's ceiling was the member's pool units, a strictly smaller and
//  entirely different scale.
//
//  Because a CACAO withdrawal signs no coin amount — only a basis-point share of
//  the position (`POOL-:<bps>`) — the display fix has a money question attached,
//  and these tests answer both halves of it: a share picked off the slider signs
//  the same memo under either ceiling, and a typed amount now resolves against
//  the CACAO figure the user was reading.
//

@testable import VultisigApp
import XCTest

@MainActor
final class MayaCacaoWithdrawCeilingTests: XCTestCase {

    /// CACAO's scale (`TokensStore.cacao.decimals`).
    private let decimals = 10
    private let oneCacao = Decimal(sign: .plus, exponent: 10, significand: 1)

    private var token: TestContextToken!

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// A member whose units are worth more than one CACAO each — the ordinary
    /// state of an earning pool, and the one that makes the two scales diverge.
    private func makePosition(cacao: Decimal, units: Decimal) -> MayaCacaoPoolPosition {
        MayaCacaoPoolPosition(
            address: "maya1fixturecacaopoolmemberaddress00000000",
            stakedAmount: cacao * oneCacao,
            availableUnits: units * oneCacao,
            userUnits: units * oneCacao,
            netDeposit: cacao * oneCacao,
            lastWithdrawHeight: 0,
            lastDepositHeight: 1_000
        )
    }

    private func project(_ position: MayaCacaoPoolPosition) -> StakePositionData {
        MayaChainStakeInteractor.stakePositionData(
            position: position,
            coin: TokensStore.cacao,
            decimals: decimals,
            apr: 0.12,
            unstakeMetadata: maturedMetadata
        )
    }

    private var maturedMetadata: UnstakeMetadata {
        UnstakeMetadata(
            lastDepositHeight: 1_000,
            maturityBlocks: 302_400,
            snapshotHeight: 1_000 + 302_400 + 10,
            snapshotTimestamp: Date().timeIntervalSince1970
        )
    }

    private func makeCacaoCoin() -> Coin {
        Coin(
            asset: TokensStore.cacao,
            address: "maya1fixturecacaopoolmemberaddress00000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    private func makeViewModel(availableToUnstake: Decimal, pubKey: String) -> UnstakeTransactionViewModel {
        let viewModel = UnstakeTransactionViewModel(
            coin: makeCacaoCoin(),
            vault: TestStore.makeVault(pubKey: pubKey),
            isAutocompound: false,
            availableToUnstake: availableToUnstake
        )
        viewModel.onLoad()
        return viewModel
    }

    /// What `UnstakeTransactionScreen` + `AmountTextField` do when the slider
    /// moves: the percentage takes ownership and the field is re-derived from the
    /// ceiling in force.
    private func selectPercentage(_ percentage: Double, on viewModel: UnstakeTransactionViewModel) {
        viewModel.percentageSelected = percentage
        viewModel.onPercentage(percentage)
        let derived = viewModel.availableAmount * Decimal(percentage) / 100
        viewModel.amountField.value = derived.formatToDecimal(digits: 4)
    }

    /// What `AmountTextField` does when the user edits the field by hand: the
    /// field takes ownership and the percentage control is cleared.
    private func typeAmount(_ amount: String, into viewModel: UnstakeTransactionViewModel) {
        viewModel.amountField.value = amount
        viewModel.percentageSelected = nil
    }

    // MARK: - The projection is CACAO on both figures

    /// The regression itself. 1000 pool units worth 1200 CACAO: the card said
    /// 1200 and the withdraw sheet said 1000.
    func testWithdrawCeilingIsTheCacaoValueNotPoolUnits() {
        let data = project(makePosition(cacao: 1_200, units: 1_000))

        XCTAssertEqual(data.amount, 1_200, "the staked card figure must stay the member's CACAO value")
        XCTAssertEqual(
            data.availableToUnstake,
            1_200,
            "the withdraw ceiling must be the same CACAO value, not the pool units the sheet used to show"
        )
        XCTAssertNotEqual(data.availableToUnstake, 1_000, "scaled pool units must never reach the withdraw path")
    }

    /// The card and the sheet are one number, at every unit/value ratio — including
    /// the degenerate 1:1 that would have hidden the bug in a fixture.
    func testCardAmountAndWithdrawCeilingAlwaysAgree() {
        let ratios: [(cacao: Decimal, units: Decimal)] = [
            (1_200, 1_000),      // an earning pool
            (500, 500),          // 1:1 — the case that hides the defect
            (Decimal(string: "0.0000000001")!, Decimal(string: "0.00000000005")!), // one base unit
            (2_002, Decimal(string: "1734.6")!)
        ]

        for ratio in ratios {
            let data = project(makePosition(cacao: ratio.cacao, units: ratio.units))
            XCTAssertEqual(
                data.availableToUnstake,
                data.amount,
                "card and withdraw ceiling diverged at \(ratio.cacao) CACAO / \(ratio.units) units"
            )
            XCTAssertEqual(data.amount, ratio.cacao)
        }
    }

    /// The projection still divides by the coin's scale — the fix changed which
    /// field is read, not whether it is converted out of base units.
    func testProjectionConvertsOutOfBaseUnits() {
        let position = makePosition(cacao: 42, units: 40)

        XCTAssertEqual(project(position).amount, 42)
        XCTAssertEqual(position.stakedAmount, 42 * oneCacao, "fixture must be in base units for the test to mean anything")
    }

    /// Everything else on the row is carried through untouched, so the ceiling fix
    /// cannot be read as a rewrite of the card.
    func testProjectionCarriesTheRestOfTheRowUnchanged() {
        let metadata = maturedMetadata
        let data = MayaChainStakeInteractor.stakePositionData(
            position: makePosition(cacao: 1_200, units: 1_000),
            coin: TokensStore.cacao,
            decimals: decimals,
            apr: 0.12,
            unstakeMetadata: metadata
        )

        XCTAssertEqual(data.coin, TokensStore.cacao)
        XCTAssertEqual(data.type, .stake)
        XCTAssertEqual(data.apr, 0.12)
        XCTAssertEqual(data.unstakeMetadata, metadata)
    }

    // MARK: - Money regression: the slider path signs the same memo either way

    /// The fund-safety question. `CacaoUnstakeTransactionBuilder` carries
    /// `amount = "0"`, so the memo is the entire instruction — and on the slider
    /// path the memo is derived from the percentage alone. Changing the ceiling
    /// from pool units to CACAO must therefore move nothing that gets signed.
    func testSliderDrivenWithdrawalSignsTheSameMemoUnderEitherCeiling() {
        let unitsCeiling: Decimal = 1_000   // what the sheet used to open on
        let cacaoCeiling: Decimal = 1_200   // what it opens on now

        for percentage in [100.0, 50.0, 25.0, 10.0] {
            let before = makeViewModel(availableToUnstake: unitsCeiling, pubKey: "cacao-before-\(Int(percentage))")
            let after = makeViewModel(availableToUnstake: cacaoCeiling, pubKey: "cacao-after-\(Int(percentage))")

            selectPercentage(percentage, on: before)
            selectPercentage(percentage, on: after)

            let beforeMemo = before.transactionBuilder?.memo
            let afterMemo = after.transactionBuilder?.memo

            XCTAssertEqual(beforeMemo, "POOL-:\(Int(percentage) * 100)")
            XCTAssertEqual(
                afterMemo,
                beforeMemo,
                "the ceiling fix moved the signed memo at \(percentage)% — it must not"
            )
        }
    }

    /// A full exit is still a full exit: 100% signs the whole position, and the
    /// builder attaches no coin amount to it.
    func testFullExitStillSignsTheWholePositionAndCarriesNoAmount() throws {
        let viewModel = makeViewModel(availableToUnstake: 1_200, pubKey: "cacao-full-exit")
        selectPercentage(100, on: viewModel)

        let builder = try XCTUnwrap(viewModel.transactionBuilder)
        XCTAssertEqual(builder.memo, "POOL-:10000")
        XCTAssertEqual(builder.amount, "0", "a CACAO withdrawal signs a share, never a coin amount")
        XCTAssertFalse(builder.sendMaxAmount)
    }

    // MARK: - The typed path is where the user-visible fix lands

    /// The sheet opens on the figure the card was showing, so a typed amount is
    /// read against CACAO. Under the old units ceiling the same figure was over
    /// the maximum and could not be submitted at all.
    func testATypedCacaoAmountResolvesAgainstTheCacaoPosition() throws {
        let underUnitsCeiling = makeViewModel(availableToUnstake: 1_000, pubKey: "cacao-typed-units")
        let underCacaoCeiling = makeViewModel(availableToUnstake: 1_200, pubKey: "cacao-typed-cacao")

        typeAmount("1100", into: underUnitsCeiling)
        typeAmount("1100", into: underCacaoCeiling)

        XCTAssertNil(
            underUnitsCeiling.transactionBuilder,
            "1100 of a 1200-CACAO position was unreachable while the ceiling was 1000 pool units"
        )

        let builder = try XCTUnwrap(underCacaoCeiling.transactionBuilder)
        XCTAssertEqual(builder.memo, "POOL-:9100", "1100 of 1200 CACAO is 91% of the position")
    }

    /// The ceiling is also what the field is validated against, so the sheet now
    /// accepts everything the card said the user holds.
    func testTheWholeCardAmountIsEnterable() throws {
        let viewModel = makeViewModel(availableToUnstake: 1_200, pubKey: "cacao-typed-max")
        typeAmount("1200", into: viewModel)

        let builder = try XCTUnwrap(viewModel.transactionBuilder)
        XCTAssertEqual(builder.memo, "POOL-:10000")
    }

    /// And nothing beyond it is: the ceiling still bounds the form.
    func testAnAmountAboveTheCardAmountIsStillRefused() {
        let viewModel = makeViewModel(availableToUnstake: 1_200, pubKey: "cacao-typed-over")
        typeAmount("1200.0001", into: viewModel)

        XCTAssertNil(viewModel.transactionBuilder)
    }

    // MARK: - The sheet opens on the ceiling it was handed

    /// Pins the seam the fix travels through: whatever the interactor projected is
    /// what the sheet renders, validates and derives from.
    func testTheSheetOpensOnTheProjectedCeiling() throws {
        let data = project(makePosition(cacao: 1_200, units: 1_000))
        let ceiling = try XCTUnwrap(data.availableToUnstake)
        let viewModel = makeViewModel(availableToUnstake: ceiling, pubKey: "cacao-seam")

        XCTAssertEqual(viewModel.availableAmount, 1_200)
        XCTAssertEqual(viewModel.availableAmount, data.amount, "the sheet must open on the card's figure")
    }
}
