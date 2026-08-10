//
//  KaminoEarnViewModelTests.swift
//  VultisigAppTests
//
//  The Earn segment's read model is shares × `tokensPerShare`, and the
//  load-bearing assertion here is `testSharesAreValuedThroughTokensPerShare…`:
//  the metrics payload also carries `sharePrice`, which is USD-denominated and
//  agrees with the token rate only on a dollar vault. On the SOL vault the two
//  differ by the price of SOL — ~74× — so picking the wrong one overstates the
//  position enormously while still rendering a plausible number.
//

@testable import VultisigApp
import BigInt
import SwiftData
import XCTest

@MainActor
final class KaminoEarnViewModelTests: XCTestCase {
    private var storeToken: TestContextToken!
    private var vault: Vault!
    private var service: FakeKaminoService!
    private var priceService: FakeCryptoPriceService!
    private let storage = KaminoPositionStorageService()

    private let steakhouse = KaminoVaultRegistry.steakhouseUSDC
    private let allez = KaminoVaultRegistry.allezSOL
    private let owner = "CXFmQi2eM4Jzt9HZwm9A5JAzGvNpKwRuxo52ua3Jyceh"

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
        service = FakeKaminoService()
        priceService = FakeCryptoPriceService()
        service.infos = [
            steakhouse.address: KaminoFixtures.steakhouseInfo,
            allez.address: KaminoFixtures.allezInfo
        ]
    }

    override func tearDown() async throws {
        priceService = nil
        service = nil
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    private func makeViewModel() -> KaminoEarnViewModel {
        KaminoEarnViewModel(vault: vault, service: service, storage: storage, priceService: priceService)
    }

    /// A second vault distinct in EVERY unique attribute. `TestStore.makeVault`
    /// varies only `pubKeyECDSA`, so two of its vaults share `pubKeyEdDSA` — and
    /// SwiftData upserts on a unique-attribute collision.
    private func makeSecondVault() -> Vault {
        let vault = Vault(
            name: "Second Test Vault",
            signers: [],
            pubKeyECDSA: "second-pub-ecdsa",
            pubKeyEdDSA: "second-pub-eddsa",
            keyshares: [],
            localPartyID: "party-2",
            hexChainCode: "hex-2",
            resharePrefix: nil,
            libType: .DKLS
        )
        Storage.shared.insert(vault)
        return vault
    }

    // MARK: - Opt-in gate

    func testNoEnabledVaultsMeansNoRowsAndNoRequests() async {
        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.hasEnabledVaults)
        await viewModel.refresh(owner: owner)

        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertEqual(service.positionsCallCount, 0, "An opted-out user must pay no request.")
    }

    func testADisabledVaultIsNeverHydrated() async throws {
        try storage.setEnabled(true, descriptor: steakhouse, for: vault)
        try storage.setEnabled(false, descriptor: allez, for: vault)
        service.positions = [
            KaminoFixtures.position(vault: steakhouse.address, shares: "100"),
            KaminoFixtures.position(vault: allez.address, shares: "1000")
        ]
        let viewModel = makeViewModel()

        await viewModel.refresh(owner: owner)

        XCTAssertEqual(viewModel.rows.map(\.id), [steakhouse.address])
        XCTAssertEqual(service.hydratedVaults, [steakhouse.address])
    }

    // MARK: - Cache-first seed

    func testSeedsFromPersistedSnapshotBeforeAnyNetworkCall() throws {
        try storage.setEnabled(true, descriptor: allez, for: vault)
        try storage.upsert(
            snapshots: [
                KaminoPositionSnapshot(
                    vaultAddress: allez.address,
                    shares: KaminoShareAmount(baseUnits: 1_000_000_000, decimals: 6),
                    tokenAmount: KaminoTokenAmount(baseUnits: 1_074_929_915, decimals: 9),
                    apy30d: Decimal(string: "0.0669"),
                    pnlToken: Decimal(string: "0.5")
                )
            ],
            for: vault
        )

        // No awaiting: the persisted rows must be readable the instant the VM exists.
        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.hasEnabledVaults)
        XCTAssertEqual(viewModel.rows.count, 1)
        XCTAssertEqual(viewModel.rows.first?.tokenAmount, Decimal(string: "1.074929915"))
        XCTAssertEqual(viewModel.rows.first?.pnlToken, Decimal(string: "0.5"))
        XCTAssertEqual(service.positionsCallCount, 0)
    }

    // MARK: - Valuation

    func testSharesAreValuedThroughTokensPerShareNotSharePrice() async throws {
        try storage.setEnabled(true, descriptor: allez, for: vault)
        service.positions = [KaminoFixtures.position(vault: allez.address, shares: "1000")]
        let viewModel = makeViewModel()

        await viewModel.refresh(owner: owner)

        let row = try XCTUnwrap(viewModel.rows.first)
        // 1000 shares × 0.0010749299151180878396 tokens/share, truncated at the
        // vault's 9 token decimals.
        XCTAssertEqual(row.tokenAmount, Decimal(string: "1.074929915"))
        XCTAssertNotEqual(
            row.tokenAmount,
            Decimal(string: "79.437779653781828774"),
            "sharePrice is USD per share; using it here would inflate the position by the price of SOL."
        )
        XCTAssertEqual(row.apy30d, KaminoFixtures.allezInfo.apy30d)
        XCTAssertEqual(row.coin?.ticker, "SOL", "wSOL is a 1:1 escrow of SOL and is displayed and priced as SOL.")
    }

    func testTheTwoDecimalScalesAreNeverAssumedToMatch() async throws {
        try storage.setEnabled(true, descriptor: steakhouse, for: vault)
        service.positions = [KaminoFixtures.position(vault: steakhouse.address, shares: "1000")]
        let viewModel = makeViewModel()

        await viewModel.refresh(owner: owner)

        // The dollar vault: 6 token decimals and 6 share decimals, rate 1.0536…
        let row = try XCTUnwrap(viewModel.rows.first)
        XCTAssertEqual(row.tokenAmount, Decimal(string: "1053.604181"))
        XCTAssertEqual(row.coin?.ticker, "USDC")
    }

    // MARK: - Failure discipline

    func testFailedPositionsReadKeepsTheLastKnownRows() async throws {
        try storage.setEnabled(true, descriptor: allez, for: vault)
        try storage.upsert(
            snapshots: [
                KaminoPositionSnapshot(
                    vaultAddress: allez.address,
                    shares: KaminoShareAmount(baseUnits: 1_000_000_000, decimals: 6),
                    tokenAmount: KaminoTokenAmount(baseUnits: 1_074_929_915, decimals: 9),
                    apy30d: nil,
                    pnlToken: nil
                )
            ],
            for: vault
        )
        service.positionsError = FakeKaminoService.StubError.unreachable
        let viewModel = makeViewModel()

        await viewModel.refresh(owner: owner)

        XCTAssertEqual(
            viewModel.rows.first?.tokenAmount,
            Decimal(string: "1.074929915"),
            "An API outage must never make a real position look like it vanished."
        )
        XCTAssertNotNil(viewModel.error)
        XCTAssertEqual(service.hydratedVaults, [], "Nothing is hydrated once the position read has failed.")
    }

    func testFailedVaultHydrationKeepsThatRowsCachedValues() async throws {
        try storage.setEnabled(true, descriptor: steakhouse, for: vault)
        try storage.setEnabled(true, descriptor: allez, for: vault)
        try storage.upsert(
            snapshots: [
                KaminoPositionSnapshot(
                    vaultAddress: allez.address,
                    shares: KaminoShareAmount(baseUnits: 1_000_000_000, decimals: 6),
                    tokenAmount: KaminoTokenAmount(baseUnits: 1_074_929_915, decimals: 9),
                    apy30d: nil,
                    pnlToken: nil
                )
            ],
            for: vault
        )
        service.positions = [
            KaminoFixtures.position(vault: steakhouse.address, shares: "1000"),
            KaminoFixtures.position(vault: allez.address, shares: "2000")
        ]
        service.infoErrors = [allez.address: FakeKaminoService.StubError.unreachable]
        let viewModel = makeViewModel()

        await viewModel.refresh(owner: owner)

        XCTAssertEqual(viewModel.rows.count, 2)
        XCTAssertEqual(viewModel.rows.first(where: { $0.id == steakhouse.address })?.tokenAmount, Decimal(string: "1053.604181"))
        // Without `tokensPerShare` the shares cannot be valued at all, so the row
        // holds its cached figure rather than showing the doubled share balance
        // at a stale rate — or nothing.
        let stale = try XCTUnwrap(viewModel.rows.first(where: { $0.id == allez.address }))
        XCTAssertEqual(stale.tokenAmount, Decimal(string: "1.074929915"))
    }

    /// An absent vault means "holds nothing"; an unparseable share value means
    /// "could not read". Collapsing the second into a zero would erase a real
    /// deposit from the row AND from the persisted DeFi total.
    func testUnparseableSharesKeepTheCachedRowRatherThanZeroingIt() async throws {
        try storage.setEnabled(true, descriptor: steakhouse, for: vault)
        try storage.upsert(
            snapshots: [
                KaminoPositionSnapshot(
                    vaultAddress: steakhouse.address,
                    shares: KaminoShareAmount(baseUnits: 1_000_000, decimals: 6),
                    tokenAmount: KaminoTokenAmount(baseUnits: 1_053_604, decimals: 6),
                    apy30d: nil,
                    pnlToken: nil
                )
            ],
            for: vault
        )
        // A grouped decimal — exactly what the strict parser is there to refuse.
        service.positions = [KaminoFixtures.position(vault: steakhouse.address, shares: "1,000")]
        let viewModel = makeViewModel()

        await viewModel.refresh(owner: owner)

        XCTAssertEqual(viewModel.rows.first?.tokenAmount, Decimal(string: "1.053604"))
        XCTAssertEqual(
            storage.position(for: vault, vaultAddress: steakhouse.address)?.tokenAmountDecimal,
            Decimal(string: "1.053604"),
            "The cached snapshot must not be overwritten with a zero."
        )
    }

    func testAnEmptyPositionsResponseZeroesTheRowButKeepsItListed() async throws {
        try storage.setEnabled(true, descriptor: steakhouse, for: vault)
        try storage.upsert(
            snapshots: [
                KaminoPositionSnapshot(
                    vaultAddress: steakhouse.address,
                    shares: KaminoShareAmount(baseUnits: 1_000_000, decimals: 6),
                    tokenAmount: KaminoTokenAmount(baseUnits: 1_053_604, decimals: 6),
                    apy30d: nil,
                    pnlToken: nil
                )
            ],
            for: vault
        )
        service.positions = []
        let viewModel = makeViewModel()

        await viewModel.refresh(owner: owner)

        XCTAssertEqual(viewModel.rows.count, 1, "The user enabled the vault; it stays listed with a zero balance.")
        XCTAssertEqual(viewModel.rows.first?.tokenAmount, .zero)
    }

    // MARK: - Persistence

    func testRefreshPersistsEverySnapshotAndKeepsTheRowsDistinct() async throws {
        try storage.setEnabled(true, descriptor: steakhouse, for: vault)
        try storage.setEnabled(true, descriptor: allez, for: vault)
        service.positions = [
            KaminoFixtures.position(vault: steakhouse.address, shares: "1000"),
            KaminoFixtures.position(vault: allez.address, shares: "1000")
        ]
        service.pnl = [steakhouse.address: KaminoFixtures.pnl(token: "12.5")]
        let viewModel = makeViewModel()

        await viewModel.refresh(owner: owner)

        XCTAssertEqual(vault.kaminoPositions.count, 2, "Two vaults must persist as two rows, not collapse onto one id.")
        let persistedSteakhouse = try XCTUnwrap(storage.position(for: vault, vaultAddress: steakhouse.address))
        let persistedAllez = try XCTUnwrap(storage.position(for: vault, vaultAddress: allez.address))
        XCTAssertEqual(persistedSteakhouse.tokenAmountDecimal, Decimal(string: "1053.604181"))
        XCTAssertEqual(persistedSteakhouse.pnlToken, Decimal(string: "12.5"))
        XCTAssertEqual(persistedAllez.tokenAmountDecimal, Decimal(string: "1.074929915"))
        XCTAssertEqual(persistedAllez.shares?.baseUnits, BigInt(1_000_000_000))
        XCTAssertTrue(persistedSteakhouse.isEnabled)
        XCTAssertTrue(persistedAllez.isEnabled)
    }

    // MARK: - Rates

    /// Fiat is read from `RateProvider`'s cache, which is populated from the
    /// vault's own coins. A user whose USDC sits inside the Earn vault and
    /// nowhere in their wallet would otherwise see a real deposit — and its
    /// share of the DeFi total — priced at zero.
    func testRefreshLoadsTheRateForEveryUnderlyingToken() async throws {
        try storage.setEnabled(true, descriptor: steakhouse, for: vault)
        try storage.setEnabled(true, descriptor: KaminoVaultRegistry.rwaUSDC, for: vault)
        try storage.setEnabled(true, descriptor: allez, for: vault)
        service.infos[KaminoVaultRegistry.rwaUSDC.address] = KaminoFixtures.steakhouseInfo
        let viewModel = makeViewModel()

        await viewModel.refresh(owner: owner)

        XCTAssertEqual(
            Set(priceService.requested.map(\.ticker)),
            ["USDC", "SOL"]
        )
        XCTAssertEqual(
            priceService.requested.count,
            2,
            "Both dollar vaults share one underlying token — it must be priced once."
        )
    }

    func testAFailedRateFetchStillPublishesThePosition() async throws {
        try storage.setEnabled(true, descriptor: allez, for: vault)
        priceService.error = FakeKaminoService.StubError.unreachable
        service.positions = [KaminoFixtures.position(vault: allez.address, shares: "1000")]
        let viewModel = makeViewModel()

        await viewModel.refresh(owner: owner)

        XCTAssertEqual(viewModel.rows.first?.tokenAmount, Decimal(string: "1.074929915"))
    }

    // MARK: - Vault switching

    /// The screen's `StateObject` outlives a vault switch, so a VM still bound
    /// to the previous vault would write the new vault's on-chain position into
    /// the old vault's rows.
    func testSwitchingVaultRebindsTheRowsAndThePersistenceTarget() async throws {
        try storage.setEnabled(true, descriptor: steakhouse, for: vault)
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.rows.count, 1)

        let other = makeSecondVault()
        viewModel.update(vault: other)
        XCTAssertTrue(viewModel.rows.isEmpty, "The new vault has enabled nothing.")

        try storage.setEnabled(true, descriptor: allez, for: other)
        viewModel.seedFromPersistedSnapshot()
        service.positions = [KaminoFixtures.position(vault: allez.address, shares: "1000")]
        await viewModel.refresh(owner: owner)

        XCTAssertEqual(
            storage.position(for: other, vaultAddress: allez.address)?.tokenAmountDecimal,
            Decimal(string: "1.074929915")
        )
        XCTAssertEqual(
            storage.position(for: vault, vaultAddress: steakhouse.address)?.tokenAmountDecimal,
            .zero,
            "The previous vault's rows must be untouched by a refresh made after the switch."
        )
    }

    // MARK: - Supersession

    /// A refresh that a newer one has replaced must neither publish its rows nor
    /// persist its snapshot.
    ///
    /// Both halves matter and they fail differently: publishing makes the screen
    /// flick back to an older figure, while persisting outlives the session and
    /// leaves the store holding a number no refresh ever confirmed. The first
    /// pass here is held open inside `/positions` and reports 1000 shares; the
    /// second reports 2000 and is the only one allowed to land.
    func testASupersededRefreshNeitherPublishesNorPersists() async throws {
        try storage.setEnabled(true, descriptor: steakhouse, for: vault)
        let viewModel = makeViewModel()

        let firstSuspended = expectation(description: "the first refresh suspended inside /positions")
        let secondReached = expectation(description: "the second refresh reached /positions")
        service.onPositionsCall { call in
            if call == 1 { firstSuspended.fulfill() } else { secondReached.fulfill() }
        }
        service.holdNextPositions()
        service.positions = [KaminoFixtures.position(vault: steakhouse.address, shares: "1000")]

        let first = Task { await viewModel.refresh(owner: owner) }
        await fulfillment(of: [firstSuspended], timeout: 5)

        // Queue the value the surviving pass should produce, then supersede.
        // Waiting for the second call proves the cancellation has already
        // happened before the first pass is let go — otherwise releasing could
        // beat it and the first would publish after all.
        service.positions = [KaminoFixtures.position(vault: steakhouse.address, shares: "2000")]
        let second = Task { await viewModel.refresh(owner: owner) }
        await fulfillment(of: [secondReached], timeout: 5)

        service.releasePositions()
        await second.value
        await first.value

        let row = try XCTUnwrap(viewModel.rows.first)
        XCTAssertEqual(
            row.tokenAmount,
            Decimal(string: "2107.208362"),
            "The superseded pass's 1000 shares must not reach the rows."
        )
        XCTAssertEqual(
            storage.position(for: vault, vaultAddress: steakhouse.address)?.tokenAmountDecimal,
            Decimal(string: "2107.208362"),
            "Nor the store — a discarded figure that persists outlives the session."
        )
    }

    /// The whole registry descriptor travels to the service, not just the
    /// address: `fetchVaultInfo` requires the registry's own entry, and refuses
    /// anything that merely carries a curated address.
    func testTheRegistryDescriptorIsPassedThroughUnchanged() async throws {
        try storage.setEnabled(true, descriptor: allez, for: vault)
        service.positions = [KaminoFixtures.position(vault: allez.address, shares: "1")]
        let viewModel = makeViewModel()

        await viewModel.refresh(owner: owner)

        XCTAssertEqual(service.hydratedDescriptors, [allez])
    }
}

// MARK: - Fixtures

private enum KaminoFixtures {
    /// Captured from `api.kamino.finance` on 2026-08-04.
    static let allezInfo = KaminoVaultInfo(
        descriptor: KaminoVaultRegistry.allezSOL,
        name: "Allez SOL",
        minDeposit: KaminoTokenAmount(baseUnits: 10_000_000, decimals: 9),
        minWithdraw: KaminoShareAmount(baseUnits: 1_000, decimals: 6),
        lookupTable: "7EzosNioQ6FDNvMKLfg6om5wTVHiJo9vVx7DZNGYBKU3",
        apy30d: decimal("0.066908831669281033201"),
        tokensPerShare: rate("0.0010749299151180878396"),
        tokenPriceUsd: decimal("73.900426936257595")
    )

    static let steakhouseInfo = KaminoVaultInfo(
        descriptor: KaminoVaultRegistry.steakhouseUSDC,
        name: "Steakhouse USDC",
        minDeposit: KaminoTokenAmount(baseUnits: 100_000, decimals: 6),
        minWithdraw: KaminoShareAmount(baseUnits: 1_000, decimals: 6),
        lookupTable: "9p2oT9J6BojHigd3V5qXzrwsQf4dtgMgLxtrzLVR3rwu",
        apy30d: decimal("0.03994268764493801732"),
        tokensPerShare: rate("1.0536041812651029025"),
        tokenPriceUsd: decimal("0.99987")
    )

    /// Fixture parsers. Force-unwrapped on purpose: a fixture that stops parsing
    /// is a broken test, not a runtime condition to tolerate.
    static func rate(_ value: String) -> KaminoRate {
        // swiftlint:disable:next force_unwrapping
        KaminoRate(apiString: value)!
    }

    static func decimal(_ value: String) -> Decimal {
        // swiftlint:disable:next force_unwrapping
        KaminoDecimal.parse(value)!
    }

    static func position(vault: String, shares: String) -> KaminoUserPositionResponse {
        KaminoUserPositionResponse(
            vaultAddress: vault,
            stakedShares: shares,
            unstakedShares: "0",
            totalShares: shares
        )
    }

    static func pnl(token: String) -> KaminoPnlResponse {
        KaminoPnlResponse(
            totalCostBasis: KaminoPnlResponse.Amounts(token: "0", sol: "0", usd: "0"),
            totalPnl: KaminoPnlResponse.Amounts(token: token, sol: "0", usd: "0")
        )
    }
}

// MARK: - Test double

// A protocol conformance has to keep the declared signatures, so unused
// parameters and `async` without `await` are unavoidable here.
// swiftlint:disable async_without_await unused_parameter

/// Protocol-level fake. The REST decoding it stands in for is covered by
/// `KaminoServiceTests`; these tests are about what the view model does with the
/// values.
private final class FakeKaminoService: KaminoServiceProtocol, @unchecked Sendable {
    enum StubError: Error {
        case unreachable
    }

    private let lock = NSLock()
    private var _positions: [KaminoUserPositionResponse] = []
    private var _positionsError: Error?
    private var _infos: [String: KaminoVaultInfo] = [:]
    private var _infoErrors: [String: Error] = [:]
    private var _pnl: [String: KaminoPnlResponse] = [:]
    private var _positionsCallCount = 0
    private var _hydratedDescriptors: [KaminoVaultDescriptor] = []
    private var _positionsGate: CheckedContinuation<Void, Never>?
    private var _holdNextPositions = false
    private var _onPositionsCall: (@Sendable (Int) -> Void)?

    var positions: [KaminoUserPositionResponse] {
        get { lock.withLock { _positions } }
        set { lock.withLock { _positions = newValue } }
    }

    var positionsError: Error? {
        get { lock.withLock { _positionsError } }
        set { lock.withLock { _positionsError = newValue } }
    }

    var infos: [String: KaminoVaultInfo] {
        get { lock.withLock { _infos } }
        set { lock.withLock { _infos = newValue } }
    }

    var infoErrors: [String: Error] {
        get { lock.withLock { _infoErrors } }
        set { lock.withLock { _infoErrors = newValue } }
    }

    var pnl: [String: KaminoPnlResponse] {
        get { lock.withLock { _pnl } }
        set { lock.withLock { _pnl = newValue } }
    }

    var positionsCallCount: Int { lock.withLock { _positionsCallCount } }

    var hydratedDescriptors: [KaminoVaultDescriptor] { lock.withLock { _hydratedDescriptors } }

    var hydratedVaults: [String] { hydratedDescriptors.map(\.address) }

    /// Arms a one-shot suspension inside the NEXT `fetchPositions`, released by
    /// `releasePositions()`. One-shot on purpose: a later call must run straight
    /// through, or it would overwrite the held continuation and strand the first.
    func holdNextPositions() {
        lock.withLock { _holdNextPositions = true }
    }

    /// Fires with the call number each time `fetchPositions` is entered — after
    /// the continuation is stored, so a test that releases on this signal can
    /// never beat the suspension it is releasing.
    func onPositionsCall(_ body: @escaping @Sendable (Int) -> Void) {
        lock.withLock { _onPositionsCall = body }
    }

    func releasePositions() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let c = _positionsGate
            _positionsGate = nil
            return c
        }
        waiter?.resume()
    }

    func fetchPositions(owner: String) async throws -> [KaminoUserPositionResponse] {
        let (hold, notify, call) = lock.withLock { () -> (Bool, (@Sendable (Int) -> Void)?, Int) in
            _positionsCallCount += 1
            let hold = _holdNextPositions
            _holdNextPositions = false
            return (hold, _onPositionsCall, _positionsCallCount)
        }
        if hold {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                lock.withLock { _positionsGate = c }
                notify?(call)
            }
        } else {
            notify?(call)
        }
        let (error, result) = lock.withLock {
            return (_positionsError, _positions)
        }
        if let error { throw error }
        return result
    }

    func fetchVaultInfo(descriptor: KaminoVaultDescriptor) async throws -> KaminoVaultInfo {
        let (error, info) = lock.withLock { () -> (Error?, KaminoVaultInfo?) in
            _hydratedDescriptors.append(descriptor)
            return (_infoErrors[descriptor.address], _infos[descriptor.address])
        }
        if let error { throw error }
        guard let info else { throw StubError.unreachable }
        return info
    }

    func fetchPnl(owner: String, vault: String) async throws -> KaminoPnlResponse {
        guard let response = lock.withLock({ _pnl[vault] }) else { throw StubError.unreachable }
        return response
    }

    func fetchVaultState(address: String) async throws -> KaminoVaultStateResponse {
        throw StubError.unreachable
    }

    func fetchVaultMetrics(address: String) async throws -> KaminoVaultMetricsResponse {
        throw StubError.unreachable
    }

    func buildDepositTransaction(
        owner: String,
        vault: KaminoVaultDescriptor,
        amount: KaminoTokenAmount
    ) async throws -> String {
        throw StubError.unreachable
    }

    func buildWithdrawTransaction(
        owner: String,
        vault: KaminoVaultDescriptor,
        shares: KaminoShareAmount
    ) async throws -> String {
        throw StubError.unreachable
    }
}

/// Records which coins a refresh asked to be priced.
private final class FakeCryptoPriceService: CryptoPriceServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _requested: [CoinMeta] = []
    private var _error: Error?

    var requested: [CoinMeta] { lock.withLock { _requested } }

    var error: Error? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    func fetchPrices(coins: [CoinMeta]) async throws {
        let error = lock.withLock { () -> Error? in
            _requested.append(contentsOf: coins)
            return _error
        }
        if let error { throw error }
    }

    func fetchPrice(coin: Coin) async throws {
        try await fetchPrices(coins: [coin.toCoinMeta()])
    }
}

// swiftlint:enable async_without_await unused_parameter
