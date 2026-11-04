//
//  SettingsInfoCard.swift
//  VultisigApp
//

import SwiftUI

extension View {
    /// The design's read-only card on the vault sub-screens: a translucent fill
    /// with a light hairline drawn inside the bounds.
    func settingsInfoCard(radius: CornerRadius = Theme.radius.md) -> some View {
        background(
            radius.shape
                .fill(Theme.colors.bgButtonDisabled.opacity(0.5))
                .strokeBorder(Theme.colors.borderLight, lineWidth: 1)
        )
    }
}
