//
//  TransactionHistorySendDetailSheet.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistorySendDetailSheet: View {
    let transaction: TransactionHistoryData

    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    detailRows
                    explorerButton
                }
                .padding(16)
            }
            .background(Theme.colors.bgPrimary)
            .navigationTitle(transaction.type == .approve ? "approve".localized : "send".localized)
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
        VStack(spacing: 12) {
            TransactionHistoryTypePill(type: transaction.type)

            AsyncImageView(
                logo: transaction.coinLogo,
                size: CGSize(width: 48, height: 48),
                ticker: transaction.coinTicker,
                tokenChainLogo: transaction.coinChainLogo
            )

            Text(transaction.amountCrypto)
                .font(Theme.fonts.priceTitle1)
                .foregroundStyle(Theme.colors.textPrimary)

            Text(transaction.amountFiat.formatToFiat(includeCurrencySymbol: true))
                .font(Theme.fonts.priceBodyS)
                .foregroundStyle(Theme.colors.textTertiary)
        }
        .padding(.vertical, 8)
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
