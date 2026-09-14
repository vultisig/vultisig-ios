import XCTest
@testable import VultisigApp

@MainActor
final class FastVaultPresenceTests: XCTestCase {
    private struct Client: HTTPClientProtocol {
        let failure: HTTPError?
        var cancelled = false
        func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
            if cancelled { throw CancellationError() }
            if let failure { throw failure }
            return HTTPResponse(data: Data(), response: HTTPURLResponse(
                url: URL(string: "https://example.invalid")!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!)
        }
    }

    func testSuccessfulLookupProvesPresence() async {
        let service = FastVaultService(httpClient: Client(failure: nil))
        let result = await service.presence(pubKeyECDSA: "fixture")
        XCTAssertEqual(result, .present)
    }

    func testAmbiguousHTTPAndTransportFailuresNeverProveAbsence() async {
        let errors: [HTTPError] = [
            .statusCode(400, nil), .statusCode(404, nil), .statusCode(429, nil),
            .statusCode(500, nil), .timeout, .networkError(URLError(.notConnectedToInternet))
        ]
        for error in errors {
            let service = FastVaultService(httpClient: Client(failure: error))
            let result = await service.presence(pubKeyECDSA: "fixture")
            XCTAssertEqual(result, .unknown(.requestFailed))
        }
    }

    func testCancelledLookupIsUnknown() async {
        let service = FastVaultService(httpClient: Client(failure: nil, cancelled: true))
        let result = await service.presence(pubKeyECDSA: "fixture")
        XCTAssertEqual(result, .unknown(.cancelled))
    }
}
