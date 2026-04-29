//
//  QBTCClaimSection.swift
//  VultisigApp
//
//  Inline "Claim" button rendered on the QBTC chain detail screen.
//  Mirrors `<QbtcClaimSection />` in vultisig-windows.
//

import SwiftUI

struct QBTCClaimSection: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text("qbtcClaimTitle".localized)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.colors.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
