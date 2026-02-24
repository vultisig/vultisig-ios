//
//  SwapDetailsSummary.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-25.
//

import SwiftUI

struct SwapDetailsSummary: View {

    @ObservedObject var tx: SwapTransaction
    @ObservedObject var swapViewModel: SwapCryptoViewModel

    @State private var showFees: Bool = true

    private var hasExpandableFees: Bool {
        swapViewModel.showGas(tx: tx) ||
        !swapViewModel.baseAffiliateFee(tx: tx).isEmpty ||
        !outboundFeeString.isEmpty ||
        !swapViewModel.vultDiscount(tx: tx).isEmpty ||
        !swapViewModel.referralDiscount(tx: tx).isEmpty ||
        !swapViewModel.priceImpactString(tx: tx).isEmpty
    }

    var body: some View {
        content
            .animation(.easeInOut, value: showFees)
    }

    var content: some View {
        VStack(spacing: 16) {
            if let providerName = tx.quote?.displayName {
                getSummaryCell(
                    leadingText: "provider",
                    trailingText: providerName
                )
            }

            if swapViewModel.showTotalFees(tx: tx) {
                totalFees
            }

            if hasExpandableFees {
                otherFees
            }
        }
        .padding(.top, 8)
    }

    var totalFees: some View {
        Button {
            showFees.toggle()
        } label: {
            totalFeesLabel
        }
    }

    var totalFeesLabel: some View {
        HStack {
            getSummaryCell(
                leadingText: "totalFee",
                trailingText: "\(swapViewModel.totalFeeString(tx: tx))"
            )

            chevron
        }
    }

    var chevron: some View {
        Image(systemName: "chevron.up")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .rotationEffect(Angle(degrees: showFees ? 0 : 180))
    }

    var otherFees: some View {
        HStack {
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Theme.colors.primaryAccent4)

            expandableFees
        }
        .frame(maxHeight: showFees ? nil : 0)
        .clipped()
    }

    var expandableFees: some View {
        VStack(spacing: 16) {
            if swapViewModel.showGas(tx: tx) {
                swapGas
            }

            if !swapViewModel.baseAffiliateFee(tx: tx).isEmpty {
                affiliateFee
            }

            if !outboundFeeString.isEmpty {
                outboundFee
            }

            if !swapViewModel.vultDiscount(tx: tx).isEmpty {
                vultDiscount
            }

            if !swapViewModel.referralDiscount(tx: tx).isEmpty {
                referralDiscount
            }

            if !swapViewModel.priceImpactString(tx: tx).isEmpty {
                priceImpact
            }
        }
    }

    var swapGas: some View {
        let gasString = swapViewModel.swapGasString(tx: tx)
        // Only show approval fee suffix when approval is required and fee is non-zero (using numeric check)
        let showApproveFee = tx.isApproveRequired && !swapViewModel.isApproveFeeZero(tx: tx)
        let approveFeeString = swapViewModel.approveFeeString(tx: tx)
        let trailingText = showApproveFee ? "\(gasString) (\(approveFeeString))" : gasString
        return getSummaryCell(
            leadingText: "networkFee",
            trailingText: trailingText
        )
    }

    var affiliateFee: some View {
        HStack {
            Text(swapViewModel.swapFeeLabel(tx: tx))
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            Text(swapViewModel.baseAffiliateFee(tx: tx))
                .foregroundColor(Theme.colors.textSecondary)
        }
        .font(Theme.fonts.caption12)
    }

    var vultDiscount: some View {
        HStack {
            vultTierIcon

            Text(swapViewModel.vultDiscountLabel(tx: tx))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)

            Spacer()

            Text(swapViewModel.vultDiscount(tx: tx))
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

            Text(swapViewModel.referralDiscountLabel(tx: tx))
                .foregroundColor(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)

            Spacer()

            Text(swapViewModel.referralDiscount(tx: tx))
                .foregroundColor(Theme.colors.textSecondary)
                .font(Theme.fonts.caption12)
        }
    }

    var priceImpact: some View {
        HStack {
            Text(NSLocalizedString("swap.price_impact", comment: "Price Impact"))
                .foregroundColor(Theme.colors.textTertiary)

            Spacer()

            Text(swapViewModel.priceImpactString(tx: tx))
                .foregroundColor(swapViewModel.priceImpactColor(tx: tx))
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
                .redacted(reason: swapViewModel.isLoading ? .placeholder : [])
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
        case .thorchain(let q), .thorchainChainnet(let q), .thorchainStagenet2(let q), .mayachain(let q):
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
        SwapDetailsSummary(tx: SwapTransaction(), swapViewModel: SwapCryptoViewModel())
    }
}
