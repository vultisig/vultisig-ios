//
//  StakewizValidatorMetadataProviderTests.swift
//  VultisigAppTests
//
//  Covers the Stakewiz validator-metadata seam: JSON → ValidatorMetadata
//  mapping (name / logo / APY fraction / score), the 1-hour cache hit/expiry
//  behavior, the graceful-degradation contract on an outage (empty/partial map,
//  no crash), and Keybase-avatar resolution taking precedence over the Stakewiz
//  `image` URL.
//

@testable import VultisigApp
import Foundation
import XCTest

final class StakewizValidatorMetadataProviderTests: XCTestCase {

    private let voteA = "9gANMngbGUmAaLXL1RC3JdiaLjRowJXNbzCTh53ht7mq"
    private let voteB = "ENVaKoD7ytn58xJ8s5htFfQ8hqQt1G9dcPUDqbSwVcgB"

    // MARK: - Mapping

    func testMapsStakewizRowIntoValidatorMetadata() async {
        let stub = StubHTTPClient(payload: Self.validatorsPayload())
        let provider = StakewizValidatorMetadataProvider(
            httpClient: stub,
            avatarService: NoAvatarService()
        )
        let result = await provider.metadata(forVotePubkeys: [voteA])
        let meta = result[voteA]
        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.name, "Yurbason")
        // No Keybase identity in this row → falls back to the Stakewiz image.
        XCTAssertEqual(meta?.logoURL, "https://media.stakewiz.com/yurbason.png")
        // apy_estimate 5.72 (percent) stored as the 0.0572 fraction.
        let apy = (meta?.apyEstimate as NSDecimalNumber?)?.doubleValue ?? 0
        XCTAssertEqual(apy, 0.0572, accuracy: 0.00001)
        XCTAssertEqual(meta?.score, 99) // wiz_score 99.44 → rounded
    }

    func testResolvesOnlyRequestedSubset() async {
        let stub = StubHTTPClient(payload: Self.validatorsPayload())
        let provider = StakewizValidatorMetadataProvider(
            httpClient: stub,
            avatarService: NoAvatarService()
        )
        let result = await provider.metadata(forVotePubkeys: [voteB])
        XCTAssertEqual(Set(result.keys), [voteB])
        XCTAssertEqual(result[voteB]?.name, "WEB34EVER")
    }

    func testPrefersStakewizImageOverKeybaseAndSkipsLookup() async {
        // voteB carries BOTH a Keybase identity and a Stakewiz `image`. The
        // bundled image is preferred (it ships in the same bulk payload), and the
        // per-validator Keybase round-trip must NOT happen — that N+1 is the
        // latency we removed.
        let stub = StubHTTPClient(payload: Self.validatorsPayload())
        let spy = SpyAvatarService(url: URL(string: "https://keybase.io/web34ever.png"))
        let provider = StakewizValidatorMetadataProvider(
            httpClient: stub,
            avatarService: spy
        )
        let result = await provider.metadata(forVotePubkeys: [voteB])
        XCTAssertEqual(result[voteB]?.logoURL, "https://media.stakewiz.com/web34ever.png")
        let calls = await spy.calls
        XCTAssertEqual(calls, 0, "Keybase must not be queried when a Stakewiz image is present.")
    }

    func testFallsBackToKeybaseWhenImageMissing() async {
        // No usable `image` but a Keybase identity present → resolve via Keybase.
        let payload = Data(#"""
        [{"vote_identity": "\#(voteB)", "name": "NoImage", "keybase": "nimg", "image": ""}]
        """#.utf8)
        let stub = StubHTTPClient(payload: payload)
        let spy = SpyAvatarService(url: URL(string: "https://keybase.io/nimg.png"))
        let provider = StakewizValidatorMetadataProvider(
            httpClient: stub,
            avatarService: spy
        )
        let result = await provider.metadata(forVotePubkeys: [voteB])
        XCTAssertEqual(result[voteB]?.logoURL, "https://keybase.io/nimg.png")
        let calls = await spy.calls
        XCTAssertEqual(calls, 1, "Keybase is the fallback when no image is bundled.")
    }

    // MARK: - Graceful degradation

    func testReturnsEmptyMapOnOutageWithoutThrowing() async {
        let stub = StubHTTPClient(payload: nil, error: HTTPError.statusCode(503, nil))
        let provider = StakewizValidatorMetadataProvider(
            httpClient: stub,
            avatarService: NoAvatarService()
        )
        let result = await provider.metadata(forVotePubkeys: [voteA, voteB])
        XCTAssertTrue(result.isEmpty)
    }

    func testReturnsPartialMapWhenPubkeyAbsentFromSource() async {
        let stub = StubHTTPClient(payload: Self.validatorsPayload())
        let provider = StakewizValidatorMetadataProvider(
            httpClient: stub,
            avatarService: NoAvatarService()
        )
        let unknown = "ZZZZunknownvotepubkeyZZZZ"
        let result = await provider.metadata(forVotePubkeys: [voteA, unknown])
        XCTAssertEqual(Set(result.keys), [voteA])
        XCTAssertNil(result[unknown])
    }

    func testReturnsEmptyMapForEmptyInput() async {
        let stub = StubHTTPClient(payload: Self.validatorsPayload())
        let provider = StakewizValidatorMetadataProvider(
            httpClient: stub,
            avatarService: NoAvatarService()
        )
        let result = await provider.metadata(forVotePubkeys: [])
        XCTAssertTrue(result.isEmpty)
        let count = await stub.requestCount
        XCTAssertEqual(count, 0)
    }

    func testTolerantOfMissingOptionalFields() async {
        // A row with only vote_identity present must not crash decoding and
        // yields all-nil enrichment.
        let payload = Data(#"[{"vote_identity": "\#(voteA)"}]"#.utf8)
        let stub = StubHTTPClient(payload: payload)
        let provider = StakewizValidatorMetadataProvider(
            httpClient: stub,
            avatarService: NoAvatarService()
        )
        let result = await provider.metadata(forVotePubkeys: [voteA])
        let meta = result[voteA]
        XCTAssertNotNil(meta)
        XCTAssertNil(meta?.name)
        XCTAssertNil(meta?.logoURL)
        XCTAssertNil(meta?.apyEstimate)
        XCTAssertNil(meta?.score)
    }

    // MARK: - Cache

    func testHitsCacheWithinTTL() async {
        let stub = StubHTTPClient(payload: Self.validatorsPayload())
        let provider = StakewizValidatorMetadataProvider(
            httpClient: stub,
            avatarService: NoAvatarService(),
            ttl: 3600,
            clock: { Date(timeIntervalSince1970: 0) }
        )
        _ = await provider.metadata(forVotePubkeys: [voteA])
        _ = await provider.metadata(forVotePubkeys: [voteA])
        let count = await stub.requestCount
        XCTAssertEqual(count, 1) // second call served from cache
    }

    func testRefetchesAfterTTLExpires() async {
        let stub = StubHTTPClient(payload: Self.validatorsPayload())
        let clockBox = ClockBox(start: Date(timeIntervalSince1970: 0))
        let provider = StakewizValidatorMetadataProvider(
            httpClient: stub,
            avatarService: NoAvatarService(),
            ttl: 3600,
            clock: { clockBox.now }
        )
        _ = await provider.metadata(forVotePubkeys: [voteA])
        clockBox.advance(by: 7200)
        _ = await provider.metadata(forVotePubkeys: [voteA])
        let count = await stub.requestCount
        XCTAssertEqual(count, 2)
    }

    // MARK: - Fixtures

    private static func validatorsPayload() -> Data {
        let json = """
        [
          {
            "vote_identity": "9gANMngbGUmAaLXL1RC3JdiaLjRowJXNbzCTh53ht7mq",
            "name": "Yurbason",
            "keybase": "",
            "image": "https://media.stakewiz.com/yurbason.png",
            "commission": 0,
            "apy_estimate": 5.72,
            "wiz_score": 99.44,
            "delinquent": false
          },
          {
            "vote_identity": "ENVaKoD7ytn58xJ8s5htFfQ8hqQt1G9dcPUDqbSwVcgB",
            "name": "WEB34EVER",
            "keybase": "web34ever",
            "image": "https://media.stakewiz.com/web34ever.png",
            "commission": 5,
            "apy_estimate": 5.81,
            "wiz_score": 98.5,
            "delinquent": false
          }
        ]
        """
        return Data(json.utf8)
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

private struct NoAvatarService: KeybaseAvatarServiceProtocol {
    // swiftlint:disable:next async_without_await
    func avatarURL(forIdentity _: String) async -> URL? { nil }
}

private struct FixedAvatarService: KeybaseAvatarServiceProtocol {
    let url: URL?
    // swiftlint:disable:next async_without_await
    func avatarURL(forIdentity _: String) async -> URL? { url }
}

/// Counts how many times the Keybase fallback is hit so a test can assert the
/// per-validator round-trip is skipped when a Stakewiz image is present.
private actor SpyAvatarService: KeybaseAvatarServiceProtocol {
    private let url: URL?
    private(set) var calls = 0

    init(url: URL?) { self.url = url }

    // Protocol conformance forces `async`; actor-isolated mutation needs no await.
    // swiftlint:disable:next async_without_await
    func avatarURL(forIdentity _: String) async -> URL? {
        calls += 1
        return url
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

    // swiftlint:disable:next async_without_await
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
