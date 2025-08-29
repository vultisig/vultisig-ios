//
//  View+Container.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/08/2025.
//

import SwiftUI

extension View {
    func containerStyle(padding: CGFloat? = nil, radius: CGFloat = 12, bgColor: Color = Theme.colors.bgPrimary) -> some View {
        self
            .padding(padding ?? 0)
            .background(bgColor)
            .cornerRadius(radius)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
            .padding(1)
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}
