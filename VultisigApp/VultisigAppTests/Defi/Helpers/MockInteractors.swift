//
//  MockInteractors.swift
//  VultisigAppTests
//
//  Test doubles for the Defi interactor protocols.
//

import Foundation
@testable import VultisigApp

// Mocks mostly don't `await` and don't read `vault` — the signatures must match the
// production protocols exactly, so we can't rename the parameter or drop `async`.

// swiftlint:disable async_without_await unused_parameter

/// Holds one interactor call open so a test can drive the view model — rebind its
/// vault, say — while a fetch is still in flight.
///
/// The handoff is an explicit arrival signal, not a sleep: `waitForArrival()`
/// returns only once a call has actually reached `wait()`, and `wait()` returns
/// only once the test calls `open()`. The window the test needs is therefore held
/// open by construction rather than raced for, which is what keeps an
/// interleaving test off the flaky list.
///
/// One waiter at a time. Gate the single call the test is reasoning about and
/// leave the view model's other fetches to run straight through.
actor InteractorCallGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var hasArrived = false
    private var arrivalWaiter: CheckedContinuation<Void, Never>?

    /// Called from the interactor. Suspends until the test calls `open()`.
    func wait() async {
        hasArrived = true
        arrivalWaiter?.resume()
        arrivalWaiter = nil
        guard !isOpen else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    /// Called from the test. Returns once a call has reached `wait()`.
    func waitForArrival() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { arrivalWaiter = $0 }
    }

    /// Called from the test. Lets the held call return.
    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}

final class MockStakeInteractor: StakeInteractor, @unchecked Sendable {
    var stub: [StakePositionData] = []
    var actionAvailabilitiesStub: StakeActionAvailabilities = [:]
    /// Set to hold `fetchStakePositions` open mid-call.
    var gate: InteractorCallGate?
    private(set) var callCount = 0
    private(set) var actionAvailabilityCallCount = 0

    func fetchStakePositions(vault: Vault) async -> [StakePositionData] {
        callCount += 1
        await gate?.wait()
        return stub
    }

    func fetchActionAvailabilities(for coins: [CoinMeta]) async -> StakeActionAvailabilities {
        actionAvailabilityCallCount += 1
        return coins.reduce(into: actionAvailabilitiesStub) { result, coin in
            if result[coin] == nil {
                result[coin] = .available
            }
        }
    }
}

final class MockBondInteractor: BondInteractor, @unchecked Sendable {
    enum StubError: Error {
        case unreachable
    }

    var stub: (active: [BondPosition], available: [BondNode]) = ([], [])
    var canUnbondStub = true
    var canAddBondStub = true
    /// Set to fail `fetchBondPositions` instead of returning `stub`.
    var error: Error?
    /// Set to hold `fetchBondPositions` open mid-call.
    var gate: InteractorCallGate?

    func fetchBondPositions(vault: Vault) async throws -> (active: [BondPosition], available: [BondNode]) {
        await gate?.wait()
        if let error {
            throw error
        }
        return stub
    }

    func canUnbond() async -> Bool { canUnbondStub }

    func canAddBond() async -> Bool { canAddBondStub }
}

final class MockLPsInteractor: LPsInteractor, @unchecked Sendable {
    var stub: [LPPositionData] = []
    /// Set to hold `fetchLPPositions` open mid-call.
    var gate: InteractorCallGate?
    private(set) var callCount = 0

    func fetchLPPositions(vault: Vault) async -> [LPPositionData] {
        callCount += 1
        await gate?.wait()
        return stub
    }
}

/// Test double for the selectable-position catalog. `lpDelay` and `lpError` let
/// a test hold the pool fetch open, fail it, or make it outlive the view model's
/// wall-clock budget — the three cases that used to blank the whole picker.
///
/// Every property sits behind a lock, which is what backs the `@unchecked
/// Sendable` here. This is not theoretical: `withTimeout` abandons a timed-out
/// operation rather than awaiting it, so `lpCoins` can still be running on the
/// cooperative pool while the test mutates the stubs from the main actor.
/// `lpCoins` therefore snapshots the stubs once, under the lock, so a single
/// call cannot observe a half-applied change.
final class MockDefiPositionsProvider: DefiPositionsProviding, @unchecked Sendable {
    enum StubError: Error {
        case unreachable
    }

    private let lock = NSLock()
    private var _bondStub: [CoinMeta] = []
    private var _stakeStub: [CoinMeta] = []
    private var _lpStub: [CoinMeta] = []
    private var _earnStub: [KaminoVaultDescriptor] = []
    private var _supportsLPs = true
    private var _lpDelay: Duration?
    private var _lpError: Error?
    private var _lpCallCount = 0

    var bondStub: [CoinMeta] {
        get { lock.withLock { _bondStub } }
        set { lock.withLock { _bondStub = newValue } }
    }

    var stakeStub: [CoinMeta] {
        get { lock.withLock { _stakeStub } }
        set { lock.withLock { _stakeStub = newValue } }
    }

    var lpStub: [CoinMeta] {
        get { lock.withLock { _lpStub } }
        set { lock.withLock { _lpStub = newValue } }
    }

    var earnStub: [KaminoVaultDescriptor] {
        get { lock.withLock { _earnStub } }
        set { lock.withLock { _earnStub = newValue } }
    }

    var supportsLPs: Bool {
        get { lock.withLock { _supportsLPs } }
        set { lock.withLock { _supportsLPs = newValue } }
    }

    var lpDelay: Duration? {
        get { lock.withLock { _lpDelay } }
        set { lock.withLock { _lpDelay = newValue } }
    }

    var lpError: Error? {
        get { lock.withLock { _lpError } }
        set { lock.withLock { _lpError = newValue } }
    }

    var lpCallCount: Int {
        lock.withLock { _lpCallCount }
    }

    func bondCoins(for chain: Chain) -> [CoinMeta] { bondStub }

    func stakeCoins(for chain: Chain) -> [CoinMeta] { stakeStub }

    func earnVaults(for chain: Chain) -> [KaminoVaultDescriptor] { earnStub }

    func supportsLiquidityPools(for chain: Chain) -> Bool { supportsLPs }

    func lpCoins(for chain: Chain) async throws -> [CoinMeta] {
        let (delay, error, stub) = lock.withLock {
            _lpCallCount += 1
            return (_lpDelay, _lpError, _lpStub)
        }

        if let delay {
            try await Task.sleep(for: delay)
        }
        if let error {
            throw error
        }
        return stub
    }
}

// swiftlint:enable async_without_await unused_parameter
