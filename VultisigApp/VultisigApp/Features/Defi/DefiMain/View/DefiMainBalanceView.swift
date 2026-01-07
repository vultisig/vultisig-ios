//
//  DefiMainBalanceView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/10/2025.
//

import SwiftUI

struct DefiMainBalanceView: View {
    @ObservedObject var vault: Vault
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    private let defiBalanceService = DefiBalanceService()
    
    @State var balance: String = ""
    
    var body: some View {
        ZStack {
            coinImages
            VStack(spacing: 8) {
                Text("defiPortfolio".localized)
                    .font(Theme.fonts.bodyLMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                
                VaultMainBalanceView(
                    vault: vault,
                    balanceToShow: balance,
                    style: .defi
                )
            }
        }
        .frame(height: 135)
        .background(
            Theme.colors.bgSurface1
                .overlay(gradientBackground.clipped())
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.colors.border))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { updateBalance() }
        .onChange(of: vault.defiPositions) { _, _ in
            updateBalance()
        }
    }
    
    var gradientBackground: some View {
        EllipticalGradient(
            stops: [
                Gradient.Stop(color: Color(red: 0.02, green: 0.22, blue: 0.78), location: 0.00),
                Gradient.Stop(color: Color(red: 0.01, green: 0.07, blue: 0.17).opacity(0), location: 1.00),
            ],
            center: UnitPoint(x: 0.5, y: 0.9)
        )
        .frame(height: 350)
        .blur(radius: 35)
        .opacity(0.7)
    }
    
    @ViewBuilder
    var coinImages: some View {
        GeometryReader { geometry in
            // Top left corner - BNB
            Image("defi-bnb")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40)
                .position(
                    x: 30,
                    y: 18
                )
            
            // Mid left - Solana
            Image("defi-solana")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40)
                .position(
                    x: 20,
                    y: 45
                )
            
            // Bottom left corner - Ethereum
            Image("defi-eth")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60)
                .position(
                    x: 30,
                    y: geometry.size.height - 25
                )
                        
            // Top right corner - Bitcoin
            Image("defi-btc")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80)
                .position(
                    x: geometry.size.width - 40,
                    y: 40
                )
            
            // Bottom right corner - XRP
            Image("defi-xrp")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40)
                .position(
                    x: geometry.size.width - 20,
                    y: geometry.size.height - 25
                )
        }
    }
    
    func updateBalance() {
        balance = defiBalanceService.totalBalanceInFiatString(for: vault.defiChains, vault: vault)
    }
}

#Preview {
    VStack {
        DefiMainBalanceView(vault: .example)
    }
    .padding(16)
    .environmentObject(HomeViewModel())
}
