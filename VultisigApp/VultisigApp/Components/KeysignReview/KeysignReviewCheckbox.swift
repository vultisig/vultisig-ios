//
//  KeysignReviewCheckbox.swift
//  VultisigApp
//

import SwiftUI

/// A confirmation the user ticks before signing.
struct KeysignReviewCheckbox: View {
    @Binding var isChecked: Bool
    /// Localization key of the statement being confirmed.
    let text: String

    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack(spacing: 8) {
                ring
                Text(text.localized)
                    .keysignReviewText(.bodyS)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isChecked)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    private var ring: some View {
        ZStack {
            Circle()
                .fill(Theme.colors.alertSuccess.opacity(0.05))
            Circle()
                .strokeBorder(isChecked ? Theme.colors.alertSuccess : Theme.colors.borderNormal, lineWidth: 1)
            if isChecked {
                KeysignReviewCheckmark()
                    .stroke(Theme.colors.alertSuccess, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 24, height: 24)
    }
}

/// The design's checkmark, drawn in a 24pt box.
private struct KeysignReviewCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: 9.2 * scale, y: 12.4 * scale))
        path.addLine(to: CGPoint(x: 11 * scale, y: 14.4 * scale))
        path.addLine(to: CGPoint(x: 14.8 * scale, y: 9.6 * scale))
        return path
    }
}
