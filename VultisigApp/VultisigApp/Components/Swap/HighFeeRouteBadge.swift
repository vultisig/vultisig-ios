//
//  HighFeeRouteBadge.swift
//  VultisigApp
//

import SwiftUI

/// Small pill marking a Select-route row whose own fees take a large share of
/// the swap. It marks the row without disabling it — the route stays selectable,
/// and it is still ranked purely on net output.
struct HighFeeRouteBadge: View {
    var body: some View {
        Text("swapRouteHighFee".localized)
            .font(Theme.fonts.caption10)
            .foregroundStyle(Theme.colors.alertWarning)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.colors.alertWarning.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.colors.bgSurface2, lineWidth: 1))
    }
}

#Preview {
    HighFeeRouteBadge()
}
