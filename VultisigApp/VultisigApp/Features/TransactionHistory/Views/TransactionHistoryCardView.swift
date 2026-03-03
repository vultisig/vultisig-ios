//
//  TransactionHistoryCardView.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistoryCardView: View {
    let transaction: TransactionHistoryData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topRow
            bottomRow
        }
        .padding(16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    // MARK: - Top Row

    private var topRow: some View {
        HStack {
            TransactionHistoryTypePill(type: transaction.type)

            Spacer()

            statusView
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch transaction.status {
        case .successful:
            Text("successful".localized)
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.alertSuccess)
        case .error:
            Text("error".localized)
                .font(Theme.fonts.caption10)
                .foregroundStyle(Theme.colors.alertError)
        case .inProgress:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("inProgress".localized)
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(spacing: 12) {
            coinIcon

            VStack(alignment: .leading, spacing: 2) {
                amountText
                addressPill
            }

            Spacer()

            fiatAmount
        }
    }

    private var coinIcon: some View {
        AsyncImageView(
            logo: transaction.coinLogo,
            size: CGSize(width: 36, height: 36),
            ticker: transaction.coinTicker,
            tokenChainLogo: transaction.coinChainLogo
        )
    }

    private var amountText: some View {
        Group {
            if transaction.type == .swap {
                HStack(spacing: 4) {
                    Text(transaction.amountCrypto)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                    Text(transaction.toAmountCrypto ?? "")
                        .lineLimit(1)
                }
            } else {
                Text(transaction.amountCrypto)
                    .lineLimit(1)
            }
        }
        .font(Theme.fonts.priceBodyS)
        .foregroundStyle(Theme.colors.textPrimary)
    }

    private var addressPill: some View {
        Group {
            if transaction.type == .send {
                Text("to".localized + " " + truncatedAddress(transaction.toAddress))
            } else if transaction.type == .swap {
                Text("to".localized + " " + (transaction.toCoinTicker ?? ""))
            } else {
                Text(truncatedAddress(transaction.toAddress))
            }
        }
        .font(Theme.fonts.caption10)
        .foregroundStyle(Theme.colors.textTertiary)
        .lineLimit(1)
    }

    private var fiatAmount: some View {
        Text(transaction.amountFiat.formatToFiat(includeCurrencySymbol: true))
            .font(Theme.fonts.priceBodyS)
            .foregroundStyle(Theme.colors.textSecondary)
    }

    // MARK: - Helpers

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}
