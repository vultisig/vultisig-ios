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
        .foregroundColor(.alertTurquoise)
        .background(Color.checkboxBlue)
        .cornerRadius(12)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.alertTurquoise, lineWidth: 1)
                .opacity(0.25)
        )
        .padding(16)
        .background(Color.backgroundBlue)
    }
    
    var icon: some View {
        Image(systemName: "arrow.up.circle.dotted")
            .font(.body20MontserratMedium)
    }
    
    var title: some View {
        Text(NSLocalizedString("upgradeYourVaultNow", comment: ""))
            .font(.body14BrockmannMedium)
    }
}

#Preview {
    UpgradeFromGG20HomeBanner()
}
