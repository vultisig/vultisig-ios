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
        VStack(alignment: .leading, spacing: 8) {
            Text(chain.name)
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
            .overlay(imageView, alignment: .trailing)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var imageName: String {
        switch chain {
        case .thorChain:
            "thorchain-banner"
        case .mayaChain:
            "mayachain-banner"
        default:
            ""
        }
    }

    @ViewBuilder
    var imageView: some View {
        switch chain {
        case .terra, .terraClassic:
            terraIconOverlay
        default:
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    private var terraIconOverlay: some View {
        ZStack {
            Circle()
                .stroke(Theme.colors.alertSuccess.opacity(0.25), lineWidth: 2)
                .frame(width: 160, height: 160)

            Circle()
                .stroke(Theme.colors.alertSuccess.opacity(0.4), lineWidth: 4)
                .frame(width: 120, height: 120)

            Image("luna")
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 70)
                .clipShape(Circle())
        }
        .offset(x: 40, y: 20)
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
