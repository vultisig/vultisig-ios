//
//  BondRewardHistoryViewModelTests.swift
//  VultisigAppTests
//
//  The "Total Rewards Earned" sheet's view model: lazy load, cancellation,
//  and — the acceptance criterion this file exists for — a history fetch
//  failure must surface as `loadError` without ever touching the bonded
//  list the sheet was opened from (that list lives entirely outside this
//  view model).
//

@testable import VultisigApp
import XCTest

@MainActor
final class BondRewardHistoryViewModelTests: XCTestCase {

    private func makeNode(lastReward: Decimal? = nil) -> BondPosition {
        BondPosition(
            node: BondNode(coin: .example, address: "thor1nodeaddress", state: .active),
            amount: 500,
            apy: 0.1,
            nextReward: 18,
            nextChurn: nil,
            lastReward: lastReward,
            vault: .example
        )
    }

    func testUpcomingAmountComesFromTheLiveBondPositionNotTheFetch() {
        let interactor = MockBondInteractor()
        let viewModel = BondRewardHistoryViewModel(
            vault: .example,
            chain: .thorChain,
            coin: .example,
            node: makeNode(),
            interactor: interactor
        )

        XCTAssertEqual(viewModel.upcomingAmount, 18)
    }

    func testTotalSumsHistoryOnlyExcludingUpcoming() async {
        let interactor = MockBondInteractor()
        interactor.rewardHistoryStub = [
            BondRewardHistoryEntry(churnHeight: 300, churnDate: Date(), amount: 10),
            BondRewardHistoryEntry(churnHeight: 200, churnDate: Date(), amount: 5)
        ]
        let viewModel = BondRewardHistoryViewModel(
            vault: .example,
            chain: .thorChain,
            coin: .example,
            node: makeNode(),
            interactor: interactor
        )

        viewModel.load()
        await waitUntil { !viewModel.isLoading }

        XCTAssertEqual(viewModel.total, 15, "excludes the live Upcoming share (18)")
        XCTAssertEqual(viewModel.history.count, 2)
    }

    /// The acceptance criterion: a failed historical query surfaces as this
    /// view model's own error state. It never reaches back into the bonded
    /// list — there is no reference from here to `DefiChainBondViewModel` at
    /// all, so "not blanking the list" is true by construction, not by luck.
    func testFetchFailureSurfacesAsLoadErrorWithoutThrowing() async {
        let interactor = MockBondInteractor()
        interactor.rewardHistoryError = MockBondInteractor.StubError.unreachable
        let viewModel = BondRewardHistoryViewModel(
            vault: .example,
            chain: .thorChain,
            coin: .example,
            node: makeNode(),
            interactor: interactor
        )

        viewModel.load()
        await waitUntil { !viewModel.isLoading }

        XCTAssertNotNil(viewModel.loadError)
        XCTAssertTrue(viewModel.history.isEmpty)
    }

    func testLoadIfNeededDoesNotRefetchOnceHistoryIsLoaded() async {
        let interactor = MockBondInteractor()
        interactor.rewardHistoryStub = [BondRewardHistoryEntry(churnHeight: 100, churnDate: Date(), amount: 1)]
        let viewModel = BondRewardHistoryViewModel(
            vault: .example,
            chain: .thorChain,
            coin: .example,
            node: makeNode(),
            interactor: interactor
        )

        viewModel.loadIfNeeded()
        await waitUntil { !viewModel.isLoading }
        XCTAssertEqual(interactor.rewardHistoryCallCount, 1)

        viewModel.loadIfNeeded()
        XCTAssertEqual(interactor.rewardHistoryCallCount, 1, "already has history — a re-appearance must not refetch")
    }

    /// `cancelLoad` is what the sheet calls from `.onDisappear` — closing the
    /// sheet mid-fetch must not leave the view model reporting a result for
    /// a view nobody is looking at.
    func testCancelLoadStopsTheInFlightFetchFromPublishingAResult() async {
        let interactor = MockBondInteractor()
        interactor.rewardHistoryStub = [BondRewardHistoryEntry(churnHeight: 100, churnDate: Date(), amount: 1)]

        let viewModel = BondRewardHistoryViewModel(
            vault: .example,
            chain: .thorChain,
            coin: .example,
            node: makeNode(),
            interactor: SlowMockBondInteractor(wrapped: interactor)
        )

        viewModel.load()
        viewModel.cancelLoad()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.history.isEmpty, "cancelled before the slow fetch could publish")
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

/// Wraps `MockBondInteractor` with an artificial delay so
/// `testCancelLoadStopsTheInFlightFetchFromPublishingAResult` can cancel
/// before the fetch resolves.
private final class SlowMockBondInteractor: BondInteractor, @unchecked Sendable {
    private let wrapped: MockBondInteractor

    init(wrapped: MockBondInteractor) {
        self.wrapped = wrapped
    }

    func fetchBondPositions(vault: Vault) async throws -> (active: [BondPosition], available: [BondNode]) {
        try await wrapped.fetchBondPositions(vault: vault)
    }

    func canUnbond() async -> Bool { await wrapped.canUnbond() }
    func canAddBond() async -> Bool { await wrapped.canAddBond() }

    func fetchRewardHistory(nodeAddress: String, myBondAddress: String) async throws -> [BondRewardHistoryEntry] {
        try await Task.sleep(nanoseconds: 200_000_000)
        return try await wrapped.fetchRewardHistory(nodeAddress: nodeAddress, myBondAddress: myBondAddress)
    }

    func bondCoinAddress(in vault: Vault) async -> String? { await wrapped.bondCoinAddress(in: vault) }
}
