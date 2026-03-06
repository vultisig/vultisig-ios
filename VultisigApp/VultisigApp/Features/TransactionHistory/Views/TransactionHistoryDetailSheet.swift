//
//  TransactionHistoryDetailSheet.swift
//  VultisigApp
//

import SwiftUI

struct TransactionHistoryDetailSheet: View {
    let transaction: TransactionHistoryData

    @Environment(\.openURL) var openURL
    @Environment(\.dismiss) var dismiss

    var body: some View {
        container
    }

    var container: some View {
#if os(iOS)
        NavigationStack {
            content
        }
#else
        content
            .presentationSizingFitted()
            .applySheetSize(700, 550)
#endif
    }
    
    var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if transaction.type == .swap {
                    fromToCards
                }
                detailRows
                explorerButton
            }
            .padding(16)
            .padding(.top, 20)
        }
        .background(ModalBackgroundView(width: .infinity))
        .presentationBackground(Theme.colors.bgSurface1)
        .presentationDragIndicator(.visible)
        .background(Theme.colors.bgSurface1)
        .crossPlatformToolbar(ignoresTopEdge: true, showsBackButton: false) {
            #if os(macOS)
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    dismiss()
                }
            }
            #endif
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if transaction.type == .swap {
            TransactionHistoryTypePill(type: .swap)
                .padding(.top, 8)
        } else {
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
    }

    // MARK: - From/To Cards (Swap only)

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
        .padding(.horizontal, 16)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.colors.bgSurface2)
                .cornerRadius(8)
        }
        .font(Theme.fonts.bodySMedium)
        .padding(.vertical, 16)
    }

    // MARK: - Explorer Button

    private var explorerButton: some View {
        PrimaryButton(title: "viewOnExplorer", type: .secondary) {
            if let url = URL(string: transaction.explorerLink) {
                openURL(url)
            }
        }
        .fixedSize()
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
