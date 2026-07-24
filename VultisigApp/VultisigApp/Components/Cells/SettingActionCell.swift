//
//  SettingActionCell.swift
//  VultisigApp
//
//  Settings → Advanced row that renders a labelled action button on the
//  right side instead of a Toggle / Picker. Used for debug-only actions
//  (e.g. "Clear SwapKit tokens cache") that fire a single closure when
//  tapped. Visual style mirrors `SettingToggleCell` / `SettingPickerCell`
//  so the rows align cleanly when stacked.
//

import SwiftUI

struct SettingActionCell: View {
    let title: String
    let icon: String
    let buttonLabel: String
    /// Button style. Defaults to `.secondary`; a destructive action passes
    /// `.alert` so the button renders in `Theme.colors.alertError` from the
    /// design system rather than a hardcoded colour.
    var buttonType: ButtonType = .secondary
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Theme.fonts.bodyLRegular)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(title)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textPrimary)
            Spacer()
            PrimaryButton(title: buttonLabel, type: buttonType, size: .mini, action: action)
                .fixedSize()
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
    }
}
