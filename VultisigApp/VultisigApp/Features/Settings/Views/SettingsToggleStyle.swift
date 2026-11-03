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
    private static let offTrack = Color(hex: "7D909E")
    private static let knob = Color(hex: "FFFFFF")

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule(style: .circular)
                .fill(configuration.isOn ? Theme.colors.textSecondary : Self.offTrack)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Self.knob)
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
