//
//  View+Container.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/08/2025.
//

import SwiftUI

extension View {
    /// Wraps the content in the app's standard container chrome: a filled,
    /// rounded surface with a hairline border.
    ///
    /// The radius stays at 12 rather than moving to the container step with
    /// the rest of the app's cards, because four of this modifier's call
    /// sites are nested *inside* another one — the referral screen wraps a
    /// `containerStyle` section around `containerStyle` cards. Equal radii
    /// one inside the other already looks flat at 12; at 24 it reads as a
    /// bug. Which of the two levels is the container is a design question,
    /// not one to answer by sweeping.
    func containerStyle(
        padding: CGFloat? = nil,
        radius: CornerRadius = Theme.radius.md,
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
