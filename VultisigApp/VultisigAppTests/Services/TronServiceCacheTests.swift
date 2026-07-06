//
//  TronServiceCacheTests.swift
//  VultisigAppTests
//
//  Pins the TTL cache behind `TronService.getAccount` /
//  `getAccountResource`: a fresh entry is served without a network call,
//  an expired entry re-fetches, and `forceRefresh` bypasses a fresh entry.
//  The DeFi screens re-fetched account + resource data on every open; this
//  cache lets re-opening paint from cache and only hit the network when
//  stale or explicitly refreshed.
//

@testable import VultisigApp
import XCTest

@MainActor
final class TronServiceCacheTests: XCTestCase {

    private let address = "TKt9bGgWeFFu2yRgULxRhmiBADuoEoadq8"

    override func tearDown() {
        TronService.accountCacheTTL = 60
        super.tearDown()
    }

    /// A second call within the TTL is served from cache — no extra network
    /// request to either endpoint.
    func testGetAccount_withinTTL_servesFromCacheWithoutNetwork() async throws {
        let stub = TronCountingHTTPClient()
        let service = TronService(httpClient: stub)

        _ = try await service.getAccount(address: address)
        _ = try await service.getAccount(address: address)

        XCTAssertEqual(stub.count(for: "/wallet/getaccount"), 1)
    }

    func testGetAccountResource_withinTTL_servesFromCacheWithoutNetwork() async throws {
        let stub = TronCountingHTTPClient()
        let service = TronService(httpClient: stub)

        _ = try await service.getAccountResource(address: address)
        _ = try await service.getAccountResource(address: address)

        XCTAssertEqual(stub.count(for: "/wallet/getaccountresource"), 1)
    }

    /// Once the entry is older than the TTL the next call re-fetches.
    func testGetAccount_afterTTL_refetchesFromNetwork() async throws {
        TronService.accountCacheTTL = 0 // expire immediately
        let stub = TronCountingHTTPClient()
        let service = TronService(httpClient: stub)

        _ = try await service.getAccount(address: address)
        _ = try await service.getAccount(address: address)

        XCTAssertEqual(stub.count(for: "/wallet/getaccount"), 2)
    }

    /// `forceRefresh` bypasses an otherwise-fresh cached entry (pull-to-refresh).
    func testGetAccount_forceRefresh_bypassesFreshCache() async throws {
        let stub = TronCountingHTTPClient()
        let service = TronService(httpClient: stub)

        _ = try await service.getAccount(address: address)
        _ = try await service.getAccount(address: address, forceRefresh: true)

        XCTAssertEqual(stub.count(for: "/wallet/getaccount"), 2)
    }

    /// `cachedAccount(for:)` peeks a fresh entry without a network call and
    /// returns nil before anything is cached.
    func testCachedAccount_reflectsCacheState() async throws {
        let stub = TronCountingHTTPClient()
        let service = TronService(httpClient: stub)

        let before = await service.cachedAccount(for: address)
        XCTAssertNil(before)

        _ = try await service.getAccount(address: address)

        let after = await service.cachedAccount(for: address)
        XCTAssertNotNil(after)
        XCTAssertEqual(stub.count(for: "/wallet/getaccount"), 1)
    }

    /// Invalidation drops the cached entry so the next load re-fetches —
    /// the freeze/unfreeze refresh path.
    func testInvalidate_forcesRefetch() async throws {
        let stub = TronCountingHTTPClient()
        let service = TronService(httpClient: stub)

        _ = try await service.getAccount(address: address)
        await service.invalidateAccountCache(for: address)
        _ = try await service.getAccount(address: address)

        XCTAssertEqual(stub.count(for: "/wallet/getaccount"), 2)
    }
}

// MARK: - Counting Stub HTTPClient

/// Path-keyed stub that counts requests per path so cache hits/misses are
/// observable. Returns canned valid JSON for the account + resource endpoints.
private final class TronCountingHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    private let responses: [String: String] = [
        "/wallet/getaccount": #"{"address":"TGexisting","balance":1}"#,
        "/wallet/getaccountresource": #"{"freeNetUsed":0,"freeNetLimit":600,"NetUsed":0,"NetLimit":10000,"EnergyUsed":0,"EnergyLimit":1000000}"#
    ]

    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        let path = target.path
        lock.lock()
        counts[path, default: 0] += 1
        lock.unlock()

        guard let json = responses[path] else {
            XCTFail("TronCountingHTTPClient has no stub for path '\(path)'")
            throw HTTPError.invalidResponse
        }
        let response = HTTPURLResponse(
            url: URL(string: "https://test.local")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: Data(json.utf8), response: response)
    }

    func count(for path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[path, default: 0]
    }
}
