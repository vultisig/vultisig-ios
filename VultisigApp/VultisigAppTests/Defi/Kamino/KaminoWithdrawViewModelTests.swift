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

    // MARK: - The farm-staked refusal

    /// The state every real position in these vaults is in. Nothing is built,
    /// nothing is requested, and the reason is a named, user-visible one.
    func testAFarmStakedPositionRefusesAndBuildsNothing() async {
        addUsdcCoin()
        service.positions = [Self.position(staked: "5.5", unstaked: "0", total: "5.5")]
        let viewModel = makeViewModel()

        await viewModel.onLoad()

        XCTAssertEqual(viewModel.eligibility, .farmStaked(KaminoShareAmount(baseUnits: BigInt(5_500_000), decimals: 6)))
        XCTAssertEqual(viewModel.unavailableReason, .farmStakedNotSupported)
        XCTAssertEqual(viewModel.availableAmount, .zero)

        viewModel.amountField.value = "1"
        let withdraw = await viewModel.makeWithdraw()

        XCTAssertNil(withdraw)
        XCTAssertTrue(preparer.requests.isEmpty)
        XCTAssertEqual(viewModel.error as? KaminoWithdrawError, .farmStakedNotSupported)
    }

    /// A partly staked position is refused whole rather than withdrawing the
    /// unstaked remainder, which would silently take out less than was asked for.
    func testAPartlyStakedPositionAlsoRefuses() async {
        addUsdcCoin()
        service.positions = [Self.position(staked: "1", unstaked: "4.5", total: "5.5")]
        let viewModel = makeViewModel()

        await viewModel.onLoad()

        XCTAssertEqual(viewModel.unavailableReason, .farmStakedNotSupported)
        XCTAssertEqual(viewModel.availableAmount, .zero)
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

        XCTAssertNotNil(viewModel.error)
        viewModel.amountField.value = "1"
        let withdraw = await viewModel.makeWithdraw()
        XCTAssertNil(withdraw)
        XCTAssertTrue(preparer.requests.isEmpty)
    }

    // MARK: - The maximum

    /// The form's ceiling is the asset value of the withdrawable shares, at the
    /// vault's own rate.
    func testTheMaximumIsTheAssetValueOfTheHeldShares() async {
        addUsdcCoin()
        service.positions = [Self.unstakedPosition]
        let viewModel = makeViewModel()

        await viewModel.onLoad()

        XCTAssertEqual(viewModel.eligibility, .withdrawable(KaminoShareAmount(baseUnits: BigInt(5_500_000), decimals: 6)))
        XCTAssertEqual(viewModel.availableAmount, Decimal(string: "5.794822"))
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
        viewModel.amountField.value = "5.794822"
        let made = await viewModel.makeWithdraw()
        let withdraw = try XCTUnwrap(made)

        XCTAssertEqual(withdraw.shares.baseUnits, BigInt(5_500_000))
        XCTAssertEqual(preparer.requests.first?.shares.baseUnits, BigInt(5_500_000))
        XCTAssertEqual(withdraw.payload.kaminoPayload?.amountBaseUnits, "5500000")
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
            Task { @MainActor in viewModel?.amountField.value = "5.794822" }
        }

        let made = await viewModel.makeWithdraw()
        let withdraw = try XCTUnwrap(made)

        XCTAssertEqual(withdraw.shares.baseUnits, BigInt(949_123))
        XCTAssertEqual(preparer.requests.first?.shares.baseUnits, BigInt(949_123))
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
        viewModel.amountField.value = "5.794822"

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
        let shares: KaminoShareAmount
        let unitPrice: UInt64
    }

    private let lock = NSLock()
    private var _requests: [Request] = []

    var unitPrice = KaminoTransactionFixtures.unitPriceMicroLamports
    var error: Error?
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
        shares: KaminoShareAmount,
        unitPrice: UInt64
    ) async throws -> KaminoPreparedTransaction {
        await Task.yield()
        lock.withLock {
            _requests.append(Request(vault: vault, owner: owner, shares: shares, unitPrice: unitPrice))
        }
        onPrepare?()
        await Task.yield()
        if let error { throw error }
        return KaminoPreparedTransaction(
            base64: KaminoTransactionFixtures.usdcWithdraw.injected,
            priorityFee: KaminoPriorityFee(
                limit: KaminoComputeBudget.withdrawUnitLimit,
                price: unitPrice
            ),
            unitsConsumed: 174_566,
            payerLamportsAfter: nil,
            recentBlockhash: "6VjnGjZWnCyLtCd5FZTLpqm9GNjnzDrGGjyEfKNXfPKa"
        )
    }
}

// swiftlint:enable async_without_await unused_parameter
