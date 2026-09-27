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

    /// Cancelling the caller's task must stop the NEXT batch from ever being
    /// scheduled — `withBoundedConcurrency` alone only stops scheduling
    /// WITHIN one batch, so without the `Task.checkCancellation()` at the
    /// top of the outer loop, a vault bonded continuously across 15 churns
    /// would still issue every one of the 3 batches even after cancellation.
    func testCancellationStopsSchedulingFurtherBatches() async {
        // 15 churns, all continuously bonded -> 3 batches of 5 if uncancelled.
        let churnCount = 15
        let churns = (1...churnCount).map { (height: $0 * 100, dateNanos: Int64($0) * 100_000_000_000) }
        var byHeight: [Int: Data] = [:]
        for churn in churns {
            byHeight[churn.height - 1] = nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [(myAddress, 1)])
        }
        let stub = CountingDelayedBondsHTTPClient(
            churns: churnsJSON(churns),
            nodeDetailsByHeight: byHeight,
            delayNanos: 30_000_000
        )
        let service = THORChainAPIService(httpClient: stub)

        let task = Task {
            try? await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress)
        }
        // Let the first batch (5 concurrent requests) start, then cancel
        // before it — or any later batch — would otherwise finish.
        try? await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()
        _ = await task.value

        let requestCount = await stub.nodeDetailsRequestCount
        XCTAssertLessThan(requestCount, churnCount, "cancellation must have prevented at least the later batches from being scheduled")
    }
}

/// Delays every node-details response and counts how many were issued —
/// used to prove cancellation actually stops later batches rather than
/// merely letting the whole 20-request walk complete quietly in the
/// background.
private actor CountingDelayedBondsHTTPClient: HTTPClientProtocol {
    private let churns: Data
    private let nodeDetailsByHeight: [Int: Data]
    private let delayNanos: UInt64
    private(set) var nodeDetailsRequestCount = 0

    init(churns: Data, nodeDetailsByHeight: [Int: Data], delayNanos: UInt64) {
        self.churns = churns
        self.nodeDetailsByHeight = nodeDetailsByHeight
        self.delayNanos = delayNanos
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        if target.path == "/churns" {
            let url = target.baseURL.appendingPathComponent(target.path)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return HTTPResponse(data: churns, response: response)
        }

        nodeDetailsRequestCount += 1
        try await Task.sleep(nanoseconds: delayNanos)

        guard
            case let .requestParameters(params, _) = target.task,
            let height = params["height"] as? Int,
            let data = nodeDetailsByHeight[height]
        else {
            throw HTTPError.statusCode(404, Data())
        }
        let url = target.baseURL.appendingPathComponent(target.path)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: data, response: response)
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
