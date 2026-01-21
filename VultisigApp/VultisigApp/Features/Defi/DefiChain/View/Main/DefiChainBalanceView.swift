//
//  DefiTHORChainBalanceView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct DefiChainBalanceView: View {
    @ObservedObject var vault: Vault
    let groupedChain: GroupedChain

    @EnvironmentObject var homeViewModel: HomeViewModel

    let service = DefiBalanceService()
    var balance: String {
        service.totalBalanceInFiatString(for: groupedChain.chain, vault: vault)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(groupedChain.name)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.bodyLMedium)

            Text("balance".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.caption12)
                .padding(.top, 12)

            HiddenBalanceText(balance)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.priceTitle1)
                .contentTransition(.numericText())
                .animation(.interpolatingSpring, value: balance)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(backgroundView)
    }

    var backgroundView: some View {
        RoundedRectangle(cornerRadius: 16)
            .inset(by: 0.5)
            .stroke(Color(hex: "34E6BF").opacity(0.17))
            .fill(gradientStyle)
            .overlay(imageView, alignment: .trailing)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var imageName: String {
        switch groupedChain.chain {
        case .thorChain:
            "thorchain-banner"
        case .mayaChain:
            "mayachain-banner"
        default:
            ""
        }
    }

    var imageView: some View {
        Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
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
}

#Preview {
    let groupedChain = GroupedChain(
        chain: .thorChain,
        address: "bc1psrjtwm7682v6nhx2...uwfgcfelrennd7pcvq",
        logo: "thorchain",
        count: 3,
        coins: [Coin.example]
    )
    DefiChainBalanceView(vault: .example, groupedChain: groupedChain)
        .environmentObject(HomeViewModel())
}
