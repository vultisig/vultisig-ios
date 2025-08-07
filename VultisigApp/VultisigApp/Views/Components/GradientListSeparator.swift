//
//  GradientListSeparator.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 30/07/2025.
//

import SwiftUI

struct GradientListSeparator: View {
    var body: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Theme.colors.bgSecondary, location: 0.00),
                Gradient.Stop(color: Theme.colors.bgTertiary, location: 0.49),
                Gradient.Stop(color: Theme.colors.bgSecondary, location: 1.00),
            ],
            startPoint: UnitPoint(x: 0, y: 0.5),
            endPoint: UnitPoint(x: 1, y: 0.5)
        )
        .frame(height: 1)
    }
}
