//
//  KeysignReviewScanStatusTests.swift
//  VultisigAppTests
//
//  The presentation logic behind tapping the header's Blockaid scan mark:
//  which content `KeysignReviewScanStatus.forSecurityScanner` builds per scan
//  state, and that its primary action always returns to the overview while
//  "Continue anyway" follows the caller's own signing-precondition gate.
//

import SwiftUI
import XCTest
@testable import VultisigApp

@MainActor
final class KeysignReviewScanStatusTests: XCTestCase {

    // MARK: - Tap availability per scanner state

    /// The scan mark is tappable only once the animation has a terminal
    /// (`.scanned`-derived) state to play; loading and hidden have no result.
    func testOnlyTerminalScanStatesAreTappable() {
        XCTAssertFalse(KeysignReviewScanRing.AnimationState.hidden.isTerminal)
        XCTAssertFalse(KeysignReviewScanRing.AnimationState.loading.isTerminal)
        XCTAssertTrue(KeysignReviewScanRing.AnimationState.success.isTerminal)
        XCTAssertTrue(KeysignReviewScanRing.AnimationState.mediumRisk.isTerminal)
        XCTAssertTrue(KeysignReviewScanRing.AnimationState.highRisk.isTerminal)
    }

    // MARK: - Nothing shows without both a trigger and a result

    func testNoStatusWithoutTheSheetFlag() {
        let status = KeysignReviewScanStatus.forSecurityScanner(
            showSecurityScannerSheet: false,
            result: KeysignReviewScanFixture.result(.noRisk),
            isContinueAnywayDisabled: false,
            onDismiss: {}, onContinueAnyway: {}
        )
        XCTAssertNil(status)
    }

    func testNoStatusWithoutAResult() {
        let status = KeysignReviewScanStatus.forSecurityScanner(
            showSecurityScannerSheet: true,
            result: nil,
            isContinueAnywayDisabled: false,
            onDismiss: {}, onContinueAnyway: {}
        )
        XCTAssertNil(status)
    }

    // MARK: - Which status is shown per risk level

    func testSecureResultsShowTheSafeStatusIncludingLowRisk() {
        for risk in [SecurityRiskLevel.noRisk, .low] {
            let status = KeysignReviewScanStatus.forSecurityScanner(
                showSecurityScannerSheet: true,
                result: KeysignReviewScanFixture.result(risk),
                isContinueAnywayDisabled: false,
                onDismiss: {}, onContinueAnyway: {}
            )
            guard case .safe = status else {
                XCTFail("\(risk) with isSecure=true must show the safe status, got \(String(describing: status))")
                continue
            }
        }
    }

    func testUnsafeResultsShowTheVerdictAtEveryRiskLevel() {
        for risk in [SecurityRiskLevel.low, .medium, .high, .critical] {
            let result = unsafeResult(risk)
            let status = KeysignReviewScanStatus.forSecurityScanner(
                showSecurityScannerSheet: true,
                result: result,
                isContinueAnywayDisabled: false,
                onDismiss: {}, onContinueAnyway: {}
            )
            guard case .verdict(let verdict) = status else {
                XCTFail("\(risk) with isSecure=false must show the verdict, got \(String(describing: status))")
                continue
            }
            XCTAssertEqual(verdict.result.riskLevel, risk)
        }
    }

    // MARK: - Primary always returns to the overview

    func testSafePrimaryReturnsToOverview() {
        var dismissed = false
        let status = KeysignReviewScanStatus.forSecurityScanner(
            showSecurityScannerSheet: true,
            result: KeysignReviewScanFixture.result(.noRisk),
            isContinueAnywayDisabled: false,
            onDismiss: { dismissed = true }, onContinueAnyway: {}
        )
        guard case .safe(let onContinue) = status else { return XCTFail("Expected .safe") }

        onContinue()

        XCTAssertTrue(dismissed)
    }

    func testVerdictGoBackReturnsToOverview() {
        var dismissed = false
        let status = KeysignReviewScanStatus.forSecurityScanner(
            showSecurityScannerSheet: true,
            result: unsafeResult(.medium),
            isContinueAnywayDisabled: false,
            onDismiss: { dismissed = true }, onContinueAnyway: {}
        )
        guard case .verdict(let verdict) = status else { return XCTFail("Expected .verdict") }

        verdict.onGoBack()

        XCTAssertTrue(dismissed)
    }

    // MARK: - Continue anyway reuses the caller's Sign/Join predicate

    func testContinueAnywayDisabledFollowsTheCallersPredicate() {
        for disabled in [true, false] {
            let status = KeysignReviewScanStatus.forSecurityScanner(
                showSecurityScannerSheet: true,
                result: unsafeResult(.high),
                isContinueAnywayDisabled: disabled,
                onDismiss: {}, onContinueAnyway: {}
            )
            guard case .verdict(let verdict) = status else {
                XCTFail("Expected .verdict")
                continue
            }
            XCTAssertEqual(verdict.isContinueAnywayDisabled, disabled)
        }
    }

    func testContinueAnywayStillProceedsWhenEnabled() {
        var proceeded = false
        let status = KeysignReviewScanStatus.forSecurityScanner(
            showSecurityScannerSheet: true,
            result: unsafeResult(.critical),
            isContinueAnywayDisabled: false,
            onDismiss: {}, onContinueAnyway: { proceeded = true }
        )
        guard case .verdict(let verdict) = status else { return XCTFail("Expected .verdict") }

        verdict.onContinueAnyway()

        XCTAssertTrue(proceeded)
    }

    /// `KeysignReviewScanFixture.result` only builds a secure low/noRisk
    /// result; the verdict path also has to cover a scanner that reports low
    /// risk but flags it unsafe (Figma's low-risk verdict state).
    private func unsafeResult(_ riskLevel: SecurityRiskLevel) -> SecurityScannerResult {
        SecurityScannerResult(
            provider: "blockaid", isSecure: false, riskLevel: riskLevel, warnings: [],
            description: nil, recommendations: "", metadata: SecurityScannerMetadata()
        )
    }

    #if canImport(UIKit)
    // MARK: - Visual smoke check against the Figma export

    /// Renders the safe status at the design's card width and attaches it for
    /// a manual side-by-side against `review-swap-scanned-safe.png`.
    func testSafeStatusRendersForVisualComparison() throws {
        let view = KeysignReviewSafeStatusView(onContinue: {})
            .padding(.horizontal, KeysignReviewSheetLayout.horizontalInset)
            .padding(.vertical, 24)
            .frame(width: 361)
            .background(Theme.colors.bgSurface1)
        try attach(view, name: "safe-status-visual-check")
    }

    /// Same harness for a risk state, so the two attachments can be compared
    /// against each other as well as against the design.
    func testHighRiskVerdictRendersForVisualComparison() throws {
        let verdict = KeysignReviewVerdict(result: unsafeResult(.high), onGoBack: {}, onContinueAnyway: {})
        let view = KeysignReviewVerdictView(verdict: verdict)
            .padding(.horizontal, KeysignReviewSheetLayout.horizontalInset)
            .padding(.vertical, 24)
            .frame(width: 361)
            .background(Theme.colors.bgSurface1)
        try attach(view, name: "verdict-high-risk-visual-check")
    }

    private func attach(_ view: some View, name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    #endif
}
