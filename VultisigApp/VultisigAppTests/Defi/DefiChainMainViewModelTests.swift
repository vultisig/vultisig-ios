//
//  DefiChainMainViewModelTests.swift
//  VultisigAppTests
//
//  The bond and stake catalogs are static in-app lists; only liquidity pools
//  need the network. These tests pin that separation: a slow, failing or
//  timing-out pool fetch must never blank the sections that need no network.
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class DefiChainMainViewModelTests: XCTestCase {
    private var storeToken: TestContextToken!
    private var vault: Vault!
    private var service: MockDefiPositionsProvider!

    private let bondCoin = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
    private let stakeCoin = CoinMeta.make(chain: .thorChain, ticker: "TCY")
    private let lpCoin = CoinMeta.make(chain: .thorChain, ticker: "BTC")

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
        service = MockDefiPositionsProvider()
        service.bondStub = [bondCoin]
        service.stakeStub = [stakeCoin]
        service.lpStub = [lpCoin]
    }

    override func tearDown() async throws {
        service = nil
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    private func makeViewModel(chain: Chain = .thorChain, lpLoadTimeout: TimeInterval = 5) -> DefiChainMainViewModel {
        DefiChainMainViewModel(
            vault: vault,
            chain: chain,
            positionsService: service,
            lpLoadTimeout: lpLoadTimeout
        )
    }

    private func section(
        _ type: DefiChainPositionType,
        in vm: DefiChainMainViewModel
    ) -> AssetSection<DefiChainPositionType, CoinMeta>? {
        vm.availablePositions.first { $0.type == type }
    }

    // MARK: - Static sections are never gated on the network

    func testStaticSectionsArePublishedBeforeLiquidityPoolsResolve() {
        // A pool fetch that never returns within the test's lifetime.
        service.lpDelay = .seconds(60)
        let vm = makeViewModel()

        vm.onLoad()

        // No awaiting: the static catalog must be readable the instant onLoad returns.
        XCTAssertEqual(vm.availablePositions.count, 3)
        XCTAssertEqual(section(.bond, in: vm)?.assets, [bondCoin])
        XCTAssertEqual(section(.stake, in: vm)?.assets, [stakeCoin])
        XCTAssertTrue(
            section(.liquidityPool, in: vm)?.state.isLoading ?? false,
            "LP section must report loading, not an empty result."
        )
    }

    func testPickerIsNeverFullyEmptyWhileLiquidityPoolsLoad() {
        service.lpDelay = .seconds(60)
        let vm = makeViewModel()

        vm.onLoad()

        // The empty state keys off "every section loaded and empty" — this is the
        // exact condition that used to render "No positions found" for the whole sheet.
        let looksEmpty = vm.availablePositions.allSatisfy { $0.state == .loaded && $0.assets.isEmpty }
        XCTAssertFalse(looksEmpty)
    }

    // MARK: - Failure isolation

    func testLiquidityPoolFailureLeavesStaticSectionsIntact() async {
        service.lpError = MockDefiPositionsProvider.StubError.unreachable
        let vm = makeViewModel()

        vm.onLoad()
        await vm.lpLoadTask?.value

        XCTAssertEqual(section(.bond, in: vm)?.assets, [bondCoin], "A pools failure must not touch the bond section.")
        XCTAssertEqual(section(.stake, in: vm)?.assets, [stakeCoin], "A pools failure must not touch the stake section.")
        XCTAssertTrue(section(.liquidityPool, in: vm)?.state.isFailed ?? false)
        XCTAssertEqual(section(.liquidityPool, in: vm)?.assets, [])
    }

    func testLiquidityPoolTimeoutIsSurfacedAsFailure() async {
        // Fetch outlives the wall-clock budget.
        service.lpDelay = .seconds(30)
        let vm = makeViewModel(lpLoadTimeout: 0.05)

        vm.onLoad()
        await vm.lpLoadTask?.value

        XCTAssertTrue(
            section(.liquidityPool, in: vm)?.state.isFailed ?? false,
            "A hung pool fetch must resolve to a retryable failure, not an endless spinner."
        )
        XCTAssertEqual(section(.bond, in: vm)?.assets, [bondCoin])
        XCTAssertEqual(section(.stake, in: vm)?.assets, [stakeCoin])
    }

    // MARK: - Retry

    func testRetryAfterFailureRepopulatesLiquidityPools() async {
        service.lpError = MockDefiPositionsProvider.StubError.unreachable
        let vm = makeViewModel()

        vm.onLoad()
        await vm.lpLoadTask?.value
        XCTAssertTrue(section(.liquidityPool, in: vm)?.state.isFailed ?? false)
        XCTAssertEqual(service.lpCallCount, 1)

        service.lpError = nil
        vm.loadLiquidityPools()
        await vm.lpLoadTask?.value

        XCTAssertEqual(service.lpCallCount, 2)
        XCTAssertEqual(section(.liquidityPool, in: vm)?.state, .loaded)
        XCTAssertEqual(section(.liquidityPool, in: vm)?.assets, [lpCoin])
    }

    func testRetryReturnsSectionToLoadingWhileInFlight() async {
        service.lpError = MockDefiPositionsProvider.StubError.unreachable
        let vm = makeViewModel()
        vm.onLoad()
        await vm.lpLoadTask?.value

        service.lpError = nil
        service.lpDelay = .seconds(60)
        vm.loadLiquidityPools()

        XCTAssertTrue(
            section(.liquidityPool, in: vm)?.state.isLoading ?? false,
            "Retry must clear the failure so the user sees progress."
        )
        vm.lpLoadTask?.cancel()
    }

    // MARK: - Success

    func testSuccessfulLoadPopulatesAllThreeSections() async {
        let vm = makeViewModel()

        vm.onLoad()
        await vm.lpLoadTask?.value

        XCTAssertEqual(section(.bond, in: vm)?.assets, [bondCoin])
        XCTAssertEqual(section(.stake, in: vm)?.assets, [stakeCoin])
        XCTAssertEqual(section(.liquidityPool, in: vm)?.assets, [lpCoin])
        XCTAssertTrue(vm.availablePositions.allSatisfy { $0.state == .loaded })
    }

    // MARK: - Section ordering (selection buckets depend on it)

    func testSectionOrderIsStableAcrossEveryLoadPhase() async {
        let expected: [DefiChainPositionType] = [.bond, .stake, .liquidityPool]
        service.lpDelay = .seconds(60)
        let vm = makeViewModel(lpLoadTimeout: 0.05)

        vm.onLoad()
        XCTAssertEqual(vm.availablePositions.map(\.type), expected, "order while loading")

        await vm.lpLoadTask?.value
        XCTAssertEqual(vm.availablePositions.map(\.type), expected, "order after failure")

        service.lpDelay = nil
        vm.loadLiquidityPools()
        await vm.lpLoadTask?.value
        XCTAssertEqual(vm.availablePositions.map(\.type), expected, "order after success")
    }

    // MARK: - Chains without liquidity pools

    func testChainWithoutLiquidityPoolsNeverEntersLoadingState() {
        service.supportsLPs = false
        service.bondStub = []
        service.stakeStub = [CoinMeta.make(chain: .ton, ticker: "TON")]
        let vm = makeViewModel(chain: .ton)

        vm.onLoad()

        XCTAssertEqual(section(.liquidityPool, in: vm)?.state, .loaded)
        XCTAssertEqual(service.lpCallCount, 0, "A chain with no pools must not hit the network.")
        XCTAssertNil(vm.lpLoadTask)
    }

    // MARK: - Search filtering

    func testSearchNarrowsToMatchingSectionsAndKeepsTheirState() async {
        let vm = makeViewModel()
        vm.onLoad()
        await vm.lpLoadTask?.value

        vm.positionsSearchText = "TCY"

        let filtered = vm.filteredAvailablePositions
        XCTAssertEqual(filtered.map(\.type), [.stake])
        XCTAssertEqual(filtered.first?.assets, [stakeCoin])
        XCTAssertEqual(filtered.first?.state, .loaded)
    }
}
