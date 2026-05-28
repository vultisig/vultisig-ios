//
//  KeybaseAvatarServiceTests.swift
//  VultisigAppTests
//
//  Covers the Keybase identity → avatar URL lookup, including the
//  positive cache (within TTL), the negative cache (missing avatar still
//  cached for the TTL), and the failure fallback to nil.
//

@testable import VultisigApp
import Foundation
import XCTest

final class KeybaseAvatarServiceTests: XCTestCase {

    func testAvatarURLResolvesPrimaryPictureWhenPresent() async {
        let stub = StubHTTPClient(payload: Self.responseWith(url: "https://s3.amazonaws.com/keybase_processed/abc.png"))
        let service = KeybaseAvatarService(httpClient: stub)
        let url = await service.avatarURL(forIdentity: "1234567890abcdef")
        XCTAssertEqual(url?.absoluteString, "https://s3.amazonaws.com/keybase_processed/abc.png")
    }

    func testAvatarURLReturnsNilOnEmptyIdentity() async {
        let stub = StubHTTPClient(payload: Data())
        let service = KeybaseAvatarService(httpClient: stub)
        let url = await service.avatarURL(forIdentity: "")
        XCTAssertNil(url)
        let count = await stub.requestCount
        XCTAssertEqual(count, 0)
    }

    func testAvatarURLReturnsNilWhenLookupHasNoUser() async {
        // Keybase returns `{"them": null}` when the identity isn't found.
        let stub = StubHTTPClient(payload: Data(#"{"them": null}"#.utf8))
        let service = KeybaseAvatarService(httpClient: stub)
        let url = await service.avatarURL(forIdentity: "deadbeefcafebabe")
        XCTAssertNil(url)
    }

    func testAvatarURLReturnsNilOnHTTPError() async {
        let stub = StubHTTPClient(payload: nil, error: HTTPError.statusCode(500, nil))
        let service = KeybaseAvatarService(httpClient: stub)
        let url = await service.avatarURL(forIdentity: "1234567890abcdef")
        XCTAssertNil(url)
    }

    func testAvatarURLHitsPositiveCacheWithinTTL() async {
        let stub = StubHTTPClient(payload: Self.responseWith(url: "https://example/a.png"))
        let service = KeybaseAvatarService(
            httpClient: stub,
            ttl: 3600,
            clock: { Date(timeIntervalSince1970: 0) }
        )
        _ = await service.avatarURL(forIdentity: "1234567890abcdef")
        _ = await service.avatarURL(forIdentity: "1234567890abcdef")
        let count = await stub.requestCount
        XCTAssertEqual(count, 1)
    }

    func testAvatarURLHitsNegativeCacheWithinTTL() async {
        // Even when the lookup returned `nil` (no avatar), we should not
        // re-query within the TTL — otherwise list re-renders hammer
        // Keybase.
        let stub = StubHTTPClient(payload: Data(#"{"them": null}"#.utf8))
        let service = KeybaseAvatarService(
            httpClient: stub,
            ttl: 3600,
            clock: { Date(timeIntervalSince1970: 0) }
        )
        _ = await service.avatarURL(forIdentity: "deadbeefcafebabe")
        _ = await service.avatarURL(forIdentity: "deadbeefcafebabe")
        let count = await stub.requestCount
        XCTAssertEqual(count, 1)
    }

    func testAvatarURLRefetchesAfterTTLExpires() async {
        let stub = StubHTTPClient(payload: Self.responseWith(url: "https://example/a.png"))
        let clockBox = ClockBox(start: Date(timeIntervalSince1970: 0))
        let service = KeybaseAvatarService(
            httpClient: stub,
            ttl: 60,
            clock: { clockBox.now }
        )
        _ = await service.avatarURL(forIdentity: "1234567890abcdef")
        clockBox.advance(by: 3600)
        _ = await service.avatarURL(forIdentity: "1234567890abcdef")
        let count = await stub.requestCount
        XCTAssertEqual(count, 2)
    }

    // MARK: - Fixtures

    private static func responseWith(url: String) -> Data {
        Data(#"{"them": [{"pictures": {"primary": {"url": "\#(url)"}}}]}"#.utf8)
    }
}

// MARK: - Test doubles

private final class ClockBox: @unchecked Sendable {
    private var current: Date

    init(start: Date) { self.current = start }

    var now: Date { current }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}

private actor StubHTTPClient: HTTPClientProtocol {
    private let payload: Data?
    private let error: Error?
    private(set) var requestCount: Int = 0

    init(payload: Data?, error: Error? = nil) {
        self.payload = payload
        self.error = error
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        requestCount += 1
        if let error { throw error }
        let data = payload ?? Data()
        let response = HTTPURLResponse(
            url: target.baseURL.appendingPathComponent(target.path),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: data, response: response)
    }
}
