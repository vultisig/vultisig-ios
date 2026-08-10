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
        XCTAssertTrue(coin.amount.contains("002.571644"), "rendered \(coin.amount)")
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

    /// ⚠️ The screen has to render at the ASSET'S precision, not the amount
    /// field's. THORChain settles in whole base units, so truncating the exact
    /// product at `coin.decimals` reproduces the payout exactly — 2002.74 at 5006
    /// bps is 1002.571644 both ways. Four decimals understated that same
    /// withdrawal by 0.000044 TCY, which is the defect this screen exists to
    /// remove, just smaller.
    func testTheHeroRendersEveryDigitTheChainWillActuallyPay() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()

        // ⚠️ A position that uses all 8 decimals, deliberately. The reported
        // 2002.74 is 200274×10^6 base units, so `units × bps` is ALWAYS divisible
        // by 10000 and truncation never happens — a test built on it passes
        // whether the formatter truncates or rounds, which is no test at all.
        // 200274123456 base units at 5002 bps lands on
        // 1001.771165526912: truncating gives 1001.77116552 (what the chain
        // pays), rounding would give ...53 and overstate it by a base unit.
        let staked = Decimal(string: "2002.74123456")!
        let stakedBaseUnits = 200_274_123_456

        let viewModel = UnstakeTransactionViewModel(
            coin: makeTCYCoin(),
            vault: vault,
            isAutocompound: false,
            availableToUnstake: staked
        )
        viewModel.availableAmount = staked
        viewModel.amountField.value = "1001.7712"
        viewModel.percentageSelected = viewModel.percentageFromAmount
        viewModel.onPercentage(viewModel.percentageFromAmount)
        viewModel.validForm = true

        let builder = try XCTUnwrap(viewModel.transactionBuilder)
        XCTAssertEqual(builder.memo, "tcy-:5002")

        let tx = builder.buildSendTransaction(vault: vault)
        let hero = try XCTUnwrap(TCYUnstakePresentation.hero(for: tx))
        guard case .send(_, let coin) = hero else {
            return XCTFail("a withdrawal should render as a resolved single-sided amount")
        }

        // The chain's own integer maths, reproduced independently of the code
        // under test: floor(units × bps / 10000) base units.
        //
        // This equality is what makes the test truncation-sensitive: `chainPays`
        // is already an exact base-unit count, so it formats the same either way,
        // while `coin.amount` formats the un-truncated 1001.771165526912. A
        // rounding formatter would render ...553 here and the two would diverge.
        let chainPays = Decimal(stakedBaseUnits * 5002 / 10_000) / pow(10, 8)
        XCTAssertEqual(coin.amount, chainPays.formatToDecimal(digits: 8))
        // Grouping separators are locale-dependent, so match past them.
        XCTAssertTrue(coin.amount.contains("001.77116552"), "rendered \(coin.amount)")
        // The one-base-unit overstatement a rounding formatter would produce.
        XCTAssertFalse(coin.amount.contains("001.77116553"), "rendered \(coin.amount)")
    }

    /// ⚠️ Emptying a dust position must read as the amount it pays, not as zero.
    /// At four decimals a full exit of this position rendered "0.0001", and
    /// anything under 0.00005 TCY rendered a flat "0" — turning "You're sending 0
    /// TCY" into "You are withdrawing 0 TCY", which is not a fix.
    ///
    /// The three have to agree at this boundary: the memo asks for the whole
    /// position (`tcy-:10000`), the sub-basis-point guard must not refuse it as
    /// if it were the `tcy-:0` case, and the screen must name the real figure.
    func testADustPositionsFullExitIsNamedNotShownAsZero() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()
        let dust = Decimal(string: "0.00012345")!

        let viewModel = UnstakeTransactionViewModel(
            coin: makeTCYCoin(),
            vault: vault,
            isAutocompound: false,
            availableToUnstake: dust
        )
        viewModel.availableAmount = dust
        viewModel.setupAmountField()          // MAX — what the sheet opens on
        // What the shared amount field renders at its own 4 decimals. The full
        // exit is still driven by MAX, so the memo takes the whole position and
        // the screen must say so rather than echoing this truncated figure.
        viewModel.amountField.value = "0.0001"

        // ⚠️ Run the REAL validator chain rather than asserting `validForm` into
        // existence. `transactionBuilder` only asks the fields to publish their
        // errors — it never recomputes `validForm` — so a hand-set flag would let
        // this pass while production's Continue button stayed blocked, which is
        // precisely the failure this test is meant to catch.
        XCTAssertNoThrow(
            try viewModel.amountField.validate(),
            "the sub-basis-point guard must not refuse a full exit of a dust position"
        )
        viewModel.validForm = true

        let builder = try XCTUnwrap(viewModel.transactionBuilder, "a dust full exit must not be refused")
        XCTAssertEqual(builder.memo, "tcy-:10000")

        let tx = builder.buildSendTransaction(vault: vault)
        XCTAssertEqual(tx.withdrawDisplayAmount, dust)

        let hero = try XCTUnwrap(TCYUnstakePresentation.hero(for: tx))
        guard case .send(_, let coin) = hero else {
            return XCTFail("a withdrawal should render as a resolved single-sided amount")
        }
        XCTAssertEqual(coin.amount, dust.formatToDecimal(digits: 8))
        XCTAssertNotEqual(coin.amount, "0")
        XCTAssertFalse(coin.amount.hasPrefix("0.0000") && !coin.amount.contains("12345"),
                       "the whole position is leaving; rendered \(coin.amount)")
    }

    /// ⚠️ The auto-compounding sTCY position is share-based: its balance is a
    /// count of `x/staking-tcy` receipt shares, each worth more than 1 TCY and
    /// drifting further as revenue compounds. Quoting a fraction of that count as
    /// "X TCY" would understate the payout on the screen where it is approved, so
    /// this position names no figure until the redemption ratio is resolved.
    func testTheAutoCompoundPositionNamesNoFigureRatherThanAShareCount() throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()

        let viewModel = UnstakeTransactionViewModel(
            coin: makeTCYCoin(),
            vault: vault,
            isAutocompound: true,
            availableToUnstake: staked
        )
        viewModel.availableAmount = staked
        viewModel.autocompoundBalance = staked
        viewModel.amountField.value = "1002.73"
        viewModel.percentageSelected = viewModel.percentageFromAmount
        viewModel.onPercentage(viewModel.percentageFromAmount)
        viewModel.validForm = true

        let builder = try XCTUnwrap(viewModel.transactionBuilder)
        XCTAssertNotNil(builder.wasmContractPayload, "the compounding position still redeems its shares")
        XCTAssertNil(builder.withdrawDisplayAmount)
        XCTAssertNil(TCYUnstakePresentation.hero(for: builder.buildSendTransaction(vault: vault)))
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
