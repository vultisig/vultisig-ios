//
//  DefiChainStakeViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class DefiChainStakeViewModelTests: XCTestCase {
    private var storeToken: DefiTestContextToken!
    private var vault: Vault!
    private var interactor: MockStakeInteractor!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try DefiTestStore.installInMemoryContainer()
        vault = DefiTestStore.makeVault()
        interactor = MockStakeInteractor()

        // Enable TCY in defi positions so vaultStakePositions resolves correctly.
        let tcyMeta = CoinMeta.make(chain: .thorChain, ticker: "TCY")
        vault.defiPositions = [DefiPositions(chain: .thorChain, bonds: [], staking: [tcyMeta], lps: [])]
    }

    override func tearDown() async throws {
        interactor = nil
        vault = nil
        DefiTestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - Init

    func testInitWithEmptyPersistedPositionsMarksInitialLoadingPending() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.stakePositions.isEmpty)
        XCTAssertFalse(vm.initialLoadingDone)
    }

    func testInitWithPersistedPositionsMarksInitialLoadingDone() throws {
        let storage = DefiPositionsStorageService()
        let tcyMeta = CoinMeta.make(chain: .thorChain, ticker: "TCY")
        try storage.upsert(stake: [
            StakePositionData(coin: tcyMeta, type: .stake, amount: 100, apr: 0.1)
        ], for: vault)

        let vm = makeViewModel()
        XCTAssertEqual(vm.stakePositions.count, 1)
        XCTAssertTrue(vm.initialLoadingDone)
    }

    // MARK: - Refresh

    func testRefreshSuccessReplacesPublishedArray() async throws {
        let vm = makeViewModel()
        let tcyMeta = CoinMeta.make(chain: .thorChain, ticker: "TCY")
        interactor.stub = [
            StakePositionData(coin: tcyMeta, type: .stake, amount: 42, apr: 0.05)
        ]

        await vm.refresh()

        XCTAssertEqual(vm.stakePositions.count, 1)
        XCTAssertEqual(vm.stakePositions.first?.amount, 42)
        XCTAssertEqual(vm.stakePositions.first?.apr, 0.05)
        XCTAssertTrue(vm.initialLoadingDone)
        XCTAssertNil(vm.refreshError)
    }

    /// Regression test for Bug 2: refresh that returns no DTOs must not flicker the list to empty.
    func testRefreshEmptyPreservesPersistedState() async throws {
        let storage = DefiPositionsStorageService()
        let tcyMeta = CoinMeta.make(chain: .thorChain, ticker: "TCY")
        try storage.upsert(stake: [
            StakePositionData(coin: tcyMeta, type: .stake, amount: 100, apr: 0.1)
        ], for: vault)

        let vm = makeViewModel()
        XCTAssertEqual(vm.stakePositions.count, 1)

        interactor.stub = [] // no DTOs returned (e.g. all per-coin fetches failed)
        await vm.refresh()

        XCTAssertEqual(vm.stakePositions.count, 1, "Empty interactor result must NOT clear the list — persisted positions stay visible.")
        XCTAssertEqual(vm.stakePositions.first?.amount, 100)
        XCTAssertEqual(vm.stakePositions.first?.apr, 0.1)
    }

    func testRefreshPartialSuccessOnlyUpdatesReturnedCoins() async throws {
        let storage = DefiPositionsStorageService()
        let tcyMeta = CoinMeta.make(chain: .thorChain, ticker: "TCY")
        let rujiMeta = CoinMeta.make(chain: .thorChain, ticker: "RUJI")

        // Enable both
        vault.defiPositions = [DefiPositions(chain: .thorChain, bonds: [], staking: [tcyMeta, rujiMeta], lps: [])]

        // Seed with prior data for both
        try storage.upsert(stake: [
            StakePositionData(coin: tcyMeta, type: .stake, amount: 100, apr: 0.1),
            StakePositionData(coin: rujiMeta, type: .stake, amount: 200, apr: 0.2)
        ], for: vault)

        // Only TCY succeeds in this refresh — RUJI per-coin fetch failed and was omitted.
        interactor.stub = [
            StakePositionData(coin: tcyMeta, type: .stake, amount: 150, apr: 0.15)
        ]

        let vm = makeViewModel()
        await vm.refresh()

        // TCY updates to 150; RUJI keeps its prior 200.
        let tcy = vm.stakePositions.first { $0.coin.ticker == "TCY" }
        let ruji = vm.stakePositions.first { $0.coin.ticker == "RUJI" }
        XCTAssertEqual(tcy?.amount, 150)
        XCTAssertEqual(ruji?.amount, 200, "Persisted RUJI must remain — partial-failure refresh preserves untouched coins.")
    }

    func testUpdateVaultReSnapshotsCache() throws {
        let vm = makeViewModel()
        XCTAssertTrue(vm.stakePositions.isEmpty)

        // Build a second vault with persisted positions, swap.
        let storage = DefiPositionsStorageService()
        let other = DefiTestStore.makeVault(pubKey: "other-vault")
        let tcyMeta = CoinMeta.make(chain: .thorChain, ticker: "TCY")
        other.defiPositions = [DefiPositions(chain: .thorChain, bonds: [], staking: [tcyMeta], lps: [])]
        try storage.upsert(stake: [
            StakePositionData(coin: tcyMeta, type: .stake, amount: 999, apr: 0.3)
        ], for: other)

        vm.update(vault: other)

        XCTAssertEqual(vm.stakePositions.count, 1)
        XCTAssertEqual(vm.stakePositions.first?.amount, 999)
    }

    // MARK: - Helpers

    private func makeViewModel() -> DefiChainStakeViewModel {
        DefiChainStakeViewModel(vault: vault, chain: .thorChain, interactor: interactor)
    }
}
