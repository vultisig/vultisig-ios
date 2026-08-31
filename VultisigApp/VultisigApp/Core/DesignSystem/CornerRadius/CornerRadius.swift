//
//  CornerRadius.swift
//  DesignSystem
//

import SwiftUI
import VultisigDesignSystem

/// Compatibility name for existing app components.
typealias CornerRadius = VultisigDesignSystem.CornerRadius

extension View {
    /// Clips the view to the given radius token.
    ///
    /// Overloads SwiftUI's deprecated `cornerRadius(_:antialiased:)` on the
    /// token type, so a tokenised call site reads the same as the literal one
    /// it replaces while routing through `clipShape` — the replacement Apple's
    /// deprecation points at.
    func cornerRadius(_ radius: CornerRadius) -> some View {
        clipShape(radius.shape)
    }
}
