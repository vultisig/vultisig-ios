//
//  DefiCircleRow.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import SwiftUI

struct DefiCircleRow: View {
    let vault: Vault
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State private var balanceText: String = "..."
    
    var body: some View {
        HStack {
            HStack(spacing: 12) {
                // Circle Logo
                Image("circle-logo")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.colors.borderLight, lineWidth: 1))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("circleTitle", comment: "Circle"))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                    
                    if let address = vault.circleWalletAddress {
                        Text(address.truncatedMiddle)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                    } else {
                        Text(NSLocalizedString("circleRowCreateWallet", comment: "Create Wallet"))
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 4) {
                    if let _ = vault.circleWalletAddress {
                        Text("USDC")
                            .font(Theme.fonts.priceBodyS)
                            .foregroundStyle(Theme.colors.textPrimary)
                        Text(NSLocalizedString("circleRowYieldAccount", comment: "Yield Account"))
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.textTertiary)
                    } else {
                        Text(NSLocalizedString("circleRowGetStarted", comment: "Get Started"))
                            .font(Theme.fonts.priceBodyS)
                            .foregroundStyle(Theme.colors.primaryAccent4)
                    }
                }
                Icon(named: "chevron-right-small", color: Theme.colors.textPrimary, size: 16)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, CircleConstants.Design.horizontalPadding)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
        .buttonStyle(.plain)
    }
}
