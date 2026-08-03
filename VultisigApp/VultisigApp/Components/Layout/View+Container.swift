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
    /// **The default is the container step, and a `containerStyle` nested
    /// inside another one passes an explicit smaller step.** Most call sites
    /// are the outer surface on their page, so that is the default; the
    /// handful that sit inside another container — the referral screen wraps a
    /// section around several cards — say `radius: Theme.radius.md` so the
    /// nesting still reads as nesting.
    ///
    /// The two levels have to *differ*. Equal radii one inside the other is
    /// what looks wrong, and it looks wrong at any value; holding everything
    /// at the inner step to avoid it just makes every container too tight.
    /// When adding a call site, look at where the view is actually rendered
    /// rather than at what it is called — a view named "banner" or "card" is
    /// still content when something else already draws the surface around it.
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
