//
//  SettingPickerCell.swift
//  VultisigApp
//
//  Settings → Advanced row that hosts a single-select picker. Mirrors
//  `SettingToggleCell`'s visual shape but exposes a dropdown menu on the
//  right side instead of a Toggle. Used today for the debug-only
//  "forcedSwapProvider" picker. Generic in `Selection: Hashable` so future
//  debug enums can reuse it.
//

import SwiftUI

struct SettingPickerCell<Selection: Hashable>: View {

    struct Option: Identifiable {
        let value: Selection
        let label: String
        var id: Selection { value }
    }

    let title: String
    let icon: String
    let options: [Option]
    @Binding var selection: Selection

    private var currentLabel: String {
        options.first(where: { $0.value == selection })?.label ?? "—"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Theme.fonts.bodyLRegular)
                .foregroundColor(Theme.colors.textPrimary)
            Text(title)
                .font(Theme.fonts.bodySRegular)
                .foregroundColor(Theme.colors.textPrimary)
            Spacer()
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(options) { option in
                        Text(option.label).tag(option.value)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentLabel)
                        .font(Theme.fonts.bodySRegular)
                        .foregroundColor(Theme.colors.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Theme.fonts.caption12)
                        .foregroundColor(Theme.colors.textPrimary)
                }
            }
        }
        .padding(12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
    }
}
