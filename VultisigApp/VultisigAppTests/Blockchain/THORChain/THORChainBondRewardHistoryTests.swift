//
//  THORChainBondRewardHistoryTests.swift
//  VultisigAppTests
//
//  `getBondRewardHistory` drives the rewards sheet: stop-at-first-gap,
//  the 20-churn cap, newest-first ordering, ns->date conversion, and the
//  no-prior-churn case all live here. No real network — `StubBondsHTTPClient`
//  is keyed by path + `height` query param so each historical snapshot can
//  return its own fixture.
//

import XCTest
@testable import VultisigApp

final class THORChainBondRewardHistoryTests: XCTestCase {

    private let myAddress = "thor1myaddress"
    private let nodeAddress = "thor1nodeaddress"

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

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress)

        XCTAssertEqual(history.map(\.churnHeight), [300, 200], "stops before the churn the vault wasn't bonded for yet")
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

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress)

        XCTAssertEqual(history.map(\.churnHeight), [300, 200, 100])
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

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress)

        let expected = Date(timeIntervalSince1970: Double(nanos) / 1_000_000_000)
        XCTAssertEqual(history.first?.churnDate.timeIntervalSince1970 ?? 0, expected.timeIntervalSince1970, accuracy: 0.001)
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

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, limit: 3)

        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.map(\.churnHeight), [500, 400, 300], "the 3 newest, not an arbitrary 3")
    }

    /// Bonded now, but never a provider at any past churn — the sheet must
    /// be able to render Upcoming-only.
    func testNoPriorChurnWhileBondedReturnsEmptyHistory() async throws {
        let stub = StubBondsHTTPClient(
            churns: churnsJSON([(100, 1)]),
            nodeDetailsByHeight: [99: nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [("other", 1)])]
        )
        let service = THORChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress)

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
            _ = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress)
            XCTFail("expected the churns failure to propagate")
        } catch {
            // Any thrown error is the contract; the specific type is HTTPClient's.
        }
    }

    /// A transient network/decode failure on ONE historical height must not
    /// be read the same as "confirmed not a provider here" — that would
    /// silently truncate (or empty out) otherwise-valid history. Height 199
    /// is simply missing from the fixture (simulating a 404/network error),
    /// distinct from height 99 which DOES decode successfully but omits the
    /// address — only the latter is a legitimate stop signal.
    func testTransientQueryFailureThrowsRatherThanTruncatingHistory() async {
        let stub = StubBondsHTTPClient(
            churns: churnsJSON([(300, 300_000_000_000), (200, 200_000_000_000), (100, 100_000_000_000)]),
            nodeDetailsByHeight: [
                299: nodeDetailsJSON(currentAward: 1000, feeBps: 0, providers: [(myAddress, 50), ("other", 50)])
                // 199 intentionally absent -> the stub throws 404 for it.
                // 99 is also absent, so it would throw too if ever reached.
            ]
        )
        let service = THORChainAPIService(httpClient: stub)

        do {
            _ = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress)
            XCTFail("a query failure must propagate, not silently truncate to the first successful entry")
        } catch {
            // Expected: the ambiguous failure is surfaced rather than guessed at.
        }
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
            try? await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress)
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

    init(churns: Data?, nodeDetailsByHeight: [Int: Data]) {
        self.churns = churns
        self.nodeDetailsByHeight = nodeDetailsByHeight
    }

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
