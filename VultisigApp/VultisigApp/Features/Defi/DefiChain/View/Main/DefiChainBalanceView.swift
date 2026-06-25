//
//  DefiChainBalanceView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiChainBalanceView: View {
    @ObservedObject var vault: Vault
    let chain: Chain

    @EnvironmentObject var homeViewModel: HomeViewModel

    private let service = DefiBalanceService()

    @State private var balance: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chain.name)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.bodyLMedium)

            HiddenBalanceText(balance)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.priceTitle1)
                .contentTransition(.numericText())
                .animation(.interpolatingSpring, value: balance)
        }
        .frame(height: 118)
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundView)
        .onAppear { updateBalance() }
        .onChange(of: vault) { _, _ in
            updateBalance()
        }
        .onChange(of: vault.defiPositions) { _, _ in
            updateBalance()
        }
        .onReceive(NotificationCenter.default.publisher(for: .defiPositionsDidChange)) { _ in
            // SwiftData mutates the vault's nested position arrays in place; the parent vault's
            // `objectWillChange` does not fire, so observe the explicit upsert notification.
            updateBalance()
        }
    }

    var backgroundView: some View {
        RoundedRectangle(cornerRadius: 16)
            .inset(by: 0.5)
            .stroke(Color(hex: "34E6BF").opacity(0.17))
            .fill(gradientStyle)
            .overlay(imageView, alignment: .topTrailing)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var imageName: String? {
        switch chain {
        case .thorChain:
            "thorchain-defi-banner"
        case .mayaChain:
            "maya-defi-banner"
        case .ton:
            "ton-defi-banner"
        case .terra, .terraClassic:
            "terra-defi-banner"
        default:
            nil
        }
    }

    private func cosmosStakingIconOverlay(logo: String) -> some View {
        ZStack {
            Image(logo)
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 70)
                .clipShape(Circle())

            Circle()
                .stroke(Color(hex: "DC9B1A").opacity(0.4), lineWidth: 2.2)
                .frame(width: 118, height: 118)

            Circle()
                .stroke(Color(hex: "EDBC5B").opacity(0.25), lineWidth: 1)
                .frame(width: 145, height: 145)
                .shadow(color: Color(red: 0, green: 0.6, blue: 0.92).opacity(0.27), radius: 13.33278, x: 0, y: 0)
        }
        .opacity(0.8)
        .frame(width: 200, height: 200)
        .offset(x: 35, y: -10)
    }

    @ViewBuilder
    var imageView: some View {
        if let imageName {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200, height: 200)
                .offset(x: 35, y: -10)
        } else {
            cosmosStakingIconOverlay(logo: "qbtc")
        }
    }

    var gradientStyle: some ShapeStyle {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(hex: "34E6BF"), location: 0.00),
                Gradient.Stop(color: Color(red: 0.11, green: 0.5, blue: 0.42).opacity(0), location: 1.00)
            ],
            startPoint: UnitPoint(x: 0.5, y: 0),
            endPoint: UnitPoint(x: 0.5, y: 1)
        ).opacity(0.09)
    }

    func updateBalance() {
        balance = service.totalBalanceInFiatString(for: chain, vault: vault)
    }
}

#Preview {
    DefiChainBalanceView(vault: .example, chain: .thorChain)
        .environmentObject(HomeViewModel())
}
