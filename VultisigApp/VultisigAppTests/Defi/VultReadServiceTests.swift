//
//  VultReadServiceTests.swift
//  VultisigAppTests
//
//  Word-decode + receipt-log decode for the sVULT read layer. The receipt-log
//  decoder is the only path by which iOS (no eth_getLogs) learns a pending
//  request's id, so its decode + fail-closed behaviour is pinned here against a
//  fixture receipt.
//

import BigInt
import XCTest
@testable import VultisigApp

final class VultReadServiceTests: XCTestCase {

    private let owner = "0x8b937c5395d95a8c8948c7c5b844e1541798d90c"
    private let amount = BigInt("1500000000000000000000")
    private let maturity = BigInt(1_750_000_000)
    private let requestId = BigInt(42)

    // MARK: - uint / address decode

    func testDecodeUIntFromHexWord() throws {
        let raw = "0x00000000000000000000000000000000000000000000005150ae84a8cdf00000"
        XCTAssertEqual(try VultReadService.decodeUInt(raw), amount)
    }

    func testDecodeUIntFailsClosedOnEmptyPayload() {
        XCTAssertThrowsError(try VultReadService.decodeUInt("0x"))
    }

    func testDecodeUIntFailsClosedOnGarbagePayload() {
        XCTAssertThrowsError(try VultReadService.decodeUInt("0xZZZZ"))
    }

    func testDecodeAddressTakesLowWord() throws {
        let raw = "0x0000000000000000000000008b937c5395d95a8c8948c7c5b844e1541798d90c"
        XCTAssertEqual(try VultReadService.decodeAddress(raw).lowercased(), owner)
    }

    func testAbiWordsFailsClosedOnMisalignedPayload() {
        XCTAssertThrowsError(try VultReadService.abiWords("0x01"))
    }

    // MARK: - getUnstakeRequest tuple decode

    func testDecodeUnstakeRequestReadsOwnerMaturityAmount() throws {
        let raw = "0x"
            + "0000000000000000000000008b937c5395d95a8c8948c7c5b844e1541798d90c"
            + "00000000000000000000000000000000000000000000000000000000684ee180"
            + "00000000000000000000000000000000000000000000005150ae84a8cdf00000"
        let request = try VultReadService.decodeUnstakeRequest(raw)
        XCTAssertEqual(request.owner.lowercased(), owner)
        XCTAssertEqual(request.maturity, maturity)
        XCTAssertEqual(request.amount, amount)
        XCTAssertFalse(request.isEmpty)
    }

    func testDecodeUnstakeRequestRejectsShortResponse() {
        XCTAssertThrowsError(try VultReadService.decodeUnstakeRequest("0x"))
    }

    func testEmptyRequestIsDetected() throws {
        // owner == 0 / amount == 0 ⇒ settled or cancelled ⇒ prune.
        let raw = "0x" + String(repeating: "0", count: 192)
        let request = try VultReadService.decodeUnstakeRequest(raw)
        XCTAssertTrue(request.isEmpty)
    }

    // MARK: - UnstakeRequested receipt-log decode (Decision 5)

    private func sampleLog(address: String) -> [String: Any] {
        [
            "address": address,
            "topics": [
                VultConstants.EventTopic.unstakeRequested,
                "0x0000000000000000000000008b937c5395d95a8c8948c7c5b844e1541798d90c",   // owner
                "0x000000000000000000000000000000000000000000000000000000000000002a"    // requestId = 42
            ],
            "data": "0x"
                + "00000000000000000000000000000000000000000000005150ae84a8cdf00000"     // amount
                + "00000000000000000000000000000000000000000000000000000000684ee180"      // maturity
        ]
    }

    func testDecodeUnstakeRequestedLogFromReceipt() throws {
        let receipt: [String: Any] = [
            "logs": [
                // An unrelated log (different contract) must be skipped.
                ["address": "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "topics": ["0xabc"], "data": "0x"],
                sampleLog(address: VultConstants.stakedVult)
            ]
        ]
        let decoded = VultReadService.decodeUnstakeRequestedLog(
            receipt: receipt,
            contract: VultConstants.stakedVult
        )
        XCTAssertEqual(decoded?.requestId, requestId)
        XCTAssertEqual(decoded?.amount, amount)
        XCTAssertEqual(decoded?.maturity, maturity)
    }

    func testDecodeUnstakeRequestedLogMatchesContractCaseInsensitively() {
        let receipt: [String: Any] = ["logs": [sampleLog(address: VultConstants.stakedVult.lowercased())]]
        let decoded = VultReadService.decodeUnstakeRequestedLog(
            receipt: receipt,
            contract: VultConstants.stakedVult
        )
        XCTAssertEqual(decoded?.requestId, requestId)
    }

    func testDecodeReturnsNilWhenNoMatchingLog() {
        // Fail closed without crashing: an absent log yields nil, not a wrong id.
        let receipt: [String: Any] = [
            "logs": [["address": "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "topics": ["0xabc"], "data": "0x"]]
        ]
        XCTAssertNil(VultReadService.decodeUnstakeRequestedLog(receipt: receipt, contract: VultConstants.stakedVult))
    }

    func testDecodeReturnsNilWhenLogsMissing() {
        XCTAssertNil(VultReadService.decodeUnstakeRequestedLog(receipt: [:], contract: VultConstants.stakedVult))
    }

    func testDecodeReturnsNilWhenDataTooShort() {
        let badLog: [String: Any] = [
            "address": VultConstants.stakedVult,
            "topics": [
                VultConstants.EventTopic.unstakeRequested,
                "0x0000000000000000000000008b937c5395d95a8c8948c7c5b844e1541798d90c",
                "0x000000000000000000000000000000000000000000000000000000000000002a"
            ],
            "data": "0x00000000000000000000000000000000000000000000005150ae84a8cdf00000"  // only 1 word
        ]
        XCTAssertNil(VultReadService.decodeUnstakeRequestedLog(
            receipt: ["logs": [badLog]],
            contract: VultConstants.stakedVult
        ))
    }
}
