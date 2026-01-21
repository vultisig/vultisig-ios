//
//  VaultMainScreenBackground.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftUI

struct VaultMainScreenBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .top) {
                Theme.colors.bgPrimary
                    .ignoresSafeArea(.all)
                linearGradient
                    .frame(width: width, height: 112)
                    .ignoresSafeArea(edges: .top)
                radialGradient
                    .frame(width: width, height: width)
                    .offset(y: -width / 3)
            }
        }
    }
    
    var radialGradient: some View {
        EllipticalGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.02, green: 0.22, blue: 0.78), location: 0.00),
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0), location: 1.00)
            ],
            center: UnitPoint(x: 0.5, y: 0.5)
        )
        .blur(radius: 36)
        .opacity(0.3)
    }
    
    var linearGradient: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.02, green: 0.22, blue: 0.78), location: 0.00),
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0), location: 1.00)
            ],
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.5, y: 1)
        )
        .blur(radius: 36)
        .opacity(0.3)
    }
}

#Preview {
    VaultMainScreenBackground()
}
