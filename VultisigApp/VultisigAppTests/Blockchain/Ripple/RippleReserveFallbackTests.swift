//
//  RippleReserveFallbackTests.swift
//  VultisigAppTests
//
//  Covers the reserve-value sourcing chain behind `RippleService.getBalance`:
//  live `server_state` → cached last-good snapshot → `RippleReserve` seeds.
//  Reserve values change only by rare validator vote, so a transient
//  `server_state` outage must never fail the whole balance read — only a
//  failed `account_info` is fatal (there is no balance without it).
//

@testable import VultisigApp
import XCTest
import BigInt

final class RippleReserveFallbackTests: XCTestCase {

    func testGetBalanceUsesLiveReserveValues() async throws {
        let client = RippleScriptedHTTPClient()
        client.accountInfoResult = .success(accountInfoJSON(balance: "10000000", ownerCount: 2))
        client.serverStateResult = .success(serverStateJSON(reserveBase: 1_000_000, reserveInc: 200_000))
        let service = makeService(client: client)

        let balance = try await service.getBalance(address: "rSender")

        // 10 XRP − (1 + 2 × 0.2) XRP reserve = 8.6 XRP.
        XCTAssertEqual(balance, "8600000")
    }

    func testGetBalanceServesCachedReserveValuesWhenServerStateFails() async throws {
        let client = RippleScriptedHTTPClient()
        client.accountInfoResult = .success(accountInfoJSON(balance: "10000000", ownerCount: 0))
        client.serverStateResult = .failure(URLError(.notConnectedToInternet))
        let service = makeService(client: client)
        // Seed a stale last-good snapshot: the expired TTL forces a refetch,
        // the refetch fails, and the cache fails open to this entry. The seeded
        // base differs from both the live and the seed constants so the
        // assertion can only pass via the cached path.
        await service.reserveValuesCache.setCached(
            RippleReserveValues(reserveBase: 5_000_000, reserveInc: 1_000_000),
            for: RippleService.reserveValuesCacheKey(for: RippleAPI.defaultHost),
            fetchedAt: Date(timeIntervalSinceNow: -60 * 60 * 48)
        )

        let balance = try await service.getBalance(address: "rSender")

        // 10 XRP − cached 5 XRP base (ownerCount 0) = 5 XRP.
        XCTAssertEqual(balance, "5000000")
    }

    func testGetBalanceFallsBackToSeedsWhenServerStateFailsWithColdCache() async throws {
        let client = RippleScriptedHTTPClient()
        client.accountInfoResult = .success(accountInfoJSON(balance: "10000000", ownerCount: 0))
        client.serverStateResult = .failure(URLError(.notConnectedToInternet))
        let service = makeService(client: client)

        let balance = try await service.getBalance(address: "rSender")

        // 10 XRP − seed 1 XRP base reserve = 9 XRP.
        XCTAssertEqual(balance, "9000000")
    }

    func testGetBalanceThrowsWhenAccountInfoFails() async {
        let client = RippleScriptedHTTPClient()
        client.accountInfoResult = .failure(URLError(.notConnectedToInternet))
        client.serverStateResult = .success(serverStateJSON(reserveBase: 1_000_000, reserveInc: 200_000))
        let service = makeService(client: client)

        do {
            _ = try await service.getBalance(address: "rSender")
            XCTFail("getBalance must rethrow an account_info failure — a reserve fallback cannot invent a balance")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testGetBalanceReusesCachedReserveValuesWithinTTL() async throws {
        let client = RippleScriptedHTTPClient()
        client.accountInfoResult = .success(accountInfoJSON(balance: "10000000", ownerCount: 1))
        client.serverStateResult = .success(serverStateJSON(reserveBase: 1_000_000, reserveInc: 200_000))
        let service = makeService(client: client)

        _ = try await service.getBalance(address: "rSender")
        let second = try await service.getBalance(address: "rSender")

        XCTAssertEqual(second, "8800000")
        XCTAssertEqual(client.serverStateCallCount, 1, "reserve values are a rare-vote constant — one fetch per TTL window")
    }

    func testGetBalanceDoesNotCacheAllNilServerState() async throws {
        // A server that is up but still syncing answers HTTP 200 with
        // `validated_ledger == null`, so both reserve fields are nil. That
        // fully-empty response must NOT be cached as authoritative for the 24h
        // TTL — caching it would pin the seeds and never refetch, even after the
        // node recovers. getBalance seeds this time and refetches next time.
        let client = RippleScriptedHTTPClient()
        client.accountInfoResult = .success(accountInfoJSON(balance: "10000000", ownerCount: 0))
        client.serverStateResult = .success(Data("""
        {"result":{"state":{"load_base":256,"load_factor":256,"validated_ledger":null}}}
        """.utf8))
        let service = makeService(client: client)

        let first = try await service.getBalance(address: "rSender")
        let second = try await service.getBalance(address: "rSender")

        // 10 XRP − seed 1 XRP base reserve (ownerCount 0) = 9 XRP, both times.
        XCTAssertEqual(first, "9000000")
        XCTAssertEqual(second, "9000000")
        XCTAssertEqual(client.serverStateCallCount, 2,
                       "an all-nil server_state must not be cached — each refresh refetches until real values arrive")
    }

    func testReserveValuesCacheIsScopedToResolvedHost() async throws {
        let client = RippleScriptedHTTPClient()
        client.accountInfoResult = .success(accountInfoJSON(balance: "10000000", ownerCount: 0))
        client.serverStateResult = .success(serverStateJSON(reserveBase: 5_000_000, reserveInc: 1_000_000))
        let resolver = MutableResolver()
        let service = RippleService(resolver: resolver, httpClient: client)

        // Warm the cache against the default host with non-mainnet reserves.
        let first = try await service.getBalance(address: "rSender")
        XCTAssertEqual(first, "5000000")

        // Switch the custom RPC override: the old host's snapshot must not
        // carry over. With the new host's server_state failing and its cache
        // cold, the seeds apply (10 − 1 XRP), not the cached 5 XRP base.
        resolver.override = "https://xrpl.example.org"
        client.serverStateResult = .failure(URLError(.notConnectedToInternet))
        let second = try await service.getBalance(address: "rSender")
        XCTAssertEqual(second, "9000000")
    }

    // MARK: - Fixtures

    private func makeService(client: HTTPClientProtocol) -> RippleService {
        RippleService(resolver: NoOverrideResolver(), httpClient: client)
    }

    /// Raw JSON keeps the test on the production decoder (`RippleAccountResponse`).
    private func accountInfoJSON(balance: String, ownerCount: Int) -> Data {
        Data("""
        {"result":{"account_data":{"Account":"rSender","Balance":"\(balance)","OwnerCount":\(ownerCount),"Sequence":1},"status":"success","validated":true}}
        """.utf8)
    }

    private func serverStateJSON(reserveBase: Int, reserveInc: Int) -> Data {
        Data("""
        {"result":{"state":{"load_base":256,"load_factor":256,"validated_ledger":{"base_fee":10,"reserve_base":\(reserveBase),"reserve_inc":\(reserveInc)}}}}
        """.utf8)
    }
}

// MARK: - Test doubles

private struct NoOverrideResolver: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

/// Resolver whose override can be flipped mid-test, modelling a runtime custom
/// RPC change against one long-lived service instance.
private final class MutableResolver: RPCEndpointResolving, @unchecked Sendable {
    var override: String?

    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { override }
}

// `async` is required by `HTTPClientProtocol`; the stub answers synchronously.
// swiftlint:disable async_without_await

/// Scripted HTTP client keyed on the `RippleAPI` endpoint, so each XRPL RPC
/// can succeed or fail independently.
private final class RippleScriptedHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    var accountInfoResult: Result<Data, Error> = .failure(URLError(.badServerResponse))
    var serverStateResult: Result<Data, Error> = .failure(URLError(.badServerResponse))

    private let queue = DispatchQueue(label: "RippleScriptedHTTPClient.queue")
    private var _serverStateCalls = 0

    var serverStateCallCount: Int {
        queue.sync { _serverStateCalls }
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        guard let api = target as? RippleAPI else {
            throw URLError(.unsupportedURL)
        }
        switch api.endpoint {
        case .accountInfo:
            return try respond(accountInfoResult)
        case .serverState:
            queue.sync { _serverStateCalls += 1 }
            return try respond(serverStateResult)
        case .submit:
            throw URLError(.unsupportedURL)
        }
    }

    private func respond(_ result: Result<Data, Error>) throws -> HTTPResponse<Data> {
        let data = try result.get()
        guard let url = URL(string: "https://xrplcluster.com"),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badURL)
        }
        return HTTPResponse(data: data, response: response)
    }
}

// swiftlint:enable async_without_await
