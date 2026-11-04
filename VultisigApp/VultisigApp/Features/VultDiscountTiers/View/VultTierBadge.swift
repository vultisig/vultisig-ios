//
//  VultTierBadge.swift
//  VultisigApp
//

import SwiftUI

/// Small pill that marks a feature as gated behind a $VULT tier, shown beside
/// the feature's title in settings rows.
struct VultTierBadge: View {
    var body: some View {
        Text("vultTierBadge".localized)
            .settingsText(.caption)
            .foregroundStyle(Theme.colors.primaryAccent4)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.colors.bgSurface12)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.colors.bgSurface2, lineWidth: 1))
    }
}

#Preview {
    VultTierBadge()
}
