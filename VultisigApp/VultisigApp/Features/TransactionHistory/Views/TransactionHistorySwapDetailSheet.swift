//
//  TransactionHistorySwapDetailSheet.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistorySwapDetailSheet: View {
    let transaction: TransactionHistoryData

    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    fromToCards
                    detailRows
                    explorerButton
                }
                .padding(16)
            }
            .background(Theme.colors.bgPrimary)
            .navigationTitle("swap".localized)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        TransactionHistoryTypePill(type: .swap)
            .padding(.top, 8)
    }

    // MARK: - From/To Cards

    private var fromToCards: some View {
        ZStack {
            HStack(spacing: 8) {
                coinCard(
                    logo: transaction.coinLogo,
                    chainLogo: transaction.coinChainLogo,
                    ticker: transaction.coinTicker,
                    amount: transaction.amountCrypto,
                    fiat: transaction.amountFiat,
                    isFrom: true
                )

                coinCard(
                    logo: transaction.toCoinLogo ?? "",
                    chainLogo: transaction.toCoinChainLogo,
                    ticker: transaction.toCoinTicker ?? "",
                    amount: transaction.toAmountCrypto ?? "",
                    fiat: transaction.toAmountFiat ?? "",
                    isFrom: false
                )
            }

            chevronIcon
        }
    }

    private func coinCard(
        logo: String,
        chainLogo: String?,
        ticker: String,
        amount: String,
        fiat: String,
        isFrom: Bool
    ) -> some View {
        VStack(spacing: 8) {
            Text(isFrom ? "from".localized : "to".localized)
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.caption10)

            AsyncImageView(
                logo: logo,
                size: CGSize(width: 32, height: 32),
                ticker: ticker,
                tokenChainLogo: chainLogo
            )
            .padding(.bottom, 8)

            VStack(spacing: 4) {
                Text(amount)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)

                Text(fiat.formatToFiat(includeCurrencySymbol: true))
                    .font(Theme.fonts.caption10)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
        .frame(height: 130)
        .frame(maxWidth: .infinity)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    private var chevronIcon: some View {
        Image(systemName: "chevron.right")
            .foregroundStyle(Theme.colors.textButtonDisabled)
            .font(Theme.fonts.caption12)
            .bold()
            .frame(width: 24, height: 24)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(60)
            .padding(8)
            .background(Theme.colors.bgPrimary)
            .cornerRadius(60)
            .overlay(
                Circle()
                    .stroke(Theme.colors.border, lineWidth: 1)
            )
    }

    // MARK: - Detail Rows

    private var detailRows: some View {
        VStack(spacing: 0) {
            detailRow(title: "status".localized, value: statusText, valueColor: statusColor)
            Separator().opacity(0.2)
            detailRow(title: "from".localized, value: truncatedAddress(transaction.fromAddress))
            Separator().opacity(0.2)
            detailRow(title: "to".localized, value: truncatedAddress(transaction.toAddress))
            Separator().opacity(0.2)
            detailRow(title: "date".localized, value: formattedDate)
            Separator().opacity(0.2)
            detailRow(title: "fee".localized, value: feeText)

            if let provider = transaction.swapProvider {
                Separator().opacity(0.2)
                detailRow(title: "provider".localized, value: provider)
            }

            Separator().opacity(0.2)
            detailRow(title: "network".localized, value: transaction.network)
        }
        .padding(.horizontal, 24)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }

    private func detailRow(title: String, value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.colors.textTertiary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor ?? Theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(Theme.fonts.bodySMedium)
        .padding(.vertical, 12)
    }

    // MARK: - Explorer Button

    private var explorerButton: some View {
        PrimaryButton(title: "viewOnExplorer") {
            if let url = URL(string: transaction.explorerLink) {
                openURL(url)
            }
        }
    }

    // MARK: - Helpers

    private var statusText: String {
        switch transaction.status {
        case .successful:
            return "successful".localized
        case .error:
            return "error".localized
        case .inProgress:
            return "inProgress".localized
        }
    }

    private var statusColor: Color {
        switch transaction.status {
        case .successful:
            return Theme.colors.alertSuccess
        case .error:
            return Theme.colors.alertError
        case .inProgress:
            return Theme.colors.textTertiary
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: transaction.createdAt)
    }

    private var feeText: String {
        if transaction.feeCrypto.isEmpty {
            return "-"
        }
        return transaction.feeCrypto
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 14 else { return address }
        return "\(address.prefix(8))...\(address.suffix(6))"
    }
}
