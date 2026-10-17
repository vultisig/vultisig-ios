//
//  DefiChainPendingLPDepositView.swift
//  VultisigApp
//

import SwiftUI

/// A half-finished paired add MayaChain is holding, with the way to finish it.
struct DefiChainPendingLPDepositView: View {
    let card: MayaPendingLPPresentation.Card
    let canComplete: Bool
    var onComplete: () -> Void

    var body: some View {
        ContainerView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Separator(color: Theme.colors.borderLight, opacity: 1)
                row(title: "lpPendingDeposited".localized, value: card.depositedAmount)
                if let address = card.pairedAddress {
                    row(title: "lpPendingFrom".localized, value: address)
                }
                row(title: "lpPendingRefundsIn".localized, value: card.refundsIn)
                DefiButton(title: "lpPendingCompleteDeposit".localized, icon: .circlePlus) {
                    onComplete()
                }
                .disabled(!canComplete)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let coin = card.awaitedCoin {
                AsyncImageView(
                    logo: coin.logo,
                    size: CGSize(width: 40, height: 40),
                    ticker: coin.ticker,
                    tokenChainLogo: coin.tokenChainLogo
                )
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                Text(String(format: "lpPendingSubtitle".localized, card.protocolName))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            Spacer()
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            HiddenBalanceText(value)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textSecondary)
        }
    }
}
