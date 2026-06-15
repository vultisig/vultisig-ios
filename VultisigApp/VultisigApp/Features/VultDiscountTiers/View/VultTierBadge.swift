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
            .font(Theme.fonts.caption10)
            .foregroundStyle(Theme.colors.primaryAccent4)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.colors.primaryAccent4.opacity(0.12))
            .clipShape(Capsule())
    }
}

#Preview {
    VultTierBadge()
}
