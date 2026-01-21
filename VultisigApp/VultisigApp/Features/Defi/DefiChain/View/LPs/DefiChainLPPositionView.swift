//
//  DefiChainLPPositionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/10/2025.
//

import SwiftUI

struct DefiChainLPPositionView: View {
    @ObservedObject var vault: Vault
    let position: LPPosition
    let fiatAmount: String
    var onRemove: () -> Void
    var onAdd: () -> Void

    var title: String {
        String(format: "coinPool".localized, "\(position.coin1.ticker)/\(position.coin2.ticker)")
    }

    var removeDisabled: Bool { position.coin1Amount.isZero }

    var body: some View {
        ContainerView {
            VStack(spacing: 16) {
                header
                Separator(color: Theme.colors.borderLight, opacity: 1)
                aprSection
                lpPositionAmountView
                lpButtonsView
            }
        }
    }

    var header: some View {
        HStack(spacing: 12) {
            AsyncImageView(
                logo: position.coin2.logo,
                size: CGSize(width: 40, height: 40),
                ticker: position.coin2.ticker,
                tokenChainLogo: position.coin2.chain.logo
            )

            VStack(alignment: .leading, spacing: .zero) {
                Text(title)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textTertiary)

                HiddenBalanceText(fiatAmount)
                    .font(Theme.fonts.priceTitle1)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.interpolatingSpring, value: fiatAmount)
            }
            Spacer()
        }
    }

    var aprSection: some View {
        HStack(spacing: 4) {
            Icon(named: "percent", size: 16)
            Text("apr".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()

            Text(position.apr.formatted(.percent.precision(.fractionLength(2))))
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.alertSuccess)
        }
    }

    var lpTitle: String {
        let amount1 = AmountFormatter.formatCryptoAmount(value: position.coin1Amount, coin: position.coin1)
        let amount2 = AmountFormatter.formatCryptoAmount(value: position.coin2Amount, coin: position.coin2)
        return "\(amount1) + \(amount2)"
    }
    var lpPositionAmountView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("position".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            HiddenBalanceText(lpTitle)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var lpButtonsView: some View {
        HStack(alignment: .top, spacing: 16) {
            DefiButton(title: "remove".localized, icon: "minus-circle", type: .secondary) {
                onRemove()
            }.disabled(removeDisabled)
            DefiButton(title: "add".localized, icon: "plus-circle") {
                onAdd()
            }
        }
    }
}

#Preview {
    VStack {
        DefiChainLPPositionView(
            vault: .example,
            position: LPPosition(
                coin1: TokensStore.TokenSelectionAssets.first(where: { $0.ticker == "RUNE" && $0.isNativeToken }) ?? .example,
                coin1Amount: 800,
                coin2: TokensStore.TokenSelectionAssets.first(where: { $0.ticker == "ETH" && $0.isNativeToken && $0.chain == .ethereum }) ?? .example,
                coin2Amount: 2,
                poolName: "AVAX.AVAX",
                poolUnits: "1234",
                apr: 0.024,
                vault: .example
            ),
            fiatAmount: "$100",
            onRemove: {},
            onAdd: {}
        )

        DefiChainLPPositionView(
            vault: .example,
            position: LPPosition(
                coin1: TokensStore.TokenSelectionAssets.first(where: { $0.ticker == "RUNE" && $0.isNativeToken }) ?? .example,
                coin1Amount: 800,
                coin2: TokensStore.TokenSelectionAssets.first(where: { $0.ticker == "USDC" && $0.chain == .ethereum }) ?? .example,
                coin2Amount: 2,
                poolName: "AVAX.AVAX",
                poolUnits: "1234",
                apr: 0.2,
                vault: .example
            ),
            fiatAmount: "$100",
            onRemove: {},
            onAdd: {}
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
    .environmentObject(HomeViewModel())
}
