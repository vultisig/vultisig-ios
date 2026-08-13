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
    /// A real RUJI compounded position: the card's RUJI-denominated value and the
    /// sRUJI share balance behind it. They differ because a share is worth more
    /// than 1 RUJI — which is exactly what makes this arm a different conversion
    /// from bRUNE's.
    private let rujiStaked = Decimal(string: "140.64866515")!
    private let rujiShares = Decimal(string: "138.55943656")!

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
    /// amount field renders 4 decimals, so a MAX on a position with more of them
    /// arrives here already short — deriving from it would leave a sliver of
    /// shares behind and keep open a position the user asked to close.
    func testClosingThePositionSpendsEveryHeldShareEvenFromTheRoundedField() {
        // What MAX prefills for a 140.64866515 position.
        XCTAssertEqual(
            ReceiptShareRedemption.baseUnits(
                forAmount: Decimal(string: "140.6486")!,
                positionValue: rujiStaked,
                receiptBaseUnits: Decimal(string: "13855943656")!,
                closingPosition: true
            ),
            Decimal(string: "13855943656")!
        )
    }

    /// ⚠️ **The MAX flag alone must not close a position.** It is set from a
    /// `Double` percentage, so an amount a hair under the balance derives exactly
    /// 100 — the value the field already held, which means SwiftUI emits no
    /// change and the flag is never cleared. Trusting it by itself would take a
    /// remainder the user asked to keep.
    func testAFlagLeftStaleByADoubleRoundedPercentageDoesNotCloseThePosition() {
        let position = Decimal(string: "100000000000")!
        let held = Decimal(string: "10000000000000000000")!
        let typed = Decimal(string: "99999999999.999999")!

        // The collision this guards against is real, not hypothetical: the
        // percentage the field would derive for that amount IS exactly 100.
        XCTAssertEqual(AmountPercentageBinding.percentage(ofAmount: typed, available: position), 100)

        let units = ReceiptShareRedemption.baseUnits(
            forAmount: typed,
            positionValue: position,
            receiptBaseUnits: held,
            closingPosition: true
        )
        XCTAssertLessThan(units, held, "an amount short of the balance must not close the position")
        XCTAssertGreaterThan(units, 0)
    }

    /// The other side of that guard: a figure MAX itself would never have written
    /// is not MAX, however close to the balance it sits.
    func testOnlyTheBalanceOrTheFigureMaxPrefillsCountsAsTheWholePosition() {
        XCTAssertTrue(ReceiptShareRedemption.isWholePosition(amount: rujiStaked, positionValue: rujiStaked))
        XCTAssertTrue(ReceiptShareRedemption.isWholePosition(
            amount: Decimal(string: "140.6486")!, positionValue: rujiStaked
        ))
        XCTAssertFalse(ReceiptShareRedemption.isWholePosition(
            amount: Decimal(string: "140.64865")!, positionValue: rujiStaked
        ))
        XCTAssertFalse(ReceiptShareRedemption.isWholePosition(
            amount: Decimal(string: "140.6485")!, positionValue: rujiStaked
        ))
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

    // MARK: - RUJI auto-compound / sRUJI
    //
    // The other arm, and not the same shape: this card renders what the receipt
    // is WORTH in RUJI, so the typed amount is priced in RUJI and the share count
    // follows from the ratio between the two balances the sheet was opened with.
    // The bRUNE arm's amount is already a share count.

    /// ⚠️ The regression test for the RUJI arm. Verified to FAIL on the parent
    /// commit, where the same inputs redeem **6789412391** shares —
    /// `Int(49.99997) = 49`, so 49% of the share balance instead of the shares
    /// 70.3243 RUJI is worth. That is ~1.4 RUJI missing from a 140 RUJI position.
    func testTheCompoundedRujiRedemptionSpendsTheSharesTheTypedAmountIsWorth() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let viewModel = makeRujiViewModel()
        type("70.3243", into: viewModel)

        XCTAssertEqual(try fundedUnits(of: viewModel), "6927968618")
    }

    /// ⚠️ Also FAILS on the parent commit, where `withdrawDisplayAmount` is `nil`
    /// for this builder and the verify screen names no figure at all.
    ///
    /// The figure is a projection at the ratio the sheet was showing, quantised
    /// to whole shares — so it tracks the typed amount to within one share's
    /// worth and never exceeds it.
    func testTheCompoundedRujiRedemptionQuotesTheRujiThatWillBePaidOut() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()

        let viewModel = makeRujiViewModel(vault: vault)
        type("70.3243", into: viewModel)
        let builder = try XCTUnwrap(viewModel.transactionBuilder)

        let typed = Decimal(string: "70.3243")!
        let quoted = try XCTUnwrap(builder.withdrawDisplayAmount)
        XCTAssertLessThanOrEqual(quoted, typed, "a redemption must never quote more than was asked for")
        XCTAssertEqual(
            NSDecimalNumber(decimal: quoted).doubleValue,
            NSDecimalNumber(decimal: typed).doubleValue,
            accuracy: 0.0000001
        )

        // And it reaches the screen that approves it. The withdrawal provider
        // keys on the builder-supplied figure rather than on TCY specifically,
        // so a redemption that carries one is described by it too.
        let hero = try XCTUnwrap(TransactionHeroResolver.hero(
            on: .functionCallVerify,
            for: .initiating(builder.buildSendTransaction(vault: vault))
        ))
        guard case .send(let title, let coin) = hero else {
            return XCTFail("a redemption should render as a resolved single-sided amount")
        }
        XCTAssertEqual(coin.ticker, "RUJI")
        XCTAssertNotEqual(coin.amount, "0")
        XCTAssertTrue(coin.amount.contains("70.32429999"), "rendered \(coin.amount)")
        XCTAssertEqual(title, "quotedWithdrawalVerifyTitle".localized)
    }

    /// The wire truth is untouched: the redemption still carries no amount of its
    /// own, because the funds are the instruction.
    func testTheCompoundedRujiRedemptionStillCarriesNoAmountOnTheWire() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let viewModel = makeRujiViewModel()
        type("70.3243", into: viewModel)
        let builder = try XCTUnwrap(viewModel.transactionBuilder)

        XCTAssertEqual(builder.amount, "0")
        XCTAssertEqual(builder.memo, "")
    }

    /// ⚠️ Asking for all but a sliver must leave that sliver staked. On the
    /// parent this redeemed 13717384219 shares — `Int(99.99)` — which also left
    /// the position open, but 138556 shares further from what was asked for.
    func testACompoundedRujiPartialRedemptionLeavesThePositionOpen() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let viewModel = makeRujiViewModel()
        type("140.6486", into: viewModel)
        let builder = try XCTUnwrap(viewModel.transactionBuilder as? RUJILiquidUnbondTransactionBuilder)

        XCTAssertEqual(try fundedUnits(of: viewModel), "13855937237")
        XCTAssertLessThan(builder.redeemedUnits, builder.heldUnits)
    }

    /// A full exit redeems every share, pinned rather than derived — the property
    /// the old `percentage == 100` path had for free.
    func testACompoundedRujiFullExitRedeemsEveryShare() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let viewModel = makeRujiViewModel()
        viewModel.setupAmountField()          // MAX — what the sheet opens on
        // What `AmountTextField.setupAmount()` writes: the balance truncated to
        // the field's 4 decimals, which is already short of the position.
        viewModel.amountField.value = "140.6486"
        viewModel.validForm = true

        XCTAssertEqual(try fundedUnits(of: viewModel), "13855943656")
    }

    /// The bonded RUJI position is exact already and must stay untouched: its
    /// `withdraw:<asset>:<raw>` memo carries an ABSOLUTE amount, so none of this
    /// applies to it. `isAutocompound` is the only thing separating the two, and
    /// both arrive on the RUJI coin.
    func testTheBondedRujiWithdrawalStillTakesTheAbsoluteAmountPath() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let viewModel = UnstakeTransactionViewModel(
            coin: makeCoin(TokensStore.ruji),
            vault: TestStore.makeVault(),
            isAutocompound: false,
            availableToUnstake: rujiStaked
        )
        viewModel.availableAmount = rujiStaked
        // The share balance is set too, so a builder that reached for it instead
        // of the bonded path would be caught rather than merely failing to build.
        viewModel.autocompoundBalance = rujiShares
        type("70.3243", into: viewModel)

        let builder = try XCTUnwrap(viewModel.transactionBuilder)
        XCTAssertTrue(builder is RUJIUnstakeTransactionBuilder)
        XCTAssertTrue(builder.memo.hasPrefix("withdraw:x/ruji:"), "built \(builder.memo)")
        XCTAssertTrue(try XCTUnwrap(builder.wasmContractPayload).coins.isEmpty)
    }

    /// ⚠️ The two balances behind this arm come from different reads — the RUJI
    /// valuation from the persisted card, the share count from the sheet's own
    /// fetch — so they can disagree. What must hold anyway: the quote never
    /// exceeds what was asked for, and a partial redemption still leaves the
    /// position open. Here the card is stale at twice the current share balance,
    /// which is the worst case that path can produce.
    func testAnIncoherentPairStillCannotOverQuoteOrCloseThePosition() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let typed = Decimal(string: "70")!
        let builder = RUJILiquidUnbondTransactionBuilder(
            coin: makeCoin(TokensStore.ruji),
            withdrawAmount: typed,
            stakedAmount: Decimal(string: "140")!,   // what the card was showing
            receiptShares: Decimal(string: "70")!,   // what is actually held now
            sendMaxAmount: false
        )

        XCTAssertLessThanOrEqual(try XCTUnwrap(builder.withdrawDisplayAmount), typed)
        XCTAssertLessThan(builder.redeemedUnits, builder.heldUnits)
        XCTAssertEqual(
            try XCTUnwrap(try XCTUnwrap(builder.wasmContractPayload).coins.first).amount,
            "3500000000"
        )
    }

    // MARK: - Beyond 64 bits

    /// ⚠️ A receipt balance is read as `UInt64` base units, so it can exceed
    /// `Int.max` — and routing the redeemed count through `Decimal.toInt()` wraps
    /// there. A wrapped count reads as negative, fails the `>= 1` guard, and
    /// makes the position unwithdrawable at MAX rather than merely mis-sized.
    /// 1e11 tokens at 8 decimals is 1e19 base units, comfortably past 9.22e18.
    func testAReceiptBalanceBeyondSixtyFourBitsStillCloses() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let huge = Decimal(string: "100000000000")!

        let brune = BRUNEUnstakeTransactionBuilder(
            coin: makeCoin(TokensStore.brune),
            withdrawAmount: huge,
            stakedAmount: huge,
            autoCompoundAmount: huge,
            sendMaxAmount: true
        )
        XCTAssertEqual(
            try XCTUnwrap(try XCTUnwrap(brune.wasmContractPayload).coins.first).amount,
            "10000000000000000000"
        )

        let ruji = RUJILiquidUnbondTransactionBuilder(
            coin: makeCoin(TokensStore.ruji),
            withdrawAmount: huge,
            stakedAmount: huge,
            receiptShares: huge,
            sendMaxAmount: true
        )
        XCTAssertEqual(
            try XCTUnwrap(try XCTUnwrap(ruji.wasmContractPayload).coins.first).amount,
            "10000000000000000000"
        )
    }

    /// The funded count is an integer string on the wire — a fractional
    /// `CosmosCoin.amount` is malformed, and dropping the 64-bit round trip means
    /// nothing else is truncating it.
    func testTheFundedCountIsAlwaysWholeDigits() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let viewModel = makeRujiViewModel()
        type("70.3243", into: viewModel)
        let units = try fundedUnits(of: viewModel)

        XCTAssertFalse(units.contains("."), "rendered \(units)")
        XCTAssertFalse(units.contains("e"), "rendered \(units)")
        XCTAssertTrue(units.allSatisfy { $0.isASCII && $0.isNumber }, "rendered \(units)")
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

    /// The RUJI compounded sheet as the DeFi card opens it: the ceiling is the
    /// RUJI the position is worth, and the thing being spent is the sRUJI share
    /// balance. A share is worth more than 1 RUJI, so the two differ.
    private func makeRujiViewModel(vault: Vault? = nil) -> UnstakeTransactionViewModel {
        let viewModel = UnstakeTransactionViewModel(
            coin: makeCoin(TokensStore.ruji),
            vault: vault ?? TestStore.makeVault(),
            isAutocompound: true,
            availableToUnstake: rujiStaked
        )
        viewModel.availableAmount = rujiStaked
        viewModel.autocompoundBalance = rujiShares
        return viewModel
    }

    private func redeemedBRuneUnits(typing amount: String) throws -> String {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }

        let viewModel = makeBRuneViewModel()
        type(amount, into: viewModel)
        return try fundedUnits(of: viewModel)
    }
}
