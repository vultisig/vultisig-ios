//
//  KeysignReviewScanRingTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class KeysignReviewScanRingTests: XCTestCase {
    func testNoVerdictDrawsNoRing() {
        XCTAssertEqual(KeysignReviewScanRing(.idle), .hidden)
        XCTAssertEqual(KeysignReviewScanRing(.scanning), .hidden)
        XCTAssertEqual(KeysignReviewScanRing(.notScanned(provider: "blockaid")), .hidden)
        XCTAssertNil(KeysignReviewScanRing(.scanning).accessibilityLabel)
    }

    func testSecureResultIsSafeIncludingLowRisk() {
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.noRisk))).tone, .safe)
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.low))).tone, .safe)
        XCTAssertNotNil(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.low))).accessibilityLabel)
    }

    func testMediumRiskIsWarning() {
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.medium))).tone, .warning)
    }

    func testHighAndCriticalRiskAreDanger() {
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.high))).tone, .danger)
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.critical))).tone, .danger)
    }
}

enum KeysignReviewScanFixture {
    static func result(_ riskLevel: SecurityRiskLevel, description: String? = nil) -> SecurityScannerResult {
        SecurityScannerResult(
            provider: "blockaid",
            isSecure: riskLevel == .noRisk || riskLevel == .low,
            riskLevel: riskLevel,
            warnings: [],
            description: description,
            recommendations: "",
            metadata: SecurityScannerMetadata()
        )
    }
}
