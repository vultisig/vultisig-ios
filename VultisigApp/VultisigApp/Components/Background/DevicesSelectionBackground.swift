//
//  DevicesSelectionBackground.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/07/2026.
//

import SwiftUI

/// Shared blue-glow backdrop for the "How many devices do you have?"
/// selection screens (onboarding and reshare).
struct DevicesSelectionBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.height, proxy.size.width)
            ZStack(alignment: .top) {
                Theme.colors.bgPrimary
                    .ignoresSafeArea(.all)
                linearGradient
                    .frame(width: proxy.size.width, height: 100)
                    .ignoresSafeArea(edges: .top)
                    .offset(y: -24)
                let radialGradientWidth = min(width, 300)
                radialGradient
                    .frame(width: radialGradientWidth, height: radialGradientWidth * 1.5)
                    .offset(y: -radialGradientWidth / 1.3)
            }
            .ignoresSafeArea()
        }
    }

    private var radialGradient: some View {
        EllipticalGradient(
            stops: [
                Gradient.Stop(color: Color(hex: "084BFF"), location: 0.00),
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0), location: 1.00)
            ],
            center: UnitPoint(x: 0.5, y: 0.5)
        )
        .blur(radius: 36)
    }

    private var linearGradient: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0), location: 0.00),
                Gradient.Stop(color: Color(red: 0.02, green: 0.22, blue: 0.78), location: 1.00)
            ],
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.5, y: 1)
        )
        .blur(radius: 48)
    }
}

#Preview {
    DevicesSelectionBackground()
}
