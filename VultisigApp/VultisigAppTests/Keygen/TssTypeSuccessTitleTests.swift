//
//  TssTypeSuccessTitleTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class TssTypeSuccessTitleTests: XCTestCase {

    func testReshareUsesVaultResharedTitle() {
        XCTAssertEqual(TssType.Reshare.keygenSuccessTitleKey, "vaultReshared")
    }

    func testNonReshareFlowsKeepVaultCreatedTitle() {
        XCTAssertEqual(TssType.Keygen.keygenSuccessTitleKey, "vaultCreated")
        XCTAssertEqual(TssType.KeyImport.keygenSuccessTitleKey, "vaultCreated")
        XCTAssertEqual(TssType.Migrate.keygenSuccessTitleKey, "vaultCreated")
        XCTAssertEqual(TssType.SingleKeygen.keygenSuccessTitleKey, "vaultCreated")
    }
}
