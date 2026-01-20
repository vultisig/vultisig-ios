//
//  BlurredBackground.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

struct BlurredBackground: View {
    var body: some View {
        EllipticalGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.2, green: 0.9, blue: 0.75), location: 0.02),
                Gradient.Stop(color: Color(red: 0.02, green: 0.22, blue: 0.78), location: 0.99)
            ],
            center: UnitPoint(x: 0.5, y: 0.5)
        )
        .opacity(0.2)
        .blur(radius: 120)
    }
}
