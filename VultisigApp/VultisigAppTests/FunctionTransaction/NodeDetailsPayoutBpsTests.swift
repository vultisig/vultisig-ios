//
//  NodeDetailsPayoutBpsTests.swift
//  VultisigAppTests
//
//  Provider entries captured from /thorchain/node/thor10tsu3gfzgywyzuuyvmjmlpehdupdcrczemne9y
//  on 2026-11-26: THORNode omits `bps` when Bond Yield is unset.
//

@testable import VultisigApp
import XCTest

final class NodeDetailsPayoutBpsTests: XCTestCase {

    private static let json = """
    {
      "node_address": "thor10tsu3gfzgywyzuuyvmjmlpehdupdcrczemne9y",
      "status": "Active",
      "current_award": "0",
      "bond_providers": {
        "node_operator_fee": "2000",
        "providers": [
          {"bond_address": "thor1kuvaypgrdqpwjccdeprvzjkwf59pgy8xyx7pp5", "bond": "4505368474649", "bps": 10000, "payout_target": "knbm"},
          {"bond_address": "thor1456ja57j5wasf23mhgjpskq8mwhxzxejplh0z5", "bond": "100692753308382"}
        ]
      }
    }
    """

    private func details() throws -> NodeDetailsResponse {
        try JSONDecoder().decode(NodeDetailsResponse.self, from: Data(Self.json.utf8))
    }

    func testReadsTheShareAProviderSet() throws {
        XCTAssertEqual(try details().payoutBps(for: "thor1kuvaypgrdqpwjccdeprvzjkwf59pgy8xyx7pp5"), 10000)
    }

    func testTreatsAnOmittedShareAsZero() throws {
        XCTAssertEqual(try details().payoutBps(for: "thor1456ja57j5wasf23mhgjpskq8mwhxzxejplh0z5"), 0)
    }

    func testHasNoShareWhenTheAddressIsNotAProvider() throws {
        XCTAssertNil(try details().payoutBps(for: "thor1x2whgc2nt665y0kc44uywhynazvp0l8tp0vtu6"))
    }
}
