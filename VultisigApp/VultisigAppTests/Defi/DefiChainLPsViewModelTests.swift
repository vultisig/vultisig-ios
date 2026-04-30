//
//  DefiChainLPsViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class DefiChainLPsViewModelTests: XCTestCase {
    private var storeToken: DefiTestContextToken!
    private var vault: Vault!
    private var interactor: MockLPsInteractor!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try DefiTestStore.installInMemoryContainer()
        vault = DefiTestStore.makeVault()
        interactor = MockLPsInteractor()

        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
        vault.defiPositions = [DefiPositions(chain: .thorChain, bonds: [], staking: [], lps: [btc])]
    }

    override func tearDown() async throws {
        interactor = nil
        vault = nil
        DefiTestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - Init

    func testInitWithNoPersistedPositionsMarksInitialLoadingPending() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.lpPositions.isEmpty)
        XCTAssertFalse(vm.initialLoadingDone)
    }

    // MARK: - Refresh

    func testRefreshSuccessReplacesPersistedArray() async throws {
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
        interactor.stub = [
            LPPositionData(coin1: rune, coin1Amount: 100, coin2: btc, coin2Amount: 1, poolName: "BTC.BTC", poolUnits: "10", apr: 0.05)
        ]

        let vm = makeViewModel()
        await vm.refresh()

        XCTAssertEqual(vm.lpPositions.count, 1)
        XCTAssertEqual(vm.lpPositions.first?.apr, 0.05)
        XCTAssertNil(vm.refreshError)
        XCTAssertTrue(vm.initialLoadingDone)
    }

    /// Regression: an LP fetch that throws must NOT clear the persisted list, and must surface refreshError.
    func testRefreshFailurePreservesStateAndSetsError() async throws {
        let storage = DefiPositionsStorageService()
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
        try storage.upsert(lp: [
            LPPositionData(coin1: rune, coin1Amount: 100, coin2: btc, coin2Amount: 1, poolName: "BTC.BTC", poolUnits: "10", apr: 0.05)
        ], for: vault)

        interactor.error = MockInteractorError.generic

        let vm = makeViewModel()
        await vm.refresh()

        XCTAssertEqual(vm.lpPositions.count, 1, "Throw must not clear persisted positions.")
        XCTAssertNotNil(vm.refreshError, "Throw must set refreshError for the screen banner.")
    }

    func testRefreshNoLpsEnabledMarksLoadingDoneWithoutCallingInteractor() async {
        // Disable LP coins
        vault.defiPositions = [DefiPositions(chain: .thorChain, bonds: [], staking: [], lps: [])]

        let vm = makeViewModel()
        await vm.refresh()

        XCTAssertEqual(interactor.callCount, 0, "Refresh must short-circuit when no LP coins are enabled.")
        XCTAssertTrue(vm.initialLoadingDone)
    }

    func testRefreshEmptyPreservesPersistedState() async throws {
        let storage = DefiPositionsStorageService()
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
        try storage.upsert(lp: [
            LPPositionData(coin1: rune, coin1Amount: 50, coin2: btc, coin2Amount: 0.5, poolName: "BTC.BTC", poolUnits: "5", apr: 0.04)
        ], for: vault)

        interactor.stub = [] // empty success

        let vm = makeViewModel()
        XCTAssertEqual(vm.lpPositions.count, 1)
        await vm.refresh()

        // After empty fetch, persistedPositions() reflects whatever survived — the upsert with []
        // is a no-op (we proved that in DefiPositionsStorageServiceTests), so persisted stays.
        XCTAssertEqual(vm.lpPositions.count, 1, "Empty fetch must not clear LP list.")
        XCTAssertNil(vm.refreshError)
    }

    // MARK: - Helpers

    private func makeViewModel() -> DefiChainLPsViewModel {
        DefiChainLPsViewModel(vault: vault, chain: .thorChain, interactor: interactor)
    }
}
