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
    ///
    /// Gated rather than timed: the interactor call is held open until the
    /// test itself releases it, so there is no artificial delay left to
    /// "beat" once `cancelLoad` has run. A no-op `cancelLoad` would publish
    /// almost immediately after the gate opens; a correct one never does,
    /// for the whole poll window — that asymmetry is what makes this
    /// discriminating rather than a wall-clock guess.
    func testCancelLoadStopsTheInFlightFetchFromPublishingAResult() async {
        let interactor = MockBondInteractor()
        interactor.rewardHistoryStub = [BondRewardHistoryEntry(churnHeight: 100, churnDate: Date(), amount: 1)]
        let gate = InteractorCallGate()
        interactor.rewardHistoryGate = gate

        let viewModel = BondRewardHistoryViewModel(
            vault: .example,
            chain: .thorChain,
            coin: .example,
            node: makeNode(),
            interactor: interactor
        )

        viewModel.load()

        // Bounded rather than an unbounded `await`: a regression that hangs
        // instead of calling through to the gate must still fail this test
        // in finite time.
        let arrived = expectation(description: "fetchRewardHistory arrived")
        Task { await gate.waitForArrival(); arrived.fulfill() }
        await fulfillment(of: [arrived], timeout: 5)

        viewModel.cancelLoad()      // cancel while it's still suspended
        await gate.open()           // let the (already-cancelled) call resolve normally

        let publishedAnyway = await waitUntilTrueOrTimeout(timeout: 0.3) { !viewModel.history.isEmpty }
        XCTAssertFalse(publishedAnyway, "a fetch cancelled before it resolved must not publish, even though the interactor call itself completed")
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Like `waitUntil`, but reports whether `condition` was ever observed
    /// true — used to prove an absence (nothing published) rather than an
    /// eventual presence.
    private func waitUntilTrueOrTimeout(timeout: TimeInterval, _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }
}
