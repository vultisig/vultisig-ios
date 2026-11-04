//
//  SettingsGlowBackground.swift
//  VultisigApp
//

import SwiftUI

/// The soft teal to blue glow behind the settings empty and update states.
struct SettingsGlowBackground: View {
    /// Moves the glow from the centre of the view it backs.
    let verticalOffset: CGFloat

    var body: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Theme.colors.turquoise, location: 0.023),
                        .init(color: Theme.colors.primaryAccent2, location: 0.986)
                    ],
                    startPoint: UnitPoint(x: -0.169, y: -0.635),
                    endPoint: UnitPoint(x: 1.295, y: -0.799)
                )
            )
            .frame(width: 374, height: 416)
            .blur(radius: 127)
            .opacity(0.18)
            .offset(y: verticalOffset)
            .allowsHitTesting(false)
    }
}
