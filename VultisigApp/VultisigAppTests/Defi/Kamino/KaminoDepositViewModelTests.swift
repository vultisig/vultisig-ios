//
//  KaminoDepositViewModelTests.swift
//  VultisigAppTests
//
//  The deposit form's job is to decide whether a request may be made at all, and
//  in what unit. Two of its rules are load-bearing:
//
//  - The minimum comes from the vault's own state, and the API does not enforce
//    it: a below-minimum deposit returns 200 and fails on chain, after the
//    keysign ceremony has been spent. So this gate is the only gate.
//  - The SOL vault's maximum is net of a measured reserve, because the deposit
//    transaction spends SOL beyond the amount.
//

import BigInt
@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class KaminoDepositViewModelTests: XCTestCase {

    private var storeToken: TestContextToken!
    private var vault: Vault!
    private var service: StubDepositService!
    private var preparer: SpyPreparer!
    private var balanceService: CountingBalanceService!

    private let owner = KaminoTransactionFixtures.usdcDeposit.feePayer

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
        service = StubDepositService()
        preparer = SpyPreparer()
        balanceService = CountingBalanceService()
    }

    override func tearDown() async throws {
        balanceService = nil
        preparer = nil
        service = nil
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - The minimum gate

    func testTheMinimumComesFromTheVaultState() async {
        addUsdcCoin(balance: "50000000")
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)

        await viewModel.onLoad()

        XCTAssertEqual(viewModel.minimumDeposit, Decimal(string: "0.1"))
        XCTAssertTrue(viewModel.minimumDepositText.contains("0.1"))
    }

    /// A below-minimum amount fails validation, so the field shows the vault's
    /// own minimum. Asserted through the validator the form installs rather than
    /// through a published flag, because that is what actually gates it.
    ///
    /// The button stays TAPPABLE — `FormScreen` cannot disable Continue on
    /// validity without removing the tap that reveals field errors — so the
    /// build path re-enforces the same bound; see
    /// `testABelowMinimumAmountIsRefusedBeforeAnyNetworkCall`.
    func testABelowMinimumAmountFailsValidation() async throws {
        addUsdcCoin(balance: "50000000")
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)
        await viewModel.onLoad()

        viewModel.amountField.value = "0.05"
        XCTAssertThrowsError(try viewModel.amountField.validateErrors())

        viewModel.amountField.value = "0.1"
        XCTAssertNoThrow(try viewModel.amountField.validateErrors())
    }

    /// Without the vault's own minimum there is no gate at all, so a failed
    /// hydration must leave the form unable to build rather than unbounded.
    func testAFailedHydrationLeavesTheFormUnableToBuild() async {
        addUsdcCoin(balance: "50000000")
        service.infoError = StubDepositService.StubError.unavailable
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)

        await viewModel.onLoad()

        XCTAssertNil(viewModel.minimumDeposit)
        XCTAssertNotNil(viewModel.error)
        viewModel.amountField.value = "100"
        let deposit = await viewModel.makeDeposit()
        XCTAssertNil(deposit)
    }

    // MARK: - Available amount

    /// A token deposit spends only the token, so nothing is held back.
    func testATokenVaultOffersTheWholeTokenBalance() async {
        addUsdcCoin(balance: "50000000")
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)

        await viewModel.onLoad()

        XCTAssertEqual(viewModel.availableAmount, Decimal(string: "50"))
        XCTAssertTrue(preparer.maxRequests.isEmpty)
    }

    /// The wrapped-SOL form never reads the coin's stored balance — its ceiling
    /// comes from the reserve probe, and the amount field renders
    /// `availableAmount` — so refreshing it would be two proxy round trips for a
    /// number nothing on the screen shows. On the slowest path the feature has,
    /// each one is another chance to draw the proxy's ~60 s stall.
    func testTheWrappedSolFormDoesNotRefreshABalanceItNeverReads() async {
        addSolCoin(balance: "3000000000")
        preparer.maxLamports = BigInt(2_490_000_000)
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.allezSOL)

        await viewModel.onLoad()

        XCTAssertTrue(balanceService.refreshedTickers.isEmpty)
        XCTAssertEqual(viewModel.availableAmount, Decimal(string: "2.49"))
    }

    /// A token vault's ceiling IS `coin.rawBalance`, so that one still waits for
    /// the refresh. Dropping it there would offer a maximum out of a stale
    /// balance.
    func testATokenVaultStillRefreshesTheBalanceItsCeilingComesFrom() async {
        addUsdcCoin(balance: "50000000")
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)

        await viewModel.onLoad()

        XCTAssertEqual(balanceService.refreshedTickers, ["USDC"])
    }

    /// The SOL vault's maximum is the measured one, not the balance. The wallet
    /// here holds 3 SOL and the reserve measurement says 2.49 is depositable.
    func testTheSolVaultOffersTheMeasuredMaximumRatherThanTheBalance() async {
        addSolCoin(balance: "3000000000")
        preparer.maxLamports = BigInt(2_490_000_000)
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.allezSOL)

        await viewModel.onLoad()

        XCTAssertEqual(viewModel.availableAmount, Decimal(string: "2.49"))
        XCTAssertLessThan(viewModel.availableAmount, Decimal(string: "3") ?? 0)
        XCTAssertEqual(preparer.maxRequests.count, 1)
        // Probed at the vault's own minimum: the smallest deposit that is
        // guaranteed to be a valid request.
        XCTAssertEqual(preparer.maxRequests.first?.probe.baseUnits, BigInt(10_000_000))
    }

    /// A reserve that could not be measured must not fall back to the raw
    /// balance — that maximum would build a transaction that cannot pay for
    /// itself, and the user would spend a ceremony to learn it.
    func testAnUnmeasurableReserveLeavesNothingAvailable() async {
        addSolCoin(balance: "3000000000")
        preparer.maxError = KaminoPreparationError.payerBalanceUnavailable
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.allezSOL)

        await viewModel.onLoad()

        XCTAssertEqual(viewModel.availableAmount, .zero)
        XCTAssertNotNil(viewModel.error)
    }

    /// Both the probe and the real deposit are priced at the same compute-unit
    /// price. Re-sampling between them would size the reserve against a fee the
    /// transaction does not pay.
    func testTheProbeAndTheDepositSharePriorityPricing() async {
        addSolCoin(balance: "3000000000")
        preparer.unitPrice = 55_000
        preparer.maxLamports = BigInt(2_490_000_000)
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.allezSOL)
        await viewModel.onLoad()

        viewModel.amountField.value = "1"
        _ = await viewModel.makeDeposit()

        XCTAssertEqual(preparer.maxRequests.first?.unitPrice, 55_000)
        XCTAssertEqual(preparer.depositRequests.first?.unitPrice, 55_000)
    }

    // MARK: - Amount unit

    /// Deposits are denominated in the underlying asset, and the SOL vault's
    /// token scale is 9 while its share scale is 6. Reading the entered amount at
    /// the wrong scale would mis-size the transfer by a factor of a thousand.
    func testTheEnteredAmountIsReadAtTheTokenScale() async {
        addSolCoin(balance: "3000000000")
        preparer.maxLamports = BigInt(2_490_000_000)
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.allezSOL)
        await viewModel.onLoad()

        viewModel.amountField.value = "1.5"

        XCTAssertEqual(viewModel.enteredAmount()?.baseUnits, BigInt(1_500_000_000))
        XCTAssertEqual(viewModel.enteredAmount()?.decimals, 9)
    }

    /// The verify screen must show the amount that is inside the bytes, not the
    /// characters the user typed. The two diverge whenever the input carries more
    /// precision than the mint has — or a separator the parser read differently
    /// from how it looks.
    func testTheVerifySummaryShowsTheParsedAmountNotTheTypedText() async throws {
        addUsdcCoin(balance: "50000000")
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)
        await viewModel.onLoad()
        viewModel.amountField.value = "10.1234567"

        let made = await viewModel.makeDeposit()
        let deposit = try XCTUnwrap(made)

        XCTAssertEqual(deposit.transaction.amount, "10.123456")
        XCTAssertEqual(deposit.payload.toAmount, BigInt(10_123_456))
    }

    /// And it must survive the round trip. Everything downstream reads
    /// `SendTransaction.amount` back through `parseInput`, so a canonical string
    /// that the device's own locale cannot read is worse than the typed text — a
    /// POSIX `10.123456` on a comma-locale device reads as ten million.
    func testTheDisplayedAmountReadsBackAsTheAmountThatWillBeSigned() async throws {
        addUsdcCoin(balance: "50000000")
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)
        await viewModel.onLoad()
        viewModel.amountField.value = "10.1234567"

        let made = await viewModel.makeDeposit()
        let deposit = try XCTUnwrap(made)
        let signed = try XCTUnwrap(viewModel.enteredAmount())

        XCTAssertEqual(deposit.transaction.amountDecimal, signed.decimalValue)
    }

    /// The summary and the payload are built from ONE reading of the amount.
    /// Preparing takes several network round trips and the field stays editable
    /// throughout, so a summary re-read afterwards could approve a different
    /// deposit from the one inside the bytes.
    func testAnEditDuringPreparationCannotSplitTheSummaryFromThePayload() async throws {
        addUsdcCoin(balance: "50000000")
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)
        await viewModel.onLoad()
        viewModel.amountField.value = "10"

        // Lands while `prepareDeposit` is suspended, which is exactly when a
        // keyboard edit would.
        preparer.onPrepare = { [weak viewModel] in
            Task { @MainActor in viewModel?.amountField.value = "40" }
        }

        let made = await viewModel.makeDeposit()
        let deposit = try XCTUnwrap(made)

        XCTAssertEqual(deposit.payload.toAmount, BigInt(10_000_000))
        XCTAssertEqual(deposit.transaction.amount, "10")
        XCTAssertEqual(preparer.depositRequests.first?.amount.baseUnits, BigInt(10_000_000))
    }

    // MARK: - Bounds the build path re-enforces

    /// `FormScreen` does not disable Continue on validation, so a below-minimum
    /// amount reaches `makeDeposit`. It must be refused HERE rather than sent:
    /// the API builds a below-minimum deposit happily and the chain rejects it
    /// afterwards, so without this the user spends several round trips to be
    /// told what the form already knew.
    func testABelowMinimumAmountIsRefusedBeforeAnyNetworkCall() async {
        addUsdcCoin(balance: "50000000")
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)
        await viewModel.onLoad()
        viewModel.amountField.value = "0.05"

        let deposit = await viewModel.makeDeposit()

        XCTAssertNil(deposit)
        XCTAssertTrue(preparer.depositRequests.isEmpty)
        XCTAssertEqual(
            viewModel.error as? KaminoDepositError,
            .belowMinimum(minimum: "0.1", ticker: "USDC")
        )
    }

    /// And the same for an amount above what is available. The ceiling is
    /// compared in base units against the measured maximum, not against the
    /// `Decimal` the form renders — on the SOL vault that maximum is exact to
    /// the lamport and rendering it rounds.
    func testAnAmountAboveTheMeasuredMaximumIsRefusedBeforeAnyNetworkCall() async {
        addSolCoin(balance: "3000000000")
        preparer.maxLamports = BigInt(2_490_000_001)
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.allezSOL)
        await viewModel.onLoad()

        XCTAssertEqual(viewModel.availableBaseUnits, BigInt(2_490_000_001))

        viewModel.amountField.value = "2.490000002"
        let deposit = await viewModel.makeDeposit()

        XCTAssertNil(deposit)
        XCTAssertTrue(preparer.depositRequests.isEmpty)

        // Exactly the maximum still builds — the refusal is above it, not at it.
        viewModel.amountField.value = "2.490000001"
        let atMaximum = await viewModel.makeDeposit()
        XCTAssertNotNil(atMaximum)
    }

    /// Continue is hard-disabled only for the states no amount reaches: no
    /// wallet coin, an unhydrated vault, or nothing available to spend. A
    /// below-minimum amount is NOT one of them — the user can fix it, and
    /// disabling the button would take away the tap that shows them why.
    func testContinueIsDisabledOnlyWhenNoAmountCouldWork() async {
        let missingCoin = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)
        await missingCoin.onLoad()
        XCTAssertTrue(missingCoin.isDepositUnavailable)

        addUsdcCoin(balance: "50000000")
        let usable = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)
        await usable.onLoad()
        XCTAssertFalse(usable.isDepositUnavailable)

        usable.amountField.value = "0.05"
        XCTAssertFalse(usable.isDepositUnavailable)
    }

    // MARK: - Payload

    /// What the verify screen ends up signing: the prepared bytes, verbatim,
    /// carried as `signSolana` — plus the marker that lets the pre-keysign
    /// refresh splice a live blockhash into them.
    func testThePayloadCarriesThePreparedBytesAndTheKaminoMarker() async throws {
        addUsdcCoin(balance: "50000000")
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)
        await viewModel.onLoad()
        viewModel.amountField.value = "10"

        let built = await viewModel.makeDeposit()
        let payload = try XCTUnwrap(built).payload

        XCTAssertEqual(
            payload.signSolana?.rawTransactions,
            [KaminoTransactionFixtures.usdcDeposit.injected]
        )
        XCTAssertEqual(payload.kaminoPayload?.vaultAddress, KaminoVaultRegistry.steakhouseUSDC.address)
        XCTAssertEqual(payload.kaminoPayload?.operation, .deposit)
        XCTAssertEqual(payload.kaminoPayload?.amountBaseUnits, "10000000")
        XCTAssertEqual(payload.toAddress, KaminoVaultRegistry.steakhouseUSDC.address)
        XCTAssertEqual(payload.toAmount, BigInt(10_000_000))
        XCTAssertEqual(payload.coin.chain, .solana)
    }

    /// The compute budget the app injected travels on the payload, so the fee the
    /// verify screen shows is the fee inside the bytes.
    func testThePayloadReportsTheInjectedComputeBudget() async throws {
        addUsdcCoin(balance: "50000000")
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)
        await viewModel.onLoad()
        viewModel.amountField.value = "10"

        let built = await viewModel.makeDeposit()
        let payload = try XCTUnwrap(built).payload

        guard case .Solana(_, let priorityFee, let priorityLimit, _, _, _) = payload.chainSpecific else {
            return XCTFail("expected Solana chain specific")
        }
        XCTAssertEqual(priorityFee, BigInt(KaminoTransactionFixtures.unitPriceMicroLamports))
        XCTAssertEqual(priorityLimit, BigInt(KaminoComputeBudget.tokenDepositUnitLimit))
    }

    /// The vault the user is depositing into is what the request names — not a
    /// ticker match, and not the other USDC vault.
    func testTheRequestNamesTheSelectedVault() async throws {
        addUsdcCoin(balance: "50000000")
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.rwaUSDC)
        await viewModel.onLoad()
        viewModel.amountField.value = "10"

        _ = await viewModel.makeDeposit()

        XCTAssertEqual(preparer.depositRequests.first?.vault.descriptor, KaminoVaultRegistry.rwaUSDC)
        XCTAssertEqual(preparer.depositRequests.first?.owner, owner)
    }

    /// A vault whose asset the wallet does not hold cannot be deposited into, and
    /// the form says so rather than building a request against a zero balance.
    func testAMissingDepositCoinIsSurfacedAndBlocksTheBuild() async {
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)

        await viewModel.onLoad()

        XCTAssertTrue(viewModel.isMissingDepositCoin)
        XCTAssertEqual(viewModel.availableAmount, .zero)
        viewModel.amountField.value = "10"
        let deposit = await viewModel.makeDeposit()
        XCTAssertNil(deposit)
        XCTAssertTrue(preparer.depositRequests.isEmpty)
    }

    /// The wrapped-SOL vault's underlying mint is wSOL, which the wallet never
    /// holds as a coin — the transaction wraps native SOL itself. Resolving it to
    /// anything but the native coin would leave the SOL vault permanently
    /// undepositable.
    func testTheWrappedSolVaultSpendsTheNativeCoin() async {
        addSolCoin(balance: "3000000000")
        preparer.maxLamports = BigInt(2_490_000_000)
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.allezSOL)

        await viewModel.onLoad()

        XCTAssertFalse(viewModel.isMissingDepositCoin)
        XCTAssertEqual(viewModel.depositCoin?.ticker, "SOL")
        XCTAssertTrue(viewModel.showsWrappedSolNotice)
    }

    /// A failed preparation is a refusal, not a payload. The user is told and
    /// nothing is signed.
    func testAPreparationFailureYieldsNoPayload() async {
        addUsdcCoin(balance: "50000000")
        preparer.depositError = KaminoPreparationError.simulationFailed(
            stage: .budgeted,
            reason: "ProgramFailedToComplete"
        )
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)
        await viewModel.onLoad()
        viewModel.amountField.value = "10"

        let deposit = await viewModel.makeDeposit()

        XCTAssertNil(deposit)
        XCTAssertNotNil(viewModel.error)
    }

    // MARK: - The bytes that get signed

    /// ⚠️ **The property the whole flow rests on: the payload carries the
    /// preparer's bytes verbatim.**
    ///
    /// Everything upstream — the pinned registry, six layers of validation, two
    /// simulations — describes one specific byte string. A form that handed the
    /// factory anything else, or re-derived a transaction from `coin` and
    /// `amount` the way the general Solana path does, would leave all of that
    /// checking a transaction nobody signs.
    ///
    /// Nothing else in the suite crosses this hop: the preparer tests stop at
    /// the preparer, and the blockhash-refresh tests start from a fixture.
    ///
    /// The sentinel bytes are a DIFFERENT vault's vector, so a re-derivation
    /// that happened to produce a plausible USDC deposit fails here instead of
    /// matching by coincidence.
    func testTheDepositPayloadCarriesThePreparedBytesVerbatim() async throws {
        addUsdcCoin(balance: "10000000")
        let viewModel = makeViewModel(descriptor: KaminoVaultRegistry.steakhouseUSDC)
        await viewModel.onLoad()

        let sentinel = KaminoPreparedTransaction(
            base64: KaminoTransactionFixtures.solDeposit.injected,
            priorityFee: KaminoPriorityFee(limit: 333_333, price: 44_444),
            unitsConsumed: 1,
            payerLamportsAfter: nil,
            recentBlockhash: "6VjnGjZWnCyLtCd5FZTLpqm9GNjnzDrGGjyEfKNXfPKa"
        )
        preparer.prepared = sentinel

        viewModel.amountField.value = "1"
        let made = await viewModel.makeDeposit()
        let handoff = try XCTUnwrap(made)

        guard case .signSolana(let solana)? = handoff.payload.signData else {
            return XCTFail("a Kamino deposit must sign raw Solana bytes, not a rebuilt transfer")
        }
        XCTAssertEqual(solana.rawTransactions, [sentinel.base64])

        // The fee row and the verify screen read these, so they have to describe
        // the transaction in `signData` rather than a second one.
        guard case .Solana(let blockhash, let price, let limit, _, _, _) = handoff.payload.chainSpecific else {
            return XCTFail("expected Solana chain-specific data")
        }
        XCTAssertEqual(blockhash, sentinel.recentBlockhash)
        XCTAssertEqual(price, BigInt(sentinel.priorityFee.price))
        XCTAssertEqual(limit, BigInt(sentinel.priorityFee.limit))

        // And the marker, which is what the initiating device's verify screen
        // cross-checks the decoded bytes against.
        let marker = try XCTUnwrap(handoff.payload.kaminoPayload)
        XCTAssertEqual(marker.vaultAddress, KaminoVaultRegistry.steakhouseUSDC.address)
        XCTAssertEqual(marker.operation, .deposit)
        XCTAssertEqual(marker.amountBaseUnits, "1000000")
        XCTAssertEqual(marker.amountDecimals, 6)
        XCTAssertEqual(handoff.payload.toAddress, KaminoVaultRegistry.steakhouseUSDC.address)
    }

    // MARK: - Helpers

    private func makeViewModel(descriptor: KaminoVaultDescriptor) -> KaminoDepositViewModel {
        KaminoDepositViewModel(
            vault: vault,
            descriptor: descriptor,
            service: service,
            preparer: preparer,
            balanceService: balanceService
        )
    }

    private func addUsdcCoin(balance: String) {
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
        coin.rawBalance = balance
        vault.coins.append(coin)
    }

    private func addSolCoin(balance: String) {
        let asset = CoinMeta(
            chain: .solana,
            ticker: "SOL",
            logo: "solana",
            decimals: 9,
            priceProviderId: "solana",
            contractAddress: "",
            isNativeToken: true
        )
        let coin = Coin(asset: asset, address: owner, hexPublicKey: "pub")
        coin.rawBalance = balance
        vault.coins.append(coin)
    }
}

// MARK: - Test doubles

// Protocol conformances keep their declared signatures, so unused parameters and
// `async` without `await` are unavoidable here.
// swiftlint:disable async_without_await unused_parameter

/// Records which coins were refreshed. The count is the assertion: a refresh is
/// two proxy round trips, and the wrapped-SOL form reads none of what they
/// produce.
private final class CountingBalanceService: BalanceServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _refreshed: [String] = []

    var refreshedTickers: [String] { lock.withLock { _refreshed } }

    func updateBalance(for coin: Coin) async {
        await Task.yield()
        let ticker = coin.ticker
        lock.withLock { _refreshed.append(ticker) }
    }

    func refreshSpendableBalanceOrThrow(for coin: Coin) async throws {
        await updateBalance(for: coin)
    }
}

private final class StubDepositService: KaminoServiceProtocol, @unchecked Sendable {
    enum StubError: Error { case unavailable }

    private let lock = NSLock()
    private var _infoError: Error?

    var infoError: Error? {
        get { lock.withLock { _infoError } }
        set { lock.withLock { _infoError = newValue } }
    }

    func fetchVaultInfo(descriptor: KaminoVaultDescriptor) async throws -> KaminoVaultInfo {
        await Task.yield()
        if let infoError { throw infoError }
        return KaminoDepositFixtures.info(for: descriptor)
    }

    func fetchVaultState(address: String) async throws -> KaminoVaultStateResponse { throw StubError.unavailable }
    func fetchVaultMetrics(address: String) async throws -> KaminoVaultMetricsResponse { throw StubError.unavailable }
    func fetchPositions(owner: String) async throws -> [KaminoUserPositionResponse] { throw StubError.unavailable }
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
private final class SpyPreparer: KaminoDepositPreparing, @unchecked Sendable {

    struct DepositRequest {
        let vault: KaminoVaultInfo
        let owner: String
        let amount: KaminoTokenAmount
        let unitPrice: UInt64
    }

    struct MaxRequest {
        let vault: KaminoVaultInfo
        let owner: String
        let probe: KaminoTokenAmount
        let unitPrice: UInt64
    }

    private let lock = NSLock()
    private var _depositRequests: [DepositRequest] = []
    private var _maxRequests: [MaxRequest] = []

    var unitPrice = KaminoTransactionFixtures.unitPriceMicroLamports
    var maxLamports = BigInt(0)
    var maxError: Error?
    var depositError: Error?
    /// Overrides what preparation returns, so a test can assert that exactly
    /// these bytes — and no re-derivation of them — reach the payload.
    var prepared: KaminoPreparedTransaction?
    /// Fires while the preparation is suspended, so a test can perturb the form
    /// exactly where a real keystroke would land.
    var onPrepare: (() -> Void)?

    var depositRequests: [DepositRequest] { lock.withLock { _depositRequests } }
    var maxRequests: [MaxRequest] { lock.withLock { _maxRequests } }

    func resolveUnitPrice() async -> UInt64 {
        await Task.yield()
        return unitPrice
    }

    func prepareDeposit(
        vault: KaminoVaultInfo,
        owner: String,
        amount: KaminoTokenAmount,
        unitPrice: UInt64
    ) async throws -> KaminoPreparedTransaction {
        await Task.yield()
        lock.withLock {
            _depositRequests.append(
                DepositRequest(vault: vault, owner: owner, amount: amount, unitPrice: unitPrice)
            )
        }
        onPrepare?()
        await Task.yield()
        if let depositError { throw depositError }
        if let prepared { return prepared }
        return KaminoPreparedTransaction(
            base64: KaminoTransactionFixtures.usdcDeposit.injected,
            priorityFee: KaminoPriorityFee(
                limit: KaminoComputeBudget.depositUnitLimit(for: vault),
                price: unitPrice
            ),
            unitsConsumed: 252_146,
            payerLamportsAfter: nil,
            recentBlockhash: "6VjnGjZWnCyLtCd5FZTLpqm9GNjnzDrGGjyEfKNXfPKa"
        )
    }

    func maxNativeDepositLamports(
        vault: KaminoVaultInfo,
        owner: String,
        probe: KaminoTokenAmount,
        unitPrice: UInt64
    ) async throws -> BigInt {
        await Task.yield()
        lock.withLock {
            _maxRequests.append(MaxRequest(vault: vault, owner: owner, probe: probe, unitPrice: unitPrice))
        }
        if let maxError { throw maxError }
        return maxLamports
    }
}

private enum KaminoDepositFixtures {

    static func info(for descriptor: KaminoVaultDescriptor) -> KaminoVaultInfo {
        KaminoVaultInfo(
            descriptor: descriptor,
            name: descriptor.fallbackName,
            minDeposit: minDeposit(for: descriptor),
            minWithdraw: KaminoShareAmount(baseUnits: BigInt(1_000), decimals: descriptor.sharesDecimals),
            lookupTable: KaminoTransactionFixtures.usdcDeposit.lookupTable,
            apy30d: 0,
            // swiftlint:disable:next force_unwrapping
            tokensPerShare: KaminoRate(apiString: "1.0536041812651029025")!,
            tokenPriceUsd: 1
        )
    }

    /// The live minimums, captured 2026-08-04: 0.1 USDC and 0.01 SOL.
    private static func minDeposit(for descriptor: KaminoVaultDescriptor) -> KaminoTokenAmount {
        descriptor.tokenMint == KaminoVaultRegistry.wrappedSolMint
            ? KaminoTokenAmount(baseUnits: BigInt(10_000_000), decimals: 9)
            : KaminoTokenAmount(baseUnits: BigInt(100_000), decimals: 6)
    }
}

// swiftlint:enable async_without_await unused_parameter
