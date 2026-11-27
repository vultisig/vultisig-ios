//
//  PerpsUnsupportedVaultScreen.swift
//  VultisigApp
//
//  Shown instead of perps for a GG20 or imported vault: the trading account
//  is a DKLS child key those vaults can't sign for, so no address, balance or
//  review is shown.
//

import SwiftUI

struct PerpsUnsupportedVaultScreen: View {
    var body: some View {
        Screen {
            VStack(spacing: 12) {
                Icon(.circleInfo, color: Theme.colors.textTertiary, size: 32)
                Text("perpsUnsupportedVaultTitle".localized)
                    .font(Theme.fonts.title3)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text("perpsUnsupportedVault".localized)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("perpsUnsupportedVault")
        }
        .screenTitle("perpsTitle".localized)
        .perpsScreenMargins()
    }
}
