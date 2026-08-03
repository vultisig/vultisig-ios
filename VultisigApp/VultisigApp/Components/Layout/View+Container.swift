//
//  View+Container.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/08/2025.
//

import SwiftUI

extension View {
    /// Wraps the content in the app's standard container chrome: a filled,
    /// rounded surface with a hairline border. The radius defaults to the
    /// container step — this modifier is only ever applied to a card, banner
    /// or list group, which is what `Theme.radius.xl` is for.
    func containerStyle(
        padding: CGFloat? = nil,
        radius: CornerRadius = Theme.radius.xl,
        bgColor: Color = Theme.colors.bgPrimary
    ) -> some View {
        self
            .padding(padding ?? 0)
            .background(bgColor)
            .cornerRadius(radius)
            .overlay(
                radius.shape
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
            .padding(1)
            .clipShape(radius.shape)
    }
}
