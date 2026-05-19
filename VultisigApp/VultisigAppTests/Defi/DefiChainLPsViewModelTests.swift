//
//  DefiChainLPsViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class DefiChainLPsViewModelTests: XCTestCase {
    private var storeToken: TestContextToken!
    private var vault: Vault!
    private var interactor: MockLPsInteractor!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
        interactor = MockLPsInteractor()

        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
        vault.defiPositions = [DefiPositions(chain: .thorChain, bonds: [], staking: [], lps: [btc])]
    }

    override func tearDown() async throws {
        interactor = nil
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - Init

    func testInitWithNoPersistedPositionsLeavesArrayEmpty() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.lpPositions.isEmpty)
        XCTAssertFalse(vm.initialLoadingDone)
    }

    // MARK: - Refresh

    func testRefreshSuccessPersistsAndPublishes() async throws {
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
        interactor.stub = [
            LPPositionData(coin1: rune, coin1Amount: 100, coin2: btc, coin2Amount: 1, poolName: "BTC.BTC", poolUnits: "10", apr: 0.05)
        ]

        let vm = makeViewModel()
        await vm.refresh()

        XCTAssertEqual(vm.lpPositions.count, 1)
        XCTAssertEqual(vm.lpPositions.first?.apr, 0.05)
        XCTAssertTrue(vm.initialLoadingDone)
    }

    /// Empty interactor result (top-level API failure) must not wipe persisted rows.
    func testRefreshEmptyPreservesPersistedState() async throws {
        let storage = DefiPositionsStorageService()
        let rune = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
        let btc = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
        try storage.upsert(lp: [
            LPPositionData(coin1: rune, coin1Amount: 50, coin2: btc, coin2Amount: 0.5, poolName: "BTC.BTC", poolUnits: "5", apr: 0.04)
        ], for: vault)

        let vm = makeViewModel()
        XCTAssertEqual(vm.lpPositions.count, 1)

        interactor.stub = []
        await vm.refresh()

        XCTAssertEqual(vm.lpPositions.count, 1)
        XCTAssertEqual(vm.lpPositions.first?.coin1Amount, 50)
    }

    // MARK: - Helpers

    private func makeViewModel() -> DefiChainLPsViewModel {
        DefiChainLPsViewModel(vault: vault, chain: .thorChain, interactor: interactor)
    }
}
