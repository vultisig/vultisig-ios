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

            if transaction.type == .swap {
                swapAmountColumn
            } else {
                amountColumn
            }

            Spacer()

            if transaction.type == .swap {
                swapAddressPill
            } else {
                addressPill
            }
        }
    }

    private var coinIcon: some View {
        AsyncImageView(
            logo: transaction.coinLogo,
            size: CGSize(width: 24, height: 24),
            ticker: transaction.coinTicker,
            tokenChainLogo: transaction.coinChainLogo
        )
    }

    // MARK: - Send/Approve Amount

    private var amountColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(transaction.amountFiat.formatToFiat(includeCurrencySymbol: true))
                .font(Theme.fonts.priceFootnote)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)

            cryptoAmountText(transaction.amountCrypto, ticker: transaction.coinTicker)
        }
    }

    // MARK: - Swap Amount

    private var swapAmountColumn: some View {
        HStack(spacing: 4) {
            cryptoAmountText(transaction.amountCrypto, ticker: transaction.coinTicker)

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(Theme.colors.textTertiary)

            cryptoAmountText(transaction.toAmountCrypto ?? "", ticker: transaction.toCoinTicker ?? "")
        }
    }

    // MARK: - Address Pill

    private var addressPill: some View {
        let prefix = transaction.type == .send ? "to".localized : "from".localized

        return HStack(spacing: 4) {
            Text(prefix)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Text(truncatedAddress(transaction.toAddress))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.colors.bgSurface2)
        .cornerRadius(99)
        .overlay(
            RoundedRectangle(cornerRadius: 99)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    private var swapAddressPill: some View {
        HStack(spacing: 4) {
            Text("to".localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Text(transaction.toCoinTicker ?? "")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.colors.bgSurface2)
        .cornerRadius(99)
        .overlay(
            RoundedRectangle(cornerRadius: 99)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func cryptoAmountText(_ crypto: String, ticker: String) -> some View {
        let amount = crypto.hasSuffix(ticker)
            ? String(crypto.dropLast(ticker.count)).trimmingCharacters(in: .whitespaces)
            : crypto

        return HStack(spacing: 4) {
            Text(amount)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(ticker)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .font(Theme.fonts.priceFootnote)
        .lineLimit(1)
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}
