//
//  UpgradeGG20HomeBanner.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI

struct UpgradeFromGG20HomeBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            icon
            title
            Spacer()
        }
        .padding(.vertical)
        .frame(height: 48)
        .foregroundColor(Theme.colors.alertInfo)
        .background(Theme.colors.bgSuccess)
        .cornerRadius(12)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.alertInfo, lineWidth: 1)
                .opacity(0.25)
        )
        .padding(16)
        .background(Theme.colors.bgPrimary)
    }

    var icon: some View {
        Image(systemName: "arrow.up.circle")
            .font(Theme.fonts.bodyLMedium)
    }

    var title: some View {
        Text(NSLocalizedString("upgradeYourVaultNow", comment: ""))
            .font(Theme.fonts.bodySMedium)
    }
}

#Preview {
    UpgradeFromGG20HomeBanner()
}
