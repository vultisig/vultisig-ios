//
//  KeysignReviewScanStatus.swift
//  VultisigApp
//

import SwiftUI

/// What the review sheet shows in place of its figures once a Blockaid scan
/// result is on screen: reached either by Sign finding a risk, or by a tap on
/// the header's scan mark. `.safe` and `.verdict` are mutually exclusive by
/// construction (`forSecurityScanner` below), so the sheet never has to
/// reconcile the two triggers itself.
enum KeysignReviewScanStatus {
    case safe(onContinue: () -> Void)
    case verdict(KeysignReviewVerdict)
}

extension KeysignReviewScanStatus {
    /// Every review's scan-status guard, in one place: shown only while the
    /// security-scanner sheet is up and it has produced a result. Routes to
    /// the safe confirmation or the risk verdict from the result alone, so a
    /// tap that lands on a secure result never renders the verdict view.
    static func forSecurityScanner(
        showSecurityScannerSheet: Bool,
        result: SecurityScannerResult?,
        isContinueAnywayDisabled: Bool,
        onDismiss: @escaping () -> Void,
        onContinueAnyway: @escaping () -> Void
    ) -> KeysignReviewScanStatus? {
        guard showSecurityScannerSheet, let result else { return nil }
        guard !result.isSecure else { return .safe(onContinue: onDismiss) }
        return .verdict(KeysignReviewVerdict(
            result: result,
            onGoBack: onDismiss,
            onContinueAnyway: onContinueAnyway,
            isContinueAnywayDisabled: isContinueAnywayDisabled
        ))
    }
}

/// Dispatches to the safe confirmation or the risk verdict.
struct KeysignReviewScanStatusView: View {
    let status: KeysignReviewScanStatus

    var body: some View {
        switch status {
        case .safe(let onContinue):
            KeysignReviewSafeStatusView(onContinue: onContinue)
        case .verdict(let verdict):
            KeysignReviewVerdictView(verdict: verdict)
        }
    }
}

/// A secure scan result, shown in place of the review's figures. Figma
/// 82357:148413.
struct KeysignReviewSafeStatusView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 24) {
                medallion

                VStack(spacing: 12) {
                    Text("securityScannerSafeTitle".localized)
                        .keysignReviewText(.title2)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("securityScannerSafeDescription".localized)
                        .keysignReviewText(.bodyS)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            PrimaryButton(title: "continue".localized, action: onContinue)
        }
    }

    private var medallion: some View {
        KeysignReviewStatusMedallion(
            tint: Theme.colors.alertSuccess,
            icon: Icon(.check, color: Theme.colors.alertSuccess, size: 20)
        )
    }
}
