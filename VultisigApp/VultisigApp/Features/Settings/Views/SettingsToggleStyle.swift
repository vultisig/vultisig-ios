//
//  SettingsToggleStyle.swift
//  VultisigApp
//

import SwiftUI

/// The design's small switch for settings rows.
struct SettingsToggleStyle: ToggleStyle {
    private static let trackSize = CGSize(width: 40, height: 24)
    private static let knobDiameter: CGFloat = 20
    private static let knobInset: CGFloat = 2

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule(style: .circular)
                .fill(configuration.isOn ? Theme.colors.textSecondary : Theme.colors.textTertiary)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Theme.colors.textPrimary)
                        .frame(width: Self.knobDiameter, height: Self.knobDiameter)
                        .padding(Self.knobInset)
                }
                .frame(width: Self.trackSize.width, height: Self.trackSize.height)
                .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
