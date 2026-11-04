//
//  SettingsToggleStyle.swift
//  VultisigApp
//

import SwiftUI

/// The design's switches for settings rows.
struct SettingsToggleStyle: ToggleStyle {
    enum Size {
        /// 40x24, for the rows of the settings lists.
        case small
        /// 56x30, for standalone rows such as Notifications.
        case regular

        var track: CGSize {
            switch self {
            case .small: CGSize(width: 40, height: 24)
            case .regular: CGSize(width: 56, height: 30)
            }
        }

        var knobDiameter: CGFloat {
            switch self {
            case .small: 20
            case .regular: 24
            }
        }

        var knobInset: CGFloat {
            switch self {
            case .small: 2
            case .regular: 3
            }
        }

        var onTrack: Color {
            switch self {
            case .small: Theme.colors.textSecondary
            case .regular: Theme.colors.primaryAccent4
            }
        }
    }

    private static let offTrack = Color(hex: "7D909E")
    private static let knob = Color(hex: "FFFFFF")

    var size: Size = .small

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule(style: .circular)
                .fill(configuration.isOn ? size.onTrack : Self.offTrack)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Self.knob)
                        .frame(width: size.knobDiameter, height: size.knobDiameter)
                        .padding(size.knobInset)
                }
                .frame(width: size.track.width, height: size.track.height)
                .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
