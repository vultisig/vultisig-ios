//
//  VultServiceTests.swift
//  VultisigAppTests
//
//  Golden calldata vectors for the sVULT staking wrapper. Each encoder is
//  byte-equal to a fixed hex string (selector + head-only static-arg layout),
//  computed independently from the verified ABI selectors. This is the
//  correctness gate before any on-chain attempt — a wrong selector or arg order
//  silently sends a bad tx.
//

import BigInt
import XCTest
@testable import VultisigApp

final class VultServiceTests: XCTestCase {

    private let account = "0x8b937c5395d95a8c8948c7c5b844e1541798d90c"
    private let receiver = "0xecfe16242e796c853aa0132c06651626d54ee1e6"
    // 1500 VULT (18 decimals) = 0x5150ae84a8cdf00000.
    private let amount = BigInt("1500000000000000000000")
    private let requestId = BigInt(42)

    private func hex(_ data: Data) -> String {
        "0x" + data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Calldata golden vectors

    func testDepositForMatchesGoldenVector() throws {
        let data = try VultService.shared.encodeDepositFor(account: account, amount: amount)
        XCTAssertEqual(
            hex(data),
            "0x2f4f21e20000000000000000000000008b937c5395d95a8c8948c7c5b844e1541798d90c00000000000000000000000000000000000000000000005150ae84a8cdf00000"
        )
    }

    func testRequestUnstakeMatchesGoldenVector() throws {
        let data = try VultService.shared.encodeRequestUnstake(amount: amount)
        XCTAssertEqual(
            hex(data),
            "0x2309572100000000000000000000000000000000000000000000005150ae84a8cdf00000"
        )
    }

    func testClaimMatchesGoldenVector() throws {
        let data = try VultService.shared.encodeClaim(requestId: requestId, receiver: receiver)
        XCTAssertEqual(
            hex(data),
            "0xddd5e1b2000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000ecfe16242e796c853aa0132c06651626d54ee1e6"
        )
    }

    func testCancelUnstakeMatchesGoldenVector() throws {
        let data = try VultService.shared.encodeCancelUnstake(requestId: requestId)
        XCTAssertEqual(
            hex(data),
            "0x2b187b2b000000000000000000000000000000000000000000000000000000000000002a"
        )
    }

    func testApproveTargetsStakedVultAsSpender() throws {
        let data = try VultService.shared.encodeApprove(amount: amount)
        XCTAssertEqual(
            hex(data),
            "0x095ea7b300000000000000000000000011113d7311fb8584a6e82bb126aa11d92e5fb39b00000000000000000000000000000000000000000000005150ae84a8cdf00000"
        )
    }

    // MARK: - Edge cases

    func testZeroRequestIdEncodes() throws {
        let data = try VultService.shared.encodeCancelUnstake(requestId: .zero)
        XCTAssertEqual(
            hex(data),
            "0x2b187b2b0000000000000000000000000000000000000000000000000000000000000000"
        )
    }

    func testInvalidAccountThrows() {
        XCTAssertThrowsError(try VultService.shared.encodeDepositFor(account: "not-an-address", amount: amount))
    }

    func testInvalidReceiverThrows() {
        XCTAssertThrowsError(try VultService.shared.encodeClaim(requestId: requestId, receiver: "0xzz"))
    }
}
