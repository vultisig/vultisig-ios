//
//  ModalBackgroundView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 29/09/2025.
//

import SwiftUI

struct ModalBackgroundView: View {
    let width: CGFloat
    
    var body: some View {
        let cornerRadius: CGFloat = 34
        ZStack(alignment: .bottom) {
            magicPattern
                .frame(maxWidth: width)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Theme.colors.bgSurface1, location: 0.50),
                    Gradient.Stop(color: Theme.colors.bgSurface1.opacity(0.5), location: 0.85),
                    Gradient.Stop(color: Theme.colors.bgSurface1.opacity(0), location: 1.00)
                ],
                startPoint: UnitPoint(x: 0.5, y: 1),
                endPoint: UnitPoint(x: 0.5, y: 0)
            )
            .frame(height: 230)
        }
    }
    
    var magicPattern: some View {
        Image("magic-pattern")
            .resizable()
            .scaledToFill()
            .opacity(0.2)
            .frame(maxHeight: .infinity)
            .clipped()
    }
}
