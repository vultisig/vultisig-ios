//
//  PrimaryBackgroundWithGradient.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/12/2025.
//

import Foundation
import SwiftUI

struct PrimaryBackgroundWithGradient: View {
    var body: some View {
        GeometryReader { proxy in
            let minSize = min(proxy.size.width, proxy.size.height)
            ZStack(alignment: .top) {
                Theme.colors.bgPrimary
                    .ignoresSafeArea(.all)
                linearGradient
                    .frame(width: proxy.size.width, height: 112)
                    .ignoresSafeArea(edges: .top)
                radialGradient
                    .frame(width: proxy.size.width, height: minSize)
                    .offset(y: -minSize / 3)
            }
        }
    }

    var radialGradient: some View {
        EllipticalGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.02, green: 0.22, blue: 1), location: 0.00),
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 1).opacity(0), location: 1.00)
            ],
            center: UnitPoint(x: 0.5, y: 0.5)
        )
        .blur(radius: 36)
        .opacity(0.8)
    }

    var linearGradient: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0, green: 0.01, blue: 0.04), location: 0.00),
                Gradient.Stop(color: Color(red: 0.02, green: 0.18, blue: 0.44), location: 1.00)
            ],
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.5, y: 1)
        )
        .blur(radius: 37.5)
    }
}

#Preview {
    PrimaryBackgroundWithGradient()
}
