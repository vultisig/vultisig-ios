//
//  GradientSeparator.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-31.
//

import SwiftUI

struct GradientSeparator: View {
    var color: Color = Theme.colors.textPrimary
    var opacity: CGFloat = 1

    var body: some View {
        LinearGradient(
            gradient:
                Gradient(colors: [
                    color.opacity(0),
                    color.opacity(1),
                    color.opacity(0)
                ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .mask(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(color)
                .opacity(opacity)
        )
        .frame(height: 24)
    }
}

#Preview {
    ZStack {
        Background()
        GradientSeparator()
    }
}
