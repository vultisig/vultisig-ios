//
//  KeysignReviewVerdictView.swift
//  VultisigApp
//

import SwiftUI

/// An unsafe scan result, shown in place of the review's figures after Sign
/// is tapped, or after a tap on the header's scan mark.
struct KeysignReviewVerdict {
    let result: SecurityScannerResult
    let onGoBack: () -> Void
    let onContinueAnyway: () -> Void
    /// Reached by tapping the scan mark, "Continue anyway" must not bypass
    /// the review's own signing preconditions (unchecked confirmations, a fee
    /// still loading, a refused decode...). Driven by the same predicate the
    /// Sign/Join button disables on, never a copy of it.
    var isContinueAnywayDisabled: Bool = false
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
                .disabled(verdict.isContinueAnywayDisabled)
                .opacity(verdict.isContinueAnywayDisabled ? 0.4 : 1)
            }
        }
    }

    private var isDanger: Bool {
        KeysignReviewScanRing.Tone.forResult(verdict.result) == .danger
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
        KeysignReviewStatusMedallion(tint: tint, icon: verdictIcon)
    }

    var verdictIcon: Icon {
        Icon(isDanger ? .keysignReviewDanger : .keysignReviewWarning, color: tint, size: 20)
    }
}

/// The circular status glyph shared by every scan-status view: a dark
/// medallion with a soft tint glow behind a centred icon.
struct KeysignReviewStatusMedallion: View {
    let tint: Color
    let icon: Icon

    var body: some View {
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

            icon
        }
        .frame(width: 48, height: 49)
        .accessibilityHidden(true)
    }
}
