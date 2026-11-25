//
//  THORChainBondRewardHistoryTests.swift
//  VultisigAppTests
//
//  `getBondRewardHistory` drives the rewards sheet: where the walk stops or
//  crosses a gap, the requested limit, newest-first ordering, ns->date conversion, and the
//  no-prior-churn case all live here. No real network — `StubBondsHTTPClient`
//  is keyed by path + `height` query param so each historical snapshot can
//  return its own fixture.
//

import XCTest
@testable import VultisigApp

final class THORChainBondRewardHistoryTests: XCTestCase {

    private let myAddress = "thor1myaddress"
    private let nodeAddress = "thor1nodeaddress"
    /// Every fixture churn is within the fetch window of this moment.
    private let fixtureNow = Date(timeIntervalSince1970: 2_000)

    // MARK: - Fixtures

    /// `date` is unix nanoseconds; `height` is the churn height. Newest
    /// first is NOT assumed of the wire response — `getBondRewardHistory`
    /// sorts defensively, so this fixture is deliberately out of order.
    private func churnsJSON(_ churns: [(height: Int, dateNanos: Int64)]) -> Data {
        let entries = churns.map { "{\"height\":\"\($0.height)\",\"date\":\"\($0.dateNanos)\"}" }
        return Data("[\(entries.joined(separator: ","))]".utf8)
    }

    private func nodeDetailsJSON(currentAward: Int, feeBps: Int, providers: [(address: String, bond: Int)]) -> Data {
        let providersJSON = providers.map { "{\"bond_address\":\"\($0.address)\",\"bond\":\"\($0.bond)\"}" }
        return Data("""
        {
          "node_address": "\(nodeAddress)",
          "status": "Active",
          "bond_providers": {
            "node_operator_fee": "\(feeBps)",
            "providers": [\(providersJSON.joined(separator: ","))]
          },
          "current_award": "\(currentAward)"
        }
        """.utf8)
    }

    // MARK: - Tests

    /// Three churns, newest -> oldest: 300, 200, 100. This vault is a
    /// provider at height 299 and 199 but NOT at 99 (it joined between the
    /// second and third churn). Only the first two dated rows come back.
    func testStopsAtFirstChurnWhereAddressIsMissingFromBondProviders() async throws {
        let stub = StubBondsHTTPClient(
            churns: churnsJSON([(300, 300_000_000_000), (200, 200_000_000_000), (100, 100_000_000_000)]),
            nodeDetailsByHeight: [
                299: nodeDetailsJSON(currentAward: 1000, feeBps: 0, providers: [(myAddress, 50), ("other", 50)]),
                199: nodeDetailsJSON(currentAward: 1000, feeBps: 0, providers: [(myAddress, 50), ("other", 50)]),
                99: nodeDetailsJSON(currentAward: 1000, feeBps: 0, providers: [("other", 100)])
            ]
        )
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, now: fixtureNow)

        XCTAssertEqual(history.map(\.id), [300, 200], "stops before the churn the vault wasn't bonded for yet")
        XCTAssertEqual(history.map(\.amount), [500, 500])
    }

    /// Newest-first, regardless of the wire order or of which historical
    /// query happens to finish first under bounded concurrency.
    func testResultsAreNewestFirst() async throws {
        let stub = StubBondsHTTPClient(
            churns: churnsJSON([(100, 1), (300, 3), (200, 2)]), // deliberately unsorted on the wire
            nodeDetailsByHeight: [
                299: nodeDetailsJSON(currentAward: 100, feeBps: 0, providers: [(myAddress, 1)]),
                199: nodeDetailsJSON(currentAward: 100, feeBps: 0, providers: [(myAddress, 1)]),
                99: nodeDetailsJSON(currentAward: 100, feeBps: 0, providers: [(myAddress, 1)])
            ]
        )
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, now: fixtureNow)

        XCTAssertEqual(history.map(\.id), [300, 200, 100])
    }

    /// `date` on the wire is unix NANOSECONDS — a raw-seconds interpretation
    /// would land in the 1970s.
    func testChurnDateConvertsFromNanoseconds() async throws {
        let nanos: Int64 = 1_784_733_471_384_558_083 // 2026-07-... in ns
        let stub = StubBondsHTTPClient(
            churns: churnsJSON([(100, nanos)]),
            nodeDetailsByHeight: [99: nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [(myAddress, 1)])]
        )
        let service = THORChainAPIService(httpClient: stub)
        let expected = Date(timeIntervalSince1970: Double(nanos) / 1_000_000_000)

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, now: expected)

        XCTAssertEqual(history.first?.date.timeIntervalSince1970 ?? 0, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    /// Cap respected even when more churns are available than `limit` asks for.
    func testRespectsTheRequestedLimit() async throws {
        let churns = (1...5).map { (height: $0 * 100, dateNanos: Int64($0) * 100_000_000_000) }
        var byHeight: [Int: Data] = [:]
        for churn in churns {
            byHeight[churn.height - 1] = nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [(myAddress, 1)])
        }
        let stub = StubBondsHTTPClient(churns: churnsJSON(churns), nodeDetailsByHeight: byHeight)
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, limit: 3, now: fixtureNow)

        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.map(\.id), [500, 400, 300], "the 3 newest, not an arbitrary 3")
    }

    /// Bonded now, but never a provider at any past churn — the sheet must
    /// be able to render Upcoming-only.
    func testNoPriorChurnWhileBondedReturnsEmptyHistory() async throws {
        let stub = StubBondsHTTPClient(
            churns: churnsJSON([(100, 1)]),
            nodeDetailsByHeight: [99: nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [("other", 1)])]
        )
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, now: fixtureNow)

        XCTAssertTrue(history.isEmpty)
    }

    /// `getBondRewardHistory` does not swallow a churns-endpoint failure into
    /// an empty history — it throws, and the CALLER decides isolation.
    /// `THORChainBondInteractor` wraps its one eager call in `try?` for
    /// exactly this reason: a failed historical query must not blank the
    /// card's bonded list, only leave that node's Last Reward unset.
    func testChurnsFetchFailurePropagatesRatherThanReturningEmptyHistory() async {
        let stub = StubBondsHTTPClient(churns: nil, nodeDetailsByHeight: [:])
        let service = THORChainAPIService(httpClient: stub)

        do {
            _ = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, now: fixtureNow)
            XCTFail("expected the churns failure to propagate")
        } catch {
            // Any thrown error is the contract; the specific type is HTTPClient's.
        }
    }

    /// A failed query (199 is missing from the fixture, so the stub 404s) keeps
    /// the rewards that loaded before it.
    func testAQueryFailureKeepsTheRewardsLoadedBeforeIt() async throws {
        let stub = StubBondsHTTPClient(
            churns: churnsJSON([(300, 300_000_000_000), (200, 200_000_000_000), (100, 100_000_000_000)]),
            nodeDetailsByHeight: [
                299: nodeDetailsJSON(currentAward: 1000, feeBps: 0, providers: [(myAddress, 50), ("other", 50)])
            ]
        )
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, now: fixtureNow)

        XCTAssertEqual(history.map(\.id), [300])
    }

    /// Nothing loaded is an error, not an empty history.
    func testEveryQueryFailingStillThrows() async {
        let stub = StubBondsHTTPClient(
            churns: churnsJSON([(300, 300_000_000_000), (200, 200_000_000_000)]),
            nodeDetailsByHeight: [:]
        )
        let service = THORChainAPIService(httpClient: stub)

        do {
            _ = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, now: fixtureNow)
            XCTFail("with no reward loaded the failure must surface")
        } catch {
            // Expected.
        }
    }

    /// A saved reward is never re-queried: 299 is absent from the fixture, so
    /// querying it would fail the walk.
    func testSavedRewardsAreNotQueriedAgain() async throws {
        let stub = StubBondsHTTPClient(
            churns: churnsJSON([(300, 300_000_000_000), (200, 200_000_000_000), (100, 100_000_000_000)]),
            nodeDetailsByHeight: [
                199: nodeDetailsJSON(currentAward: 1000, feeBps: 0, providers: [(myAddress, 50), ("other", 50)]),
                99: nodeDetailsJSON(currentAward: 1000, feeBps: 0, providers: [("other", 100)])
            ]
        )
        let service = THORChainAPIService(httpClient: stub)
        let saved = BondRewardHistoryEntry(churnHeight: 300, churnDate: Date(timeIntervalSince1970: 300), amount: 777)

        let history = try await service.getBondRewardHistory(
            nodeAddress: nodeAddress,
            myBondAddress: myAddress,
            known: [300: saved],
            now: fixtureNow
        )

        XCTAssertEqual(history.map(\.id), [300, 200])
        XCTAssertEqual(history.map(\.amount), [777, 500])
    }

    /// Cancelling before batch 1 resolves must prevent every later batch
    /// from ever being scheduled. Deterministic, not timed: the stub
    /// suspends every node-details request until the test releases it, and
    /// — critically — never throws on cancellation itself (unlike a plain
    /// `Task.sleep`, which cancels itself and would make this pass even
    /// with no cancellation handling at all in `getBondRewardHistory`). The
    /// test waits for exactly `concurrency` requests to arrive (all of
    /// batch 1, in flight simultaneously), cancels, THEN releases them —
    /// so the only things that can stop batch 2/3 from running are
    /// `getBondRewardHistory`'s own `Task.checkCancellation()` before each
    /// batch and `withBoundedConcurrency`'s fail-closed throw once a batch
    /// observes the cancellation. Either mechanism alone is enough to pass
    /// this test; it fails only if BOTH are removed, which is what "prove
    /// it: RED by mutation" below actually verifies for this file — the two
    /// are intentionally overlapping defenses for adjacent race windows,
    /// not independently isolable from outside the function.
    func testCancellationStopsSchedulingFurtherBatches() async throws {
        // 15 churns, all continuously bonded -> 3 batches of 5 if uncancelled.
        let churnCount = 15
        let churns = (1...churnCount).map { (height: $0 * 100, dateNanos: Int64($0) * 100_000_000_000) }
        let nodeDetails = nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [(myAddress, 1)])
        let stub = GatedCountingBondsHTTPClient(
            churns: churnsJSON(churns),
            nodeDetailsData: nodeDetails,
            arrivalTarget: BondRewardHistoryConfig.concurrency
        )
        let service = THORChainAPIService(httpClient: stub)

        let task = Task {
            try? await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, now: fixtureNow)
        }

        // All of batch 1 (one request per concurrency slot) is now in
        // flight and suspended — batch 2 cannot have started yet, since
        // batch 1's own `withBoundedConcurrency` call hasn't returned.
        // Bounded rather than an unbounded `await`: a regression that hangs
        // (rather than failing) must still fail this test in finite time,
        // not wedge the whole suite.
        let arrived = expectation(description: "batch 1 fully arrived")
        Task { await stub.waitForArrivals(); arrived.fulfill() }
        await fulfillment(of: [arrived], timeout: 5)

        task.cancel()
        await stub.release()

        let completed = expectation(description: "getBondRewardHistory returned after cancellation")
        Task { _ = await task.value; completed.fulfill() }
        await fulfillment(of: [completed], timeout: 10)

        let requestCount = await stub.totalRequestCount
        XCTAssertEqual(requestCount, BondRewardHistoryConfig.concurrency, "cancellation must have prevented every later batch from ever being scheduled")
    }

    // MARK: - Gaps: churns too old to read that were never saved

    private let gapNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func nanos(daysAgo: Double) -> Int64 {
        Int64((gapNow.timeIntervalSince1970 - daysAgo * 24 * 60 * 60) * 1_000_000_000)
    }

    private func savedRow(_ height: Int) -> BondRewardHistoryEntry {
        BondRewardHistoryEntry(churnHeight: height, churnDate: Date(timeIntervalSince1970: 0), amount: 7)
    }

    /// `provider` is set when an operator (`sender`) unbonds a provider: THORChain puts it last in the memo.
    private func unbondsJSON(_ unbonds: [(height: Int, nodeAddress: String, sender: String, provider: String?)]) -> Data {
        let actions = unbonds.map {
            let memo = "UNBOND:\($0.nodeAddress):1" + ($0.provider.map { ":\($0)" } ?? "")
            return """
            {"height":"\($0.height)","type":"unbond","status":"success","date":"0","pools":[],\
            "in":[{"address":"\($0.sender)","coins":[],"txID":"TX"}],"out":[],\
            "metadata":{"bond":{"memo":"\(memo)","nodeAddress":"\($0.nodeAddress)"}}}
            """
        }
        return Data("{\"actions\":[\(actions.joined(separator: ","))],\"meta\":{\"nextPageToken\":\"\",\"prevPageToken\":\"\"}}".utf8)
    }

    /// 400 is read (1 day old), 300 is a gap (20 days, unsaved), 200 and 100 are saved.
    private func gapStub(unbondActions: Data?) -> StubBondsHTTPClient {
        StubBondsHTTPClient(
            churns: churnsJSON([(400, nanos(daysAgo: 1)), (300, nanos(daysAgo: 20)), (200, nanos(daysAgo: 25)), (100, nanos(daysAgo: 30))]),
            nodeDetailsByHeight: [399: nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [(myAddress, 1)])],
            unbondActions: unbondActions
        )
    }

    func testAGapWithNoUnbondIsBridgedToTheSavedRowsBehindIt() async throws {
        let stub = gapStub(unbondActions: unbondsJSON([]))
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(
            nodeAddress: nodeAddress,
            myBondAddress: myAddress,
            known: [200: savedRow(200), 100: savedRow(100)],
            now: gapNow
        )

        XCTAssertEqual(history.map(\.id), [400, 200, 100])
        XCTAssertEqual(stub.actionsRequestCount, 1)
        XCTAssertEqual(stub.lastActionsQuery?["address"] as? String, nodeAddress)
        XCTAssertEqual(stub.lastActionsQuery?["type"] as? String, "unbond")
    }

    func testAnUnbondFromThisNodeInsideAGapCutsTheHistoryThere() async throws {
        // 500 read; gap 400; 300 saved; gap 250; 200 saved. The unbond at 260 is inside the second gap.
        let stub = StubBondsHTTPClient(
            churns: churnsJSON([
                (500, nanos(daysAgo: 1)), (400, nanos(daysAgo: 20)), (300, nanos(daysAgo: 22)),
                (250, nanos(daysAgo: 24)), (200, nanos(daysAgo: 26))
            ]),
            nodeDetailsByHeight: [499: nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [(myAddress, 1)])],
            unbondActions: unbondsJSON([(260, nodeAddress, myAddress, nil)])
        )
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(
            nodeAddress: nodeAddress,
            myBondAddress: myAddress,
            known: [300: savedRow(300), 200: savedRow(200)],
            now: gapNow
        )

        XCTAssertEqual(history.map(\.id), [500, 300])
        XCTAssertEqual(stub.actionsRequestCount, 1)
    }

    func testAGapIsBridgedWhenTheOnlyUnbondWasFromAnotherNode() async throws {
        let stub = gapStub(unbondActions: unbondsJSON([(350, "thor1othernode", myAddress, nil)]))
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(
            nodeAddress: nodeAddress,
            myBondAddress: myAddress,
            known: [200: savedRow(200), 100: savedRow(100)],
            now: gapNow
        )

        XCTAssertEqual(history.map(\.id), [400, 200, 100])
    }

    func testAnOperatorUnbondOfThisProviderInsideAGapCutsTheHistoryThere() async throws {
        let stub = gapStub(unbondActions: unbondsJSON([(350, nodeAddress, "thor1operator", myAddress)]))
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(
            nodeAddress: nodeAddress,
            myBondAddress: myAddress,
            known: [200: savedRow(200), 100: savedRow(100)],
            now: gapNow
        )

        XCTAssertEqual(history.map(\.id), [400])
        XCTAssertEqual(stub.lastActionsQuery?["address"] as? String, nodeAddress, "operator unbonds are only indexed by node")
    }

    func testAnOperatorUnbondNamingThisProviderInUppercaseCutsTheHistory() async throws {
        let stub = gapStub(unbondActions: unbondsJSON([(350, nodeAddress, "thor1operator", myAddress.uppercased())]))

        let history = try await THORChainAPIService(httpClient: stub).getBondRewardHistory(
            nodeAddress: nodeAddress,
            myBondAddress: myAddress,
            known: [200: savedRow(200), 100: savedRow(100)],
            now: gapNow
        )

        XCTAssertEqual(history.map(\.id), [400])
    }

    func testAGapIsBridgedWhenOnlyAnotherProviderUnbondedFromThisNode() async throws {
        let stub = gapStub(unbondActions: unbondsJSON([
            (350, nodeAddress, "thor1otherprovider", nil),
            (340, nodeAddress, "thor1operator", "thor1otherprovider")
        ]))
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(
            nodeAddress: nodeAddress,
            myBondAddress: myAddress,
            known: [200: savedRow(200), 100: savedRow(100)],
            now: gapNow
        )

        XCTAssertEqual(history.map(\.id), [400, 200, 100])
    }

    func testAGapIsBridgedWhenThisAddressAsOperatorOnlyUnbondedAnotherProvider() async throws {
        let stub = gapStub(unbondActions: unbondsJSON([(350, nodeAddress, myAddress, "thor1otherprovider")]))
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(
            nodeAddress: nodeAddress,
            myBondAddress: myAddress,
            known: [200: savedRow(200), 100: savedRow(100)],
            now: gapNow
        )

        XCTAssertEqual(history.map(\.id), [400, 200, 100])
    }

    /// A saved row reads the block before its churn, so an unbond in the older churn's
    /// own block is inside the gap, and one in the newer churn's block is not.
    func testAnUnbondInTheOlderChurnsBlockCutsAndOneInTheNewerChurnsBlockDoesNot() async throws {
        let known = [200: savedRow(200), 100: savedRow(100)]
        let atOlder = gapStub(unbondActions: unbondsJSON([(200, nodeAddress, myAddress, nil)]))
        let atNewer = gapStub(unbondActions: unbondsJSON([(400, nodeAddress, myAddress, nil)]))

        let cut = try await THORChainAPIService(httpClient: atOlder)
            .getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, known: known, now: gapNow)
        let bridged = try await THORChainAPIService(httpClient: atNewer)
            .getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, known: known, now: gapNow)

        XCTAssertEqual(cut.map(\.id), [400])
        XCTAssertEqual(bridged.map(\.id), [400, 200, 100])
    }

    /// One request bounded to the gaps: from the saved churn below the lowest gap
    /// (inclusive) to the known churn above the highest gap (exclusive).
    func testTheUnbondLookupIsBoundedToTheGaps() async throws {
        // 500 read; gap 400; 300 saved; gap 250; 200, 100 saved.
        let stub = StubBondsHTTPClient(
            churns: churnsJSON([
                (500, nanos(daysAgo: 1)), (400, nanos(daysAgo: 20)), (300, nanos(daysAgo: 22)),
                (250, nanos(daysAgo: 24)), (200, nanos(daysAgo: 26)), (100, nanos(daysAgo: 28))
            ]),
            nodeDetailsByHeight: [499: nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [(myAddress, 1)])],
            unbondActions: unbondsJSON([])
        )

        let history = try await THORChainAPIService(httpClient: stub).getBondRewardHistory(
            nodeAddress: nodeAddress,
            myBondAddress: myAddress,
            known: [300: savedRow(300), 200: savedRow(200), 100: savedRow(100)],
            now: gapNow
        )

        XCTAssertEqual(history.map(\.id), [500, 300, 200, 100])
        XCTAssertEqual(stub.actionsRequestCount, 1)
        XCTAssertEqual(stub.lastActionsQuery?["fromHeight"] as? Int, 200)
        XCTAssertEqual(stub.lastActionsQuery?["height"] as? Int, 500)
    }

    func testAnOpenEndedTopGapLeavesTheUnbondLookupUnboundedAbove() async throws {
        // The newest churn is itself a gap, so nothing known sits above it.
        let stub = StubBondsHTTPClient(
            churns: churnsJSON([(400, nanos(daysAgo: 20)), (300, nanos(daysAgo: 22))]),
            nodeDetailsByHeight: [:],
            unbondActions: unbondsJSON([])
        )

        let history = try await THORChainAPIService(httpClient: stub).getBondRewardHistory(
            nodeAddress: nodeAddress,
            myBondAddress: myAddress,
            known: [300: savedRow(300)],
            now: gapNow
        )

        XCTAssertEqual(history.map(\.id), [300])
        XCTAssertEqual(stub.lastActionsQuery?["fromHeight"] as? Int, 300)
        XCTAssertNil(stub.lastActionsQuery?["height"])
    }

    func testAFailedUnbondLookupCutsTheHistoryAtTheGapWithoutAnError() async throws {
        let stub = gapStub(unbondActions: nil)
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(
            nodeAddress: nodeAddress,
            myBondAddress: myAddress,
            known: [200: savedRow(200), 100: savedRow(100)],
            now: gapNow
        )

        XCTAssertEqual(history.map(\.id), [400])
        XCTAssertEqual(stub.actionsRequestCount, 1)
    }
}

/// Suspends every node-details request until released, and counts them —
/// deliberately ignores cancellation itself (unlike `Task.sleep`), so a
/// passing test proves `getBondRewardHistory`'s OWN cancellation handling
/// is what stopped later batches, not the stub aborting on its own.
///
/// Parks each suspended request's continuation in a QUEUE, not a single
/// property: `arrivalTarget` requests suspend concurrently (one per
/// bounded-concurrency slot), and a single `var continuation` would be
/// silently overwritten by the 2nd..Nth arrival, leaking the 1st..(N-1)th
/// forever — the exact "SWIFT TASK CONTINUATION MISUSE: leaked its
/// continuation without resuming it" hang this actor used to cause.
/// `release()` drains and resumes every queued continuation, so nothing
/// parked here can ever be left unresumed.
private actor GatedCountingBondsHTTPClient: HTTPClientProtocol {
    private let churns: Data
    private let nodeDetailsData: Data
    private let arrivalTarget: Int
    private var arrivedCount = 0
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var isReleased = false
    private var pendingReleaseContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var totalRequestCount = 0

    init(churns: Data, nodeDetailsData: Data, arrivalTarget: Int) {
        self.churns = churns
        self.nodeDetailsData = nodeDetailsData
        self.arrivalTarget = arrivalTarget
    }

    /// Returns once `arrivalTarget` node-details requests have arrived and
    /// are suspended (never once any have completed).
    func waitForArrivals() async {
        guard arrivedCount < arrivalTarget else { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    /// Resumes every request parked so far, and lets any future one resolve
    /// immediately too. Also unblocks a still-pending `waitForArrivals()` —
    /// if the expected count is never reached (a regression stops requests
    /// from arriving at all), the test's `fulfillment(of:timeout:)` still
    /// times out and fails as expected, but without this, the `Task`
    /// wrapping `waitForArrivals()` would stay suspended forever after the
    /// test itself has already moved on and finished.
    func release() {
        isReleased = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        let continuations = pendingReleaseContinuations
        pendingReleaseContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        if target.path == "/churns" {
            let url = target.baseURL.appendingPathComponent(target.path)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return HTTPResponse(data: churns, response: response)
        }

        totalRequestCount += 1
        arrivedCount += 1
        if arrivedCount == arrivalTarget {
            arrivalContinuation?.resume()
            arrivalContinuation = nil
        }

        if !isReleased {
            await withCheckedContinuation { continuation in
                pendingReleaseContinuations.append(continuation)
            }
        }

        let url = target.baseURL.appendingPathComponent(target.path)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: nodeDetailsData, response: response)
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> { // swiftlint:disable:this async_without_await
        throw HTTPError.statusCode(500, Data())
    }
}

// MARK: - Test double

/// Keyed by path, with `?height=` further disambiguating node-details calls
/// — several historical snapshots of the same node all share one path.
private final class StubBondsHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let churns: Data?
    private let nodeDetailsByHeight: [Int: Data]
    /// Midgard's unbond actions page; `nil` fails the request.
    private let unbondActions: Data?
    private let lock = NSLock()
    private var actionsQueries: [[String: Any]] = []

    init(churns: Data?, nodeDetailsByHeight: [Int: Data], unbondActions: Data? = nil) {
        self.churns = churns
        self.nodeDetailsByHeight = nodeDetailsByHeight
        self.unbondActions = unbondActions
    }

    var actionsRequestCount: Int { lock.withLock { actionsQueries.count } }

    var lastActionsQuery: [String: Any]? { lock.withLock { actionsQueries.last } }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        let data = try responseData(for: target)
        let url = target.baseURL.appendingPathComponent(target.path)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: data, response: response)
    }

    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> { // swiftlint:disable:this async_without_await
        throw HTTPError.statusCode(500, Data())
    }

    private func responseData(for target: TargetType) throws -> Data {
        if target.path == "/churns" {
            guard let churns else { throw HTTPError.statusCode(500, Data()) }
            return churns
        }
        if target.path == "/actions" {
            if case let .requestParameters(params, _) = target.task {
                lock.withLock { actionsQueries.append(params) }
            }
            guard let unbondActions else { throw HTTPError.statusCode(500, Data()) }
            return unbondActions
        }
        if target.path.hasPrefix("/thorchain/node/") {
            guard
                case let .requestParameters(params, _) = target.task,
                let height = params["height"] as? Int,
                let data = nodeDetailsByHeight[height]
            else {
                throw HTTPError.statusCode(404, Data())
            }
            return data
        }
        throw HTTPError.statusCode(501, Data())
    }
}
