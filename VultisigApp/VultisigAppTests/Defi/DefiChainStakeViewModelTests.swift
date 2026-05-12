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

    func testInitWithoutPersistedPositionsLeavesArrayEmpty() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.stakePositions.isEmpty)
        XCTAssertFalse(vm.initialLoadingDone, "No persisted rows ⇒ skeleton must show until first refresh.")
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

    func testRefreshSuccessPersistsAndPublishes() async throws {
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
    }

    /// Refresh that returns no DTOs (e.g. all per-coin fetches failed) must not flicker the list
    /// to empty — persisted rows stay visible.
    func testRefreshEmptyPreservesPersistedState() async throws {
        let storage = DefiPositionsStorageService()
        let tcyMeta = CoinMeta.make(chain: .thorChain, ticker: "TCY")
        try storage.upsert(stake: [
            StakePositionData(coin: tcyMeta, type: .stake, amount: 100, apr: 0.1)
        ], for: vault)

        let vm = makeViewModel()
        XCTAssertEqual(vm.stakePositions.count, 1)

        interactor.stub = []
        await vm.refresh()

        XCTAssertEqual(vm.stakePositions.count, 1)
        XCTAssertEqual(vm.stakePositions.first?.amount, 100)
    }

    /// Per-coin partial success: TCY refresh succeeds, RUJI's per-coin fetch failed (interactor
    /// omits it). RUJI's persisted row must stay untouched.
    func testRefreshPartialSuccessPreservesOmittedCoinsRow() async throws {
        let storage = DefiPositionsStorageService()
        let tcyMeta = CoinMeta.make(chain: .thorChain, ticker: "TCY")
        let rujiMeta = CoinMeta.make(chain: .thorChain, ticker: "RUJI")

        vault.defiPositions = [DefiPositions(chain: .thorChain, bonds: [], staking: [tcyMeta, rujiMeta], lps: [])]
        try storage.upsert(stake: [
            StakePositionData(coin: tcyMeta, type: .stake, amount: 100, apr: 0.1),
            StakePositionData(coin: rujiMeta, type: .stake, amount: 200, apr: 0.2)
        ], for: vault)

        interactor.stub = [
            StakePositionData(coin: tcyMeta, type: .stake, amount: 150, apr: 0.15)
        ]

        let vm = makeViewModel()
        await vm.refresh()

        let tcy = vm.stakePositions.first { $0.coin.ticker == "TCY" }
        let ruji = vm.stakePositions.first { $0.coin.ticker == "RUJI" }
        XCTAssertEqual(tcy?.amount, 150)
        XCTAssertEqual(ruji?.amount, 200, "RUJI must keep its persisted amount when omitted from refresh.")
    }

    // MARK: - Helpers

    private func makeViewModel() -> DefiChainStakeViewModel {
        DefiChainStakeViewModel(vault: vault, chain: .thorChain, interactor: interactor)
    }
}
