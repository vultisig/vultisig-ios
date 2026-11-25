//
//  MayaChainBondRewardHistoryTests.swift
//  VultisigAppTests
//
//  Maya mirror of THORChainBondRewardHistoryTests — same `getBondRewardHistory`
//  contract, but Maya's provider bond comes from summing `pools` rather than
//  a single `bond` string, and Maya previously had no churns endpoint at all.
//

import XCTest
@testable import VultisigApp

final class MayaChainBondRewardHistoryTests: XCTestCase {

    private let myAddress = "maya1myaddress"
    private let nodeAddress = "maya1nodeaddress"
    /// Every fixture churn is within the fetch window of this moment.
    private let fixtureNow = Date(timeIntervalSince1970: 2_000)

    private func churnsJSON(_ churns: [(height: Int, dateNanos: Int64)]) -> Data {
        let entries = churns.map { "{\"height\":\"\($0.height)\",\"date\":\"\($0.dateNanos)\"}" }
        return Data("[\(entries.joined(separator: ","))]".utf8)
    }

    /// `bond` in Maya's `BondProvider` is a computed sum of `pools`, so the
    /// fixture puts each provider's whole bond into one pool.
    private func nodeDetailsJSON(currentAward: Int, feeBps: Int, providers: [(address: String, bond: Int)]) -> Data {
        let providersJSON = providers.map {
            "{\"bond_address\":\"\($0.address)\",\"bonded\":true,\"reward\":\"0\",\"pools\":{\"THOR.RUNE\":\"\($0.bond)\"}}"
        }
        return Data("""
        {
          "node_address": "\(nodeAddress)",
          "status": "Active",
          "bond": "0",
          "bond_providers": {
            "node_operator_fee": "\(feeBps)",
            "providers": [\(providersJSON.joined(separator: ","))]
          },
          "reward": "\(currentAward)"
        }
        """.utf8)
    }

    func testStopsAtFirstChurnWhereAddressIsMissingFromBondProviders() async throws {
        let stub = StubMayaBondsHTTPClient(
            churns: churnsJSON([(300, 300_000_000_000), (200, 200_000_000_000), (100, 100_000_000_000)]),
            nodeDetailsByHeight: [
                299: nodeDetailsJSON(currentAward: 1000, feeBps: 0, providers: [(myAddress, 50), ("other", 50)]),
                199: nodeDetailsJSON(currentAward: 1000, feeBps: 0, providers: [(myAddress, 50), ("other", 50)]),
                99: nodeDetailsJSON(currentAward: 1000, feeBps: 0, providers: [("other", 100)])
            ]
        )
        let service = MayaChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, now: fixtureNow)

        XCTAssertEqual(history.map(\.id), [300, 200])
        XCTAssertEqual(history.map(\.amount), [500, 500])
    }

    func testNoPriorChurnWhileBondedReturnsEmptyHistory() async throws {
        let stub = StubMayaBondsHTTPClient(
            churns: churnsJSON([(100, 1)]),
            nodeDetailsByHeight: [99: nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [("other", 1)])]
        )
        let service = MayaChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, now: fixtureNow)

        XCTAssertTrue(history.isEmpty)
    }

    /// Maya had no `getChurns()` at all before this feature — confirms the
    /// new endpoint wiring actually reaches the churns list.
    func testChurnsFetchFailurePropagates() async {
        let stub = StubMayaBondsHTTPClient(churns: nil, nodeDetailsByHeight: [:])
        let service = MayaChainAPIService(httpClient: stub)

        do {
            _ = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, now: fixtureNow)
            XCTFail("expected the churns failure to propagate")
        } catch {
            // Any thrown error is the contract.
        }
    }

    /// Mirrors the THORChain case: a failed query keeps the rewards that loaded
    /// before it.
    func testAQueryFailureKeepsTheRewardsLoadedBeforeIt() async throws {
        let stub = StubMayaBondsHTTPClient(
            churns: churnsJSON([(300, 300_000_000_000), (200, 200_000_000_000), (100, 100_000_000_000)]),
            nodeDetailsByHeight: [
                299: nodeDetailsJSON(currentAward: 1000, feeBps: 0, providers: [(myAddress, 50), ("other", 50)])
            ]
        )
        let service = MayaChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, now: fixtureNow)

        XCTAssertEqual(history.map(\.id), [300])
    }

    func testAGapWithNoUnbondIsBridgedToTheSavedRowsBehindIt() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let nanos = { (daysAgo: Double) in Int64((now.timeIntervalSince1970 - daysAgo * 24 * 60 * 60) * 1_000_000_000) }
        let saved = BondRewardHistoryEntry(churnHeight: 200, churnDate: Date(timeIntervalSince1970: 0), amount: 7)
        let stub = StubMayaBondsHTTPClient(
            churns: churnsJSON([(400, nanos(1)), (300, nanos(20)), (200, nanos(25))]),
            nodeDetailsByHeight: [399: nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [(myAddress, 1)])],
            unbondActions: Data(#"{"actions":[],"meta":{"nextPageToken":"","prevPageToken":""}}"#.utf8)
        )
        let service = MayaChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(
            nodeAddress: nodeAddress,
            myBondAddress: myAddress,
            known: [200: saved],
            now: now
        )

        XCTAssertEqual(history.map(\.id), [400, 200])
    }

    // MARK: - Unbond memo shapes seen live on MayaChain

    private let gapNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func gapHistory(memo: String, sender: String) async throws -> [Int] {
        let nanos = { (daysAgo: Double) in Int64((self.gapNow.timeIntervalSince1970 - daysAgo * 24 * 60 * 60) * 1_000_000_000) }
        let unbond = """
        {"actions":[{"height":"350","type":"unbond","status":"success","date":"0","pools":[],\
        "in":[{"address":"\(sender)","coins":[],"txID":"TX"}],"out":[],\
        "metadata":{"bond":{"memo":"\(memo)","nodeAddress":"\(nodeAddress)"}}}],\
        "meta":{"nextPageToken":"","prevPageToken":""}}
        """
        let stub = StubMayaBondsHTTPClient(
            churns: churnsJSON([(400, nanos(1)), (300, nanos(20)), (200, nanos(25))]),
            nodeDetailsByHeight: [399: nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [(myAddress, 1)])],
            unbondActions: Data(unbond.utf8)
        )
        let saved = BondRewardHistoryEntry(churnHeight: 200, churnDate: Date(timeIntervalSince1970: 0), amount: 7)
        return try await MayaChainAPIService(httpClient: stub)
            .getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress, known: [200: saved], now: gapNow)
            .map(\.id)
    }

    /// Like height 19195939: the node is the last memo field and the provider sent it.
    func testTheProvidersOwnUnbondWithTheNodeLastInTheMemoCutsTheHistory() async throws {
        let history = try await gapHistory(memo: "UNBOND:BTC.BTC:455300000000000:\(nodeAddress)", sender: myAddress)

        XCTAssertEqual(history, [400])
    }

    /// Like height 16651453: the operator sent it and named the provider fifth.
    func testAnOperatorUnbondNamingThisProviderFifthCutsTheHistory() async throws {
        let history = try await gapHistory(memo: "UNBOND:::\(nodeAddress):\(myAddress)", sender: "maya1operator")

        XCTAssertEqual(history, [400])
    }

    func testAnOperatorUnbondNamingAnotherProviderFifthIsBridged() async throws {
        let history = try await gapHistory(memo: "UNBOND:::\(nodeAddress):maya1otherprovider", sender: myAddress)

        XCTAssertEqual(history, [400, 200])
    }
}

private final class StubMayaBondsHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let churns: Data?
    private let nodeDetailsByHeight: [Int: Data]
    /// Midgard's unbond actions page; `nil` fails the request.
    private let unbondActions: Data?

    init(churns: Data?, nodeDetailsByHeight: [Int: Data], unbondActions: Data? = nil) {
        self.churns = churns
        self.nodeDetailsByHeight = nodeDetailsByHeight
        self.unbondActions = unbondActions
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
        if target.path == "/actions" {
            guard let unbondActions else { throw HTTPError.statusCode(500, Data()) }
            return unbondActions
        }
        if target.path.hasPrefix("/mayachain/node/") {
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
