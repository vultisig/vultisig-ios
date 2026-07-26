//
//  BroadcastErrorClassifierTests.swift
//  VultisigAppTests
//
//  Guards the broadcast dup-sentinel classifier shared by the EVM
//  (`RpcServiceStruct`) and substrate (`RpcService`, backing Polkadot and
//  Bittensor) broadcast paths. The old substring match reported real rejections
//  — a nonce gap, a rate-limited RPC, any "unknown …" message — as a duplicate,
//  which downstream converts to a fake success hash. These tests lock in which
//  messages are true duplicates and which must stay rejections.
//

@testable import VultisigApp
import XCTest

final class BroadcastErrorClassifierTests: XCTestCase {

    func testTrueDuplicatesAreClassified() {
        for message in [
            "already known",
            "ALREADY_EXISTS",
            "transaction already exists",
            "Transaction already imported.",
            "already mined",
            "Transaction is temporarily banned",
            "nonce too low"
        ] {
            XCTAssertTrue(BroadcastErrorClassifier.isDuplicateBroadcast(message), "\(message) should be a duplicate")
        }
    }

    func testRejectionsAreNotClassifiedAsDuplicates() {
        for message in [
            "nonce too high",
            "unknown block",
            "unknown method eth_foo",
            "many requests for a specific RPC call",
            "insufficient funds for gas",
            "invalid extrinsic"
        ] {
            XCTAssertFalse(BroadcastErrorClassifier.isDuplicateBroadcast(message), "\(message) should NOT be a duplicate")
        }
    }
}
