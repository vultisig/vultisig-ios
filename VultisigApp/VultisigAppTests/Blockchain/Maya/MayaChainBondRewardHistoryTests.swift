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

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress)

        XCTAssertEqual(history.map(\.churnHeight), [300, 200])
        XCTAssertEqual(history.map(\.amount), [500, 500])
    }

    func testNoPriorChurnWhileBondedReturnsEmptyHistory() async throws {
        let stub = StubMayaBondsHTTPClient(
            churns: churnsJSON([(100, 1)]),
            nodeDetailsByHeight: [99: nodeDetailsJSON(currentAward: 10, feeBps: 0, providers: [("other", 1)])]
        )
        let service = MayaChainAPIService(httpClient: stub)

        let history = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress)

        XCTAssertTrue(history.isEmpty)
    }

    /// Maya had no `getChurns()` at all before this feature — confirms the
    /// new endpoint wiring actually reaches the churns list.
    func testChurnsFetchFailurePropagates() async {
        let stub = StubMayaBondsHTTPClient(churns: nil, nodeDetailsByHeight: [:])
        let service = MayaChainAPIService(httpClient: stub)

        do {
            _ = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress)
            XCTFail("expected the churns failure to propagate")
        } catch {
            // Any thrown error is the contract.
        }
    }

    /// Mirrors THORChainBondRewardHistoryTests' identical case: a query
    /// failure (height 199 missing from the fixture) must not be read the
    /// same as "confirmed not a provider" — it should throw, not truncate.
    func testTransientQueryFailureThrowsRatherThanTruncatingHistory() async {
        let stub = StubMayaBondsHTTPClient(
            churns: churnsJSON([(300, 300_000_000_000), (200, 200_000_000_000), (100, 100_000_000_000)]),
            nodeDetailsByHeight: [
                299: nodeDetailsJSON(currentAward: 1000, feeBps: 0, providers: [(myAddress, 50), ("other", 50)])
            ]
        )
        let service = MayaChainAPIService(httpClient: stub)

        do {
            _ = try await service.getBondRewardHistory(nodeAddress: nodeAddress, myBondAddress: myAddress)
            XCTFail("a query failure must propagate, not silently truncate to the first successful entry")
        } catch {
            // Expected.
        }
    }
}

private final class StubMayaBondsHTTPClient: HTTPClientProtocol, @unchecked Sendable {
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
