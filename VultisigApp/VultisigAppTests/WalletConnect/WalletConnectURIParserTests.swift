//
//  WalletConnectURIParserTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class WalletConnectURIParserTests: XCTestCase {
    func testRecognizesWalletConnectURI() {
        let uri = "wc:abc123@2?relay-protocol=irn&symKey=secret"

        XCTAssertEqual(WalletConnectURIParser.normalizedURI(from: uri), uri)
    }

    func testRecognizesUppercaseWalletConnectScheme() {
        let uri = "WC:abc123@2?relay-protocol=irn&symKey=secret"

        XCTAssertEqual(WalletConnectURIParser.normalizedURI(from: uri), uri)
    }

    func testRejectsNormalVultisigAddressURI() {
        XCTAssertNil(WalletConnectURIParser.normalizedURI(from: "vultisig://thor1address"))
    }

    func testRejectsHTTPURI() {
        XCTAssertNil(WalletConnectURIParser.normalizedURI(from: "https://vultisig.com"))
    }
}
