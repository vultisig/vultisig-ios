//
//  Checkbox.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-17.
//

import SwiftUI

struct Checkbox: View {
    enum Appearance: Equatable {
        case standard
        /// The settings confirmation row: caption text, the design's check, and a
        /// tappable row at least this tall.
        case settings(rowMinHeight: CGFloat)
    }

    private static var settingsRowPadding: CGFloat { 8 }

    @Binding var isChecked: Bool
    let text: String?
    var font: Font
    var alignment: TextAlignment
    var isExtended: Bool
    let appearance: Appearance

    init(
        isChecked: Binding<Bool>,
        text: String? = nil,
        font: Font = Theme.fonts.bodySMedium,
        alignment: TextAlignment = .leading,
        isExtended: Bool = true,
        appearance: Appearance = .standard
    ) {
        self._isChecked = isChecked
        self.text = text
        self.font = font
        self.alignment = alignment
        self.isExtended = isExtended
        self.appearance = appearance
    }

    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            switch appearance {
            case .standard:
                HStack(spacing: 10) {
                    check
                    description

                    if isExtended {
                        Spacer()
                    }
                }
                .contentShape(Rectangle())
            case .settings(let rowMinHeight):
                HStack(spacing: Self.settingsRowPadding) {
                    settingsCheck
                    settingsDescription

                    if isExtended {
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, Self.settingsRowPadding)
                .frame(minHeight: rowMinHeight)
                .contentShape(Rectangle())
            }
        }
        .sensoryFeedback(.selection, trigger: isChecked)
        .buttonStyle(.plain)
    }

    var check: some View {
        Image(systemName: "checkmark")
            .font(Theme.fonts.caption12)
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
            .background(bgColor)
            .cornerRadius(Theme.radius.pill)
            .opacity(isChecked ? 1 : 0)
            .overlay(
                Circle()
                    .strokeBorder(color, lineWidth: 1)
            )
    }

    private var settingsCheck: some View {
        Icon(.check2, color: Theme.colors.alertSuccess, size: 24)
            .opacity(isChecked ? 1 : 0)
            .background(
                Circle()
                    .fill(isChecked ? Theme.colors.alertSuccess.opacity(0.05) : Theme.colors.bgSurface1)
                    .strokeBorder(color, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var settingsDescription: some View {
        if let text {
            Text(NSLocalizedString(text, comment: "Checkbox description"))
                .settingsText(.caption)
                .foregroundStyle(Theme.colors.textSecondary)
                .multilineTextAlignment(alignment)
        }
    }

    var color: Color {
        isChecked ? Theme.colors.alertSuccess : Theme.colors.border
    }

    var bgColor: Color {
        isChecked ? Theme.colors.bgSuccess : Theme.colors.bgSurface1
    }

    @ViewBuilder
    var description: some View {
        if let text {
            Text(NSLocalizedString(text, comment: "Checkbox description"))
                .font(font)
                .foregroundStyle(Theme.colors.textSecondary)
                .multilineTextAlignment(alignment)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        Checkbox(isChecked: .constant(true), text: "sendingRightAddressCheck")
        Checkbox(isChecked: .constant(false), text: "sendingRightAddressCheck")
    }
    .frame(maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
