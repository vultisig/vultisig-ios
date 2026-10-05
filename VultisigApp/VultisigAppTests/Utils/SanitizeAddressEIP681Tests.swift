//
//  SanitizeAddressEIP681Tests.swift
//  VultisigAppTests
//
//  An EIP-681 ERC-20 transfer link leads with the token contract; the payee is the
//  `address` parameter.
//

@testable import VultisigApp
import XCTest

final class SanitizeAddressEIP681Tests: XCTestCase {
    private let token = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    private let payee = "0xfA0635a1d083D0bF377EFbD48DA46BB17e0106cA"

    func testTransferLinkResolvesToPayeeNotTokenContract() {
        let link = "ethereum:\(token)/transfer?address=\(payee)&uint256=8000"
        XCTAssertEqual(Utils.sanitizeAddress(address: link), payee)
    }

    func testTransferLinkWithChainIdResolvesToPayee() {
        let link = "ethereum:\(token)@1/transfer?address=\(payee)&uint256=8000"
        XCTAssertEqual(Utils.sanitizeAddress(address: link), payee)
    }

    func testTransferLinkWithoutPayeeDoesNotFallBackToTokenContract() {
        let link = "ethereum:\(token)/transfer?uint256=8000"
        XCTAssertNotEqual(Utils.sanitizeAddress(address: link), token)
    }

    func testPlainEthereumLinkStillStripsPrefix() {
        XCTAssertEqual(Utils.sanitizeAddress(address: "ethereum:\(payee)"), payee)
    }

    func testNonEthereumInputIsUnchanged() {
        XCTAssertEqual(Utils.sanitizeAddress(address: payee), payee)
    }
}
