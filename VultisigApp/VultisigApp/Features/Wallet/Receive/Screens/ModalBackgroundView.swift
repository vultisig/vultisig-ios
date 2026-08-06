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
        // Not a scale step, and deliberately not tokenised: this pattern is the
        // backdrop of a presented sheet and its corner traces the sheet's, which
        // the platform owns. The scale stops at 24 for the same reason it has no
        // sheet step — a number that has to match a platform default is not ours
        // to standardise.
        let cornerRadius: CGFloat = 34 // swiftlint:disable:this no_raw_corner_radius
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
