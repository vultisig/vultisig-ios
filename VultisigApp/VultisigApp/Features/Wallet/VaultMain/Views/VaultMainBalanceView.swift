//
//  VaultMainBalanceView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 10/09/2025.
//

import SwiftUI

struct VaultMainBalanceView: View {
    enum Style {
        case wallet
        case defi
    }

    @ObservedObject var vault: Vault
    let balanceToShow: String
    let style: Style
    @EnvironmentObject var homeViewModel: HomeViewModel

    var body: some View {
        VStack(spacing: spacing) {
            balanceLabel
                .allowsHitTesting(false)
            Button {
                homeViewModel.hideVaultBalance.toggle()
            } label: {
                toggleBalanceVisibilityButton
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }

    var balanceLabel: some View {
        HiddenBalanceText(balanceToShow)
            .font(font)
            .foregroundStyle(Theme.colors.textPrimary)
            .contentTransition(.numericText())
            .animation(.interpolatingSpring, value: balanceToShow)
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

    var spacing: CGFloat {
        switch style {
        case .wallet: 12
        case .defi: 8
        }
    }

    var font: Font {
        switch style {
        case .wallet: Theme.fonts.priceLargeTitle
        case .defi: Theme.fonts.priceTitle1
        }
    }
}

#Preview {
    VStack {
        VaultMainBalanceView(
            vault: .example,
            balanceToShow: "US$ 100.000.000,00",
            style: .wallet
        ).environmentObject(HomeViewModel())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
}
