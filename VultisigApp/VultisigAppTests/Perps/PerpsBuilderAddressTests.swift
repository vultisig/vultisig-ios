//
//  PerpsBuilderAddressTests.swift
//  VultisigAppTests
//
//  The perps builder fee goes to the Vultisig EVM fee address. A look-alike
//  sharing its first and last characters exists (address poisoning), so pin
//  the builder to the exact address the swap integrations already pay.
//

import XCTest
@testable import VultisigApp

final class PerpsBuilderAddressTests: XCTestCase {
    private static let vultisigFeeAddress = "0x8E247a480449c84a5fDD25974A8501f3EFa4ABb9"

    func testBuilderIsTheKyberSwapReferrer() {
        XCTAssertEqual(PerpsConfig.builderAddress, KyberSwapService.referrerAddress)
    }

    func testBuilderIsTheFullVultisigFeeAddress() {
        XCTAssertEqual(PerpsConfig.builderAddress, Self.vultisigFeeAddress)
        XCTAssertEqual(PerpsConfig.builderAddress.count, 42)
    }

    func testBuilderOnTheWireIsTheSameAddressLowercased() throws {
        let fee = try XCTUnwrap(PerpsConfig.builderFee(tier: nil))
        let action = HLActions.order([], builder: fee).jsonString
        XCTAssertTrue(action.contains("\"b\":\"\(Self.vultisigFeeAddress.lowercased())\""), action)
    }
}
