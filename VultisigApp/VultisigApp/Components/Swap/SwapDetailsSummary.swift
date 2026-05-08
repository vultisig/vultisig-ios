//
//  SwapDetailsSummary.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-25.
//

import SwiftUI

struct SwapDetailsSummary: View {

    @Bindable var detailsViewModel: SwapDetailsViewModel

    @State private var showFees: Bool = true

    private var draft: SwapDraft { detailsViewModel.draft }

    private var hasExpandableFees: Bool {
        SwapCryptoLogic.showGas(draft: draft) ||
        !SwapCryptoLogic.baseAffiliateFee(draft: draft).isEmpty ||
        !outboundFeeString.isEmpty ||
        !SwapCryptoLogic.vultDiscount(draft: draft).isEmpty ||
        !SwapCryptoLogic.referralDiscount(draft: draft).isEmpty ||
        !SwapCryptoLogic.priceImpactString(draft: draft).isEmpty
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
                if let providerName = draft.quote?.displayName {
                    getSummaryCell(
                        leadingText: "provider",
                        trailingText: providerName
                    )
                }

                if SwapCryptoLogic.showTotalFees(draft: draft) {
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
                trailingText: "\(SwapCryptoLogic.totalFeeString(draft: draft))"
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
            if SwapCryptoLogic.showGas(draft: draft) {
                swapGas
            }

            if !SwapCryptoLogic.baseAffiliateFee(draft: draft).isEmpty {
                affiliateFee
            }

            if !outboundFeeString.isEmpty {
                outboundFee
            }

            if !SwapCryptoLogic.vultDiscount(draft: draft).isEmpty {
                vultDiscount
            }

            if !SwapCryptoLogic.referralDiscount(draft: draft).isEmpty {
                referralDiscount
            }

            if !SwapCryptoLogic.priceImpactString(draft: draft).isEmpty {
                priceImpact
            }
        }
    }

    var swapGas: some View {
        let gasString = SwapCryptoLogic.swapGasString(draft: draft)
        // Only show approval fee suffix when approval is required and fee is non-zero (using numeric check)
        let showApproveFee = SwapCryptoLogic.isApproveRequired(draft: draft) && !SwapCryptoLogic.isApproveFeeZero(draft: draft)
        let approveFeeString = SwapCryptoLogic.approveFeeString(draft: draft)
        let trailingText = showApproveFee ? "\(gasString) (\(approveFeeString))" : gasString
        return getSummaryCell(
            leadingText: "networkFee",
            trailingText: trailingText
        )
    }

    var affiliateFee: some View {
        HStack {
            Text(SwapCryptoLogic.swapFeeLabel(draft: draft))
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            Text(SwapCryptoLogic.baseAffiliateFee(draft: draft))
                .foregroundColor(Theme.colors.textSecondary)
        }
        .font(Theme.fonts.caption12)
    }

    var vultDiscount: some View {
        HStack {
            vultTierIcon

            Text(SwapCryptoLogic.vultDiscountLabel(draft: draft))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)

            Spacer()

            Text(SwapCryptoLogic.vultDiscount(draft: draft))
                .foregroundColor(Theme.colors.textSecondary)
                .font(Theme.fonts.caption12)
        }
    }

    @ViewBuilder
    private var vultTierIcon: some View {
        if let tier = VultDiscountTier.from(bpsDiscount: draft.vultDiscountBps) {
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

            Text(SwapCryptoLogic.referralDiscountLabel(draft: draft))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)

            Spacer()

            Text(SwapCryptoLogic.referralDiscount(draft: draft))
                .foregroundColor(Theme.colors.textSecondary)
                .font(Theme.fonts.caption12)
        }
    }

    var priceImpact: some View {
        HStack {
            Text(NSLocalizedString("swap.price_impact", comment: "Price Impact"))
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            Text(SwapCryptoLogic.priceImpactString(draft: draft))
                .foregroundColor(SwapCryptoLogic.priceImpactColor(draft: draft))
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
        guard let quote = draft.quote else { return .empty }

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
        let feeCoin = draft.toCoin
        let feeDecimal = feeAmount / pow(10, feeDecimals)
        let fiatValue = feeCoin.fiat(decimal: feeDecimal)

        return fiatValue.formatToFiat(includeCurrencySymbol: true)
    }
}

#Preview {
    ZStack {
        Background()
        SwapDetailsSummary(detailsViewModel: SwapDetailsViewModel())
    }
}
