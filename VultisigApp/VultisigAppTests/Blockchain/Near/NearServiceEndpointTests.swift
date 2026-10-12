//
//  NearServiceEndpointTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

private struct FakeRPCResolver: RPCEndpointResolving {
    var overrides: [Chain: String] = [:]
    func url(for chain: Chain) -> String? { overrides[chain] }
}

private final class RecordingHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    var requestedURLs: [URL] { lock.withLock { urls } }

    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        lock.withLock { urls.append(target.baseURL) }
        let json = #"{"jsonrpc":"2.0","id":"query","result":{"amount":"1","locked":"0","storage_usage":1}}"#
        let response = HTTPURLResponse(url: target.baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(json.utf8), response: response)
    }

    // swiftlint:disable:next async_without_await
    func requestEmpty(_: TargetType) async throws -> HTTPResponse<EmptyResponse> {
        throw HTTPError.invalidResponse
    }
}

final class NearServiceEndpointTests: XCTestCase {

    func test_usesCustomRPCWhenSet() async throws {
        let http = RecordingHTTPClient()
        let service = NearService(client: http, resolver: FakeRPCResolver(overrides: [.near: "https://my-node.example/near"]))
        _ = try await service.fetchAccount(accountId: "a.near")
        XCTAssertEqual(http.requestedURLs.map(\.absoluteString), ["https://my-node.example/near"])
    }

    func test_usesDefaultEndpointWithoutOverride() async throws {
        let http = RecordingHTTPClient()
        let service = NearService(client: http, resolver: FakeRPCResolver())
        _ = try await service.fetchAccount(accountId: "a.near")
        XCTAssertEqual(http.requestedURLs.map(\.absoluteString), [Endpoint.nearServiceRpc])
    }
}
