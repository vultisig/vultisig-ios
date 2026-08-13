//
//  ReceiptShareRedemptionTests.swift
//  VultisigAppTests
//
//  The two unstake arms that redeem RECEIPT SHARES rather than asking a memo for
//  a fraction of a position. Their `liquid.unbond` is funded with an absolute
//  count of receipt base units, so the typed amount is expressible exactly — but
//  it was reached through `Int(percentageSelected ?? percentageFromAmount)`,
//  which floors the fraction to a whole percent and makes one step a whole 1% of
//  the position. On the 2002.74 position the sibling defect was reported against
//  that is ~20 tokens, silently.
//

@testable import VultisigApp
import XCTest

@MainActor
final class ReceiptShareRedemptionTests: XCTestCase {

    /// The position from the bug report, reused here so the two arms can be
    /// compared against the same arithmetic.
    private let staked = Decimal(string: "2002.74")!
    /// The same position in receipt base units, at the 8 decimals bRUNE, ybRUNE,
    /// RUJI and sRUJI all share.
    private let stakedUnits = Decimal(string: "200274000000")!

    // MARK: - The conversion

    func testAnExactShareOfThePositionConvertsExactly() {
        XCTAssertEqual(
            ReceiptShareRedemption.baseUnits(
                forAmount: Decimal(string: "1002.73")!,
                positionValue: staked,
                receiptBaseUnits: stakedUnits,
                closingPosition: false
            ),
            Decimal(string: "100273000000")!
        )
    }

    /// Truncated, never rounded up: a redemption must not spend more of the
    /// position than was asked for, and a fractional `CosmosCoin.amount` is
    /// malformed besides.
    func testAFractionalUnitIsTruncatedRatherThanRounded() {
        // 3 units of a 3-token position, asking for 1.9999 tokens' worth.
        XCTAssertEqual(
            ReceiptShareRedemption.baseUnits(
                forAmount: Decimal(string: "1.9999")!,
                positionValue: 3,
                receiptBaseUnits: 3,
                closingPosition: false
            ),
            1
        )
    }

    /// ⚠️ A full exit pins the whole held balance instead of deriving it. The
    /// amount field renders a rounded figure, so a derived MAX could leave a
    /// sliver of shares behind and keep open a position the user asked to close.
    func testClosingThePositionSpendsEveryHeldShare() {
        XCTAssertEqual(
            ReceiptShareRedemption.baseUnits(
                forAmount: Decimal(string: "1.5")!,
                positionValue: staked,
                receiptBaseUnits: stakedUnits,
                closingPosition: true
            ),
            stakedUnits
        )
    }

    /// ⚠️ The other half of the same invariant: a PARTIAL withdrawal must never
    /// close the position. Truncation only moves the result down, so the held
    /// balance is reached only by an amount that reaches the whole position.
    func testAPartialRedemptionNeverSpendsTheWholeBalance() {
        let units = ReceiptShareRedemption.baseUnits(
            forAmount: Decimal(string: "2002.7399")!,
            positionValue: staked,
            receiptBaseUnits: stakedUnits,
            closingPosition: false
        )
        XCTAssertLessThan(units, stakedUnits)
        XCTAssertEqual(units, Decimal(string: "200273990000")!)
    }

    /// Rejecting an over-balance figure is `AmountBalanceValidator`'s job, and it
    /// has to let the value through to report it — so the conversion clamps
    /// rather than asking the chain for shares that do not exist.
    func testMoreThanThePositionClampsToWhatIsHeld() {
        XCTAssertEqual(
            ReceiptShareRedemption.baseUnits(
                forAmount: staked * 3,
                positionValue: staked,
                receiptBaseUnits: stakedUnits,
                closingPosition: false
            ),
            stakedUnits
        )
    }

    /// An amount below a single receipt base unit has nothing to redeem. This is
    /// the floor under these two arms — one base unit rather than the one basis
    /// point a fractional-withdrawal memo floors at.
    func testAnAmountTooSmallForOneBaseUnitIsZero() {
        XCTAssertEqual(
            ReceiptShareRedemption.baseUnits(
                forAmount: Decimal(string: "0.000000001")!,
                positionValue: staked,
                receiptBaseUnits: stakedUnits,
                closingPosition: false
            ),
            0
        )
    }

    /// A share balance that has not loaded, failed to load, or is empty. Nothing
    /// is redeemable, MAX included — pinning a balance of nothing would build a
    /// redemption funded with nothing.
    func testThereIsNothingToRedeemWithoutAShareBalance() {
        for closing in [true, false] {
            XCTAssertEqual(
                ReceiptShareRedemption.baseUnits(
                    forAmount: 10,
                    positionValue: staked,
                    receiptBaseUnits: 0,
                    closingPosition: closing
                ),
                0
            )
        }
    }

    func testThereIsNothingToRedeemAgainstAnEmptyPosition() {
        XCTAssertEqual(
            ReceiptShareRedemption.baseUnits(
                forAmount: 10,
                positionValue: 0,
                receiptBaseUnits: stakedUnits,
                closingPosition: false
            ),
            0
        )
    }

    // MARK: - bRUNE / ybRUNE

    /// ⚠️ The regression test for the bRUNE arm. Verified to FAIL on the parent
    /// commit, where the same inputs fund the unbond with **100137000000** —
    /// `Int(50.0679) = 50`, so 50% of the receipt balance instead of the 1002.73
    /// that was typed. The difference is 1.36 ybRUNE on this position.
    func testABRuneUnbondRedeemsTheAmountThatWasTypedNotAFlooredPercentage() throws {
        XCTAssertEqual(try redeemedBRuneUnits(typing: "1002.73"), "100273000000")
    }

    /// ⚠️ Also FAILS on the parent commit, at the top of the range where the
    /// flooring is most expensive: `Int(99.995) = 99` unbonded 198271260000 —
    /// 19.93 ybRUNE less than the 2002.64 asked for. Both figures leave the
    /// position open, which is the point of the assertion below them; only one of
    /// them withdraws what was requested.
    func testABRunePartialUnbondTakesTheTypedAmountAndLeavesThePositionOpen() throws {
        let units = try redeemedBRuneUnits(typing: "2002.64")
        XCTAssertEqual(units, "200264000000")
        XCTAssertLessThan(Decimal(string: units)!, stakedUnits)
    }

    /// A full exit still empties the receipt balance exactly — the property the
    /// old `percentage == 100` path had for free and the new one has to pin.
    func testABRuneFullExitUnbondsTheWholeReceiptBalance() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let viewModel = makeBRuneViewModel()
        viewModel.setupAmountField()          // MAX — what the sheet opens on
        viewModel.amountField.value = "2002.7400"
        viewModel.validForm = true

        XCTAssertEqual(try fundedUnits(of: viewModel), "200274000000")
    }

    /// Nothing to redeem must mean no transaction, not a redemption funded with
    /// nothing: the fee would be spent unbonding zero.
    func testABRuneUnbondBelowOneReceiptUnitBuildsNothing() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let viewModel = makeBRuneViewModel()
        type("0.000000001", into: viewModel)

        XCTAssertNil(try XCTUnwrap(viewModel.transactionBuilder).wasmContractPayload)
    }

    /// The share balance not having loaded (or having failed to load) leaves
    /// nothing to unbond, MAX included.
    func testABRuneUnbondBuildsNothingBeforeTheReceiptBalanceLoads() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let viewModel = makeBRuneViewModel()
        viewModel.autocompoundBalance = 0
        viewModel.setupAmountField()
        viewModel.amountField.value = "2002.7400"
        viewModel.validForm = true

        XCTAssertNil(try XCTUnwrap(viewModel.transactionBuilder).wasmContractPayload)
    }

    // MARK: - Fixtures

    private func makeCoin(_ asset: CoinMeta) -> Coin {
        Coin(
            asset: asset,
            address: "thor1fixturereceiptvaultaddress0000000000",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    /// Types `amount` into the sheet the way the field does, so the view model is
    /// left in the state the real screen leaves it in.
    ///
    /// The two lines after the assignment are what `AmountTextField` and
    /// `UnstakeTransactionScreen` do between them on every keystroke: derive the
    /// percentage from the typed amount, then let the view model reconsider
    /// whether the position is being closed. Skipping them would leave
    /// `percentageSelected` on its initial 100 and quietly test a MAX withdrawal
    /// instead of a custom one.
    private func type(_ amount: String, into viewModel: UnstakeTransactionViewModel) {
        viewModel.amountField.value = amount
        viewModel.percentageSelected = viewModel.percentageFromAmount
        viewModel.onPercentage(viewModel.percentageFromAmount)
        viewModel.validForm = true
    }

    /// The bRUNE sheet as the DeFi card opens it: the ybRUNE receipt balance is
    /// both the ceiling and the thing being spent, because the staked card
    /// renders receipt units directly.
    private func makeBRuneViewModel() -> UnstakeTransactionViewModel {
        let viewModel = UnstakeTransactionViewModel(
            coin: makeCoin(TokensStore.brune),
            vault: TestStore.makeVault(),
            isAutocompound: true,
            availableToUnstake: staked
        )
        viewModel.availableAmount = staked
        viewModel.autocompoundBalance = staked
        return viewModel
    }

    private func fundedUnits(of viewModel: UnstakeTransactionViewModel) throws -> String {
        let payload = try XCTUnwrap(try XCTUnwrap(viewModel.transactionBuilder).wasmContractPayload)
        return try XCTUnwrap(payload.coins.first).amount
    }

    private func redeemedBRuneUnits(typing amount: String) throws -> String {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let viewModel = makeBRuneViewModel()
        type(amount, into: viewModel)
        return try fundedUnits(of: viewModel)
    }
}
