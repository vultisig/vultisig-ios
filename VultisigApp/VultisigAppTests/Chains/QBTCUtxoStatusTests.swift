//
//  QBTCUtxoStatusTests.swift
//  VultisigAppTests
//
//  Tests for the per-UTXO chain-state filter that drops already-claimed
//  and not-yet-indexed UTXOs from the selection screen. Covers all three
//  documented response shapes (claimable / claimed / 404), plus the
//  fail-open path so a transient chain blip doesn't hide a UTXO the user
//  can see in their BTC wallet.
//

@testable import VultisigApp
import XCTest

final class QBTCUtxoStatusTests: XCTestCase {
    private static let txid1 = String(repeating: "aa", count: 32)
    private static let txid2 = String(repeating: "bb", count: 32)
    private static let txid3 = String(repeating: "cc", count: 32)

    // MARK: - fetchUtxoStatus

    func testFetchUtxoStatusDecodesClaimable() async throws {
        let json = #"{"utxo":{"txid":"\#(Self.txid1)","entitled_amount":"100000"}}"#
        let mock = MockUtxoHTTPClient(routes: [
            "/qbtc/v1/utxo/\(Self.txid1)/0": .ok(body: json)
        ])
        let service = QBTCChainService(httpClient: mock)

        let status = try await service.fetchUtxoStatus(txid: Self.txid1, vout: 0)

        XCTAssertEqual(status, .claimable(entitledAmount: 100_000))
    }

    func testFetchUtxoStatusReportsClaimedWhenEntitledAmountIsZero() async throws {
        let json = #"{"utxo":{"txid":"\#(Self.txid1)","entitled_amount":"0"}}"#
        let mock = MockUtxoHTTPClient(routes: [
            "/qbtc/v1/utxo/\(Self.txid1)/0": .ok(body: json)
        ])
        let service = QBTCChainService(httpClient: mock)

        let status = try await service.fetchUtxoStatus(txid: Self.txid1, vout: 0)

        XCTAssertEqual(status, .claimed)
    }

    func testFetchUtxoStatusReportsNotIndexedOn404() async throws {
        let mock = MockUtxoHTTPClient(routes: [
            "/qbtc/v1/utxo/\(Self.txid1)/0": .notFound
        ])
        let service = QBTCChainService(httpClient: mock)

        let status = try await service.fetchUtxoStatus(txid: Self.txid1, vout: 0)

        XCTAssertEqual(status, .notIndexed)
    }

    // MARK: - filterClaimable

    func testFilterClaimableDropsClaimedAndNotIndexed() async {
        let utxos = [
            ClaimableUtxo(txid: Self.txid1, vout: 0, amount: 100_000), // claimable
            ClaimableUtxo(txid: Self.txid2, vout: 1, amount: 200_000), // claimed
            ClaimableUtxo(txid: Self.txid3, vout: 2, amount: 300_000)  // not indexed
        ]
        let mock = MockUtxoHTTPClient(routes: [
            "/qbtc/v1/utxo/\(Self.txid1)/0": .ok(body: #"{"utxo":{"txid":"\#(Self.txid1)","entitled_amount":"100000"}}"#),
            "/qbtc/v1/utxo/\(Self.txid2)/1": .ok(body: #"{"utxo":{"txid":"\#(Self.txid2)","entitled_amount":"0"}}"#),
            "/qbtc/v1/utxo/\(Self.txid3)/2": .notFound
        ])
        let service = QBTCChainService(httpClient: mock)

        let filtered = await service.filterClaimable(utxos)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].txid, Self.txid1)
        XCTAssertEqual(filtered[0].vout, 0)
    }

    func testFilterClaimableReplacesAmountWithEntitledAmount() async {
        // Blockchair reports 500_000; chain says only 400_000 is entitled.
        // The total in the UI must reflect what the chain will mint, so we
        // overwrite the amount on the way through.
        let utxos = [ClaimableUtxo(txid: Self.txid1, vout: 0, amount: 500_000)]
        let mock = MockUtxoHTTPClient(routes: [
            "/qbtc/v1/utxo/\(Self.txid1)/0": .ok(body: #"{"utxo":{"txid":"\#(Self.txid1)","entitled_amount":"400000"}}"#)
        ])
        let service = QBTCChainService(httpClient: mock)

        let filtered = await service.filterClaimable(utxos)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].amount, 400_000)
    }

    func testFilterClaimableFailsOpenOnTransientError() async {
        // 5xx / decode errors must NOT hide the UTXO — better to let the
        // user attempt the claim than drop something they can see in their
        // BTC wallet because of a flaky chain RPC.
        let utxos = [
            ClaimableUtxo(txid: Self.txid1, vout: 0, amount: 100_000),
            ClaimableUtxo(txid: Self.txid2, vout: 1, amount: 200_000)
        ]
        let mock = MockUtxoHTTPClient(routes: [
            "/qbtc/v1/utxo/\(Self.txid1)/0": .ok(body: #"{"utxo":{"txid":"\#(Self.txid1)","entitled_amount":"100000"}}"#),
            "/qbtc/v1/utxo/\(Self.txid2)/1": .failure(MockError.boom)
        ])
        let service = QBTCChainService(httpClient: mock)

        let filtered = await service.filterClaimable(utxos)

        XCTAssertEqual(filtered.count, 2)
        // First entry: chain confirmed claimable, amount unchanged here.
        XCTAssertEqual(filtered[0].txid, Self.txid1)
        XCTAssertEqual(filtered[0].amount, 100_000)
        // Second entry: chain query failed — fail-open keeps the original
        // blockchair amount untouched.
        XCTAssertEqual(filtered[1].txid, Self.txid2)
        XCTAssertEqual(filtered[1].amount, 200_000)
    }

    func testFilterClaimablePreservesInputOrder() async {
        // Parallel TaskGroup completion order is non-deterministic; the
        // collector must restore input order so the UI doesn't shuffle.
        let utxos = (0..<5).map { i in
            // Use (i+1) so no amount is 0 — entitled_amount=0 would be
            // interpreted as already-claimed and filtered out.
            ClaimableUtxo(txid: String(repeating: String(format: "%02x", i), count: 32), vout: UInt32(i), amount: UInt64((i + 1) * 1000))
        }
        var routes: [String: MockResponse] = [:]
        for utxo in utxos {
            let body = #"{"utxo":{"txid":"\#(utxo.txid)","entitled_amount":"\#(utxo.amount)"}}"#
            routes["/qbtc/v1/utxo/\(utxo.txid)/\(utxo.vout)"] = .ok(body: body)
        }
        let service = QBTCChainService(httpClient: MockUtxoHTTPClient(routes: routes))

        let filtered = await service.filterClaimable(utxos)

        XCTAssertEqual(filtered.map(\.txid), utxos.map(\.txid))
    }

    func testFilterClaimableHandlesEmptyInput() async {
        let service = QBTCChainService(httpClient: MockUtxoHTTPClient(routes: [:]))
        let filtered = await service.filterClaimable([])
        XCTAssertEqual(filtered, [])
    }
}

// MARK: - Test doubles

private enum MockResponse {
    case ok(body: String)
    case notFound
    case failure(Error)
}

private enum MockError: Error {
    case boom
    case unexpectedRoute(String)
}

private final class MockUtxoHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let routes: [String: MockResponse]

    init(routes: [String: MockResponse]) {
        self.routes = routes
    }

    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        let path = target.path
        guard let route = routes[path] else {
            throw MockError.unexpectedRoute(path)
        }
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://example.test\(path)")!
        switch route {
        case .ok(let body):
            // swiftlint:disable:next force_unwrapping
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return HTTPResponse(data: Data(body.utf8), response: response)
        case .notFound:
            // swiftlint:disable:next force_unwrapping
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return HTTPResponse(data: Data(), response: response)
        case .failure(let error):
            throw error
        }
    }
}
