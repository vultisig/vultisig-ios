//
//  KeysignReviewScanRingTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class KeysignReviewScanRingTests: XCTestCase {
    func testBottomInsetsMatchPlatformForLayoutAndDetentSizing() {
        #if os(macOS)
        XCTAssertEqual(KeysignReviewSheetLayout.bottomInset, 32)
        XCTAssertEqual(KeysignReviewSheetLayout.verdictBottomInset, 16)
        #else
        XCTAssertEqual(KeysignReviewSheetLayout.bottomInset, 0)
        XCTAssertEqual(KeysignReviewSheetLayout.verdictBottomInset, 0)
        #endif
    }

    func testScanPhasesSelectAnimationStates() {
        XCTAssertEqual(KeysignReviewScanRing(.idle), KeysignReviewScanRing(.scanning))
        XCTAssertEqual(KeysignReviewScanRing(.scanning).animationState, .loading)
        XCTAssertNotNil(KeysignReviewScanRing(.scanning).accessibilityLabel)
    }

    func testUnavailableScanHidesAfterCompletion() {
        XCTAssertEqual(KeysignReviewScanRing(.idle, isScanComplete: true), .hidden)
        XCTAssertEqual(KeysignReviewScanRing.hidden.animationState, .hidden)
        XCTAssertNil(KeysignReviewScanRing.hidden.accessibilityLabel)
    }

    func testFailedScanHidesRegardlessOfCompletionDelivery() {
        XCTAssertEqual(KeysignReviewScanRing(.notScanned(provider: "blockaid")), .hidden)
        XCTAssertEqual(KeysignReviewScanRing(.notScanned(provider: "blockaid"), isScanComplete: true), .hidden)
    }

    func testCompletionDoesNotHideAnActiveScanOrVerdict() {
        XCTAssertEqual(KeysignReviewScanRing(.scanning, isScanComplete: true).animationState, .loading)
        let result = KeysignReviewScanFixture.result(.noRisk)
        XCTAssertEqual(KeysignReviewScanRing(.scanned(result), isScanComplete: true).animationState, .success)
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
