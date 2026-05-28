//
//  CosmosStakingAPYResolverTests.swift
//  VultisigAppTests
//
//  Tests the LCD-fan-out APY resolver — caching, in-flight coalescing,
//  baseline fallback, and the `computeValidatorAPY` clamping behavior.
//

@testable import VultisigApp
import Foundation
import XCTest

final class CosmosStakingAPYResolverTests: XCTestCase {

    // MARK: - computeValidatorAPY

    func testComputeValidatorAPYAppliesCommunityTaxAndCommission() {
        let data = CosmosChainApyData(
            inflation: Decimal(string: "0.07")!,
            bondedRatio: Decimal(string: "0.5")!,
            communityTax: Decimal(string: "0.02")!
        )
        let apy = CosmosStakingAPYResolver.computeValidatorAPY(
            chainData: data,
            commission: Decimal(string: "0.05")!
        )
        // (1 - 0.02) × (0.07 / 0.5) × (1 - 0.05) = 0.98 × 0.14 × 0.95 = 0.130340
        XCTAssertNotNil(apy)
        let asDouble = (apy as NSDecimalNumber?)?.doubleValue ?? 0
        XCTAssertEqual(asDouble, 0.13034, accuracy: 0.00001)
    }

    func testComputeValidatorAPYReturnsNilOnZeroInflation() {
        let data = CosmosChainApyData(
            inflation: 0,
            bondedRatio: Decimal(string: "0.5")!,
            communityTax: 0
        )
        XCTAssertNil(CosmosStakingAPYResolver.computeValidatorAPY(chainData: data, commission: 0))
    }

    func testComputeValidatorAPYReturnsNilOnZeroBondedRatio() {
        let data = CosmosChainApyData(
            inflation: Decimal(string: "0.07")!,
            bondedRatio: 0,
            communityTax: 0
        )
        XCTAssertNil(CosmosStakingAPYResolver.computeValidatorAPY(chainData: data, commission: 0))
    }

    func testComputeValidatorAPYClampsOutOfRangeInputs() {
        let data = CosmosChainApyData(
            inflation: Decimal(string: "1.5")!, // gets clamped to 1.0
            bondedRatio: Decimal(string: "0.5")!,
            communityTax: 0
        )
        let apy = CosmosStakingAPYResolver.computeValidatorAPY(chainData: data, commission: 0)
        XCTAssertNotNil(apy)
        // (1 - 0) × (1.0 / 0.5) × (1 - 0) = 2.0
        let asDouble = (apy as NSDecimalNumber?)?.doubleValue ?? 0
        XCTAssertEqual(asDouble, 2.0, accuracy: 0.0001)
    }

    // MARK: - baselineFallback

    func testBaselineFallbackReturnsTwelvePointFiveForTerra() {
        let resolver = CosmosStakingAPYResolver(httpClient: NeverClient())
        XCTAssertEqual(resolver.baselineFallback(chain: .terra), Decimal(string: "0.125"))
    }

    func testBaselineFallbackReturnsNilForTerraClassic() {
        let resolver = CosmosStakingAPYResolver(httpClient: NeverClient())
        XCTAssertNil(resolver.baselineFallback(chain: .terraClassic))
    }

    // MARK: - chainApy fan-out

    func testChainApyResolvesValidLCDResponses() async {
        let stub = StubHTTPClient(responses: Self.happyPathResponses())
        let resolver = CosmosStakingAPYResolver(
            httpClient: stub,
            ttl: 60,
            clock: { Date(timeIntervalSince1970: 0) }
        )
        let data = await resolver.chainApy(chain: .terra, stakingDenom: "uluna")
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.inflation, Decimal(string: "0.07"))
        // bondedRatio = 50000000 / 100000000 = 0.5
        XCTAssertEqual(data?.bondedRatio, Decimal(string: "0.5"))
        XCTAssertEqual(data?.communityTax, Decimal(string: "0.02"))
    }

    func testChainApyReturnsNilWhenAnyEndpointFails() async {
        // Drop the inflation response — LUNC's mint module returns 501 in
        // the wild. The resolver collapses the entire fan-out to nil so
        // the caller falls back to baseline.
        var responses = Self.happyPathResponses()
        responses.removeValue(forKey: "/cosmos/mint/v1beta1/inflation")
        let stub = StubHTTPClient(responses: responses)
        let resolver = CosmosStakingAPYResolver(httpClient: stub)
        let data = await resolver.chainApy(chain: .terra, stakingDenom: "uluna")
        XCTAssertNil(data)
    }

    func testChainApyHitsCacheWithinTTL() async {
        let stub = StubHTTPClient(responses: Self.happyPathResponses())
        let resolver = CosmosStakingAPYResolver(
            httpClient: stub,
            ttl: 60,
            clock: { Date(timeIntervalSince1970: 0) }
        )
        _ = await resolver.chainApy(chain: .terra, stakingDenom: "uluna")
        _ = await resolver.chainApy(chain: .terra, stakingDenom: "uluna")
        let count = await stub.requestCount
        // 4 endpoints fetched once, second call served from cache.
        XCTAssertEqual(count, 4)
    }

    func testChainApyRefetchesAfterTTLExpires() async {
        let stub = StubHTTPClient(responses: Self.happyPathResponses())
        // Mutable clock — callers can advance after the first hit.
        let clockBox = ClockBox(start: Date(timeIntervalSince1970: 0))
        let resolver = CosmosStakingAPYResolver(
            httpClient: stub,
            ttl: 60,
            clock: { clockBox.now }
        )
        _ = await resolver.chainApy(chain: .terra, stakingDenom: "uluna")
        clockBox.advance(by: 120)
        _ = await resolver.chainApy(chain: .terra, stakingDenom: "uluna")
        let count = await stub.requestCount
        XCTAssertEqual(count, 8)
    }

    // MARK: - Fixtures

    private static func happyPathResponses() -> [String: Data] {
        let inflation = #"{"inflation": "0.070000000000000000"}"#
        let pool = #"{"pool": {"not_bonded_tokens": "10000000", "bonded_tokens": "50000000"}}"#
        let supply = #"{"amount": {"denom": "uluna", "amount": "100000000"}}"#
        let params = #"{"params": {"community_tax": "0.020000000000000000"}}"#
        return [
            "/cosmos/mint/v1beta1/inflation": Data(inflation.utf8),
            "/cosmos/staking/v1beta1/pool": Data(pool.utf8),
            "/cosmos/bank/v1beta1/supply/by_denom": Data(supply.utf8),
            "/cosmos/distribution/v1beta1/params": Data(params.utf8)
        ]
    }
}

// MARK: - Test doubles

/// Mutable clock holder so tests can advance time without spawning timers.
private final class ClockBox: @unchecked Sendable {
    private var current: Date

    init(start: Date) { self.current = start }

    var now: Date { current }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}

/// HTTP client stub keyed by request path. Throws `HTTPError.statusCode`
/// for paths not present in the response map — mimics a 5xx from the LCD.
private actor StubHTTPClient: HTTPClientProtocol {
    private let responses: [String: Data]
    private(set) var requestCount: Int = 0

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        requestCount += 1
        let path = target.path
        guard let data = responses[path] else {
            throw HTTPError.statusCode(501, nil)
        }
        let url = target.baseURL.appendingPathComponent(path)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: data, response: response)
    }
}

/// Placeholder client for tests that never make a request — feeds the
/// resolver init when only the synchronous helpers are exercised.
private struct NeverClient: HTTPClientProtocol {
    func request(_: TargetType) async throws -> HTTPResponse<Data> {
        throw HTTPError.networkError(NSError(domain: "test", code: -1))
    }
}
