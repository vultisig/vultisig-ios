//
//  DeeplinkDepositTests.swift
//  VultisigAppTests
//
//  `type=Deposit` hands a MsgDeposit memo to the Custom form. The link is attacker-supplied,
//  so what it may and may not stage is pinned here.
//

import XCTest
@testable import VultisigApp

@MainActor
final class DeeplinkDepositTests: XCTestCase {

    private let logic = DeeplinkLogic(locale: Locale(identifier: "en_US"))

    private func parse(_ url: String) throws -> DeeplinkLogic.DeeplinkResult {
        try logic.extractParameters(URL(string: url)!, vaults: [])
    }

    func testParsesDepositLink() throws {
        let result = try parse("vultisig://vultisig.com?type=Deposit&assetChain=THORChain&memo=TCY%2B&amount=0.01")

        XCTAssertEqual(result.type, .Deposit)
        XCTAssertEqual(result.assetChain, "THORChain")
        XCTAssertNil(result.assetTicker)
        XCTAssertEqual(result.sendMemo, "TCY+")
        XCTAssertEqual(result.sendAmount, "0.01")
        XCTAssertTrue(result.pendingDepositDeeplink)
        XCTAssertTrue(result.shouldNotify)
    }

    func testMemoIsDecodedOnce() throws {
        let result = try parse("vultisig://vultisig.com?type=Deposit&assetChain=THORChain&memo=a%2520b")
        XCTAssertEqual(result.sendMemo, "a%20b")
    }

    func testDepositNeverCarriesKeysignOrKeygenPayload() throws {
        let result = try parse("vultisig://vultisig.com?type=Deposit&assetChain=THORChain&memo=x&jsonData=abc")
        XCTAssertNil(result.jsonData)
        XCTAssertNil(result.tssType)
    }

    func testBadAmountIsDropped() throws {
        let result = try parse("vultisig://vultisig.com?type=Deposit&assetChain=THORChain&memo=x&amount=1e5")
        XCTAssertNil(result.sendAmount)
    }

    func testRejectsBlankMemoAndUnsupportedChains() {
        XCTAssertNotNil(logic.depositError(assetChain: "THORChain", memo: nil))
        XCTAssertNotNil(logic.depositError(assetChain: "THORChain", memo: "  "))
        XCTAssertNotNil(logic.depositError(assetChain: nil, memo: "TCY+"))
        XCTAssertNotNil(logic.depositError(assetChain: "Ethereum", memo: "TCY+"))
        XCTAssertNotNil(logic.depositError(assetChain: "THORChainStagenet", memo: "TCY+"))
        XCTAssertNil(logic.depositError(assetChain: "thorchain", memo: "TCY+"))
        XCTAssertNil(logic.depositError(assetChain: "MayaChain", memo: "TCY+"))
    }

    func testDepositLinkDoesNotRequireJoinConfirmationOrPushRoute() {
        let url = URL(string: "https://vultisig.com?type=Deposit&assetChain=THORChain&memo=x")!
        XCTAssertFalse(DeeplinkRoutingPolicy.requiresJoinConfirmation(url))
        XCTAssertFalse(DeeplinkRoutingPolicy.allowsPushNotificationRoute(url))
    }
}
