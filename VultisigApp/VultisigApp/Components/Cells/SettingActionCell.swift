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
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Theme.fonts.bodyLRegular)
                .foregroundColor(Theme.colors.textPrimary)
            Text(title)
                .font(Theme.fonts.bodySRegular)
                .foregroundColor(Theme.colors.textPrimary)
            Spacer()
            Button(action: action) {
                Text(buttonLabel)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundColor(Theme.colors.textPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.colors.bgSurface2, lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
    }
}
