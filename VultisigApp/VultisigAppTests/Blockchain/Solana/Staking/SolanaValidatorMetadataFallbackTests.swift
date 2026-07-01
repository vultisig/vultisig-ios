//
//  SolanaValidatorMetadataFallbackTests.swift
//  VultisigAppTests
//
//  Verifies the graceful-degradation contract end to end: when the metadata
//  provider returns an empty/partial map, folding it onto on-chain validators
//  leaves them with a truncated-vote-pubkey display name, no logo, and the
//  on-chain commission intact — no crash. Enriched rows pick up name/logo/APY.
//

@testable import VultisigApp
import Foundation
import XCTest

final class SolanaValidatorMetadataFallbackTests: XCTestCase {

    private let voteA = "9gANMngbGUmAaLXL1RC3JdiaLjRowJXNbzCTh53ht7mq"

    private func onChainValidator(commission: Int = 7) -> SolanaValidator {
        SolanaValidator(
            votePubkey: voteA,
            nodePubkey: "YuRBAsy9Stw1u46A8dMp7WQVBFweLP1PKuYibzYAMmQ",
            activatedStake: 154_529,
            commission: commission,
            epochVoteAccount: true,
            isDelinquent: false
        )
    }

    func testEmptyMetadataFallsBackToTruncatedPubkeyAndOnChainCommission() {
        let validator = onChainValidator(commission: 7)
        // No metadata applied (empty provider result).
        XCTAssertEqual(validator.displayName, "9gAN…t7mq")
        XCTAssertNil(validator.logoURL)
        XCTAssertNil(validator.metadata.apyEstimate)
        XCTAssertEqual(validator.commission, 7) // on-chain commission preserved
    }

    func testEnrichedMetadataIsSurfacedThroughDisplayHelpers() async {
        let stub = StubHTTPClient(payload: Self.payload())
        let provider = StakewizValidatorMetadataProvider(
            httpClient: stub,
            avatarService: NoAvatarService()
        )
        let map = await provider.metadata(forVotePubkeys: [voteA])

        var validator = onChainValidator()
        if let meta = map[validator.votePubkey] {
            validator.metadata = meta
        }

        XCTAssertEqual(validator.displayName, "Yurbason")
        XCTAssertEqual(validator.logoURL?.absoluteString, "https://media.stakewiz.com/yurbason.png")
        let apy = (validator.metadata.apyEstimate as NSDecimalNumber?)?.doubleValue ?? 0
        XCTAssertEqual(apy, 0.0572, accuracy: 0.00001)
        // Provider absence for unknown pubkeys leaves on-chain commission as-is.
        XCTAssertEqual(validator.commission, 7)
    }

    func testTruncatedPubkeyReturnsShortInputUnchanged() {
        XCTAssertEqual(SolanaValidator.truncatedPubkey("short"), "short")
    }

    // MARK: - Fixtures

    private static func payload() -> Data {
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
          }
        ]
        """
        return Data(json.utf8)
    }
}

// MARK: - Test doubles

private struct NoAvatarService: KeybaseAvatarServiceProtocol {
    // swiftlint:disable:next async_without_await
    func avatarURL(forIdentity _: String) async -> URL? { nil }
}

private actor StubHTTPClient: HTTPClientProtocol {
    private let payload: Data?

    init(payload: Data?) { self.payload = payload }

    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
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
