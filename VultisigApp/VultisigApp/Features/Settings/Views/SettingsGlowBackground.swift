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
        /// The neutral glow, dimmer, behind the referral guide and My Referral.
        case referral

        var colors: (start: Color, end: Color) {
            switch self {
            case .neutral, .referral: (Theme.colors.turquoise, Theme.colors.primaryAccent2)
            case .destructive: (Theme.colors.destructiveGlow, Theme.colors.alertError)
            }
        }

        var size: CGSize {
            switch self {
            case .neutral, .referral: CGSize(width: 374, height: 416)
            case .destructive: CGSize(width: 374, height: 512)
            }
        }

        var opacity: Double {
            switch self {
            case .neutral: 0.18
            case .destructive: 0.12
            case .referral: 0.1
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
