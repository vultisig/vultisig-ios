//
//  SwapDetailsSummary.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-25.
//

import SwiftUI

struct SwapDetailsSummary: View {

    @ObservedObject var tx: SwapTransaction
    @ObservedObject var detailsViewModel: SwapDetailsViewModel

    @State private var showFees: Bool = true

    private var hasExpandableFees: Bool {
        SwapCryptoLogic.showGas(tx: tx) ||
        !SwapCryptoLogic.baseAffiliateFee(tx: tx).isEmpty ||
        !outboundFeeString.isEmpty ||
        !SwapCryptoLogic.vultDiscount(tx: tx).isEmpty ||
        !SwapCryptoLogic.referralDiscount(tx: tx).isEmpty ||
        !SwapCryptoLogic.priceImpactString(tx: tx).isEmpty
    }

    /// Hide the entire Provider + fees block while a quote error is on screen
    /// (the tooltip already surfaces the error). Keep it visible during loading
    /// so placeholders still appear, and whenever a valid quote is available.
    private var isBlockVisible: Bool {
        detailsViewModel.error == nil || detailsViewModel.isLoadingQuotes
    }

    var body: some View {
        content
    }

    var content: some View {
        VStack(spacing: 16) {
            if isBlockVisible {
                if let providerName = tx.quote?.displayName {
                    getSummaryCell(
                        leadingText: "provider",
                        trailingText: providerName
                    )
                }

                if SwapCryptoLogic.showTotalFees(tx: tx) {
                    if hasExpandableFees {
                        ExpandableView(isExpanded: $showFees) {
                            totalFeesLabel()
                        } content: {
                            HStack {
                                Rectangle()
                                    .frame(width: 1)
                                    .foregroundStyle(Theme.colors.primaryAccent4)

                                expandableFees
                            }
                            .padding(.top, 16)
                        }
                    } else {
                        totalFeesLabel(showChevron: false)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func totalFeesLabel(showChevron: Bool = true) -> some View {
        HStack {
            getSummaryCell(
                leadingText: "totalFee",
                trailingText: "\(SwapCryptoLogic.totalFeeString(tx: tx))"
            )

            if showChevron {
                chevron
            }
        }
    }

    var chevron: some View {
        Image(systemName: "chevron.up")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .rotationEffect(Angle(degrees: showFees ? 0 : 180))
            .animation(.easeInOut, value: showFees)
    }

    var expandableFees: some View {
        VStack(spacing: 16) {
            if SwapCryptoLogic.showGas(tx: tx) {
                swapGas
            }

            if !SwapCryptoLogic.baseAffiliateFee(tx: tx).isEmpty {
                affiliateFee
            }

            if !outboundFeeString.isEmpty {
                outboundFee
            }

            if !SwapCryptoLogic.vultDiscount(tx: tx).isEmpty {
                vultDiscount
            }

            if !SwapCryptoLogic.referralDiscount(tx: tx).isEmpty {
                referralDiscount
            }

            if !SwapCryptoLogic.priceImpactString(tx: tx).isEmpty {
                priceImpact
            }
        }
    }

    var swapGas: some View {
        let gasString = SwapCryptoLogic.swapGasString(tx: tx)
        // Only show approval fee suffix when approval is required and fee is non-zero (using numeric check)
        let showApproveFee = tx.isApproveRequired && !SwapCryptoLogic.isApproveFeeZero(tx: tx)
        let approveFeeString = SwapCryptoLogic.approveFeeString(tx: tx)
        let trailingText = showApproveFee ? "\(gasString) (\(approveFeeString))" : gasString
        return getSummaryCell(
            leadingText: "networkFee",
            trailingText: trailingText
        )
    }

    var affiliateFee: some View {
        HStack {
            Text(SwapCryptoLogic.swapFeeLabel(tx: tx))
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            Text(SwapCryptoLogic.baseAffiliateFee(tx: tx))
                .foregroundColor(Theme.colors.textSecondary)
        }
        .font(Theme.fonts.caption12)
    }

    var vultDiscount: some View {
        HStack {
            vultTierIcon

            Text(SwapCryptoLogic.vultDiscountLabel(tx: tx))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)

            Spacer()

            Text(SwapCryptoLogic.vultDiscount(tx: tx))
                .foregroundColor(Theme.colors.textSecondary)
                .font(Theme.fonts.caption12)
        }
    }

    @ViewBuilder
    private var vultTierIcon: some View {
        if let tier = VultDiscountTier.from(bpsDiscount: tx.vultDiscountBps) {
            Image(tier.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "star.circle.fill")
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.turquoise)
        }
    }

    var outboundFee: some View {
        getSummaryCell(
            leadingText: "swap.outbound_fee",
            trailingText: outboundFeeString
        )
    }

    var referralDiscount: some View {
        HStack {
            Image(systemName: "megaphone.fill")
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.primaryAccent4)

            Text(SwapCryptoLogic.referralDiscountLabel(tx: tx))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)

            Spacer()

            Text(SwapCryptoLogic.referralDiscount(tx: tx))
                .foregroundColor(Theme.colors.textSecondary)
                .font(Theme.fonts.caption12)
        }
    }

    var priceImpact: some View {
        HStack {
            Text(NSLocalizedString("swap.price_impact", comment: "Price Impact"))
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            Text(SwapCryptoLogic.priceImpactString(tx: tx))
                .foregroundColor(SwapCryptoLogic.priceImpactColor(tx: tx))
        }
        .font(Theme.fonts.caption12)
    }

    private func getSummaryCell(leadingText: String, trailingText: String) -> some View {
        HStack {
            Text(NSLocalizedString(leadingText, comment: ""))
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            Text(trailingText)
                .foregroundColor(Theme.colors.textSecondary)
                .redacted(reason: detailsViewModel.isLoading ? .placeholder : [])
        }
        .font(Theme.fonts.caption12)
    }

    private func getImage(_ image: String) -> some View {
        Image(image)
            .resizable()
            .frame(width: 16, height: 16)
    }

    private func getErrorCell(text: String) -> some View {
        HStack {
            Text(text)
                .foregroundColor(Theme.colors.alertError)
                .font(Theme.fonts.caption12)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)

            Spacer()
        }
    }

    private var outboundFeeString: String {
        guard let quote = tx.quote else { return .empty }

        var outboundFeeString: String?
        let feeDecimals: Int = 8 // Default to 8 (THORChain standard)

        switch quote {
        case .thorchain(let q), .thorchainChainnet(let q), .thorchainStagenet(let q), .mayachain(let q):
            outboundFeeString = q.fees.outbound
        default:
            return .empty
        }

        guard let outboundFeeString = outboundFeeString else {
            return .empty
        }
        let feeAmount = outboundFeeString.toDecimal()

        // Fee is in output asset
        let feeCoin = tx.toCoin
        let feeDecimal = feeAmount / pow(10, feeDecimals)
        let fiatValue = feeCoin.fiat(decimal: feeDecimal)

        return fiatValue.formatToFiat(includeCurrencySymbol: true)
    }
}

#Preview {
    ZStack {
        Background()
        SwapDetailsSummary(tx: SwapTransaction(), detailsViewModel: SwapDetailsViewModel())
    }
}
