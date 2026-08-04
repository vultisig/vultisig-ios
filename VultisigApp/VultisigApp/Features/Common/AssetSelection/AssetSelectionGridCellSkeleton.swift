//
//  AssetSelectionGridCellSkeleton.swift
//  VultisigApp
//

import SwiftUI

/// Placeholder tile shown while a section's assets are still being fetched.
/// Mirrors `AssetSelectionGridCell`'s geometry so the grid does not reflow when
/// the real cells arrive.
struct AssetSelectionGridCellSkeleton: View {
    var body: some View {
        VStack(spacing: 10) {
            // `xl` is the tile the real cell draws, and `xs` the scale's
            // skeleton-bar step — the same pair the DeFi position skeletons use.
            Theme.radius.xl.shape
                .fill(Theme.colors.borderLight.opacity(0.3))
                .frame(width: 74, height: 74)

            Theme.radius.xs.shape
                .fill(Theme.colors.borderLight.opacity(0.3))
                .frame(width: 40, height: 12)
        }
        .frame(width: 74, height: 100)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(0..<4, id: \.self) { _ in
            AssetSelectionGridCellSkeleton()
        }
    }
}
