//
//  KeysignReviewVerdictView.swift
//  VultisigApp
//

import SwiftUI

/// An unsafe scan result, shown in place of the review's figures after Sign
/// is tapped.
struct KeysignReviewVerdict {
    let result: SecurityScannerResult
    let onGoBack: () -> Void
    let onContinueAnyway: () -> Void
}

struct KeysignReviewVerdictView: View {
    let verdict: KeysignReviewVerdict

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 24) {
                medallion

                VStack(spacing: 12) {
                    Text(title)
                        .keysignReviewText(.title2)
                        .foregroundStyle(tint)
                        .multilineTextAlignment(.center)

                    Text(verdict.result.description ?? "securityScannerDefaultDescription".localized)
                        .keysignReviewText(.bodyS)
                        .foregroundStyle(Theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 8) {
                PrimaryButton(title: "securityScannerContinueGoBack".localized, action: verdict.onGoBack)

                Button(action: verdict.onContinueAnyway) {
                    Text("securityScannerContinueAnyway".localized)
                        .keysignReviewText(.captionSmall)
                        .foregroundStyle(Theme.colors.textButtonDisabled)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var isDanger: Bool {
        KeysignReviewScanRing(.scanned(verdict.result)).tone == .danger
    }

    private var tint: Color {
        isDanger ? Theme.colors.alertError : Theme.colors.alertWarning
    }

    private var title: String {
        switch verdict.result.riskLevel {
        case .medium:
            "securityScannerMediumRiskTitle".localized
        case .high:
            "securityScannerHighRiskTitle".localized
        case .critical:
            "securityScannerCriticalRiskTitle".localized
        case .noRisk, .low:
            "securityScannerLowRiskTitle".localized
        }
    }

    private var medallion: some View {
        ZStack {
            Circle()
                .fill(Theme.colors.bgPrimary)
                .overlay(
                    Circle()
                        .stroke(Theme.colors.medallionInsetShadow, lineWidth: 2)
                        .blur(radius: 0.9)
                        .offset(y: 1.7)
                        .mask(Circle())
                )
                .overlay(Circle().stroke(Theme.colors.buttonBevelLight, lineWidth: 2))
                .frame(width: 43, height: 43)

            Rectangle()
                .fill(tint)
                .frame(width: 13.3, height: 6.7)
                .blur(radius: 7.7)

            verdictIcon
        }
        .frame(width: 48, height: 49)
        .accessibilityHidden(true)
    }

    var verdictIcon: Icon {
        Icon(isDanger ? .keysignReviewDanger : .keysignReviewWarning, color: tint, size: 20)
    }
}
