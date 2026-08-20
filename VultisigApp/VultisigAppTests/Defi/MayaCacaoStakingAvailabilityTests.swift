//
//  MayaCacaoStakingAvailabilityTests.swift
//  VultisigAppTests
//
//  Native MsgDeposit availability for CACAO pool Add / Remove.
//

import Foundation
@testable import VultisigApp
import XCTest

final class MayaCacaoStakingAvailabilityTests: XCTestCase {

    func testMimirDecodesEveryNativeDepositHaltInput() throws {
        let mimir = try decodeMimir(
            haltChainGlobal: 1,
            nodePauseChainGlobal: 200,
            haltMayaChain: 2,
            solvencyHaltMayaChain: 3
        )

        XCTAssertEqual(mimir.haltChainGlobal, 1)
        XCTAssertEqual(mimir.nodePauseChainGlobal, 200)
        XCTAssertEqual(mimir.haltMayaChain, 2)
        XCTAssertEqual(mimir.solvencyHaltMayaChain, 3)
    }

    func testMimirDecodesNativeHaltKeysFromLivePayloadShape() throws {
        let data = Data("""
        {
          "CACAOPOOLDEPOSITMATURITYBLOCKS": 302400,
          "HALTCHAINGLOBAL": 1,
          "NODEPAUSECHAINGLOBAL": 16576652,
          "HALTMAYACHAIN": -1,
          "SOLVENCYHALTMAYACHAIN": -1
        }
        """.utf8)

        let mimir = try JSONDecoder().decode(MayaMimir.self, from: data)

        XCTAssertEqual(mimir.haltChainGlobal, 1)
        XCTAssertEqual(mimir.nodePauseChainGlobal, 16_576_652)
        XCTAssertEqual(mimir.haltMayaChain, -1)
        XCTAssertEqual(mimir.solvencyHaltMayaChain, -1)
    }

    func testGlobalAndMayaHaltsStartAfterTheirConfiguredHeight() throws {
        for key in ["HALTCHAINGLOBAL", "HALTMAYACHAIN", "SOLVENCYHALTMAYACHAIN"] {
            XCTAssertFalse(try decodeMimir(extra: [key: 100]).isNativeDepositHalted(at: 100))
            XCTAssertTrue(try decodeMimir(extra: [key: 100]).isNativeDepositHalted(at: 101))
        }
    }

    func testNodePauseIsActiveOnlyBeforeItsResumeHeight() throws {
        let mimir = try decodeMimir(nodePauseChainGlobal: 200)

        XCTAssertTrue(mimir.isNativeDepositHalted(at: 199))
        XCTAssertFalse(mimir.isNativeDepositHalted(at: 200))
        XCTAssertFalse(mimir.isNativeDepositHalted(at: 201))
    }

    func testMissingZeroNegativeAndFutureAdminHaltsAreAvailable() throws {
        XCTAssertFalse(try decodeMimir().isNativeDepositHalted(at: 100))
        XCTAssertFalse(try decodeMimir(haltChainGlobal: 0).isNativeDepositHalted(at: 100))
        XCTAssertFalse(try decodeMimir(haltChainGlobal: -1).isNativeDepositHalted(at: 100))
        XCTAssertFalse(try decodeMimir(haltChainGlobal: 101).isNativeDepositHalted(at: 100))
    }

    func testAvailabilityCacheCanBeBypassedForSigningBoundary() async throws {
        let client = MayaAvailabilityHTTPClient(
            responses: [
                "/mayachain/lastblock": [
                    lastBlockJSON(height: 100),
                    lastBlockJSON(height: 100),
                    lastBlockJSON(height: 101)
                ],
                "/mayachain/mimir": [mimirJSON(haltChainGlobal: 0), mimirJSON(haltChainGlobal: 1)]
            ]
        )
        let service = MayaChainAPIService(httpClient: client)

        let initialAvailability = try await service.getNativeDepositAvailability()
        let cachedAvailability = try await service.getNativeDepositAvailability()
        let refreshedAvailability = try await service.getNativeDepositAvailability(shouldCache: false)
        let lastBlockRequestCount = await client.requestCount(for: "/mayachain/lastblock")
        let mimirRequestCount = await client.requestCount(for: "/mayachain/mimir")

        XCTAssertEqual(initialAvailability, .available)
        XCTAssertEqual(
            cachedAvailability,
            .available,
            "The ordinary UI read may reuse its five-minute snapshot."
        )
        XCTAssertEqual(
            refreshedAvailability,
            .halted,
            "The signing-boundary read must observe a halt that began after the card loaded."
        )
        XCTAssertEqual(lastBlockRequestCount, 3)
        XCTAssertEqual(mimirRequestCount, 2)
    }

    private func decodeMimir(
        haltChainGlobal: Int64? = nil,
        nodePauseChainGlobal: Int64? = nil,
        haltMayaChain: Int64? = nil,
        solvencyHaltMayaChain: Int64? = nil
    ) throws -> MayaMimir {
        var extra: [String: Int64] = [:]
        extra["HALTCHAINGLOBAL"] = haltChainGlobal
        extra["NODEPAUSECHAINGLOBAL"] = nodePauseChainGlobal
        extra["HALTMAYACHAIN"] = haltMayaChain
        extra["SOLVENCYHALTMAYACHAIN"] = solvencyHaltMayaChain
        return try decodeMimir(extra: extra)
    }

    private func decodeMimir(extra: [String: Int64]) throws -> MayaMimir {
        try JSONDecoder().decode(MayaMimir.self, from: mimirJSON(extra: extra))
    }

    private func mimirJSON(haltChainGlobal: Int64) -> Data {
        mimirJSON(extra: ["HALTCHAINGLOBAL": haltChainGlobal])
    }

    private func mimirJSON(extra: [String: Int64]) -> Data {
        var values = extra
        values["CACAOPOOLDEPOSITMATURITYBLOCKS"] = 302_400
        let fields = values
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\":\($0.value)" }
            .joined(separator: ",")
        return Data("{\(fields)}".utf8)
    }

    private func lastBlockJSON(height: Int64) -> Data {
        Data("""
        [{"chain":"THOR","last_observed_in":27477640,"last_signed_out":17978543,"mayachain":\(height)}]
        """.utf8)
    }
}

private actor MayaAvailabilityHTTPClient: HTTPClientProtocol {
    private var responses: [String: [Data]]
    private var counts: [String: Int] = [:]

    init(responses: [String: [Data]]) {
        self.responses = responses
    }

    func requestCount(for path: String) -> Int {
        counts[path, default: 0]
    }

    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        let path = target.path
        counts[path, default: 0] += 1
        guard var queued = responses[path], !queued.isEmpty else {
            throw HTTPError.statusCode(501, nil)
        }
        let data = queued.removeFirst()
        responses[path] = queued

        let response = HTTPURLResponse(
            url: target.baseURL.appendingPathComponent(path),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: data, response: response)
    }
}
