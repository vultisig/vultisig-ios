//
//  SettingsCommunityTile.swift
//  VultisigApp
//

import SwiftUI

/// One of the equal-width community link tiles: an icon over a short label.
/// Tiles fill the row's height, so a label that wraps grows the whole row.
struct SettingsCommunityTile: View {
    static let height: CGFloat = 70

    let icon: ImageResource?
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            if let icon {
                Icon(icon, color: Theme.colors.textSecondary, size: 20)
            }

            Text(title)
                .settingsText(.caption)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: .infinity)
        .background(Theme.colors.bgSurface1)
        .clipShape(Theme.radius.lg.shape)
    }
}
