//
//  QBTCChainServiceTests.swift
//  VultisigAppTests
//
//  Pure-helper tests for QBTCChainService (no network).
//  Mirrors vultisig-sdk/.../getQbtcAccountInfo.ts and
//  getClaimWithProofDisabled.ts.
//

@testable import VultisigApp
import XCTest

final class QBTCChainServiceTests: XCTestCase {
    // MARK: - parseDisabledFlag

    func testDisabledFlagZeroIsEnabled() throws {
        XCTAssertFalse(try QBTCChainService.parseDisabledFlag("0"))
    }

    func testDisabledFlagOneIsDisabled() throws {
        XCTAssertTrue(try QBTCChainService.parseDisabledFlag("1"))
    }

    func testDisabledFlagAnyPositiveIsDisabled() throws {
        XCTAssertTrue(try QBTCChainService.parseDisabledFlag("5"))
        XCTAssertTrue(try QBTCChainService.parseDisabledFlag("9999"))
    }

    func testDisabledFlagRejectsNonNumeric() {
        XCTAssertThrowsError(try QBTCChainService.parseDisabledFlag("yes"))
        XCTAssertThrowsError(try QBTCChainService.parseDisabledFlag(""))
        XCTAssertThrowsError(try QBTCChainService.parseDisabledFlag("1.5"))
    }

    // MARK: - computeTimeoutNs

    func testComputeTimeoutNsAddsTenMinutesToBlockTime() throws {
        let service = QBTCChainService()
        // 2026-01-01T00:00:00Z → 1767225600000 ms → 1767225600_000_000_000 ns
        let blockTimeNs: UInt64 = 1767225600 * 1_000_000_000
        let expected = blockTimeNs + QBTCChainService.claimTimeoutNs

        let result = try service.computeTimeoutNs(blockTime: "2026-01-01T00:00:00Z")
        XCTAssertEqual(result, expected)
    }

    func testComputeTimeoutNsParsesFractionalSeconds() throws {
        let service = QBTCChainService()
        // 2026-01-01T00:00:00.500Z → blockTimeNs = 1767225600_500_000_000
        let blockTimeNs: UInt64 = 1767225600 * 1_000_000_000 + 500_000_000
        let expected = blockTimeNs + QBTCChainService.claimTimeoutNs

        let result = try service.computeTimeoutNs(blockTime: "2026-01-01T00:00:00.500Z")
        XCTAssertEqual(result, expected)
    }

    func testComputeTimeoutNsRejectsMalformedTimestamp() {
        let service = QBTCChainService()
        XCTAssertThrowsError(try service.computeTimeoutNs(blockTime: "not-a-time"))
        XCTAssertThrowsError(try service.computeTimeoutNs(blockTime: ""))
    }

    // MARK: - DTO decoding

    func testAuthAccountResponseDecodes() throws {
        let json = """
        {"account": {"address": "qbtc1abc", "account_number": "42", "sequence": "7"}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(QBTCAuthAccountResponse.self, from: json)
        XCTAssertEqual(decoded.account?.accountNumber, "42")
        XCTAssertEqual(decoded.account?.sequence, "7")
    }

    func testAuthAccountResponseDecodesEmptyBody() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(QBTCAuthAccountResponse.self, from: json)
        XCTAssertNil(decoded.account)
    }

    func testLatestBlockResponseDecodes() throws {
        let json = """
        {"block": {"header": {"height": "12345", "time": "2026-01-01T00:00:00Z"}}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(QBTCLatestBlockResponse.self, from: json)
        XCTAssertEqual(decoded.block.header.height, "12345")
        XCTAssertEqual(decoded.block.header.time, "2026-01-01T00:00:00Z")
    }

    func testParamResponseDecodes() throws {
        let json = #"{"param":{"key":"ClaimWithProofDisabled","value":"0"}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(QBTCParamResponse.self, from: json)
        XCTAssertEqual(decoded.param.key, "ClaimWithProofDisabled")
        XCTAssertEqual(decoded.param.value, "0")
    }

    // MARK: - claimTimeoutNs constant

    func testClaimTimeoutNsIsTenMinutes() {
        // 10 minutes = 600 seconds = 600 * 1e9 ns
        XCTAssertEqual(QBTCChainService.claimTimeoutNs, 600_000_000_000)
    }
}
