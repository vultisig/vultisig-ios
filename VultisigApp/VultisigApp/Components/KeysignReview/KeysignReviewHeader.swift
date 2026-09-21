//
//  KeysignReviewHeader.swift
//  VultisigApp
//

import SwiftUI

/// The ring around the Blockaid mark: the scan's verdict, or no ring while
/// there is none to show. The ring is colour only, so it carries the words
/// VoiceOver reads for it.
struct KeysignReviewScanRing: Equatable {
    enum Tone: Equatable {
        case safe
        case warning
        case danger
    }

    let tone: Tone?
    let accessibilityLabel: String?

    static let hidden = KeysignReviewScanRing(tone: nil, accessibilityLabel: nil)

    private init(tone: Tone?, accessibilityLabel: String?) {
        self.tone = tone
        self.accessibilityLabel = accessibilityLabel
    }

    init(_ state: SecurityScannerState) {
        guard let result = state.result else {
            self = .hidden
            return
        }
        if result.isSecure {
            self.init(
                tone: .safe,
                accessibilityLabel: "\("securityScannerTransactionScannedBy".localized) \(result.provider.capitalized)"
            )
            return
        }
        switch result.riskLevel {
        case .high:
            self.init(tone: .danger, accessibilityLabel: "securityScannerHighRiskTitle".localized)
        case .critical:
            self.init(tone: .danger, accessibilityLabel: "securityScannerCriticalRiskTitle".localized)
        case .medium:
            self.init(tone: .warning, accessibilityLabel: "securityScannerMediumRiskTitle".localized)
        case .noRisk, .low:
            self.init(tone: .warning, accessibilityLabel: "securityScannerLowRiskTitle".localized)
        }
    }

    var color: Color? {
        switch tone {
        case nil: nil
        case .safe: Theme.colors.alertSuccess
        case .warning: Theme.colors.alertWarning
        case .danger: Theme.colors.alertError
        }
    }
}

struct KeysignReviewHeader<Accessory: View>: View {
    let title: String
    let scanRing: KeysignReviewScanRing
    let onClose: () -> Void
    /// Shown just before the close button.
    let accessory: () -> Accessory

    @State private var trailingWidth: CGFloat = KeysignReviewSheetLayout.controlSize

    var body: some View {
        HStack(spacing: 0) {
            scanMark
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                accessory()
                closeButton
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trailingWidth = $0 }
        }
        .frame(height: KeysignReviewSheetLayout.controlSize)
        .overlay {
            // Centred on the sheet, so it keeps clear of the wider side.
            Text(title)
                .keysignReviewText(.title3)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, max(KeysignReviewSheetLayout.controlSize, trailingWidth) + 8)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var scanMark: some View {
        Image(.blockaidLogomark)
            .resizable()
            .foregroundStyle(Theme.colors.textPrimary)
            .frame(width: 12, height: 14)
            .frame(width: KeysignReviewSheetLayout.controlSize, height: KeysignReviewSheetLayout.controlSize)
            .background(Circle().fill(Theme.colors.bgSheetControl))
            .overlay {
                if let ringColor = scanRing.color {
                    Circle().strokeBorder(ringColor, lineWidth: 1)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(scanRing.accessibilityLabel ?? "")
            .accessibilityHidden(scanRing.accessibilityLabel == nil)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.colors.textSecondary)
                .frame(width: KeysignReviewSheetLayout.controlSize, height: KeysignReviewSheetLayout.controlSize)
                .background(Circle().fill(Theme.colors.bgSheetControl))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("close".localized)
    }
}
