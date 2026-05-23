//
//  SwapProviderIdToleranceTests.swift
//  VultisigAppTests
//
//  Forward-compat tolerance for the `provider` discriminator in
//  `GenericSwapPayload` / `OneInchSwapPayload.provider`. A peer iOS running an
//  older build receives a keysign payload tagged with a provider name it
//  doesn't recognise. The decode MUST NOT throw — the peer falls back to a
//  raw-string display tag and signs the calldata as normal.
//

import XCTest
@testable import VultisigApp

final class SwapProviderIdToleranceTests: XCTestCase {

    func testKnownProvidersDecodeToTypedCases() throws {
        XCTAssertEqual(decode("1inch"), .oneInch)
        XCTAssertEqual(decode("li.fi"), .lifi)
        XCTAssertEqual(decode("kyber"), .kyberSwap)
        XCTAssertEqual(decode("swapkit"), .swapkit)
    }

    func testUnknownProviderDecodesToUnknownCasePreservingRaw() throws {
        let value = decode("future-provider-v2")
        XCTAssertEqual(value, .unknown("future-provider-v2"))
        XCTAssertEqual(value.name, "future-provider-v2")
        XCTAssertEqual(value.rawValue, "future-provider-v2")
    }

    func testRoundTripIsLosslessForUnknownProviders() throws {
        let original = SwapProviderId.unknown("future-provider-v2")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SwapProviderId.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testKnownProvidersRoundTripToTheirCanonicalRawString() throws {
        for provider in [SwapProviderId.oneInch, .lifi, .kyberSwap, .swapkit] {
            let encoded = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(SwapProviderId.self, from: encoded)
            XCTAssertEqual(decoded, provider, "round-trip failed for \(provider)")
        }
    }

    func testFromRawValueMatchesDecoderBehaviour() {
        XCTAssertEqual(SwapProviderId.from(rawValue: "1inch"), .oneInch)
        XCTAssertEqual(SwapProviderId.from(rawValue: "kyber"), .kyberSwap)
        XCTAssertEqual(SwapProviderId.from(rawValue: "swapkit"), .swapkit)
        XCTAssertEqual(SwapProviderId.from(rawValue: "unknown-x"), .unknown("unknown-x"))
    }

    // MARK: - Helpers

    private func decode(_ rawValue: String) -> SwapProviderId {
        let json = Data("\"\(rawValue)\"".utf8)
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(SwapProviderId.self, from: json)
    }
}
