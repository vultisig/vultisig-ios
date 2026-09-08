//
//  SwapKitRequestEchoTests.swift
//  VultisigAppTests
//
//  Every case mutates one field of the recorded `v3-real-ton-swap` response rather than
//  hand-rolling JSON: a hand-written body drifted from the real wire shape twice here, once
//  fatally (no `tx` key under `txType: "TON"`, so every test died at decode).
//

import XCTest
@testable import VultisigApp

final class SwapKitRequestEchoTests: XCTestCase {

    // The request that produced `v3-real-ton-swap.json`, as literals: passing the response's
    // own fields back in would assert `x == x` and pass against any implementation.
    private let routeId = "c6340348-2bc4-4052-9bd7-d5913312de49"
    private let sourceAddress = "UQBAETYfujlv90Oa5P3K5vnABkvoOnXBSCo3W8q_2-sXIN5U"
    private let destinationAddress = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    private let sourceAddressBounceable = "EQBAETYfujlv90Oa5P3K5vnABkvoOnXBSCo3W8q_2-sXIIOR"

    // MARK: - The guard is wired into buildSwapTx, not merely defined

    /// Deleting the call site, or letting the surrounding `catch HTTPError.statusCode` remap
    /// the error to `.generic`, would leave every other test here green — hence the error type
    /// is asserted through the real method.
    func testBuildSwapTxRejectsAResponseBuiltForADifferentRoute() async throws {
        let service = SwapKitService(
            httpClient: StubSwapHTTPClient(
                payload: try makeResponseData(routeId: "00000000-0000-0000-0000-000000000000")
            )
        )
        do {
            _ = try await service.buildSwapTx(
                routeId: routeId,
                sourceAddress: sourceAddress,
                destinationAddress: destinationAddress
            )
            XCTFail("expected buildSwapTx to refuse a response built for another route")
        } catch let error as SwapKitError {
            guard case .responseEchoMismatch(let detail) = error else {
                return XCTFail("expected responseEchoMismatch, got \(error)")
            }
            XCTAssertTrue(detail.contains("routeId"), "detail \(detail) should name routeId")
        }
    }

    func testBuildSwapTxReturnsAResponseThatEchoesTheRequest() async throws {
        let service = SwapKitService(httpClient: StubSwapHTTPClient(payload: try makeResponseData()))
        let response = try await service.buildSwapTx(
            routeId: routeId,
            sourceAddress: sourceAddress,
            destinationAddress: destinationAddress
        )
        XCTAssertEqual(response.routeId, routeId)
    }

    // MARK: - The rule itself

    func testAcceptsTheRecordedResponseAgainstTheRequestThatProducedIt() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-real-ton-swap"
        )
        XCTAssertNoThrow(
            try SwapKitService.validateRequestEcho(
                response: response,
                routeId: routeId,
                sourceAddress: sourceAddress,
                destinationAddress: destinationAddress
            )
        )
    }

    func testRejectsASourceAddressThatDoesNotEchoTheRequest() throws {
        let response = try decode(makeResponseData(
            sourceAddress: "EQCrq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq8Uk"
        ))
        assertEchoMismatch(response, mentioning: "sourceAddress")
    }

    func testRejectsADestinationAddressThatDoesNotEchoTheRequest() throws {
        let response = try decode(makeResponseData(
            destinationAddress: "0x0000000000000000000000000000000000000001"
        ))
        assertEchoMismatch(response, mentioning: "destinationAddress")
    }

    /// EVM checksum casing is not a different address.
    func testAcceptsAnEvmDestinationDifferingOnlyByChecksumCase() throws {
        let response = try decode(makeResponseData())
        XCTAssertNoThrow(
            try SwapKitService.validateRequestEcho(
                response: response,
                routeId: routeId,
                sourceAddress: sourceAddress,
                destinationAddress: destinationAddress.lowercased()
            )
        )
    }

    /// One TON account re-spelled between request and response is the same account.
    func testAcceptsATonSourceReSpelledBounceable() throws {
        let response = try decode(makeResponseData())
        XCTAssertNoThrow(
            try SwapKitService.validateRequestEcho(
                response: response,
                routeId: routeId,
                sourceAddress: sourceAddressBounceable,
                destinationAddress: destinationAddress
            )
        )
    }

    /// Base58 is case-sensitive, so a case-only difference outside EVM is a different address.
    func testRejectsANonEvmSourceDifferingOnlyByCase() throws {
        let base58Source = "rPVMhWBsfF9iMXYj3aAzJVkPDTFNSyWdKy"
        let response = try decode(makeResponseData(sourceAddress: base58Source))
        assertEchoMismatch(
            response,
            sourceAddress: base58Source.lowercased(),
            mentioning: "sourceAddress"
        )
    }

    // MARK: - Helpers

    private func assertEchoMismatch(
        _ response: SwapKitSwapResponse,
        sourceAddress: String? = nil,
        mentioning fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try SwapKitService.validateRequestEcho(
                response: response,
                routeId: routeId,
                sourceAddress: sourceAddress ?? self.sourceAddress,
                destinationAddress: destinationAddress
            ),
            file: file,
            line: line
        ) { error in
            guard let swapKitError = error as? SwapKitError,
                  case .responseEchoMismatch(let detail) = swapKitError else {
                return XCTFail("expected responseEchoMismatch, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(
                detail.contains(fragment),
                "detail \(detail) should name \(fragment)",
                file: file,
                line: line
            )
        }
    }

    private func decode(_ data: Data) throws -> SwapKitSwapResponse {
        try JSONDecoder().decode(SwapKitSwapResponse.self, from: data)
    }

    private func makeResponseData(
        routeId: String? = nil,
        sourceAddress: String? = nil,
        destinationAddress: String? = nil
    ) throws -> Data {
        let data = try SwapKitFixtureLoader.loadData("v3-real-ton-swap")
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "SwapKitRequestEchoTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "fixture is not a JSON object"]
            )
        }
        if let routeId { object["routeId"] = routeId }
        if let sourceAddress { object["sourceAddress"] = sourceAddress }
        if let destinationAddress { object["destinationAddress"] = destinationAddress }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

/// One canned `/v3/swap` body for any target, so `buildSwapTx` runs end to end.
private final class StubSwapHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let payload: Data

    init(payload: Data) {
        self.payload = payload
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        _ = target
        await Task.yield()
        guard let url = URL(string: "https://api.vultisig.com/swapkit/v3/swap"),
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
              ) else {
            throw HTTPError.statusCode(500, nil)
        }
        return HTTPResponse(data: payload, response: response)
    }
}
