//
//  KeysignReviewScanRingTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class KeysignReviewScanRingTests: XCTestCase {
    func testScanPhasesSelectAnimationStates() {
        XCTAssertEqual(KeysignReviewScanRing(.idle), .hidden)
        XCTAssertEqual(KeysignReviewScanRing(.notScanned(provider: "blockaid")), .hidden)
        XCTAssertEqual(KeysignReviewScanRing(.scanning).animationState, .loading)
        XCTAssertNotNil(KeysignReviewScanRing(.scanning).accessibilityLabel)
    }

    func testSecureResultIsSafeIncludingLowRisk() {
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.noRisk))).tone, .safe)
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.low))).tone, .safe)
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.low))).animationState, .success)
        XCTAssertNotNil(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.low))).accessibilityLabel)
    }

    func testMediumRiskIsWarning() {
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.medium))).tone, .warning)
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.medium))).animationState, .mediumRisk)
    }

    func testHighAndCriticalRiskAreDanger() {
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.high))).tone, .danger)
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.critical))).tone, .danger)
        XCTAssertEqual(KeysignReviewScanRing(.scanned(KeysignReviewScanFixture.result(.critical))).animationState, .highRisk)
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
