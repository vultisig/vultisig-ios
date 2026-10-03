//
//  WalletConnectRoutingTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class WalletConnectRoutingTests: XCTestCase {
    func testDeeplinkLogicRoutesWalletConnectWithoutTreatingItAsAddress() throws {
        let uri = "wc:abc123@2?relay-protocol=irn&symKey=secret"
        let result = try DeeplinkLogic().extractParameters(URL(string: uri)!, vaults: [])

        XCTAssertEqual(result.type, .Unknown)
        XCTAssertEqual(result.walletConnectURI, uri)
        XCTAssertNil(result.address)
        XCTAssertFalse(result.shouldNotify)
    }

    func testDeeplinkLogicStillRoutesAddressOnlyLinksAsUnknownAddress() throws {
        let result = try DeeplinkLogic().extractParameters(URL(string: "vultisig://thor1address")!, vaults: [])

        XCTAssertEqual(result.type, .Unknown)
        XCTAssertEqual(result.address, "thor1address")
        XCTAssertTrue(result.shouldNotify)
        XCTAssertNil(result.walletConnectURI)
    }
}
