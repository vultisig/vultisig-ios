//
//  DeeplinkRoutingPolicyTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class DeeplinkRoutingPolicyTests: XCTestCase {
    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    func testPushAllowsKeysignLink() {
        XCTAssertTrue(DeeplinkRoutingPolicy.allowsPushNotificationRoute(
            url("vultisig://vultisig.com?type=SignTransaction&vault=abc&jsonData=xyz")
        ))
    }

    func testPushRejectsKeygenLink() {
        XCTAssertFalse(DeeplinkRoutingPolicy.allowsPushNotificationRoute(
            url("vultisig://vultisig.com?type=NewVault&tssType=Keygen&jsonData=xyz")
        ))
    }

    func testPushRejectsReshareLink() {
        XCTAssertFalse(DeeplinkRoutingPolicy.allowsPushNotificationRoute(
            url("vultisig://vultisig.com?type=NewVault&tssType=Reshare&jsonData=xyz")
        ))
    }

    func testPushRejectsSendAndAddressLinks() {
        XCTAssertFalse(DeeplinkRoutingPolicy.allowsPushNotificationRoute(
            url("vultisig://send?assetChain=Bitcoin&toAddress=bc1qabc")
        ))
        XCTAssertFalse(DeeplinkRoutingPolicy.allowsPushNotificationRoute(
            url("vultisig://bc1qabc")
        ))
        XCTAssertFalse(DeeplinkRoutingPolicy.allowsPushNotificationRoute(
            url("vultisig://vultisig.com/send?type=SignTransaction")
        ))
    }

    func testPushRejectsMissingOrUnknownType() {
        XCTAssertFalse(DeeplinkRoutingPolicy.allowsPushNotificationRoute(
            url("vultisig://vultisig.com?jsonData=xyz")
        ))
        XCTAssertFalse(DeeplinkRoutingPolicy.allowsPushNotificationRoute(
            url("vultisig://vultisig.com?type=Other&jsonData=xyz")
        ))
    }

    func testExternalKeygenAndReshareRequireConfirmation() {
        XCTAssertTrue(DeeplinkRoutingPolicy.requiresJoinConfirmation(
            url("vultisig://vultisig.com?type=NewVault&tssType=Keygen&jsonData=xyz")
        ))
        XCTAssertTrue(DeeplinkRoutingPolicy.requiresJoinConfirmation(
            url("vultisig://vultisig.com?type=NewVault&tssType=Reshare&jsonData=xyz")
        ))
        XCTAssertTrue(DeeplinkRoutingPolicy.requiresJoinConfirmation(
            url("https://vultisig.com/?type=NewVault&jsonData=xyz")
        ))
    }

    func testExternalSessionPayloadWithoutKeysignTypeRequiresConfirmation() {
        XCTAssertTrue(DeeplinkRoutingPolicy.requiresJoinConfirmation(
            url("vultisig://vultisig.com?type=Other&tssType=Keygen&jsonData=xyz")
        ))
        XCTAssertTrue(DeeplinkRoutingPolicy.requiresJoinConfirmation(
            url("vultisig://vultisig.com?jsonData=xyz")
        ))
    }

    func testKeysignSendAndAddressLinksDoNotRequireConfirmation() {
        XCTAssertFalse(DeeplinkRoutingPolicy.requiresJoinConfirmation(
            url("vultisig://vultisig.com?type=SignTransaction&vault=abc&jsonData=xyz")
        ))
        XCTAssertFalse(DeeplinkRoutingPolicy.requiresJoinConfirmation(
            url("vultisig://send?assetChain=Bitcoin&toAddress=bc1qabc")
        ))
        XCTAssertFalse(DeeplinkRoutingPolicy.requiresJoinConfirmation(
            url("vultisig://bc1qabc")
        ))
    }
}
