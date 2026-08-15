//
//  TcyUserDistributionsDecodingTests.swift
//  VultisigAppTests
//
//  Midgard's `/v2/tcy/distribution/{address}` sends `"distributions": null`,
//  verbatim, for an address with no payout history yet. Against a
//  non-optional `[TcyUserDistribution]` that threw `DecodingError
//  .valueNotFound`, which aborted the whole TCY staking-details fetch (APR,
//  reward estimate, and the position itself) for any address too new or too
//  small to have been paid out.
//
//  The fixture below is captured verbatim from mainnet Midgard.
//

import XCTest
@testable import VultisigApp

final class TcyUserDistributionsDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> TcyUserDistributionsResponse {
        try JSONDecoder().decode(TcyUserDistributionsResponse.self, from: Data(json.utf8))
    }

    /// ⚠️ The regression. A staked address with no payout history yet.
    func testANullDistributionsListDecodesToNil() throws {
        let response = try decode(Self.responseWithNoHistory)

        XCTAssertNil(response.distributions)
        XCTAssertEqual(response.total, "0")
    }

    /// The populated case keeps working the same way.
    func testAPopulatedDistributionsListDecodes() throws {
        let response = try decode(Self.responseWithHistory)

        let distributions = try XCTUnwrap(response.distributions)
        XCTAssertEqual(distributions.count, 1)
        XCTAssertEqual(distributions.first?.amount, "12345")
    }

    /// Midgard omitting the key entirely, rather than sending `null`, must decode
    /// the same way — `decodeIfPresent` treats both as absent.
    func testAnOmittedDistributionsKeyDecodesToNil() throws {
        let response = try decode(Self.responseWithOmittedKey)
        XCTAssertNil(response.distributions)
    }

    /// A genuinely empty list is a third shape for the same "no history" case.
    func testAnEmptyDistributionsListDecodes() throws {
        let response = try decode(Self.responseWithEmptyList)
        XCTAssertEqual(response.distributions, [])
    }

    /// All three "no history" shapes normalize to the same `[]` the call site
    /// (`calculateTcyAPY`'s `guard !distributions.isEmpty else { return 0 }`)
    /// keys its zero-rate branch on.
    func testAllNoHistoryShapesNormalizeToAnEmptyArray() throws {
        for json in [Self.responseWithNoHistory, Self.responseWithOmittedKey, Self.responseWithEmptyList] {
            let normalized = try decode(json).distributions ?? []
            XCTAssertEqual(normalized, [])
        }
    }

    // MARK: - Fixtures

    /// Verbatim from `https://.../thorchain_midgard/v2/tcy/distribution/{address}`
    /// for a real address with a small, fresh TCY stake.
    private static let responseWithNoHistory = """
    {
        "address": "thor18altpx2gwt4c4ejr5uzda4kyzsudyn9q56fnng",
        "apr": "0",
        "distributions": null,
        "total": "0"
    }
    """

    private static let responseWithHistory = """
    {
        "address": "thor18altpx2gwt4c4ejr5uzda4kyzsudyn9q56fnng",
        "apr": "1.5",
        "distributions": [{"date": "1700000000", "amount": "12345"}],
        "total": "12345"
    }
    """

    private static let responseWithOmittedKey = """
    {
        "address": "thor18altpx2gwt4c4ejr5uzda4kyzsudyn9q56fnng",
        "apr": "0",
        "total": "0"
    }
    """

    private static let responseWithEmptyList = """
    {
        "address": "thor18altpx2gwt4c4ejr5uzda4kyzsudyn9q56fnng",
        "apr": "0",
        "distributions": [],
        "total": "0"
    }
    """
}
