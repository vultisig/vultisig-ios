//
//  VaultMainBalanceView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/09/2025.
//

import SwiftUI

struct VaultMainBalanceView: View {
    @ObservedObject var vault: Vault
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var vaultBalanceText: String {
        guard !homeViewModel.hideVaultBalance else {
            return Array.init(repeating: "•", count: 8).joined(separator: " ")
        }
        
        return homeViewModel.selectedVault?.coins.totalBalanceInFiatString ?? ""
    }
    
    var body: some View {
        Button {
            homeViewModel.hideVaultBalance.toggle()
        } label: {
            VStack(spacing: 12) {
                balanceLabel
                toggleBalanceVisibilityButton
            }
            .animation(.interactiveSpring(duration: 0.3), value: homeViewModel.hideVaultBalance)
        }
    }
    
    var balanceLabel: some View {
        Text(vaultBalanceText)
            .font(Theme.fonts.largeTitle)
            .foregroundStyle(Theme.colors.textPrimary)
            .frame(height: 47)
    }

    
    var toggleBalanceVisibilityButton: some View {
        HStack(spacing: 4) {
            Icon(
                named: homeViewModel.hideVaultBalance ? "eye-closed" : "eye-open",
                color: Color(hex: "5180FC"),
                size: 16
            )
            Text(homeViewModel.hideVaultBalance ? "showBalance".localized : "hideBalance".localized)
                .foregroundStyle(Color(hex: "5180FC"))
                .font(Theme.fonts.caption12)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "5180FC").opacity(0.12)))
    }
}

#Preview {
    VStack {
        VaultMainBalanceView(vault: .example)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
}
