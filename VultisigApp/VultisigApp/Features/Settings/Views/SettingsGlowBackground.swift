//
//  SettingsGlowBackground.swift
//  VultisigApp
//

import SwiftUI

/// The soft glow behind the settings empty, update and destructive states.
struct SettingsGlowBackground: View {
    enum Tint {
        /// Teal to blue, behind empty and update states.
        case neutral
        /// Red, behind Delete Vault.
        case destructive

        var colors: (start: Color, end: Color) {
            switch self {
            case .neutral: (Color(hex: "33E6BF"), Color(hex: "0439C7"))
            case .destructive: (Color(hex: "D32829"), Color(hex: "FF5C5C"))
            }
        }

        var size: CGSize {
            switch self {
            case .neutral: CGSize(width: 374, height: 416)
            case .destructive: CGSize(width: 374, height: 512)
            }
        }

        var opacity: Double {
            switch self {
            case .neutral: 0.18
            case .destructive: 0.12
            }
        }
    }

    var tint: Tint = .neutral
    /// Moves the glow from the centre of the view it backs.
    let verticalOffset: CGFloat

    var body: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: tint.colors.start, location: 0.023),
                        .init(color: tint.colors.end, location: 0.986)
                    ],
                    startPoint: UnitPoint(x: -0.169, y: -0.635),
                    endPoint: UnitPoint(x: 1.295, y: -0.799)
                )
            )
            .frame(width: tint.size.width, height: tint.size.height)
            .blur(radius: 127)
            .opacity(tint.opacity)
            .offset(y: verticalOffset)
            .allowsHitTesting(false)
    }
}
