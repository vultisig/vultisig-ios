//
//  KaminoWithdrawViewModelTests.swift
//  VultisigAppTests
//
//  The withdraw form decides three things, and each one can cost the user money
//  if it is wrong:
//
//  1. **Whether a withdraw may be built at all.** Every deposit into these
//     vaults auto-stakes its shares into the vault's farm, and the transaction
//     that spends staked shares has never been observed. That is a refusal, and
//     it has to be one the user can see rather than a failure deep in the
//     pipeline.
//  2. **How many shares to request.** The form is denominated in the asset and
//     the API is denominated in shares. A request above the user's balance is
//     silently rewritten to `u64::MAX` — withdraw everything — so the maximum is
//     sent as the exact held balance and never as a converted number.
//  3. **What the user approves.** The summary and the payload come from one
//     reading of the amount, so an edit landing during preparation cannot split
//     them.
//

import BigInt
@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class KaminoWithdrawViewModelTests: XCTestCase {

    private var storeToken: TestContextToken!
    private var vault: Vault!
    private var service: StubWithdrawService!
    private var preparer: SpyWithdrawPreparer!

    private let owner = KaminoTransactionFixtures.usdcWithdraw.feePayer

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
        service = StubWithdrawService()
        preparer = SpyWithdrawPreparer()
    }

    override func tearDown() async throws {
        preparer = nil
        service = nil
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - Farm-staked positions

    /// The state every real position in these vaults is in, and it now builds.
    /// The form offers the whole position — not just its unstaked part — and the
    /// request it hands down carries the split, so the validator knows to
    /// require the farm release.
    func testAFarmStakedPositionIsWithdrawable() async throws {
        addUsdcCoin()
        service.positions = [Self.position(staked: "5.5", unstaked: "0", total: "5.5")]
        let viewModel = makeViewModel()

        await viewModel.onLoad()

        XCTAssertNil(viewModel.unavailableReason)
        XCTAssertNotEqual(viewModel.availableAmount, .zero)

        viewModel.amountField.value = "1"
        let made = await viewModel.makeWithdraw()
        let withdraw = try XCTUnwrap(made)

        let request = try XCTUnwrap(preparer.requests.first?.request)
        XCTAssertEqual(request.unstakedShares.baseUnits, BigInt(0))
        // Nothing is unstaked, so the whole request has to come out of the farm.
        XCTAssertEqual(request.unstakeShares, request.shares)
        XCTAssertTrue(request.requiresUnstake)
        XCTAssertEqual(withdraw.shares, request.shares)
    }

    /// A partly staked position spends across the boundary in one transaction:
    /// the unstaked part directly, the shortfall out of the farm.
    func testAPartlyStakedPositionUnstakesOnlyTheShortfall() async throws {
        addUsdcCoin()
        service.positions = [Self.position(staked: "1", unstaked: "4.5", total: "5.5")]
        let viewModel = makeViewModel()

        await viewModel.onLoad()
        XCTAssertNil(viewModel.unavailableReason)

        // 5.4 shares' worth of asset, comfortably above the 4.5 unstaked.
        viewModel.amountField.value = "5.688"
        let made = await viewModel.makeWithdraw()
        XCTAssertNotNil(made)

        let request = try XCTUnwrap(preparer.requests.first?.request)
        XCTAssertEqual(request.unstakedShares.baseUnits, BigInt(4_500_000))
        XCTAssertTrue(request.requiresUnstake)
        XCTAssertEqual(
            request.unstakeShares.baseUnits,
            request.shares.baseUnits - BigInt(4_500_000)
        )
    }

    /// And a request that fits inside the unstaked balance asks for no release
    /// at all — the two-instruction shape, which the validator then REQUIRES to
    /// carry no farms instruction.
    func testARequestInsideTheUnstakedBalanceNeedsNoRelease() async throws {
        addUsdcCoin()
        service.positions = [Self.position(staked: "1", unstaked: "4.5", total: "5.5")]
        let viewModel = makeViewModel()

        await viewModel.onLoad()

        viewModel.amountField.value = "1"
        let made = await viewModel.makeWithdraw()
        XCTAssertNotNil(made)

        let request = try XCTUnwrap(preparer.requests.first?.request)
        XCTAssertFalse(request.requiresUnstake)
        XCTAssertEqual(request.unstakeShares.baseUnits, BigInt(0))
    }

    func testAnEmptyPositionSaysSoAndOffersNothing() async {
        addUsdcCoin()
        service.positions = []
        let viewModel = makeViewModel()

        await viewModel.onLoad()

        XCTAssertEqual(viewModel.eligibility, .empty)
        XCTAssertEqual(viewModel.unavailableReason, .nothingToWithdraw)
        XCTAssertEqual(viewModel.availableAmount, .zero)
    }

    /// A failed position read must not fall back to the cached token figure. That
    /// figure is a value derived from a rate, and sizing a withdraw from it is
    /// exactly the round trip this flow refuses to perform.
    func testAFailedPositionReadLeavesNothingWithdrawable() async {
        addUsdcCoin()
        service.positionsError = StubWithdrawService.StubError.unavailable
        let viewModel = makeViewModel()

        await viewModel.onLoad()

        XCTAssertEqual(viewModel.eligibility, .unreadable)
        XCTAssertEqual(viewModel.unavailableReason, .positionUnreadable)
        XCTAssertEqual(viewModel.availableAmount, .zero)
    }

    /// Without the vault's rate there is no conversion between the asset and
    /// shares at all, so the form stays unusable rather than guessing one.
    func testAFailedHydrationLeavesTheFormUnableToBuild() async {
        addUsdcCoin()
        service.infoError = StubWithdrawService.StubError.unavailable
        let viewModel = makeViewModel()

        await viewModel.onLoad()

        XCTAssertNotNil(viewModel.loadError)
        XCTAssertNotNil(viewModel.loadErrorText)
        XCTAssertNil(viewModel.error)
        viewModel.amountField.value = "1"
        let withdraw = await viewModel.makeWithdraw()
        XCTAssertNil(withdraw)
        XCTAssertTrue(preparer.requests.isEmpty)
    }

    /// And it is recoverable, with the same shape as the deposit form's: the
    /// retry re-runs the load, and a second pass must not stack a second
    /// minimum and a second balance check on the first's.
    func testRetryingAFailedLoadHydratesTheFormWithoutDoublingItsValidators() async {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        service.infoError = StubWithdrawService.StubError.unavailable
        let viewModel = makeViewModel()

        await viewModel.onLoad()
        XCTAssertNotNil(viewModel.loadError)

        service.infoError = nil
        await viewModel.onLoad()

        XCTAssertNil(viewModel.loadError)
        XCTAssertNil(viewModel.loadErrorText)
        XCTAssertNotNil(viewModel.vaultInfo)
        XCTAssertNil(viewModel.unavailableReason)
        // Required, minimum, balance — one of each, not two.
        XCTAssertEqual(viewModel.amountField.validators.count, 3)
    }

    /// ⚠️ A load that fails after a successful one must not leave the previous
    /// position standing. Keeping it would show a maximum for a position that
    /// may now be empty, and let a withdraw be built against a balance this
    /// pass could not confirm.
    func testALoadThatFailsAfterASuccessfulOneLeavesNoPositionBehind() async {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        let viewModel = makeViewModel()

        await viewModel.onLoad()
        XCTAssertGreaterThan(viewModel.availableAmount, 0)

        service.infoError = StubWithdrawService.StubError.unavailable
        await viewModel.onLoad()

        XCTAssertNotNil(viewModel.loadError)
        XCTAssertNil(viewModel.vaultInfo)
        XCTAssertNil(viewModel.eligibility)
        XCTAssertEqual(viewModel.availableAmount, .zero)
        // `unavailableReason` reads a nil eligibility as "no reason to refuse",
        // so it is not enough on its own — Continue has to read the hydration.
        XCTAssertNil(viewModel.unavailableReason)
        XCTAssertTrue(viewModel.isWithdrawUnavailable)

        viewModel.amountField.value = "1"
        let withdraw = await viewModel.makeWithdraw()
        XCTAssertNil(withdraw)
    }

    // MARK: - The maximum

    /// The form's ceiling is the asset value of the withdrawable shares, at the
    /// vault's own rate.
    func testTheMaximumIsTheAssetValueOfTheHeldShares() async {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        let viewModel = makeViewModel()

        await viewModel.onLoad()

        XCTAssertEqual(
            viewModel.eligibility,
            .withdrawable(
                KaminoWithdrawableShares(
                    // One base unit below the balance: `5.5` is exactly
                    // representable, and asking for the whole of it is what the
                    // API answers with its withdraw-everything sentinel.
                    maximum: KaminoShareAmount(baseUnits: BigInt(5_499_999), decimals: 6),
                    unstaked: KaminoShareAmount(baseUnits: BigInt(5_500_000), decimals: 6)
                )
            )
        )
        XCTAssertEqual(viewModel.availableAmount, Decimal(string: "5.794821"))
    }

    /// The trap, end to end. A 100% withdraw sends the exact share balance —
    /// never the number that comes back from converting the asset amount, which
    /// is what could tip over the balance and become `u64::MAX`.
    func testAFullWithdrawRequestsTheExactHeldShareBalance() async throws {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        let viewModel = makeViewModel()
        await viewModel.onLoad()

        // What the 100% button writes: the maximum, at the asset's own scale.
        viewModel.amountField.value = "5.794821"
        let made = await viewModel.makeWithdraw()
        let withdraw = try XCTUnwrap(made)

        XCTAssertEqual(withdraw.shares.baseUnits, BigInt(5_499_999))
        XCTAssertEqual(preparer.requests.first?.request.shares.baseUnits, BigInt(5_499_999))
        XCTAssertEqual(withdraw.payload.kaminoPayload?.amountBaseUnits, "5499999")
        // The one thing this must never be.
        XCTAssertNotEqual(withdraw.shares.baseUnits, BigInt(UInt64.max))
    }

    /// And an amount ABOVE the maximum is refused rather than clamped to it.
    ///
    /// This is the case the shared form cannot stop: `FormScreen` disables
    /// Continue only on its own flag and never on `validForm`, so an amount the
    /// balance validator rejected still reaches the build. Treating it as "the
    /// whole position" would make a mistyped digit a full exit.
    func testAnAmountAboveTheMaximumIsRefusedRatherThanClamped() async {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        let viewModel = makeViewModel()
        await viewModel.onLoad()

        for typed in ["5.7949", "58", "999999999"] {
            viewModel.amountField.value = typed
            let withdraw = await viewModel.makeWithdraw()

            XCTAssertNil(withdraw, typed)
            XCTAssertEqual(
                viewModel.error as? AmountBalanceValidator.ValidationError,
                .exceedsBalance,
                typed
            )
        }
        XCTAssertTrue(preparer.requests.isEmpty)
    }

    /// Below the maximum the amount converts, truncating.
    func testAPartialWithdrawConvertsTheAssetAmountRoundedDown() async throws {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        let viewModel = makeViewModel()
        await viewModel.onLoad()

        viewModel.amountField.value = "1"
        let made = await viewModel.makeWithdraw()
        let withdraw = try XCTUnwrap(made)

        // 1 USDC ÷ 1.0536041812651029025 = 0.949123… shares, truncated.
        XCTAssertEqual(withdraw.shares.baseUnits, BigInt(949_123))
        XCTAssertLessThan(withdraw.shares.baseUnits, BigInt(5_500_000))
    }

    // MARK: - The minimum

    /// The vault's minimum is in SHARE base units, so it is judged after the
    /// conversion. Asserted through the validator the form installs, because
    /// that is what actually gates the continue button.
    func testTheMinimumIsJudgedAfterTheConversion() async throws {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        service.minWithdrawShares = BigInt(1_000_000)
        let viewModel = makeViewModel()
        await viewModel.onLoad()

        // 1 USDC is 949,123 shares — below a one-share minimum, even though the
        // token figure is comfortably above it.
        viewModel.amountField.value = "1"
        XCTAssertThrowsError(try viewModel.amountField.validateErrors())

        viewModel.amountField.value = "1.1"
        XCTAssertNoThrow(try viewModel.amountField.validateErrors())
    }

    /// The minimum rounds away from the user and the maximum rounds toward
    /// them, so a position sitting on the minimum can render a minimum one base
    /// unit above its own balance — a form that says "at least 5.794822" over a
    /// balance of 5.794821, while Max still works, because Max sends the exact
    /// share count rather than a figure converted back out of the asset.
    ///
    /// The displayed minimum is capped at the maximum in that case only.
    func testTheDisplayedMinimumNeverExceedsABalanceThatCanSatisfyIt() async throws {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        // Exactly the spendable share balance: 5.5 shares truncates exactly, so
        // `spendable` steps back one base unit to stay clear of the sentinel.
        service.minWithdrawShares = BigInt(5_499_999)
        let viewModel = makeViewModel()
        await viewModel.onLoad()

        // 5_499_999 × 1.0536041812651029025 = 5_794_821.94…, so the two
        // conversions land either side of it.
        XCTAssertEqual(viewModel.minimumWithdraw?.baseUnits, BigInt(5_794_821))
    }

    /// But a position that genuinely cannot reach the minimum keeps the real
    /// figure, because that user needs to see what they are short of.
    func testAPositionBelowTheMinimumStillShowsTheRealMinimum() async throws {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        service.minWithdrawShares = BigInt(6_000_000)
        let viewModel = makeViewModel()
        await viewModel.onLoad()

        // 6_000_000 × 1.0536041812651029025 = 6_321_625.08…, rounded up.
        XCTAssertEqual(viewModel.minimumWithdraw?.baseUnits, BigInt(6_321_626))
    }

    /// And the build refuses it too, so a form bug cannot spend a ceremony on a
    /// transaction the chain rejects.
    func testABelowMinimumWithdrawIsRefusedAtBuildTime() async {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        service.minWithdrawShares = BigInt(1_000_000)
        let viewModel = makeViewModel()
        await viewModel.onLoad()

        viewModel.amountField.value = "1"
        let withdraw = await viewModel.makeWithdraw()

        XCTAssertNil(withdraw)
        XCTAssertTrue(preparer.requests.isEmpty)
        guard case .belowMinimum = viewModel.error as? KaminoWithdrawError else {
            return XCTFail("expected a below-minimum refusal, got \(String(describing: viewModel.error))")
        }
    }

    // MARK: - Single capture

    /// The summary and the payload are built from ONE reading of the amount.
    /// Preparing takes several network round trips and the field stays editable,
    /// so a re-read afterwards could approve a different withdraw from the one
    /// inside the bytes.
    func testAnEditDuringPreparationCannotSplitTheSummaryFromThePayload() async throws {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        let viewModel = makeViewModel()
        await viewModel.onLoad()
        viewModel.amountField.value = "1"

        preparer.onPrepare = { [weak viewModel] in
            Task { @MainActor in viewModel?.amountField.value = "5.794821" }
        }

        let made = await viewModel.makeWithdraw()
        let withdraw = try XCTUnwrap(made)

        XCTAssertEqual(withdraw.shares.baseUnits, BigInt(949_123))
        XCTAssertEqual(preparer.requests.first?.request.shares.baseUnits, BigInt(949_123))
        XCTAssertEqual(withdraw.transaction.amount, "0.999999")
    }

    // MARK: - Payload and summary

    /// What the verify screen ends up signing: the prepared bytes verbatim,
    /// carried as `signSolana`, plus the marker that lets the pre-keysign
    /// refresh splice a live blockhash into them.
    func testThePayloadCarriesThePreparedBytesAndTheWithdrawMarker() async throws {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        let viewModel = makeViewModel()
        await viewModel.onLoad()
        viewModel.amountField.value = "1"

        let made = await viewModel.makeWithdraw()
        let payload = try XCTUnwrap(made).payload

        XCTAssertEqual(
            payload.signSolana?.rawTransactions,
            [KaminoTransactionFixtures.usdcWithdraw.injected]
        )
        XCTAssertEqual(payload.kaminoPayload?.operation, .withdraw)
        XCTAssertEqual(payload.kaminoPayload?.vaultAddress, KaminoVaultRegistry.steakhouseUSDC.address)
        // The marker records the unit that is actually in the bytes: SHARES.
        XCTAssertEqual(payload.kaminoPayload?.amountBaseUnits, "949123")
        // The payload's own amount is the asset figure the user reads, and the
        // destination is the user's own account — a withdraw pays them.
        XCTAssertEqual(payload.toAddress, owner)
        XCTAssertEqual(payload.toAmount, BigInt(999_999))
    }

    /// The summary shows what the shares are worth, not the characters that were
    /// typed — and it has to read back as the same number on the device's own
    /// locale, because everything downstream re-parses `SendTransaction.amount`.
    func testTheDisplayedAmountReadsBackAsTheAmountBeingWithdrawn() async throws {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        let viewModel = makeViewModel()
        await viewModel.onLoad()
        viewModel.amountField.value = "5.794821"

        let made = await viewModel.makeWithdraw()
        let withdraw = try XCTUnwrap(made)

        let expected = try XCTUnwrap(
            withdraw.shares.tokenValue(tokensPerShare: Self.rate, tokenDecimals: 6)
        )
        XCTAssertEqual(withdraw.transaction.amountDecimal, expected.decimalValue)
    }

    /// The compute budget the app injected travels on the payload, at the
    /// withdraw limit rather than a deposit's.
    func testThePayloadReportsTheInjectedComputeBudget() async throws {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        let viewModel = makeViewModel()
        await viewModel.onLoad()
        viewModel.amountField.value = "1"

        let made = await viewModel.makeWithdraw()
        let payload = try XCTUnwrap(made).payload

        guard case .Solana(_, let priorityFee, let priorityLimit, _, _, _) = payload.chainSpecific else {
            return XCTFail("expected Solana chain specific")
        }
        XCTAssertEqual(priorityFee, BigInt(KaminoTransactionFixtures.unitPriceMicroLamports))
        XCTAssertEqual(priorityLimit, BigInt(KaminoComputeBudget.withdrawUnitLimit))
    }

    /// A vault whose asset the wallet does not carry has nowhere to settle into
    /// that the app can name, so the form says so and builds nothing.
    func testAMissingWalletCoinIsSurfacedAndBlocksTheBuild() async {
        let viewModel = makeViewModel()

        await viewModel.onLoad()

        XCTAssertTrue(viewModel.isMissingWithdrawCoin)
        viewModel.amountField.value = "1"
        let withdraw = await viewModel.makeWithdraw()
        XCTAssertNil(withdraw)
        XCTAssertTrue(preparer.requests.isEmpty)
    }

    // MARK: - Liquidity

    /// A withdraw above the vault's liquid buffer is rendered as an ordinary
    /// state. The buffer is 0.36% of this vault, so most withdrawals land here.
    func testAWithdrawAboveTheLiquidBufferIsSurfacedAsAState() async {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        service.tokensAvailable = "0.5"
        let viewModel = makeViewModel()
        await viewModel.onLoad()

        viewModel.amountField.value = "0.4"
        XCTAssertEqual(viewModel.liquidity, .instant)
        XCTAssertNil(viewModel.limitedLiquidityText)

        viewModel.amountField.value = "1"
        XCTAssertEqual(
            viewModel.liquidity,
            .delayed(available: KaminoTokenAmount(baseUnits: BigInt(500_000), decimals: 6))
        )
        XCTAssertNotNil(viewModel.limitedLiquidityText)
    }

    /// A simulation refusal on a withdraw that exceeded the published buffer is
    /// reported as the shortfall it can see. It does not claim to have decoded a
    /// program error — none has ever been observed — so any other failure keeps
    /// its own message.
    func testASimulationFailureBeyondTheBufferIsReportedAsAShortfall() async {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        service.tokensAvailable = "0.5"
        preparer.error = KaminoPreparationError.simulationFailed(stage: .budgeted, reason: "Custom(6003)")
        let viewModel = makeViewModel()
        await viewModel.onLoad()
        viewModel.amountField.value = "1"

        let withdraw = await viewModel.makeWithdraw()

        XCTAssertNil(withdraw)
        guard case .insufficientLiquidity = viewModel.error as? KaminoWithdrawError else {
            return XCTFail("expected an insufficient-liquidity refusal, got \(String(describing: viewModel.error))")
        }
    }

    func testASimulationFailureWithinTheBufferKeepsItsOwnMessage() async {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        service.tokensAvailable = "500"
        preparer.error = KaminoPreparationError.simulationFailed(stage: .budgeted, reason: "Custom(6003)")
        let viewModel = makeViewModel()
        await viewModel.onLoad()
        viewModel.amountField.value = "1"

        let withdraw = await viewModel.makeWithdraw()

        XCTAssertNil(withdraw)
        XCTAssertEqual(
            viewModel.error as? KaminoPreparationError,
            .simulationFailed(stage: .budgeted, reason: "Custom(6003)")
        )
    }

    // MARK: - The bytes that get signed

    /// The withdraw half of the same property — see the deposit test for why
    /// this hop is worth its own assertion.
    ///
    /// The marker records SHARES, not the asset amount the user typed: the bytes
    /// are denominated in shares and `toAmount` is a projection at the current
    /// rate. Getting those two the wrong way round is the mistake the typed
    /// amounts exist to prevent, and this is where it would surface.
    func testTheWithdrawPayloadCarriesThePreparedBytesVerbatim() async throws {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        let viewModel = makeViewModel()
        await viewModel.onLoad()

        let sentinel = KaminoPreparedTransaction(
            base64: KaminoTransactionFixtures.solDeposit.injected,
            priorityFee: KaminoPriorityFee(limit: 222_222, price: 55_555),
            unitsConsumed: 1,
            payerLamportsAfter: nil,
            recentBlockhash: "6VjnGjZWnCyLtCd5FZTLpqm9GNjnzDrGGjyEfKNXfPKa"
        )
        preparer.prepared = sentinel

        viewModel.amountField.value = "1"
        let made = await viewModel.makeWithdraw()
        let withdraw = try XCTUnwrap(made)

        guard case .signSolana(let solana)? = withdraw.payload.signData else {
            return XCTFail("a Kamino withdraw must sign raw Solana bytes, not a rebuilt transfer")
        }
        XCTAssertEqual(solana.rawTransactions, [sentinel.base64])

        guard case .Solana(let blockhash, let price, let limit, _, _, _) = withdraw.payload.chainSpecific else {
            return XCTFail("expected Solana chain-specific data")
        }
        XCTAssertEqual(blockhash, sentinel.recentBlockhash)
        XCTAssertEqual(price, BigInt(sentinel.priorityFee.price))
        XCTAssertEqual(limit, BigInt(sentinel.priorityFee.limit))

        let marker = try XCTUnwrap(withdraw.payload.kaminoPayload)
        XCTAssertEqual(marker.operation, .withdraw)
        XCTAssertEqual(
            marker.amountBaseUnits, String(withdraw.shares.baseUnits),
            "the marker must record the shares the bytes carry, not the asset amount typed"
        )
        // A withdraw pays the user, so the destination is their own account.
        XCTAssertEqual(withdraw.payload.toAddress, owner)
    }

    // MARK: - Helpers

    private func makeViewModel() -> KaminoWithdrawViewModel {
        KaminoWithdrawViewModel(
            vault: vault,
            descriptor: KaminoVaultRegistry.steakhouseUSDC,
            service: service,
            preparer: preparer
        )
    }

    private func addUsdcCoin() {
        let asset = CoinMeta(
            chain: .solana,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: KaminoVaultRegistry.usdcMint,
            isNativeToken: false
        )
        let coin = Coin(asset: asset, address: owner, hexPublicKey: "pub")
        coin.rawBalance = "0"
        vault.coins.append(coin)
    }

    private static let rate = KaminoRate(apiString: "1.0536041812651029025") ?? KaminoRate(apiString: "1")!

    private static var unstakedPosition: KaminoUserPositionResponse {
        position(staked: "0", unstaked: "5.5", total: "5.5")
    }

    private static func position(
        staked: String,
        unstaked: String,
        total: String
    ) -> KaminoUserPositionResponse {
        KaminoUserPositionResponse(
            vaultAddress: KaminoVaultRegistry.steakhouseUSDC.address,
            stakedShares: staked,
            unstakedShares: unstaked,
            totalShares: total
        )
    }
}

// MARK: - Test doubles

// Protocol conformances keep their declared signatures, so unused parameters and
// `async` without `await` are unavoidable here.
// swiftlint:disable async_without_await unused_parameter

private final class StubWithdrawService: KaminoServiceProtocol, @unchecked Sendable {
    enum StubError: Error { case unavailable }

    private let lock = NSLock()
    private var _infoError: Error?
    private var _positionsError: Error?
    private var _positions: [KaminoUserPositionResponse] = []
    private var _minWithdrawShares = BigInt(1_000)
    private var _tokensAvailable: String?

    var infoError: Error? {
        get { lock.withLock { _infoError } }
        set { lock.withLock { _infoError = newValue } }
    }

    var positionsError: Error? {
        get { lock.withLock { _positionsError } }
        set { lock.withLock { _positionsError = newValue } }
    }

    var positions: [KaminoUserPositionResponse] {
        get { lock.withLock { _positions } }
        set { lock.withLock { _positions = newValue } }
    }

    var minWithdrawShares: BigInt {
        get { lock.withLock { _minWithdrawShares } }
        set { lock.withLock { _minWithdrawShares = newValue } }
    }

    /// The vault's liquid buffer, in human units. `nil` means the metrics
    /// response carried nothing readable.
    var tokensAvailable: String? {
        get { lock.withLock { _tokensAvailable } }
        set { lock.withLock { _tokensAvailable = newValue } }
    }

    func fetchVaultInfo(descriptor: KaminoVaultDescriptor) async throws -> KaminoVaultInfo {
        await Task.yield()
        if let infoError { throw infoError }
        return KaminoVaultInfo(
            descriptor: descriptor,
            name: descriptor.fallbackName,
            minDeposit: KaminoTokenAmount(baseUnits: BigInt(100_000), decimals: descriptor.tokenDecimals),
            minWithdraw: KaminoShareAmount(baseUnits: minWithdrawShares, decimals: descriptor.sharesDecimals),
            lookupTable: KaminoTransactionFixtures.usdcWithdraw.lookupTable,
            apy30d: 0,
            // swiftlint:disable:next force_unwrapping
            tokensPerShare: KaminoRate(apiString: "1.0536041812651029025")!,
            tokenPriceUsd: 1,
            tokensAvailable: tokensAvailable.flatMap {
                KaminoTokenAmount(decimalString: $0, decimals: descriptor.tokenDecimals)
            }
        )
    }

    func fetchPositions(owner: String) async throws -> [KaminoUserPositionResponse] {
        await Task.yield()
        if let positionsError { throw positionsError }
        return positions
    }

    func fetchVaultState(address: String) async throws -> KaminoVaultStateResponse { throw StubError.unavailable }
    func fetchVaultMetrics(address: String) async throws -> KaminoVaultMetricsResponse { throw StubError.unavailable }
    func fetchPnl(owner: String, vault: String) async throws -> KaminoPnlResponse { throw StubError.unavailable }
    func buildDepositTransaction(owner: String, vault: KaminoVaultDescriptor, amount: KaminoTokenAmount) async throws -> String {
        throw StubError.unavailable
    }
    func buildWithdrawTransaction(owner: String, vault: KaminoVaultDescriptor, shares: KaminoShareAmount) async throws -> String {
        throw StubError.unavailable
    }
}

/// Records what the form asks the pipeline for. The pipeline itself is covered by
/// `KaminoTransactionPreparerTests`; these tests are about the form's decisions.
private final class SpyWithdrawPreparer: KaminoWithdrawPreparing, @unchecked Sendable {

    struct Request {
        let vault: KaminoVaultInfo
        let owner: String
        let request: KaminoWithdrawRequest
        let unitPrice: UInt64
    }

    private let lock = NSLock()
    private var _requests: [Request] = []

    var unitPrice = KaminoTransactionFixtures.unitPriceMicroLamports
    var error: Error?
    /// Overrides what preparation returns, so a test can assert that exactly
    /// these bytes — and no re-derivation of them — reach the payload.
    var prepared: KaminoPreparedTransaction?
    /// Fires while the preparation is suspended, so a test can perturb the form
    /// exactly where a real keystroke would land.
    var onPrepare: (() -> Void)?

    var requests: [Request] { lock.withLock { _requests } }

    func resolveUnitPrice() async -> UInt64 {
        await Task.yield()
        return unitPrice
    }

    func prepareWithdraw(
        vault: KaminoVaultInfo,
        owner: String,
        request: KaminoWithdrawRequest,
        unitPrice: UInt64
    ) async throws -> KaminoPreparedTransaction {
        await Task.yield()
        lock.withLock {
            _requests.append(Request(vault: vault, owner: owner, request: request, unitPrice: unitPrice))
        }
        onPrepare?()
        await Task.yield()
        if let error { throw error }
        if let prepared { return prepared }
        return KaminoPreparedTransaction(
            base64: KaminoTransactionFixtures.usdcWithdraw.injected,
            priorityFee: KaminoPriorityFee(
                limit: KaminoComputeBudget.withdrawUnitLimit,
                price: unitPrice
            ),
            unitsConsumed: 283_786,
            payerLamportsAfter: nil,
            recentBlockhash: "6VjnGjZWnCyLtCd5FZTLpqm9GNjnzDrGGjyEfKNXfPKa"
        )
    }
}

// swiftlint:enable async_without_await unused_parameter
