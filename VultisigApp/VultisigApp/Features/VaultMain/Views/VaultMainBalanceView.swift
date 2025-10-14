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
    
    var body: some View {
        Button {
            homeViewModel.hideVaultBalance.toggle()
        } label: {
            VStack(spacing: 12) {
                balanceLabel
                toggleBalanceVisibilityButton
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    var balanceLabel: some View {
        Text(homeViewModel.vaultBalanceText)
            .font(Theme.fonts.priceLargeTitle)
            .foregroundStyle(Theme.colors.textPrimary)
            .frame(height: 47)
            .contentTransition(.numericText())
            .animation(.interpolatingSpring, value: homeViewModel.vaultBalanceText)
    }

    var toggleBalanceVisibilityButton: some View {
        HStack(spacing: 4) {
            Icon(
                named: homeViewModel.hideVaultBalance ? "eye-open" : "eye-closed",
                color: Color(hex: "5180FC"),
                size: 16
            )
            .contentTransition(.symbolEffect)
            Text(homeViewModel.hideVaultBalance ? "showBalance".localized : "hideBalance".localized)
                .foregroundStyle(Color(hex: "5180FC"))
                .font(Theme.fonts.caption12)
                .contentTransition(.interpolate)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "5180FC").opacity(0.12)))
        .frame(width: 120)
        .animation(.interactiveSpring(duration: 0.3), value: homeViewModel.hideVaultBalance)
    }
}

#Preview {
    VStack {
        VaultMainBalanceView(vault: .example)
            .environmentObject(HomeViewModel())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
}
